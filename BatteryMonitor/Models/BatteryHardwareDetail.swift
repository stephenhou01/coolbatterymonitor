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

struct BatteryCarrierModeDetail: Equatable, Sendable {
    var highVoltage: Int?
    var lowVoltage: Int?
    var status: Int?
}

struct BatteryPortControllerDetail: Identifiable, Equatable, Sendable {
    let index: Int
    var attachCount: Int?
    var detachCount: Int?
    var capabilityMismatch: Int?
    var electionFailReason: Int?

    var id: Int { index }
}

struct BatteryHardwareDetail: Equatable {

    /// Exact raw paths that were present in the latest IOKit snapshot.
    ///
    /// Several older model properties intentionally remain non-optional because
    /// the consumer calculations use numeric fallbacks. The evidence table must
    /// still distinguish a real hardware `0` from an absent field, so it checks
    /// this set before rendering those raw values.
    var presentRawFields: Set<String> = []

    // MARK: 电芯级
    var cellVoltages: [Int] = []          // mV，每节电芯
    var qmax: [Int] = []                  // mAh，各电芯库仑计最大容量
    var weightedRa: [Int] = []            // mΩ，各电芯加权内阻
    var presentDOD: [Int] = []            // %，各电芯当前放电深度
    /// 本机只有两个 0，而电池是三芯；保留原值用于审计，不参与评分。
    var cellWom: [Int]? = nil
    /// Ra00...Ra14，电量计在不同放电深度下的15点内阻表。
    var raCurve: [Int]? = nil
    /// 0 在本机表示不可用；仍须和字段缺失区分开。
    var chemicalWeightedRa: Int? = nil

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
    /// Apple Silicon 上通常是0–100百分比，Intel上也可能是mAh；保留原值。
    var currentCapacityRaw: Int? = nil
    var maxCapacityRaw: Int? = nil
    /// 与 AppleRawMaxCapacity 重复的电量计补偿副本，用于交叉核验。
    var fccComp1: Int? = nil
    var fccComp2: Int? = nil

    /// 原始容量保持率（%）：实测满充容量 ÷ 设计容量，不做任何修正。
    /// **比系统「设置 → 电池 → 最大容量」显示的数低**，两者定义不同，见
    /// `systemHealthPercent`。这个数只给硬件表格用。
    var rawHealthPercent: Double? {
        guard designCapacity > 0, appleRawMaxCapacity > 0 else { return nil }
        return Double(appleRawMaxCapacity) / Double(designCapacity) * 100.0
    }

    /// 与 macOS「设置 → 电池 → 电池健康 → 最大容量」一致的容量保持率（%）。
    ///
    /// 公式是逆推出来的：`(AppleRawMaxCapacity + PackReserve) / (DesignCapacity - PackReserve)`。
    /// PackReserve 是电池预留、不暴露给用户的缓冲容量；Apple 把它加回分子（电芯
    /// 实际能装这么多）又从分母减掉（用户可见的设计容量不含缓冲）。
    ///
    /// 实测本机：(4111 + 127) / (4629 - 127) = 94.14% → 系统显示 94%，
    /// 而裸比值是 88.8%。穷举过的其他候选公式分别落在 89% / 92%，只有这个对得上。
    ///
    /// **注意这是逆向推断，只在一台机器上验证过。** 之所以以它为主显示：用户会拿
    /// 系统设置对照，差 6 个点只会被当成我们算错，可信度直接归零。若日后在别的
    /// 机型上发现不符，改这里一处即可。
    var systemHealthPercent: Double? {
        guard designCapacity > 0, appleRawMaxCapacity > 0, packReserve >= 0,
              designCapacity > packReserve else { return rawHealthPercent }
        return Double(appleRawMaxCapacity + packReserve)
             / Double(designCapacity - packReserve) * 100.0
    }

    /// 产品统一健康度口径，单位为百分比。
    var systemHealth: Double? { systemHealthPercent }

    /// 「化学上存在但取不出来」的电荷（mAh）。
    ///
    /// = min(Qmax) − FCC。**这是电量计自己算的数**，不是我们估的：Impedance Track
    /// 用 Ra 阻抗表推算出「放到这里端电压就会跌破截止线」，把这部分从可用容量里扣掉。
    /// 串联取 min，因为任何一节先到截止整组就得停。
    /// （早先我用自建物理模型估过 674 mAh，同量级，但这个 520 才是权威值。）
    var unusableCharge: Int? {
        guard let q = learnedChemicalCapacity else { return nil }
        return q - appleRawMaxCapacity
    }

    /// 本次从满充到当前已经使用的容量；充电后可恢复，不属于老化。
    var usedSinceFullCapacity: Int? {
        guard presentRawFields.contains("AppleRawCurrentCapacity"),
              appleRawMaxCapacity > 0, appleRawCurrentCapacity >= 0,
              appleRawCurrentCapacity <= appleRawMaxCapacity else { return nil }
        return appleRawMaxCapacity - appleRawCurrentCapacity
    }

    /// 电量计学习到的整包化学容量，以串联电芯中最弱一节为边界。
    var learnedChemicalCapacity: Int? {
        guard let q = qmax.min(), designCapacity > 0, appleRawMaxCapacity > 0,
              q >= appleRawMaxCapacity, q <= designCapacity else { return nil }
        return q
    }

