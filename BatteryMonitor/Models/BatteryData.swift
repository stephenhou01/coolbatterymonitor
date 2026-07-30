import Foundation

// MARK: - Battery Condition Enum

enum BatteryCondition: String, Codable {
    case normal
    case replaceSoon
    case replaceNow

    var localizedDescription: String {
        switch self {
        case .normal: return L("condition.normal")
        case .replaceSoon: return L("condition.replace_soon")
        case .replaceNow: return L("condition.replace_now")
        }
    }
}

// MARK: - Usage Level Enum (for charging history notes)

enum UsageLevel: String, Codable {
    case heavy
    case moderate
    case light
    case idle

    var localizedDescription: String {
        switch self {
        case .heavy: return L("usage.heavy")
        case .moderate: return L("usage.moderate")
        case .light: return L("usage.light")
        case .idle: return L("usage.idle")
        }
    }

    static func from(ratePerHour: Double) -> UsageLevel {
        if ratePerHour < 20 { return .heavy }
        else if ratePerHour < 35 { return .moderate }
        else if ratePerHour < 50 { return .light }
        else { return .idle }
    }
}

// MARK: - Battery Data

struct BatteryData: Equatable {
    var percent: Int = 0
    var isCharging: Bool = false
    var isOnAC: Bool = false
    /// 分钟数；nil = 系统尚在测算。存数字而不是本地化字符串 —— model 层不碰译文，
    /// 否则切换语言后已有实例不会更新（Observation 追踪不到 body 之外的 L() 调用）。
    var timeRemainingMinutes: Int? = nil
    var amperage: Int = 0       // mA, signed
    var voltage: Double = 0     // V
    var currentPowerWatts: Double = 0
    var chargerWattage: Int = 0   // 0 = no adapter
    var cycleCount: Int = 0
    var maxCapacityPercent: Int = 100
    var condition: BatteryCondition = .normal
    var temperatureCelsius: Double = 0
    var designCapacity: Int = 0  // mAh
    var maxCapacity: Int = 0     // mAh
    var isFullyCharged: Bool = false
    var chargeRatePerHour: Double = 0
    var batteryModel: String = ""
    var firmwareVersion: String = ""
    var lastUpdated: Date = Date()
    /// IOKit 原始硬件数据。有完整默认值，缺字段时各处按 0/空数组优雅降级。
    var hardwareDetail = BatteryHardwareDetail()
}

struct ChargingSession: Identifiable, Equatable, Codable {
    var id: String { "\(date)_\(startTime)" }
    let date: String
    let startTime: String
    let endTime: String
    let startPercent: Int
    let endPercent: Int
    let durationMinutes: Int
    let ratePerHour: Double
    let note: UsageLevel

    init(date: String, startTime: String, endTime: String = "", startPercent: Int, endPercent: Int, durationMinutes: Int, ratePerHour: Double, note: UsageLevel = .moderate) {
        self.date = date
        self.startTime = startTime
        self.endTime = endTime
        self.startPercent = startPercent
        self.endPercent = endPercent
        self.durationMinutes = durationMinutes
        self.ratePerHour = ratePerHour
        self.note = note
    }

    // Backward-compatible decoding: old cache has String for note
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        date = try container.decode(String.self, forKey: .date)
        startTime = try container.decode(String.self, forKey: .startTime)
        endTime = try container.decodeIfPresent(String.self, forKey: .endTime) ?? ""
        startPercent = try container.decode(Int.self, forKey: .startPercent)
        endPercent = try container.decode(Int.self, forKey: .endPercent)
        durationMinutes = try container.decode(Int.self, forKey: .durationMinutes)
        ratePerHour = try container.decode(Double.self, forKey: .ratePerHour)
        // Try enum first, fall back to mapping old Chinese strings
        if let level = try? container.decode(UsageLevel.self, forKey: .note) {
            note = level
        } else if let str = try? container.decode(String.self, forKey: .note) {
            switch str {
            case "重度使用", "heavy": note = .heavy
            case "中度使用", "moderate": note = .moderate
            case "轻度使用", "light": note = .light
            case "息屏/空闲", "idle": note = .idle
            default: note = UsageLevel.from(ratePerHour: ratePerHour)
            }
        } else {
            note = UsageLevel.from(ratePerHour: ratePerHour)
        }
    }
}

// Real-time data point for live charts
struct RealtimeDataPoint: Identifiable {
    let id = UUID()
    let timestamp: Date
    let voltage: Double      // V
    let amperage: Double     // mA (signed)
    let power: Double        // W
    let temperature: Double  // °C
    let percent: Int
}
