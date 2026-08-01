import Foundation

struct ProcessPowerInfo: Identifiable, Equatable {
    var id: Int { pid }  // Stable identity → no re-entry animation flicker on refresh
    let name: String
    let displayName: String
    let cpuPercent: Double
    let memoryMB: Double
    let pid: Int
    let energyImpact: EnergyLevel
    let cpuHistory: [Double]   // 最近若干次采样的 CPU%（末尾为最新）
    let isForeground: Bool

    init(pid: Int, name: String, cpuPercent: Double, memoryMB: Double,
         cpuHistory: [Double] = [], isForeground: Bool = false) {
        self.pid = pid
        self.name = name
        self.cpuPercent = cpuPercent
        self.memoryMB = memoryMB
        self.cpuHistory = cpuHistory
        self.isForeground = isForeground
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

    private static func extractDisplayName(_ fullPath: String) -> String {
        let name = URL(fileURLWithPath: fullPath).lastPathComponent
        return name.replacingOccurrences(of: ".app", with: "")
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