    /// 设计容量与已学习化学容量之间的差额。只有在 Qmax 有效且边界合理时
    /// 才能把它单独称为“真正老化掉”的部分。
    var permanentChemicalLoss: Int? {
        guard let learnedChemicalCapacity else { return nil }
        return designCapacity - learnedChemicalCapacity
    }

    /// 相对设计容量的当前满充总差额（mAh）：出厂设计容量 − 当前可用满充。
    /// 它同时包含 Qmax 学到的化学容量下降，以及受阻抗/截止条件影响而暂时
    /// 取不出来的部分，不能把整个差额都武断解释为永久化学老化。
    var chargeDeficitTotal: Int? {
        guard designCapacity > 0, appleRawMaxCapacity > 0,
              designCapacity > appleRawMaxCapacity else { return nil }
        return designCapacity - appleRawMaxCapacity
    }

    /// 平均每循环扣押的电荷（mAh）。
    /// ⚠️ 只用于描述**已发生**的事，不可用于外推寿命 —— 锂电衰减前期快后期趋平，
    /// 线性外推会算出荒谬的短寿命。剩余寿命请以额定循环数为准。
    var chargeDeficitPerCycle: Double? {
        guard let total = chargeDeficitTotal, cycleCount > 0 else { return nil }
        return Double(total) / Double(cycleCount)
    }

    /// 距电量计上次成功学习 Qmax 过了多少循环。越小，健康度读数越新鲜可信。
    var calibrationAgeCycles: Int? {
        guard cycleCountLastQmax > 0, cycleCount >= cycleCountLastQmax else { return nil }
        return cycleCount - cycleCountLastQmax
    }

    /// 循环使用率（0–1）
    var cycleUsage: Double? {
        guard designCycleCount > 0, cycleCount >= 0 else { return nil }
        return Double(cycleCount) / Double(designCycleCount)
    }
    var cycleCount: Int = 0

    /// 电量计自报的本次发布时刻（顶层 UpdateTime，epoch 秒）。实测每 60 秒精确推进
    /// 一次，所有测量类字段都跟着它变，所以它才是这批读数的真实年龄基准；我们的轮询
    /// 时刻只说明「我们什么时候去看」。缺字段或值不合理时为 nil。
    var gaugeUpdateTime: Date? = nil

    /// 上一次发布到这一次发布之间实际隔了多久，由服务层比对连续两个 `UpdateTime`
    /// 得到。实测通常是 60 秒，但插拔电源会让节拍重置，所以倒计时用实测周期而不是
    /// 常量——观察到一次真实间隔之后，下一次预测就是准的。首次读取或间隔不合理时
    /// 为 nil，由调用方回落到 60 秒。
    var gaugePublishInterval: TimeInterval? = nil

    // MARK: 系统续航原始值
    var timeRemainingRaw: Int? = nil
    var avgTimeToEmpty: Int? = nil
    var avgTimeToFull: Int? = nil
    var batteryInvalidWakeSeconds: Int? = nil

    // MARK: 电气
    var packVoltage: Int = 0               // mV
    var voltageRaw: Int? = nil             // Voltage，mV
    var appleRawBatteryVoltage: Int? = nil // AppleRawBatteryVoltage，mV
    var temperatureRaw: Int? = nil         // 不同平台标度不同，转换见 decodeTemperature
    var virtualTemperatureRaw: Int? = nil  // VirtualTemperature，保留电量计原始整数
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
    var carrierMode: BatteryCarrierModeDetail? = nil
    var portControllers: [BatteryPortControllerDetail] = []

    // MARK: 功耗遥测
    var systemLoad: Int = 0                // mW，电池供电时也有值
    var batteryPower: Int = 0              // mW，signed（放电为负）
    var systemPowerIn: Int = 0             // mW，仅插电
    var systemVoltageIn: Int = 0           // mV，仅插电
    var systemCurrentIn: Int = 0           // mA，仅插电
    var adapterEfficiencyLoss: Int = 0     // mW，仅插电
    var accumulatedWallEnergy: Int = 0     // 累计，一直有值
    var accumulatedSystemLoad: Int64? = nil
    var systemLoadAccumulatorCount: Int64? = nil

    /// 电量计累计遥测给出的本机长期平均功耗（W）。
    var averageTelemetryPowerWatts: Double? {
        guard let accumulatedSystemLoad,
              let systemLoadAccumulatorCount,
              systemLoadAccumulatorCount > 0 else { return nil }
        return Double(accumulatedSystemLoad) / Double(systemLoadAccumulatorCount) / 1000.0
    }

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
    var algorithmChemistryID: Int? = nil
    var manufactureDateRaw: Int? = nil
    var dateOfFirstUseRaw: Int? = nil
    var dataFlashWriteCount: Int = 0
    var qmaxDisqualificationReason: Int? = nil
    var permanentFailureStatus: Int = 0
    var cellDisconnectCount: Int = 0
    var batteryInstalled: Bool? = nil
    var isBuiltIn: Bool? = nil

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
    /// 上次成功学习 Qmax 时的循环数，用来判断健康度读数的新鲜度
    var cycleCountLastQmax: Int = 0

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
