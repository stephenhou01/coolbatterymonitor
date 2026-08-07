import Foundation
import Darwin

/// 全机 CPU 占用率，来自 `host_statistics(HOST_CPU_LOAD_INFO)`。
///
/// 存在的理由是诚实：进程列表只覆盖当前用户可读的进程，`proc_pidinfo` 对 root 进程
/// 一律失败，所以 WindowServer、kernel_task 这些经常是真正大头的进程永远不在列表里。
/// 实测本机全机 28.0% 忙，可读进程只解释了其中约 1/4。有了全机数，缺口就能标成
/// 「未归因负载」而不是假装列表是全量。
///
/// 这个调用不需要任何 entitlement，也不会弹窗（实测返回 KERN_SUCCESS）。
enum SystemCPULoad {

    /// `mach_host_self()` 每次调用都返回一个新的 send right，不 deallocate 就漏一个
    /// port 引用。10 秒一次跑一个月是 26 万次，所以只取一次。
    private static let hostPort: host_t = mach_host_self()

    /// 累计 tick 快照。`natural_t` 是 UInt32，约 50 天 uptime 后会回绕，
    /// 所以差值一律用 `&-`，不能先比大小再相减。
    struct Sample: Sendable, Equatable {
        let user: UInt32
        let system: UInt32
        let idle: UInt32
        let nice: UInt32
    }

    static func sample() -> Sample? {
        var info = host_cpu_load_info()
        // HOST_CPU_LOAD_INFO_COUNT 这个宏在 Swift 里不可用（"structure not supported"），
        // 它的定义就是结构体大小除以 integer_t 大小。
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.stride
                                           / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(hostPort, HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        // cpu_ticks 是 4 元 UInt32 元组，不能用变量下标，只能按 CPU_STATE_* 的顺序取：
        // 0 = USER, 1 = SYSTEM, 2 = IDLE, 3 = NICE
        return Sample(user: info.cpu_ticks.0, system: info.cpu_ticks.1,
                      idle: info.cpu_ticks.2, nice: info.cpu_ticks.3)
    }

    /// 两次快照之间的全机忙碌百分比。
    ///
    /// **注意口径**：这里返回的是 0…100 的**整机容量**百分比（所有核加起来算 100%），
    /// 与 `ProcessPowerInfo.cpuPercent` 的「100% = 占满一个核」不是同一个单位。
    /// 想把两者放在一起比较，必须先用 `machinePercent(perCorePercent:coreCount:)` 换算，
    /// 否则 10 核机器上「整机 30%」减「Chrome 300%」会得到负数。
    ///
    /// 返回 nil 表示这一拍没有可用差值（首次采样、或两次采样之间 tick 没动）。
    static func busyPercent(from previous: Sample, to current: Sample) -> Double? {
        let user = Double(current.user &- previous.user)
        let system = Double(current.system &- previous.system)
        let nice = Double(current.nice &- previous.nice)
        let idle = Double(current.idle &- previous.idle)
        let total = user + system + nice + idle
        guard total > 0 else { return nil }
        return min(100, max(0, (user + system + nice) / total * 100))
    }

    /// 把「100% = 一个核」的读数换算成「100% = 整机」。
    /// 这是把进程读数和全机读数放到同一个坐标系里的唯一正确方式。
    static func machinePercent(perCorePercent: Double, coreCount: Int) -> Double {
        guard perCorePercent.isFinite, perCorePercent > 0 else { return 0 }
        return min(100, perCorePercent / Double(max(1, coreCount)))
    }

    /// 全机忙碌里归不到可见进程头上的那部分 —— WindowServer、kernel_task 和其他
    /// root 进程。两个入参必须都已经是整机口径。
    static func systemPercent(machineBusyPercent: Double, visibleMachinePercent: Double) -> Double {
        guard machineBusyPercent.isFinite, visibleMachinePercent.isFinite else { return 0 }
        return min(100, max(0, machineBusyPercent - visibleMachinePercent))
    }
}

/// 一次全机 CPU 观测的结果，直接给 UI 用。三个数都是整机口径（0…100）。
struct SystemCPUSnapshot: Sendable, Equatable {
    /// 全机忙碌百分比。nil 表示还没有第二次采样，UI 应当显示「—」而不是 0.0%。
    let machineBusyPercent: Double?
    /// 可见进程合计（已从每核口径换算成整机口径）。
    let visiblePercent: Double
    /// 剩下那部分是未归因负载，包含沙箱读不到的系统进程与采样差额。
    /// machineBusyPercent 为 nil 时也是 nil。
    let systemPercent: Double?

    static let unavailable = SystemCPUSnapshot(machineBusyPercent: nil, visiblePercent: 0,
                                               systemPercent: nil)

    init(machineBusyPercent: Double?, visiblePercent: Double, systemPercent: Double?) {
        self.machineBusyPercent = machineBusyPercent
        self.visiblePercent = visiblePercent
        self.systemPercent = systemPercent
    }

    /// 从「每核口径」的进程合计和一对 tick 快照构造。
    init(machineBusy: Double?, visiblePerCorePercent: Double, coreCount: Int) {
        let visible = SystemCPULoad.machinePercent(perCorePercent: visiblePerCorePercent,
                                                  coreCount: coreCount)
        self.machineBusyPercent = machineBusy
        self.visiblePercent = visible
        self.systemPercent = machineBusy.map {
            SystemCPULoad.systemPercent(machineBusyPercent: $0, visibleMachinePercent: visible)
        }
    }
}
