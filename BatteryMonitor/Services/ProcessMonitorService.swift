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
                                    now: TimeInterval) -> Double {
        var bsd = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &bsd, size) == size else { return 0 }
        let started = TimeInterval(bsd.pbi_start_tvsec) + TimeInterval(bsd.pbi_start_tvusec) / 1_000_000
        let age = now - started
        guard age > 1 else { return 0 }   // 刚起来的进程平均值没意义
        // Match Activity Monitor's process CPU convention: 100% is one fully
        // occupied core, so a multi-threaded application may exceed 100%.
        return Double(totalCPUTime) / (age * 1_000_000_000.0) * 100.0
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
        let candidates = applicationCandidates()
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let processes = self.getTopProcesses(candidates: candidates)

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
                        cpuHistory: history,
                        isForeground: proc.isForeground
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
    }

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

    private func getTopProcesses(candidates: [ApplicationCandidate]) -> [RawProcess] {
        var processes: [RawProcess] = []
        let now = Date().timeIntervalSince1970
        for candidate in candidates {
            let pid = candidate.pid

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
                    cpuPercent = Double(delta) / (timeDelta * 1_000_000_000.0) * 100.0
                } else {
                    cpuPercent = prev.lastPercent
                }
            } else {
                // 兜底：用进程生命周期平均 CPU%（总 CPU 时间 ÷ 进程已存活时长）。
                // 单次采样就能算，是真实值而非估算，只是反映的是历史平均而非瞬时。
                cpuPercent = lifetimeAverageCPU(pid: pid, totalCPUTime: totalCPUTime,
                                                now: now)
            }
            previousCPUTimes[pid] = (user: taskInfo.pti_total_user,
                                     system: taskInfo.pti_total_system,
                                     timestamp: now,
                                     lastPercent: cpuPercent)

            // Memory in MB (resident size)
            let memoryMB = Double(taskInfo.pti_resident_size) / 1024.0 / 1024.0

            // A zero delta is a valid observation: the app is running but idle.
            // Keeping it avoids turning an idle ten-second window into a false
            // "no applications" state.
            processes.append(RawProcess(
                pid: Int(pid),
                name: candidate.name,
                groupIdentifier: candidate.groupIdentifier,
                cpuPercent: max(cpuPercent, 0),
                memoryMB: memoryMB,
                isForeground: candidate.isForeground
            ))
        }

        // The workspace can expose more than one regular instance of an app.
        // Combine those real main-process readings so the menu does not show the
        // same recognizable app multiple times. This is CPU activity context,
        // never a fabricated watt allocation.
        var grouped: [String: RawProcess] = [:]
        for process in processes {
            guard let current = grouped[process.groupIdentifier] else {
                grouped[process.groupIdentifier] = process
                continue
            }
            grouped[process.groupIdentifier] = RawProcess(
                pid: min(current.pid, process.pid),
                name: current.name,
                groupIdentifier: current.groupIdentifier,
                cpuPercent: current.cpuPercent + process.cpuPercent,
                memoryMB: current.memoryMB + process.memoryMB,
                isForeground: current.isForeground || process.isForeground
            )
        }

        // Clean up samples for applications that have exited.
        let livePids = Set(candidates.map(\.pid))
        previousCPUTimes = previousCPUTimes.filter { livePids.contains($0.key) }

        return Array(grouped.values)
    }
}
