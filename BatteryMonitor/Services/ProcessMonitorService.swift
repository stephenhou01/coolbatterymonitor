import Foundation
import Combine
import Darwin

class ProcessMonitorService: ObservableObject {
    @Published var topProcesses: [ProcessPowerInfo] = []
    /// 是否已完成至少一次采样。View 靠它区分「还在加载」和「采过了但确实没有」——
    /// 之前只看 topProcesses.isEmpty，空闲机器上会一直显示「正在加载进程列表…」。
    @Published var hasSampled = false
    @Published private(set) var isLiveRefreshEnabled = true

    private var timer: Timer?
    /// Process activity is context for the ten-second power chart. It is never
    /// presented as a per-process watt allocation.
    static let liveRefreshInterval: TimeInterval = 10
    private let refreshInterval = ProcessMonitorService.liveRefreshInterval
    private let totalMemMB = Double(ProcessInfo.processInfo.physicalMemory) / 1024.0 / 1024.0
    private var cpuHistoryByPid: [Int32: [Double]] = [:]
    private let maxHistoryPoints = 24

    // Previous CPU time samples for delta calculation
    private var previousCPUTimes: [Int32: (user: UInt64, system: UInt64,
                                           timestamp: TimeInterval, lastPercent: Double)] = [:]
    /// 短于这个间隔的两次采样差值没有意义（连点刷新），沿用上次读数
    private static let minSampleInterval: TimeInterval = 0.5
    /// 防止刷新按钮连点导致并发采样把 previousCPUTimes 写乱
    private var isSampling = false

