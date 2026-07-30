import Foundation

// MARK: - Hardware Detail
//
// 从 IOKit Registry (AppleSmartBattery) 读到的原始硬件数据。字段集是在真机上
// dump 过 registry 后按「实际存在」筛的，不是照文档抄的 —— 否则表格会是一屏「—」。
//
// 已知的机型差异见 BatteryService.parseHardwareDetail：
//   · AdapterDetails 的 Watts/AdapterVoltage/Current/Description 只在插电时出现，
//     拔掉后整个子字典只剩 {FamilyCode: 0}
//   · PowerTelemetryData 的瞬时字段（SystemPowerIn/VoltageIn/CurrentIn/
//     WallEnergyEstimate/AdapterEfficiencyLoss）在电池供电时全为 0，只有
//     SystemLoad 和 BatteryPower 是活的；Accumulated* 系列一直有值
//   · MaxCapacity / CurrentCapacity 在 Apple Silicon 上是百分比而非 mAh，
//     真实容量要读 AppleRawMaxCapacity / AppleRawCurrentCapacity

struct BatteryHardwareDetail: Equatable {

    // MARK: 电芯级
    var cellVoltages: [Int] = []          // mV，每节电芯
    var qmax: [Int] = []                  // mAh，各电芯库仑计最大容量
    var weightedRa: [Int] = []            // mΩ，各电芯加权内阻
    var presentDOD: [Int] = []            // %，各电芯当前放电深度

    /// 电芯压差（mV）。最大最小之差，衡量电芯一致性。
    var cellVoltageDelta: Int? {
        guard let mx = cellVoltages.max(), let mn = cellVoltages.min(), cellVoltages.count > 1 else { return nil }
        return mx - mn
    }

    // MARK: 容量与寿命
    var nominalChargeCapacity: Int = 0
    var appleRawMaxCapacity: Int = 0
    var appleRawCurrentCapacity: Int = 0
    var packReserve: Int = 0
    var designCapacity: Int = 0
    var designCycleCount: Int = 0          // DesignCycleCount9C，本机 = 1000

    /// 原始容量保持率（%）。用 AppleRaw 而非 MaxCapacity —— 后者在 AS 上是百分比。
    var rawHealthPercent: Double? {
        guard designCapacity > 0, appleRawMaxCapacity > 0 else { return nil }
        return Double(appleRawMaxCapacity) / Double(designCapacity) * 100.0
    }

    /// 循环使用率（0–1）
    var cycleUsage: Double? {
        guard designCycleCount > 0, cycleCount >= 0 else { return nil }
        return Double(cycleCount) / Double(designCycleCount)
    }
    var cycleCount: Int = 0

    // MARK: 电气
    var packVoltage: Int = 0               // mV
    var instantAmperage: Int = 0           // mA，signed
    var smoothedAmperage: Int = 0          // mA，signed
    var virtualTemperature: Double = 0     // °C，含热模型补偿
    var systemPowerWatts: Double = 0       // W，BatteryData.SystemPower 直接是 Double

    // MARK: 充电器（仅插电时有值）
    var adapterWatts: Int = 0
    var adapterVoltage: Int = 0            // mV
    var adapterCurrent: Int = 0            // mA
    var adapterDescription: String = ""    // "pd charger" / "magsafe"
    var adapterIsWireless: Bool = false
    var usbHvcMenu: [PDProfile] = []

    /// PD 协商菜单里的一档。用结构体而非元组，好让 Equatable 自动合成。
    struct PDProfile: Equatable {
        let voltage: Int    // mV
        let current: Int    // mA
    }

    // MARK: 充电控制
    var chargingVoltageLimit: Int = 0      // mV
    var chargingCurrentLimit: Int = 0      // mA
    var notChargingReason: Int = 0         // bitmask
    var chargerID: Int = 0

    // MARK: 功耗遥测
    var systemLoad: Int = 0                // mW，电池供电时也有值
    var batteryPower: Int = 0              // mW，signed（放电为负）
    var systemPowerIn: Int = 0             // mW，仅插电
    var systemVoltageIn: Int = 0           // mV，仅插电
    var systemCurrentIn: Int = 0           // mA，仅插电
    var adapterEfficiencyLoss: Int = 0     // mW，仅插电
    var accumulatedWallEnergy: Int = 0     // 累计，一直有值

    /// 适配器效率（%）。**实测常为 nil**，不要指望它。
    ///
    /// 瞬时 AdapterEfficiencyLoss 有噪声会翻负（实测 -104 mW），而累计值
    /// AccumulatedAdapterEfficiencyLoss / AccumulatedSystemPowerIn 比值 ≈ 3.1，
    /// 物理上也讲不通（损耗不可能是输入的 3 倍）。所以只在损耗落在合理区间内
    /// 才给结果，否则返回 nil 让 UI 隐藏该行 —— 宁可不显示，也不显示一个编的效率。
    var adapterEfficiency: Double? {
        guard systemPowerIn > 0,
              adapterEfficiencyLoss > 0,
              adapterEfficiencyLoss < systemPowerIn else { return nil }
        let total = Double(systemPowerIn)
        return (total - Double(adapterEfficiencyLoss)) / total * 100.0
    }

    // MARK: 身份
    var serialNumber: String = ""
    var gaugeChip: String = ""             // DeviceName，如 "bq40z651"
    var gaugeFirmwareVersion: Int = 0
    var chemistryID: Int = 0
    var dataFlashWriteCount: Int = 0
    var permanentFailureStatus: Int = 0
    var cellDisconnectCount: Int = 0

