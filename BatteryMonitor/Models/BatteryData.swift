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
    /// `hw.model`，例如 Mac16,12；用于匹配Apple公开的设计能量与续航规格。
    var modelIdentifier: String = ""
    /// IOKit 原始硬件数据。有完整默认值，缺字段时各处按 0/空数组优雅降级。
    var hardwareDetail = BatteryHardwareDetail()

    var modelSpecification: BatteryModelSpecification? {
        BatteryModelSpecification.lookup(modelIdentifier: modelIdentifier)
    }

    /// 与主界面统一的系统口径健康度。无法取得预留容量时退回裸容量比例。
    var systemHealthPercent: Double? {
        hardwareDetail.systemHealthPercent
    }

    /// 产品统一健康度口径，单位为百分比。
    var systemHealth: Double? { systemHealthPercent }

    /// 这块电池目前充满时可提供的能量。统一用机型额定Wh缩放，避免用满电瞬时
    /// 高电压乘mAh而高估整段放电能量。
    var currentFullEnergyWh: Double? {
        guard let spec = modelSpecification,
              hardwareDetail.designCapacity > 0,
              hardwareDetail.appleRawMaxCapacity > 0 else { return nil }
        return spec.designEnergyWh
            * Double(hardwareDetail.appleRawMaxCapacity)
            / Double(hardwareDetail.designCapacity)
    }

    /// 当前真正剩余的能量；当前mAh最多按FCC封顶。
    var remainingEnergyWh: Double? {
        guard let spec = modelSpecification,
              hardwareDetail.designCapacity > 0,
              hardwareDetail.presentRawFields.contains("AppleRawCurrentCapacity"),
              hardwareDetail.appleRawCurrentCapacity >= 0,
              hardwareDetail.appleRawMaxCapacity > 0 else { return nil }
        let current = min(hardwareDetail.appleRawCurrentCapacity,
                          hardwareDetail.appleRawMaxCapacity)
        return spec.designEnergyWh * Double(current) / Double(hardwareDetail.designCapacity)
    }

    /// 插电时也可展示的“按当前电脑状态拔电预计”；这是推导值，不是系统剩余时间。
    var unplugEstimateMinutes: Int? {
        guard let energy = remainingEnergyWh, currentPowerWatts > 0.5 else { return nil }
        let minutes = max(0, Int((energy / currentPowerWatts * 60).rounded()))
        return RuntimeSample.isValid(minutes: minutes) ? minutes : nil
    }

    /// Apple官方网页续航隐含的平均测试功耗。
    var officialImpliedPowerWatts: Double? {
        guard let spec = modelSpecification, spec.officialWebHours > 0 else { return nil }
        return spec.designEnergyWh / spec.officialWebHours
    }

    /// 与产品指标命名一致；单位为 W。
    var officialImpliedPower: Double? { officialImpliedPowerWatts }

    /// 当前电池容量若回到Apple网页测试负载，大约可使用多久。
    var sameLoadRuntimeHours: Double? {
        guard let energy = currentFullEnergyWh,
              let power = officialImpliedPowerWatts,
              power > 0 else { return nil }
        return energy / power
    }

    /// 与产品指标命名一致；单位为小时。
    var sameLoadRuntime: Double? { sameLoadRuntimeHours }

    var averageTelemetryPowerWatts: Double? {
        hardwareDetail.averageTelemetryPowerWatts
    }

    /// 与产品指标命名一致；单位为 W。
    var averageTelemetryPower: Double? { averageTelemetryPowerWatts }
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
struct RealtimeDataPoint: Identifiable, Codable {
    let timestamp: Date
    let voltage: Double      // V
    let amperage: Double     // mA (signed)
    let power: Double        // W
    let temperature: Double  // °C
    let percent: Int
    /// Whole-Mac input power reported by PowerTelemetryData while connected to AC.
    /// This is intentionally separate from `power`, which is the Mac's load.
    let inputPower: Double?  // W
    let adapterVoltage: Double? // negotiated V
    let adapterCurrent: Double? // negotiated A
    /// Whether the adapter was attached when this sample was taken. Recorded
    /// because `inputPower` cannot stand in for it: SystemPowerIn is measured to
    /// drop to 0 while plugged in, so "no input reading" and "no adapter" are
    /// genuinely different states and only this flag distinguishes them.
    let isOnAC: Bool
    /// `AppleRawCurrentCapacity` in mAh at this sample. Recorded alongside
    /// `percent` rather than instead of it because charge *speed* cannot be
    /// differenced off an integer percentage: over a two-minute window the
    /// displayed SOC moves 2–3 points, so ±1 of quantisation is a ±35% error on
    /// the rate. This counter is ~1 mAh out of ~5000. nil when the field is absent.
    let rawCurrentCapacity: Int?
    /// Values captured with the same timestamp so the overview help charts and
    /// the Trends page can use one honest history source instead of rebuilding
    /// old readings from the latest battery snapshot.
    let adapterRatedPower: Double?
    let adapterOutputPower: Double?
    let chargingPower: Double?
    let cycleCount: Int?
    let healthPercent: Double?
    /// Raw samples have a weight of one. Three-minute archive buckets carry the
    /// number of real polls they summarize, which lets an interrupted bucket be
    /// resumed after relaunch without counting an average as one fresh sample.
    var sampleCount: Int = 1