    /// 进程生命周期平均 CPU%。首次采样没有前值可比时用它兜底。
    /// 走 proc_pidinfo(PROC_PIDTBSDINFO) 取进程启动时间，纯只读、无需授权。
    private func lifetimeAverageCPU(pid: Int32, totalCPUTime: UInt64,
                                    cpuCount: Int, now: TimeInterval) -> Double {
        var bsd = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &bsd, size) == size else { return 0 }
        let started = TimeInterval(bsd.pbi_start_tvsec) + TimeInterval(bsd.pbi_start_tvusec) / 1_000_000
        let age = now - started
        guard age > 1 else { return 0 }   // 刚起来的进程平均值没意义
        return Double(totalCPUTime) / (age * 1_000_000_000.0) / Double(cpuCount) * 100.0
    }

    func startMonitoring() {
        timer?.invalidate()
        guard isLiveRefreshEnabled else { return }
        fetchProcesses()
        scheduleTimer()
    }

    private func scheduleTimer() {
        timer?.invalidate()
        timer = Timer(timeInterval: refreshInterval, repeats: true) { [weak self] _ in
            self?.fetchProcesses()
        }
        RunLoop.main.add(timer!, forMode: .common)
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
            stopMonitoring()
        }
    }

    func fetchProcesses() {
        guard !isSampling else { return }   // 刷新连点时丢弃重入，避免并发写坏采样状态
        isSampling = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let processes = self.getTopProcesses()

            DispatchQueue.main.async {
                defer { self.isSampling = false }
                let livePids = Set(processes.map { Int32($0.pid) })
                self.cpuHistoryByPid = self.cpuHistoryByPid.filter { livePids.contains($0.key) }

                let withHistory = processes.map { proc -> ProcessPowerInfo in
                    let pid32 = Int32(proc.pid)
                    var history = self.cpuHistoryByPid[pid32] ?? []
                    history.append(proc.cpuPercent)
                    if history.count > self.maxHistoryPoints {
                        history.removeFirst(history.count - self.maxHistoryPoints)
                    }
                    self.cpuHistoryByPid[pid32] = history
                    return ProcessPowerInfo(
                        pid: proc.pid,
                        name: proc.name,
                        cpuPercent: proc.cpuPercent,
                        memoryMB: proc.memoryMB,
                        cpuHistory: history
                    )
                }
                self.topProcesses = withHistory
                self.hasSampled = true
            }
        }
    }

    // MARK: - Native Process Enumeration via sysctl + proc_pidinfo

    private struct RawProcess {
        let pid: Int
        let name: String
        let cpuPercent: Double
        let memoryMB: Double
    }

    private func getTopProcesses() -> [RawProcess] {
        var processes: [RawProcess] = []
        let now = Date().timeIntervalSince1970

        // Get all PIDs via proc_listpids
        let bufferSize = proc_listpids(UInt32(PROC_ALL_PIDS), 0, nil, 0)
        guard bufferSize > 0 else { return [] }

        let count = Int(bufferSize) / MemoryLayout<Int32>.size
        var pids = [Int32](repeating: 0, count: count)
        let actualSize = proc_listpids(UInt32(PROC_ALL_PIDS), 0, &pids, bufferSize)
        let actualCount = Int(actualSize) / MemoryLayout<Int32>.size

        let myPid = getpid()
        let cpuCount = ProcessInfo.processInfo.processorCount

        for i in 0..<actualCount {
            let pid = pids[i]
            guard pid > 0, pid != myPid else { continue }

            // Get task info (CPU time + memory)
            var taskInfo = proc_taskinfo()
            let taskInfoSize = Int32(MemoryLayout<proc_taskinfo>.size)
            let result = proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &taskInfo, taskInfoSize)
            guard result == taskInfoSize else { continue }

            // CPU% 靠两次采样求差。首次采样没有前值可比 —— 这里必须兜底，否则
            // 所有进程的 cpuPercent 都是 0，被下面的阈值全部滤掉，列表会一直卡在
            // 「正在加载进程列表…」直到第二次采样。
            let totalCPUTime = taskInfo.pti_total_user &+ taskInfo.pti_total_system
            var cpuPercent: Double = 0

            if let prev = previousCPUTimes[pid] {
                let prevTotal = prev.user &+ prev.system
                let delta = totalCPUTime > prevTotal ? totalCPUTime - prevTotal : 0
                let timeDelta = now - prev.timestamp
                // 间隔太短（连点刷新）时差值没有意义，保留上一次的读数而不是显示 0
                if timeDelta >= Self.minSampleInterval {
                    cpuPercent = Double(delta) / (timeDelta * 1_000_000_000.0) / Double(cpuCount) * 100.0
                } else {
                    cpuPercent = prev.lastPercent
                }
            } else {
                // 兜底：用进程生命周期平均 CPU%（总 CPU 时间 ÷ 进程已存活时长）。
                // 单次采样就能算，是真实值而非估算，只是反映的是历史平均而非瞬时。
                cpuPercent = lifetimeAverageCPU(pid: pid, totalCPUTime: totalCPUTime,
                                                cpuCount: cpuCount, now: now)
            }
            previousCPUTimes[pid] = (user: taskInfo.pti_total_user,
                                     system: taskInfo.pti_total_system,
                                     timestamp: now,
                                     lastPercent: cpuPercent)

            // 只排除完全没有 CPU 活动的。原来的 0.1% 阈值在空闲机器上会把几乎所有
            // 进程滤掉 —— 实测空闲时只剩 1 个，而 View 把空列表当成「加载中」，
            // 于是永远转圈。排序后取 top N 就够了，不需要在这里设业务阈值。
            guard cpuPercent > 0 else { continue }

            // Memory in MB (resident size)
            let memoryMB = Double(taskInfo.pti_resident_size) / 1024.0 / 1024.0

            // Get process name
            let maxPathSize: UInt32 = 4096 // MAXPATHLEN
            var nameBuffer = [CChar](repeating: 0, count: Int(maxPathSize))
            let nameResult = proc_pidpath(pid, &nameBuffer, maxPathSize)
            let name: String
            if nameResult > 0 {
                name = String(cString: nameBuffer)
            } else {
                // Fallback: get short name via proc_name
                var shortNameBuffer = [CChar](repeating: 0, count: 256)
                proc_name(pid, &shortNameBuffer, 256)
                name = String(cString: shortNameBuffer)
            }

            // Skip system/irrelevant processes
            let cmdLower = name.lowercased()
            let skipPatterns = ["kernel_task", "launchd", "syslogd", "configd", "notifyd",
                               "mdworker", "cfprefsd", "diskimages", "batterymonitor"]
            if skipPatterns.contains(where: { cmdLower.contains($0) }) { continue }

            processes.append(RawProcess(pid: Int(pid), name: name, cpuPercent: cpuPercent, memoryMB: memoryMB))
        }

        // Clean up stale entries
        let livePids = Set(pids.prefix(actualCount).filter { $0 > 0 })
        previousCPUTimes = previousCPUTimes.filter { livePids.contains($0.key) }

        return processes.sorted { $0.cpuPercent > $1.cpuPercent }.prefix(12).map { $0 }
    }
}