    // MARK: 寿命统计（LifetimeData）
    var totalOperatingMinutes: Int = 0
    var averageTemperature: Double = 0     // °C（原始值 ÷10）
    var minimumTemperature: Int = 0        // °C，直接值
    var maximumTemperature: Int = 0        // °C，直接值
    var maximumChargeCurrent: Int = 0      // mA
    var maximumDischargeCurrent: Int = 0   // mA，已是负数
    var minimumPackVoltage: Int = 0        // mV
    var maximumPackVoltage: Int = 0        // mV
    var temperatureSamples: Int = 0

    // MARK: 当日 SOC 快照（只有当天，做周报要 app 自己攒历史）
    var dailyMaxSoc: Int = 0
    var dailyMinSoc: Int = 0

    // MARK: 平台
    var architecture: ChipArchitecture = .unknown
    var chipModel: String = ""             // "Apple M4"
    var osVersion: String = ""             // "15.5" / build

    enum ChipArchitecture: String {
        case appleSilicon = "Apple Silicon"
        case intel = "Intel"
        case unknown = "—"
    }

    /// 是否拿到了插电才有的那批字段
    var hasAdapterData: Bool { adapterWatts > 0 || adapterVoltage > 0 }
    /// 瞬时功耗遥测是否可用（电池供电时这批是 0）
    var hasLiveTelemetry: Bool { systemPowerIn > 0 }
}

// MARK: - Battery Age Estimate

/// 电池年龄估算结果。`isDecodedFromHardware` 为 true 表示来自真实制造日期，
/// 否则是按循环次数推的经验估算（UI 必须标注「估算值」）。
struct BatteryAgeEstimate: Equatable {
    let years: Int
    let months: Int
    let isDecodedFromHardware: Bool

    var totalMonths: Int { years * 12 + months }
}

enum BatteryAgeEstimator {

    // MARK: 可调参数
    //
    // Apple Silicon 上 ManufactureDate 是厂商 ASCII 批号、DateOfFirstUse 恒为 0,
    // 所以拿不到真实出厂日期,只能按「循环次数 ÷ 每日充放频率」反推使用时长。
    // 这几个常量是经验值,单独抽出来方便后续按实测数据调参。

    /// 假定的平均每日循环次数。1.3 ≈ 每天一次完整充放（略多于一次浅充）。
    static let assumedCyclesPerDay: Double = 1.3
    /// 健康度低于此阈值(%)时认为老化偏快
    static let fastAgingHealthThreshold: Double = 90
    /// 老化偏快时对估算年龄的修正系数
    static let fastAgingCorrection: Double = 0.85
    /// Smart Battery 规范里 ManufactureDate 的无效哨兵值上限
    static let manufactureDateSentinel: Int = 0xFFFF

    /// 按循环次数与健康度估算电池年龄。
    /// - Parameters:
    ///   - cycleCount: 当前循环次数
    ///   - healthPercent: 容量保持率(%)，用于老化速度修正
    /// - Returns: 无法估算时返回 nil（循环次数为 0 或缺数据）
    static func estimate(cycleCount: Int, healthPercent: Double?) -> BatteryAgeEstimate? {
        guard cycleCount > 0 else { return nil }

        var days = Double(cycleCount) / assumedCyclesPerDay
        // 健康度偏低说明单次循环损耗更大 —— 相同循环数下实际使用时间可能更短
        if let h = healthPercent, h > 0, h < fastAgingHealthThreshold {
            days *= fastAgingCorrection
        }

        let totalMonths = max(0, Int((days / 30.44).rounded()))
        return BatteryAgeEstimate(years: totalMonths / 12,
                                  months: totalMonths % 12,
                                  isDecodedFromHardware: false)
    }

    /// Intel 机型的 ManufactureDate 若符合 Smart Battery 规范（bit0-4 日、
    /// bit5-8 月、bit9-15 年偏移 1980），优先用真实出厂日期。
    /// Apple Silicon 上该字段是 ASCII 批号（远大于 0xFFFF），会走 nil 分支。
    static func decodeManufactureDate(_ raw: Int, now: Date = Date(),
                                      calendar: Calendar = .current) -> BatteryAgeEstimate? {
        guard raw > 0, raw <= manufactureDateSentinel else { return nil }
        let day = raw & 0x1F
        let month = (raw >> 5) & 0x0F
        let year = 1980 + (raw >> 9)
        guard (1...31).contains(day), (1...12).contains(month), year >= 1990 else { return nil }

        var comps = DateComponents()
        comps.year = year; comps.month = month; comps.day = day
        guard let made = calendar.date(from: comps), made <= now else { return nil }

        let diff = calendar.dateComponents([.year, .month], from: made, to: now)
        return BatteryAgeEstimate(years: max(0, diff.year ?? 0),
                                  months: max(0, diff.month ?? 0),
                                  isDecodedFromHardware: true)
    }

    /// 组合入口：能解码真实日期就用真实的，否则退到经验估算。
    static func resolve(manufactureDateRaw: Int, cycleCount: Int,
                        healthPercent: Double?) -> BatteryAgeEstimate? {
        decodeManufactureDate(manufactureDateRaw)
            ?? estimate(cycleCount: cycleCount, healthPercent: healthPercent)
    }
}
