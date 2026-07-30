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

    init(pid: Int, name: String, cpuPercent: Double, memoryMB: Double, cpuHistory: [Double] = []) {
        self.pid = pid
        self.name = name
        self.cpuPercent = cpuPercent
        self.memoryMB = memoryMB
        self.cpuHistory = cpuHistory
        self.displayName = ProcessPowerInfo.extractDisplayName(name)
        self.energyImpact = ProcessPowerInfo.calculateEnergy(cpu: cpuPercent)
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