    var id: Date { timestamp }

    init(
        timestamp: Date,
        voltage: Double,
        amperage: Double,
        power: Double,
        temperature: Double,
        percent: Int,
        inputPower: Double? = nil,
        adapterVoltage: Double? = nil,
        adapterCurrent: Double? = nil,
        isOnAC: Bool = false,
        rawCurrentCapacity: Int? = nil,
        adapterRatedPower: Double? = nil,
        adapterOutputPower: Double? = nil,
        chargingPower: Double? = nil,
        cycleCount: Int? = nil,
        healthPercent: Double? = nil,
        sampleCount: Int = 1
    ) {
        self.timestamp = timestamp
        self.voltage = voltage
        self.amperage = amperage
        self.power = power
        self.temperature = temperature
        self.percent = percent
        self.inputPower = inputPower
        self.adapterVoltage = adapterVoltage
        self.adapterCurrent = adapterCurrent
        self.isOnAC = isOnAC
        self.rawCurrentCapacity = rawCurrentCapacity
        self.adapterRatedPower = adapterRatedPower
        self.adapterOutputPower = adapterOutputPower
        self.chargingPower = chargingPower
        self.cycleCount = cycleCount
        self.healthPercent = healthPercent
        self.sampleCount = max(1, sampleCount)
    }

    private enum CodingKeys: String, CodingKey {
        case timestamp, voltage, amperage, power, temperature, percent
        case inputPower, adapterVoltage, adapterCurrent, isOnAC, rawCurrentCapacity
        case adapterRatedPower, adapterOutputPower, chargingPower, cycleCount, healthPercent
        case sampleCount
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        timestamp = try values.decode(Date.self, forKey: .timestamp)
        voltage = try values.decode(Double.self, forKey: .voltage)
        amperage = try values.decode(Double.self, forKey: .amperage)
        power = try values.decode(Double.self, forKey: .power)
        temperature = try values.decode(Double.self, forKey: .temperature)
        percent = try values.decode(Int.self, forKey: .percent)
        inputPower = try values.decodeIfPresent(Double.self, forKey: .inputPower)
        adapterVoltage = try values.decodeIfPresent(Double.self, forKey: .adapterVoltage)
        adapterCurrent = try values.decodeIfPresent(Double.self, forKey: .adapterCurrent)
        isOnAC = try values.decodeIfPresent(Bool.self, forKey: .isOnAC) ?? false
        rawCurrentCapacity = try values.decodeIfPresent(Int.self, forKey: .rawCurrentCapacity)
        adapterRatedPower = try values.decodeIfPresent(Double.self, forKey: .adapterRatedPower)
        adapterOutputPower = try values.decodeIfPresent(Double.self, forKey: .adapterOutputPower)
        chargingPower = try values.decodeIfPresent(Double.self, forKey: .chargingPower)
        cycleCount = try values.decodeIfPresent(Int.self, forKey: .cycleCount)
        healthPercent = try values.decodeIfPresent(Double.self, forKey: .healthPercent)
        sampleCount = max(1, try values.decodeIfPresent(Int.self, forKey: .sampleCount) ?? 1)
    }
}
