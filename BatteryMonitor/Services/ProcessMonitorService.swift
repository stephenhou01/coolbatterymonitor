import Foundation
import Combine
import Darwin

class ProcessMonitorService: ObservableObject {
    @Published var topProcesses: [ProcessPowerInfo] = []

    private var timer: Timer?
    private let refreshInterval: TimeInterval = 5
    private let totalMemMB = Double(ProcessInfo.processInfo.physicalMemory) / 1024.0 / 1024.0
    private var cpuHistoryByPid: [Int32: [Double]] = [:]
    private let maxHistoryPoints = 24

    // Previous CPU time samples for delta calculation
    private var previousCPUTimes: [Int32: (user: UInt64, system: UInt64, timestamp: TimeInterval)] = [:]

    func startMonitoring() {
        fetchProcesses()
        timer = Timer(timeInterval: refreshInterval, repeats: true) { [weak self] _ in
            self?.fetchProcesses()
        }
        RunLoop.main.add(timer!, forMode: .common)
    }

    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }

    func fetchProcesses() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let processes = self.getTopProcesses()

            DispatchQueue.main.async {
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

            // Calculate CPU% from delta of CPU times
            let totalCPUTime = taskInfo.pti_total_user &+ taskInfo.pti_total_system
            var cpuPercent: Double = 0

            if let prev = previousCPUTimes[pid] {
                let prevTotal = prev.user &+ prev.system
                let delta = totalCPUTime > prevTotal ? totalCPUTime - prevTotal : 0
                let timeDelta = now - prev.timestamp
                if timeDelta > 0 {
                    // Convert nanoseconds to percentage
                    cpuPercent = Double(delta) / (timeDelta * 1_000_000_000.0) / Double(cpuCount) * 100.0
                }
            }
            previousCPUTimes[pid] = (user: taskInfo.pti_total_user, system: taskInfo.pti_total_system, timestamp: now)

            // Skip very low CPU processes
            guard cpuPercent >= 0.1 else { continue }

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
