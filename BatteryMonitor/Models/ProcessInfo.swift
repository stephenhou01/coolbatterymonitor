import Foundation

struct ProcessPowerInfo: Identifiable, Equatable {
    /// 一行现在是一个聚合体（app + 它的子进程），代表 pid 会随子进程进出而变，
    /// 所以身份用稳定的 groupKey 而不是 pid，否则排序变动会让 SwiftUI 错位重建行。
    var id: String { groupKey }
    let name: String
    let displayName: String
    let cpuPercent: Double
    let memoryMB: Double
    let pid: Int
    let energyImpact: EnergyLevel
    let cpuHistory: [Double]   // 最近若干次采样的 CPU%（末尾为最新）
    let isForeground: Bool
    /// 稳定的分组标识：app 行用 `app:<bundleID>`，非 app 行用 `proc:<pid>:<comm>`。
    let groupKey: String
    /// 这一行合并了多少个进程。1 表示没有子进程。
    let processCount: Int
    /// 组内 CPU 最高的那个子进程名。「Terminal 31.6%」不告诉你该关什么，
    /// 「Terminal · claude」才告诉你。
    ///
    /// 判据刻意不是「子进程比主进程更重」：实测这两个值会在相邻采样之间反复交换
    /// （Terminal 主进程 9.6% vs claude 10.8%，下一拍就反过来），那样副标题会每 10 秒
    /// 出现一次又消失一次，行高跟着跳。改成绝对门槛，显示与否是稳定的。
    let topChildName: String?

    init(pid: Int, name: String, cpuPercent: Double, memoryMB: Double,
         cpuHistory: [Double] = [], isForeground: Bool = false,
         groupKey: String? = nil, processCount: Int = 1, topChildName: String? = nil) {
        self.pid = pid
        self.name = name
        self.cpuPercent = cpuPercent
        self.memoryMB = memoryMB
        self.cpuHistory = cpuHistory
        self.isForeground = isForeground
        // 默认用 pid 而不是 name：同名两个进程会撞 ForEach 的 ID 并让行内容错乱。
        self.groupKey = groupKey ?? "pid:\(pid)"
        self.processCount = max(1, processCount)
        self.topChildName = topChildName
        self.displayName = ProcessPowerInfo.extractDisplayName(name)
        self.energyImpact = ProcessPowerInfo.calculateEnergy(cpu: cpuPercent)
    }

    /// Rank real observations without imposing a minimum CPU threshold. A
    /// running app with a 0% delta is idle, not missing. Foreground state and
    /// resident memory provide deterministic tie breakers only when CPU is equal.
    static func rankedForDisplay(_ processes: [ProcessPowerInfo], limit: Int) -> [ProcessPowerInfo] {
        guard limit > 0 else { return [] }
        return Array(processes.sorted { lhs, rhs in
            if abs(lhs.cpuPercent - rhs.cpuPercent) > 0.000_001 {
                return lhs.cpuPercent > rhs.cpuPercent
            }
            if lhs.isForeground != rhs.isForeground {
                return lhs.isForeground
            }
            if abs(lhs.memoryMB - rhs.memoryMB) > 0.000_001 {
                return lhs.memoryMB > rhs.memoryMB
            }
            return lhs.displayName.localizedStandardCompare(rhs.displayName) == .orderedAscending
        }.prefix(limit))
    }

    enum EnergyLevel: String {
        case low = "Low"
        case moderate = "Moderate"
        case high = "High"
        case veryHigh = "Very High"
    }

    /// 只剥尾部的 `.app`，不做全局子串替换。
    /// `replacingOccurrences(of: ".app")` 是任意位置替换，会把反向域名式的进程名打烂：
    /// `com.apple.WebKit.WebContent` → `comle.WebKit.WebContent`。本机有 20 多个
    /// `com.apple.*` 进程，一旦列表覆盖到非 GUI 进程就会全部端到用户面前。
    private static func extractDisplayName(_ fullPath: String) -> String {
        let name = URL(fileURLWithPath: fullPath).lastPathComponent
        return name.hasSuffix(".app") ? String(name.dropLast(4)) : name
    }

    private static func calculateEnergy(cpu: Double) -> EnergyLevel {
        switch cpu {
        case ..<5: return .low
        case ..<20: return .moderate
        case ..<50: return .high
        default: return .veryHigh
        }
    }
}
