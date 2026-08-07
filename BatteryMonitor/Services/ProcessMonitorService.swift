import Foundation
import Combine
import Darwin
import AppKit

class ProcessMonitorService: ObservableObject {
    @Published var topProcesses: [ProcessPowerInfo] = []
    /// 是否已完成至少一次采样。View 靠它区分「还在加载」和「采过了但确实没有」——
    /// 之前只看 topProcesses.isEmpty，空闲机器上会一直显示「正在加载进程列表…」。
    @Published var hasSampled = false
    @Published private(set) var isLiveRefreshEnabled = true
    /// 全机 CPU 与「可见 / 系统」拆分。列表只覆盖当前用户可读的进程，这个快照负责
    /// 把读不到的那部分明确标出来，而不是让列表看起来像全量。
    @Published private(set) var systemCPU = SystemCPUSnapshot.unavailable

    /// 上一拍的全机 tick 快照，用来求差。
    private var previousCPULoad: SystemCPULoad.Sample?

    private var timer: Timer?
    /// Process activity is context for the ten-second power chart. It is never
    /// presented as a per-process watt allocation.
    static let liveRefreshInterval: TimeInterval = 10
    /// 没有任何进程界面可见时仍给菜单栏保留低频上下文，但不再每 10 秒扫描数百个进程。
    static let backgroundRefreshInterval: TimeInterval = 60
    /// 超过这个间隔说明中间经历了暂停、睡眠或调度停顿。旧前值不能再冒充「当前窗口」。
    static let baselineResetInterval: TimeInterval = 150
    enum HighFrequencyConsumer: Hashable, Sendable {
        case technicalPowerCenter
        case trendsPage
        case menuBar
    }
    private var highFrequencyConsumers: Set<HighFrequencyConsumer> = []
    private var effectiveRefreshInterval: TimeInterval {
        Self.refreshInterval(hasHighFrequencyConsumer: !highFrequencyConsumers.isEmpty)
    }
    /// 这两个状态只在主线程读写；真正的 pid 前值在采样队列中按本次标记清空。
    private var forceBaselineReset = false
    private var lastSamplingStartedAt: TimeInterval?

    static func refreshInterval(hasHighFrequencyConsumer: Bool) -> TimeInterval {
        hasHighFrequencyConsumer ? liveRefreshInterval : backgroundRefreshInterval
    }

    static func shouldResetBaseline(lastSamplingStartedAt: TimeInterval?,
                                    nextSamplingStartedAt: TimeInterval) -> Bool {
        guard let lastSamplingStartedAt else { return false }
        return nextSamplingStartedAt - lastSamplingStartedAt > baselineResetInterval
    }
    /// 按 groupKey 而不是 pid 索引：一行是 app + 子进程的聚合，代表 pid 会变，
    /// 按 pid 存历史会在子进程进出时把曲线接断。
    private var cpuHistoryByGroup: [String: [Double]] = [:]
    private let maxHistoryPoints = 24
    /// pid → 可执行文件路径。`proc_pidpath` 每轮对 300+ 进程各调一次纯属浪费，
    /// 而路径在进程存活期内不会变。键带 startTime 是为了防 pid 回绕把新进程的
    /// 图标和名字接到一个已经退出的旧进程上。
    private var executablePathCache: [Int32: (startTime: TimeInterval, path: String)] = [:]

    // Previous CPU time samples for delta calculation
    private var previousCPUTimes: [Int32: (user: UInt64, system: UInt64,
                                           timestamp: TimeInterval, lastPercent: Double)] = [:]
    /// 短于这个间隔的两次采样差值没有意义（连点刷新），沿用上次读数
    private static let minSampleInterval: TimeInterval = 0.5
    /// 防止刷新按钮连点导致并发采样把 previousCPUTimes 写乱
    private var isSampling = false

    deinit {
        // The run loop retains scheduled timers. Invalidate explicitly so a
        // discarded monitor cannot leave a ten-second no-op wake-up behind.
        timer?.invalidate()
    }

    /// 进程生命周期平均 CPU%。首次采样没有前值可比时用它兜底。
    /// 走 proc_pidinfo(PROC_PIDTBSDINFO) 取进程启动时间，纯只读、无需授权。
    private func lifetimeAverageCPU(pid: Int32, totalCPUTime: UInt64,
                                    now: TimeInterval) -> Double {
        var bsd = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &bsd, size) == size else { return 0 }
        let started = TimeInterval(bsd.pbi_start_tvsec) + TimeInterval(bsd.pbi_start_tvusec) / 1_000_000
        let age = now - started
        guard age > 1 else { return 0 }   // 刚起来的进程平均值没意义
        // Match Activity Monitor's process CPU convention: 100% is one fully
        // occupied core, so a multi-threaded application may exceed 100%.
        return Self.cpuPercent(ticksDelta: totalCPUTime, seconds: age)
    }

    func startMonitoring() {
        timer?.invalidate()
        guard isLiveRefreshEnabled else { return }
        fetchProcesses()
        scheduleTimer()
    }

    private func scheduleTimer() {
        timer?.invalidate()
        let interval = effectiveRefreshInterval
        let t = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            self?.fetchProcesses()
        }
        // Align this wake-up with the battery refresh whenever macOS can do so.
        // 相关界面可见时仍是十秒；后台低频模式也允许系统合并唤醒。
        t.tolerance = min(10, interval * 0.15)
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }

    func setLiveRefreshEnabled(_ enabled: Bool) {
        guard enabled != isLiveRefreshEnabled else { return }
        isLiveRefreshEnabled = enabled
        if enabled {
            fetchProcesses()
            scheduleTimer()
        } else {
            // 恢复后的第一拍只建立新基线，避免把整个暂停期平均成「此刻 CPU」。
            forceBaselineReset = true
            stopMonitoring()
        }
    }

    /// 进程明细只有在相关界面可见时才需要 10 秒刷新；其余时间降到 60 秒。
    /// 用集合而不是计数，避免 SwiftUI 重复 onAppear/onDisappear 把状态加坏。
    func setHighFrequencyConsumer(_ consumer: HighFrequencyConsumer, visible: Bool) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.setHighFrequencyConsumer(consumer, visible: visible)
            }
            return
        }
        let changed: Bool
        if visible {
            changed = highFrequencyConsumers.insert(consumer).inserted
        } else {
            changed = highFrequencyConsumers.remove(consumer) != nil
        }
        guard changed, isLiveRefreshEnabled else { return }
        if visible { fetchProcesses() }
        scheduleTimer()
    }

    func fetchProcesses() {
        // NSWorkspace is an AppKit API. Snapshot the visible applications on the
        // main thread, then do the comparatively expensive proc_pidinfo reads in
        // the background. Timer and UI refreshes normally arrive on main, while
        // this hop also makes direct/test callers safe.
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.fetchProcesses() }
            return
        }
        guard !isSampling else { return }   // 刷新连点时丢弃重入，避免并发写坏采样状态
        isSampling = true
        let samplingStartedAt = Date().timeIntervalSince1970
        let exceededValidWindow = Self.shouldResetBaseline(
            lastSamplingStartedAt: lastSamplingStartedAt,
            nextSamplingStartedAt: samplingStartedAt
        )
        let shouldResetBaseline = forceBaselineReset || exceededValidWindow
        forceBaselineReset = false
        lastSamplingStartedAt = samplingStartedAt
        if shouldResetBaseline { previousCPULoad = nil }
        let candidates = applicationCandidates()
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else { return }
            if shouldResetBaseline { self.previousCPUTimes.removeAll() }
            // 全机 tick 要在进程采样前后各取一次？不需要 —— 它是累计值，与上一拍求差
            // 覆盖的正好是同一段 10 秒窗口，和进程 CPU% 的窗口对齐。
            let loadSample = SystemCPULoad.sample()
            let sampled = self.getTopProcesses(candidates: candidates)
            let processes = sampled.groups

            DispatchQueue.main.async {
                defer { self.isSampling = false }

                // 差值口径：busyPercent 是整机 0…100，进程合计是「100% = 一核」，
                // 必须换算后再相减，否则 10 核机上「整机 30% − Chrome 300%」恒为负。
                let busy = loadSample.flatMap { current -> Double? in
                    defer { self.previousCPULoad = current }
                    guard let previous = self.previousCPULoad else { return nil }
                    return SystemCPULoad.busyPercent(from: previous, to: current)
                }
                self.systemCPU = SystemCPUSnapshot(
                    machineBusy: busy,
                    visiblePerCorePercent: sampled.visiblePerCorePercent,
                    coreCount: ProcessInfo.processInfo.activeProcessorCount
                )

                let liveGroups = Set(processes.map(\.groupIdentifier))
                self.cpuHistoryByGroup = self.cpuHistoryByGroup.filter { liveGroups.contains($0.key) }

                let withHistory = processes.map { proc -> ProcessPowerInfo in
                    var history = self.cpuHistoryByGroup[proc.groupIdentifier] ?? []
                    history.append(proc.cpuPercent)
                    if history.count > self.maxHistoryPoints {
                        history.removeFirst(history.count - self.maxHistoryPoints)
                    }
                    self.cpuHistoryByGroup[proc.groupIdentifier] = history
                    return ProcessPowerInfo(
                        pid: proc.pid,
                        name: proc.name,
                        cpuPercent: proc.cpuPercent,
                        memoryMB: proc.memoryMB,
                        cpuHistory: history,
                        isForeground: proc.isForeground,
                        groupKey: proc.groupIdentifier,
                        processCount: proc.processCount,
                        topChildName: proc.topChildName
                    )
                }
                self.topProcesses = ProcessPowerInfo.rankedForDisplay(withHistory, limit: 12)
                self.hasSampled = true
            }
        }
    }

    // MARK: - Native Process Enumeration via sysctl + proc_pidinfo

    private struct ApplicationCandidate: Sendable {
        let pid: Int32
        let name: String
        let groupIdentifier: String
        let isForeground: Bool
    }

    private struct RawProcess {
        let pid: Int
        let name: String
        let groupIdentifier: String
        let cpuPercent: Double
        let memoryMB: Double
        let isForeground: Bool
        let processCount: Int
        let topChildName: String?
    }

    /// 聚合过程中的累加器。组内 CPU 最高的子进程要留名，所以不能只累加数字。
    /// 名字这里先只存 comm（sysctl 白送的，无系统调用），可执行文件路径留到第二遍
    /// 只对会展示的那几组解析 —— `proc_pidpath` 对 300+ 进程每轮全调一次纯属浪费。
    private struct GroupAccumulator {
        let key: String
        let rootPid: Int32
        /// app 行有 NSWorkspace 给的 bundle 路径；非 app 行为 nil。
        let bundlePath: String?
        let rootComm: String
        var cpuPercent: Double = 0
        var memoryMB: Double = 0
        var isForeground: Bool = false
        var processCount: Int = 0
        var rootCPUPercent: Double = 0
        var topChildPid: Int32?
        var topChildComm: String?
        var topChildCPUPercent: Double = 0
    }

    /// 第二遍解析可执行文件路径的组数上限。展示上限是 12 组，24 留了一倍余量，
    /// 同时把 `proc_pidpath` 的调用量从「每轮 300+」压到「每轮 ≤48」。
    private static let maxResolvedGroups = 24

    /// 副标题点名子进程的门槛（占满一个核的 1%）。低于这个值的子进程不值得占一行文字。
    static let minimumTopChildCPUPercent: Double = 1.0

    /// App Sandbox deliberately returns 0 for `proc_listpids(..., nil, 0)` even
    /// though `proc_pidinfo` remains available for many user applications whose
    /// PID is already known. Enumerating user-visible applications through
    /// NSWorkspace gives us those real PIDs without requesting an entitlement or
    /// inventing per-process power attribution.
    private func applicationCandidates() -> [ApplicationCandidate] {
        let ownPID = getpid()
        let ownBundleIdentifier = Bundle.main.bundleIdentifier
        var seenPIDs = Set<Int32>()

        return NSWorkspace.shared.runningApplications.compactMap { app in
            let pid = app.processIdentifier
            guard pid > 0, pid != ownPID, !app.isTerminated,
                  app.bundleIdentifier != ownBundleIdentifier,
                  app.activationPolicy == .regular || app.activationPolicy == .accessory,
                  seenPIDs.insert(pid).inserted else { return nil }

            let fallback = app.bundleURL?.deletingPathExtension().lastPathComponent
                ?? app.executableURL?.lastPathComponent
            guard let displayName = (app.localizedName ?? fallback)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !displayName.isEmpty else { return nil }
            // Preserve a bundle/executable path when available. ProcessPowerInfo
            // still derives the friendly name, while the menu can now render the
            // application's real icon instead of a generic placeholder.
            let name = app.bundleURL?.path ?? app.executableURL?.path ?? displayName

            return ApplicationCandidate(
                pid: pid,
                name: name,
                groupIdentifier: app.bundleIdentifier ?? displayName.lowercased(),
                isForeground: app.isActive
            )
        }
    }

    /// 采样结果。`visiblePerCorePercent` 是**全部**可读进程的 CPU% 合计（每核口径），
    /// 不是 `groups` 那 24 组的合计 —— 用截断后的合计去减会低估可读进程、
    /// 高估未归因负载。
    private struct SampleResult {
        let groups: [RawProcess]
        let visiblePerCorePercent: Double
    }

    private func getTopProcesses(candidates: [ApplicationCandidate]) -> SampleResult {
        let table = ProcessTable.snapshot()
        // 枚举拿不到东西时回落到只看 NSWorkspace 的老路。`KERN_PROC_ALL` 在沙箱下
        // 可用是未文档化的行为，未来系统或审核环境收紧时宁可覆盖面退化，也不能变成空列表。
        guard table.count >= ProcessTable.minimumPlausibleCount else {
            return sampleApplicationsOnly(candidates: candidates)
        }

        let candidatesByPID = Dictionary(candidates.map { ($0.pid, $0) },
                                         uniquingKeysWith: { first, _ in first })
        let entriesByPID = Dictionary(table.map { ($0.pid, $0) },
                                      uniquingKeysWith: { first, _ in first })
        let roots = ProcessTable.rollUp(entries: table,
                                        appPids: Set(candidatesByPID.keys),
                                        excludingSubtreeOf: getpid())

        let now = Date().timeIntervalSince1970
        var groups: [String: GroupAccumulator] = [:]
        var sampledPids: Set<Int32> = []
        var visiblePerCorePercent: Double = 0

        for entry in table {
            // roots 里没有的是本进程那棵子树，直接跳过。
            guard let root = roots[entry.pid],
                  let sample = sampleProcess(pid: entry.pid, now: now) else { continue }
            sampledPids.insert(entry.pid)
            // 新 PID 的第一拍是生命周期平均值，只用于该行的临时展示；顶部归因必须
            // 等第二拍拿到与全机相同窗口的差值后再纳入。
            if sample.isWindowSample { visiblePerCorePercent += sample.cpuPercent }

            let candidate = candidatesByPID[root]
            // app 行按 bundleID 归组，不按 root pid：NSWorkspace 可能报出同一个 app
            // 的两个主进程（实测 Chrome 就有两个），按 pid 归组会让它出现两行。
            let key = candidate.map { "app:\($0.groupIdentifier)" }
                ?? "proc:\(root):\(entriesByPID[root]?.comm ?? entry.comm)"

            var group = groups[key] ?? GroupAccumulator(
                key: key,
                rootPid: root,
                bundlePath: candidate?.name,
                rootComm: entriesByPID[root]?.comm ?? entry.comm
            )
            group.cpuPercent += sample.cpuPercent
            group.memoryMB += sample.memoryMB
            group.processCount += 1
            group.isForeground = group.isForeground || (candidate?.isForeground ?? false)
            if entry.pid == root {
                group.rootCPUPercent = sample.cpuPercent
            } else if sample.cpuPercent > group.topChildCPUPercent {
                group.topChildCPUPercent = sample.cpuPercent
                group.topChildPid = entry.pid
                group.topChildComm = entry.comm
            }
            groups[key] = group
        }

        // 前值和路径缓存都只保留本轮实际采样到的 pid。
        // 用 candidates 剪枝是个陷阱：采样集比 candidates 大一个数量级，那样会把多出来
        // 的进程前值每轮全丢掉，下一轮取不到前值就永远退化成生命周期均值 —— 显示的是
        // 历史平均而不是当前 10 秒，症状看起来跟「timebase 没修好」一模一样。
        previousCPUTimes = previousCPUTimes.filter { sampledPids.contains($0.key) }
        executablePathCache = executablePathCache.filter { sampledPids.contains($0.key) }

        // 第二遍：只对最重的若干组解析可执行文件路径，其余组不值得为它们调系统调用。
        let ranked = groups.values
            .sorted { $0.cpuPercent > $1.cpuPercent }
            .prefix(Self.maxResolvedGroups)

        let rows = ranked.map { group -> RawProcess in
            let name = group.bundlePath
                ?? executablePath(pid: group.rootPid, entries: entriesByPID)
                ?? group.rootComm
            // 点名组内最重的子进程 ——「Terminal 31.6%」不告诉你该关什么，
            // 「Terminal · claude」才告诉你。
            //
            // 门槛是绝对值而不是「比主进程更重」：实测这两个值会在相邻采样间反复交换
            // （Terminal 9.6% vs claude 10.8%，下一拍反过来），用相对比较会让副标题
            // 每 10 秒闪一次、行高跟着跳。绝对门槛也顺手滤掉了「└ zsh 0.0%」这种噪音。
            var topChildName: String?
            if let childPid = group.topChildPid,
               group.topChildCPUPercent >= Self.minimumTopChildCPUPercent {
                let resolved = executablePath(pid: childPid, entries: entriesByPID)
                    .map { URL(fileURLWithPath: $0).lastPathComponent }
                topChildName = resolved ?? group.topChildComm
            }
            return RawProcess(
                pid: Int(group.rootPid),
                name: name,
                groupIdentifier: group.key,
                cpuPercent: Self.sanitizedCPUPercent(group.cpuPercent),
                memoryMB: group.memoryMB,
                isForeground: group.isForeground,
                processCount: group.processCount,
                topChildName: topChildName
            )
        }
        return SampleResult(groups: Array(rows), visiblePerCorePercent: visiblePerCorePercent)
    }

    /// 全表枚举不可用时的退路：只采 NSWorkspace 报出来的 GUI app 主进程。
    /// 覆盖面会退回到「看不见子进程」的状态，但数值仍然是对的。
    private func sampleApplicationsOnly(candidates: [ApplicationCandidate]) -> SampleResult {
        let now = Date().timeIntervalSince1970
        var groups: [String: RawProcess] = [:]
        var sampledPids: Set<Int32> = []
        var visiblePerCorePercent: Double = 0

        for candidate in candidates {
            guard let sample = sampleProcess(pid: candidate.pid, now: now) else { continue }
            sampledPids.insert(candidate.pid)
            if sample.isWindowSample { visiblePerCorePercent += sample.cpuPercent }
            let key = "app:\(candidate.groupIdentifier)"
            if let current = groups[key] {
                groups[key] = RawProcess(
                    pid: min(current.pid, Int(candidate.pid)),
                    name: current.name,
                    groupIdentifier: key,
                    cpuPercent: Self.sanitizedCPUPercent(current.cpuPercent + sample.cpuPercent),
                    memoryMB: current.memoryMB + sample.memoryMB,
                    isForeground: current.isForeground || candidate.isForeground,
                    processCount: current.processCount + 1,
                    topChildName: nil
                )
            } else {
                groups[key] = RawProcess(
                    pid: Int(candidate.pid),
                    name: candidate.name,
                    groupIdentifier: key,
                    cpuPercent: Self.sanitizedCPUPercent(sample.cpuPercent),
                    memoryMB: sample.memoryMB,
                    isForeground: candidate.isForeground,
                    processCount: 1,
                    topChildName: nil
                )
            }
        }
        previousCPUTimes = previousCPUTimes.filter { sampledPids.contains($0.key) }
        return SampleResult(groups: Array(groups.values),
                            visiblePerCorePercent: visiblePerCorePercent)
    }

    /// 读单个进程的 CPU% 和常驻内存。返回 nil 表示这个 pid 读不到 ——
    /// root 进程一律如此，即使完全不沙箱也读不到。
    private func sampleProcess(pid: Int32, now: TimeInterval) -> (
        cpuPercent: Double,
        memoryMB: Double,
        isWindowSample: Bool
    )? {
        var taskInfo = proc_taskinfo()
        let taskInfoSize = Int32(MemoryLayout<proc_taskinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &taskInfo, taskInfoSize) == taskInfoSize
        else { return nil }

        // CPU% 靠两次采样求差。首次采样没有前值可比 —— 这里必须兜底，否则
        // 所有进程的 cpuPercent 都是 0，列表会一直卡在「正在加载进程列表…」。
        let totalCPUTime = taskInfo.pti_total_user &+ taskInfo.pti_total_system
        var cpuPercent: Double = 0
        var isWindowSample = false

        if let prev = previousCPUTimes[pid] {
            let prevTotal = prev.user &+ prev.system
            let delta = totalCPUTime > prevTotal ? totalCPUTime - prevTotal : 0
            let timeDelta = now - prev.timestamp
            // 间隔太短（连点刷新）时差值没有意义，保留上一次的读数而不是显示 0
            if timeDelta >= Self.minSampleInterval {
                cpuPercent = Self.cpuPercent(ticksDelta: delta, seconds: timeDelta)
                isWindowSample = true
            } else {
                cpuPercent = prev.lastPercent
            }
        } else {
            // 兜底：用进程生命周期平均 CPU%（总 CPU 时间 ÷ 进程已存活时长）。
            // 单次采样就能算，是真实值而非估算，只是反映的是历史平均而非瞬时。
            cpuPercent = lifetimeAverageCPU(pid: pid, totalCPUTime: totalCPUTime, now: now)
        }
        previousCPUTimes[pid] = (user: taskInfo.pti_total_user,
                                 system: taskInfo.pti_total_system,
                                 timestamp: now,
                                 lastPercent: cpuPercent)

        // A zero delta is a valid observation: the app is running but idle.
        return (cpuPercent: Self.sanitizedCPUPercent(cpuPercent),
                memoryMB: Double(taskInfo.pti_resident_size) / 1024.0 / 1024.0,
                isWindowSample: isWindowSample)
    }

    /// 可执行文件绝对路径，带缓存。路径在进程存活期内不变，所以只在首次见到这个
    /// (pid, startTime) 组合时调 `proc_pidpath`。startTime 参与判别是因为 macOS 的
    /// pid 到 99999 会回绕，只按 pid 缓存会把新进程的图标和名字接到旧进程身上。
    private func executablePath(pid: Int32, entries: [Int32: ProcessTable.Entry]) -> String? {
        let startTime = entries[pid]?.startTime ?? 0
        if let cached = executablePathCache[pid], cached.startTime == startTime {
            return cached.path.isEmpty ? nil : cached.path
        }
        // PROC_PIDPATHINFO_MAXSIZE 这个宏在 Swift 里不可用（"structure not supported"），
        // 它的定义就是 4 * MAXPATHLEN。
        let capacity = 4 * Int(MAXPATHLEN)
        var buffer = [CChar](repeating: 0, count: capacity)
        let length = proc_pidpath(pid, &buffer, UInt32(capacity))
        let path = length > 0 ? String(cString: buffer) : ""
        executablePathCache[pid] = (startTime: startTime, path: path)
        return path.isEmpty ? nil : path
    }

    // MARK: - CPU 时间换算

    /// `proc_pidinfo` 返回的 `pti_total_user` / `pti_total_system` 是 **mach absolute
    /// time tick，不是纳秒**。Apple Silicon 的 timebase 是 125/3（`hw.tbfrequency`
    /// 24 MHz），1 tick ≈ 41.667 ns；把它当纳秒直接除 1e9 会让所有进程的 CPU% 低估
    /// 41.67 倍 —— 实测「单线程占满一个核 3 秒」会被读成 2.40% 而不是 100%，连带把
    /// `EnergyLevel` 阈值、`sanitizedCPUPercent` 上限和耗电提示阈值全部压到永不触发。
    /// Intel 上 numer/denom 都是 1，这个换算天然是 no-op。
    /// 只取一次存 static：每个 pid 都调一遍纯属浪费。
    static let machTicksToNanoseconds: Double = {
        var info = mach_timebase_info_data_t()
        guard mach_timebase_info(&info) == KERN_SUCCESS, info.denom > 0 else { return 1 }
        return Double(info.numer) / Double(info.denom)
    }()

    /// tick 差值 → Activity Monitor 惯例的 CPU%（100% = 占满一个核，多线程可超 100%）。
    /// 抽成纯函数是为了能在测试里传入固定 timebase 断言，不依赖跑测试那台机器的架构。
    static func cpuPercent(ticksDelta: UInt64, seconds: TimeInterval,
                           ticksToNanoseconds: Double = ProcessMonitorService.machTicksToNanoseconds) -> Double {
        guard seconds > 0, ticksToNanoseconds > 0 else { return 0 }
        let nanoseconds = Double(ticksDelta) * ticksToNanoseconds
        return nanoseconds / (seconds * 1_000_000_000.0) * 100.0
    }

    /// proc counters are unsigned and normally monotonic, but process exits,
    /// sleep/wake boundaries, or an unexpected clock sample must never leak a
    /// NaN/Infinity into sorting and charts. Activity Monitor's convention can
    /// exceed 100% for multi-threaded apps, capped here at all logical cores.
    static func sanitizedCPUPercent(
        _ value: Double,
        logicalCoreCount: Int = ProcessInfo.processInfo.activeProcessorCount
    ) -> Double {
        guard value.isFinite else { return 0 }
        let upperBound = Double(max(1, logicalCoreCount)) * 100
        return min(upperBound, max(0, value))
    }
}
