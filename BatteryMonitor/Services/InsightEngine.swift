import Foundation

// MARK: - Consumer-Facing Insight Models
//
// 把 50+ 个硬件字段翻译成消费者能秒懂的结论。核心纪律：**只输出数据支撑得住的结论**。
//
// 三处刻意不做的事（原型里有，但真机数据推不出来）：
//   1. 不给「预计退役 2028 Q3」这种日历日期 —— IOKit 里 DateOfFirstUse 恒为 0、
//      ManufactureDate 在 Apple Silicon 上是 ASCII 批号，拿不到电池年龄，也就
//      无法推出每日循环速率。改为给「剩余约 N 次循环」（真实可推），并让 app
//      自己观测循环速率，攒够 observationDaysNeeded 天后才给年份。
//   2. 不说「关掉 Chrome 省 1.8W、续航多 45 分钟」—— CPU% 不能换算成瓦特。
//      改为并列两个真事实：当前总功耗（真实读数）+ 谁占 CPU 最多。
//   3. 不显示适配器效率 —— 见 BatteryHardwareDetail.adapterEfficiency 注释。

enum FactorStatus: Equatable { case pass, warn, fail, neutral }

enum HealthLevel: Equatable {
    case excellent, good, fair, poor, critical

    static func from(score: Int) -> HealthLevel {
        switch score {
        case 90...:   return .excellent
        case 75..<90: return .good
        case 60..<75: return .fair
        case 40..<60: return .poor
        default:      return .critical
        }
    }

    var labelKey: String {
        switch self {
        case .excellent: return "insight.level.excellent"
        case .good:      return "insight.level.good"
        case .fair:      return "insight.level.fair"
        case .poor:      return "insight.level.poor"
        case .critical:  return "insight.level.critical"
        }
    }
}

struct HealthFactor: Identifiable, Equatable {
    var id: String { labelKey }
    let icon: String
    let labelKey: String
    let status: FactorStatus
    let consumerDetail: String   // 消费者语言，已本地化
    let rawValue: String         // 原始值，展开时给极客看
}

/// 剩余寿命。刻意不含日历日期 —— 只有观测够久才给年份。
struct RemainingLife: Equatable {
    let remainingCycles: Int?     // 按容量衰减推的剩余循环数
    let estimatedMonths: Int?     // 仅当观测到真实循环速率时才非 nil
    let observedDays: Int         // 已观测天数
    let daysNeeded: Int           // 还需观测到多少天才给年份
    var isEstimateReady: Bool { estimatedMonths != nil }
}

struct HealthDiagnosis: Equatable {
    let score: Int
    let level: HealthLevel
    let headline: String
    let factors: [HealthFactor]
    let remainingLife: RemainingLife
    let age: BatteryAgeEstimate?
}

struct BehaviorItem: Identifiable, Equatable {
    var id: String { labelKey }
    let labelKey: String
    let status: FactorStatus
    let detail: String
}

struct ChargingHabitScore: Equatable {
    let score: Int?              // nil = 数据不足
    let grade: String
    let behaviors: [BehaviorItem]
    let topSuggestion: String?
    let daysCollected: Int
    let daysNeeded: Int
    var isReady: Bool { score != nil }
}

struct AccessoryCheck: Identifiable, Equatable {
    var id: String { labelKey }
    let labelKey: String
    let passed: Bool
    let detail: String
}

struct AccessoryDiagnosis: Equatable {
    let isConnected: Bool
    let summary: String
    let subtitle: String
    let checks: [AccessoryCheck]
    let suggestion: String?
}

enum PowerLevel: Equatable {
    case idle, light, moderate, heavy, full

    static func from(watts: Double) -> PowerLevel {
        switch watts {
        case ..<5:    return .idle
        case ..<15:   return .light
        case ..<30:   return .moderate
        case ..<50:   return .heavy
        default:      return .full
        }
    }

    var labelKey: String {
        switch self {
        case .idle:     return "insight.power.idle"
        case .light:    return "insight.power.light"
        case .moderate: return "insight.power.moderate"
        case .heavy:    return "insight.power.heavy"
        case .full:     return "insight.power.full"
        }
    }
}

struct PowerAnalysis: Equatable {
    let currentWatts: Double
    let level: PowerLevel
    let estimatedHoursRemaining: Double?   // nil = AC 供电
    let topConsumers: [ProcessPowerInfo]
    let note: String?                      // 只陈述事实，不做瓦特归因
}

struct WeeklyHabitReport: Equatable {
    let chargeCount: Int
    let avgMaxSoc: Int
    let avgMinSoc: Int
    let maxTemp: Double
    let grade: String
    let daysCollected: Int
    let daysNeeded: Int
    var isReady: Bool { daysCollected >= daysNeeded }
}

struct BatteryInsight: Equatable {
    let health: HealthDiagnosis
    let habit: ChargingHabitScore
    let accessory: AccessoryDiagnosis
    let power: PowerAnalysis
    let weekly: WeeklyHabitReport
}

// MARK: - Engine

enum InsightEngine {

    // MARK: 可调参数
    /// 认为电池该退役的容量保持率阈值（%）
    static let retirementHealthThreshold: Double = 80
    /// 磨合期循环数。低于此值时容量衰减斜率不可靠（前期陡降），不用它下修剩余寿命。
    static let runInCycles = 300
    /// 给出年份预估前需要观测的天数
    static let observationDaysNeeded = 14
    /// 生成充电习惯评分需要的天数
    static let habitDaysNeeded = 3
    /// 生成周报需要的天数
    static let weeklyDaysNeeded = 7

    static func analyze(data: BatteryData,
                        history: [ChargingSession],
                        processes: [ProcessPowerInfo],
                        socLog: SOCHistory) -> BatteryInsight {
        let d = data.hardwareDetail
        return BatteryInsight(
            health: health(data: data, d: d, socLog: socLog),
            habit: habit(data: data, d: d, history: history, socLog: socLog),
            accessory: accessory(data: data, d: d),
            power: power(data: data, d: d, processes: processes),
            weekly: weekly(history: history, d: d, socLog: socLog)
        )
    }

    // MARK: - 健康诊断

    static func health(data: BatteryData, d: BatteryHardwareDetail, socLog: SOCHistory) -> HealthDiagnosis {
        var score = 100
        var factors: [HealthFactor] = []

        // 1) 容量保持率 30%
        let health = d.rawHealthPercent ?? Double(data.maxCapacityPercent)
        let capDeduct: Int
        switch health {
        case 95...:    capDeduct = 0
        case 90..<95:  capDeduct = 3
        case 85..<90:  capDeduct = 8
        case 80..<85:  capDeduct = 14
        case 70..<80:  capDeduct = 20
        default:       capDeduct = 26
        }
        score -= capDeduct
        factors.append(HealthFactor(
            icon: "battery.100",
            labelKey: "insight.factor.capacity",
            status: health >= 85 ? .pass : (health >= 70 ? .warn : .fail),
            consumerDetail: health >= 85
                ? L("insight.factor.capacity_good", health)
                : L("insight.factor.capacity_aging", health),
            rawValue: LNum("%.1f%% (%d/%d mAh)", health, d.appleRawMaxCapacity, d.designCapacity)))

        // 2) 循环使用率 20%
        let usage = d.cycleUsage ?? (Double(data.cycleCount) / 1000.0)
        score -= min(20, Int((usage * 20).rounded()))
        factors.append(HealthFactor(
            icon: "arrow.triangle.2.circlepath",
            labelKey: "insight.factor.cycles",
            status: usage < 0.5 ? .pass : (usage < 0.8 ? .warn : .fail),
            consumerDetail: L("insight.factor.cycles_detail", Int((usage * 100).rounded())),
            rawValue: "\(data.cycleCount) / \(d.designCycleCount > 0 ? d.designCycleCount : 1000)"))

        // 3) 电芯一致性 15%（拿不到电芯数据就不扣分也不显示）
        if let delta = d.cellVoltageDelta {
            let deduct: Int
            switch delta {
            case ..<11:  deduct = 0
            case 11..<21: deduct = 3
            case 21..<41: deduct = 8
            default:      deduct = 15
            }
            score -= deduct
            factors.append(HealthFactor(
                icon: "equal.circle",
                labelKey: "insight.factor.balance",
                status: delta <= 15 ? .pass : (delta <= 30 ? .warn : .fail),
                consumerDetail: delta <= 15
                    ? L("insight.factor.balance_good", delta)
                    : L("insight.factor.balance_warn", delta),
                rawValue: d.cellVoltages.map { LNum("%.3fV", Double($0) / 1000) }.joined(separator: " / ")))
        }

        // 4) 内部阻力 15%
        //
        // 阈值是启发式的：Apple 未公开 WeightedRa 的合格范围，实测健康的
        // bq40z651 三芯电池普遍落在 90–130 mΩ。所以刻意取保守值 —— 宁可漏报也
        // 不误报，否则一块各项全绿的新电池会因为内阻单项被标黄，属于制造焦虑。
        // 若日后有可靠数据，只需改这两组边界。
        if let maxRa = d.weightedRa.max(), maxRa > 0 {
            let deduct: Int
            switch maxRa {
            case ..<131:    deduct = 0
            case 131..<201: deduct = 6
            case 201..<301: deduct = 11
            default:        deduct = 15
            }
            score -= deduct
            factors.append(HealthFactor(
                icon: "waveform.path",
                labelKey: "insight.factor.resistance",
                status: maxRa <= 130 ? .pass : (maxRa <= 200 ? .warn : .fail),
                consumerDetail: maxRa <= 130      // 与上面 status 的阈值保持一致
                    ? L("insight.factor.resistance_good")
                    : L("insight.factor.resistance_high"),
                rawValue: d.weightedRa.map { "\($0)mΩ" }.joined(separator: " / ")))
        }

        // 5) 温度历史 10%
        if d.maximumTemperature > 0 {
            let t = d.maximumTemperature
            score -= t < 40 ? 0 : (t < 45 ? 3 : 8)
            factors.append(HealthFactor(
                icon: "thermometer.sun",
                labelKey: "insight.factor.temperature",
                status: t < 40 ? .pass : (t < 45 ? .warn : .fail),
                consumerDetail: t < 40 ? L("insight.factor.temp_good", t) : L("insight.factor.temp_high", t),
                rawValue: LNum("%d°C max · %.1f°C avg", t, d.averageTemperature)))
        }

        // 6) 硬件故障 10% —— 任一非 0 直接压到 20 分
        let hasFault = d.permanentFailureStatus != 0 || d.cellDisconnectCount > 0
        if hasFault { score = min(score, 20) }
        factors.append(HealthFactor(
            icon: "checkmark.shield",
            labelKey: "insight.factor.fault",
            status: hasFault ? .fail : .pass,
            consumerDetail: hasFault ? L("insight.factor.fault_found") : L("insight.factor.fault_none"),
            rawValue: "PF=\(d.permanentFailureStatus) · disconnect=\(d.cellDisconnectCount)"))

        score = max(0, min(100, score))
        let level = HealthLevel.from(score: score)

        return HealthDiagnosis(
            score: score,
            level: level,
            headline: headline(level: level, data: data, d: d, health: health),
            factors: factors,
            remainingLife: remainingLife(data: data, d: d, health: health, socLog: socLog),
            age: BatteryAgeEstimator.estimate(cycleCount: data.cycleCount, healthPercent: d.rawHealthPercent))
    }

    static func headline(level: HealthLevel, data: BatteryData,
                        d: BatteryHardwareDetail, health: Double) -> String {
        switch level {
        case .excellent: return L("insight.headline.excellent")
        case .good:
            return data.cycleCount > 500 ? L("insight.headline.good_high_cycle", data.cycleCount)
                                         : L("insight.headline.good")
        case .fair:
            if let ra = d.weightedRa.max(), ra > 150 { return L("insight.headline.fair_resistance") }
            return L("insight.headline.fair_capacity", health)
        case .poor:     return L("insight.headline.poor")
        case .critical: return L("insight.headline.critical")
        }
    }

    /// 剩余寿命。
    ///
    /// **以额定循环寿命为基准**（Apple 标称 1000 次，`DesignCycleCount9C` 直接读得到），
    /// 而不是拿当前容量做线性外推。原因：锂电池容量衰减是前期快、之后趋平的，
    /// 用早期斜率线性外推会严重高估衰减速度 —— 实测这块 210 循环 / 88.7% 的电池，
    /// 线性外推只剩 162 次循环（约 5 个月），却和「状态良好」的结论直接打脸。
    /// 额定基准给出 790 次（约 2 年），既有出处又自洽。
    ///
    /// 容量外推仅用作**下修**：只有当它比额定基准更保守且电池已过磨合期
    /// （循环数足够多，斜率才有意义）时才采用，避免新电池被前期陡降误判。
    static func remainingLife(data: BatteryData, d: BatteryHardwareDetail,
                              health: Double, socLog: SOCHistory) -> RemainingLife {
        var remainingCycles: Int?

        // 基准：额定循环寿命剩余
        if d.designCycleCount > 0 {
            remainingCycles = max(0, d.designCycleCount - data.cycleCount)
        }

        // 下修：过了磨合期后，若容量衰减明显更快则采纳更保守的数
        if data.cycleCount >= runInCycles, health > retirementHealthThreshold {
            let lossPerCycle = (100.0 - health) / Double(data.cycleCount)
            if lossPerCycle > 0.0001 {
                let byCapacity = max(0, Int((health - retirementHealthThreshold) / lossPerCycle))
                remainingCycles = remainingCycles.map { min($0, byCapacity) } ?? byCapacity
            }
        }

        var months: Int?
        if let rate = socLog.observedCyclesPerDay,
           rate > 0, socLog.observedDays >= observationDaysNeeded, let rc = remainingCycles {
            months = max(0, Int((Double(rc) / rate / 30.44).rounded()))
        }
        return RemainingLife(remainingCycles: remainingCycles,
                             estimatedMonths: months,
                             observedDays: socLog.observedDays,
                             daysNeeded: observationDaysNeeded)
    }

    // MARK: - 充电习惯

    static func habit(data: BatteryData, d: BatteryHardwareDetail,
                      history: [ChargingSession], socLog: SOCHistory) -> ChargingHabitScore {
        let days = socLog.observedDays
        guard days >= habitDaysNeeded else {
            return ChargingHabitScore(score: nil, grade: "—", behaviors: [], topSuggestion: nil,
                                      daysCollected: days, daysNeeded: habitDaysNeeded)
        }

        var score = 100
        var items: [BehaviorItem] = []
        var suggestions: [String] = []

        // 充电深度：用 app 自己记录的 SOC 区间，而不是 IOKit 的当日单点快照
        if let hi = socLog.averageMaxSoc, let lo = socLog.averageMinSoc {
            let deepCycle = hi >= 95 && lo <= 10
            let full = hi >= 98
            score -= deepCycle ? 20 : (full ? 10 : 0)
            items.append(BehaviorItem(
                labelKey: "insight.habit.depth",
                status: deepCycle ? .fail : (full ? .warn : .pass),
                detail: L("insight.habit.depth_detail", lo, hi)))
            if deepCycle { suggestions.append(L("insight.habit.tip_full_cycle")) }
            else if full { suggestions.append(L("insight.habit.tip_optimized_charging")) }
        }

        // 满充存放
        if socLog.fullChargeHoldEvents > 0 {
            score -= min(15, socLog.fullChargeHoldEvents * 5)
            items.append(BehaviorItem(
                labelKey: "insight.habit.standby",
                status: .warn,
                detail: L("insight.habit.standby_detail", socLog.fullChargeHoldEvents)))
            suggestions.append(L("insight.habit.tip_avoid_overnight"))
        } else {
            items.append(BehaviorItem(labelKey: "insight.habit.standby", status: .pass,
                                      detail: L("insight.habit.standby_good")))
        }

        // 充电温度
        if let t = socLog.maxChargingTemp, t > 0 {
            score -= t > 40 ? 15 : (t > 35 ? 6 : 0)
            items.append(BehaviorItem(
                labelKey: "insight.habit.temp",
                status: t <= 35 ? .pass : (t <= 40 ? .warn : .fail),
                detail: L("insight.habit.temp_detail", t)))
            if t > 38 { suggestions.append(L("insight.habit.tip_temp", Int(t.rounded()))) }
        }

        // 浅充频率（浅充是好习惯）。0 次不算问题，只是没这个加分项 ——
        // 状态与文案必须一致，不能一边显示黄色警告一边写「习惯良好」。
        let shallow = history.filter { $0.durationMinutes < 40 }.count
        if !history.isEmpty {
            items.append(BehaviorItem(
                labelKey: "insight.habit.shallow",
                status: shallow > 0 ? .pass : .neutral,
                detail: shallow > 0 ? L("insight.habit.shallow_detail", shallow)
                                    : L("insight.habit.shallow_none")))
        }

        score = max(0, min(100, score))
        return ChargingHabitScore(score: score, grade: grade(for: score), behaviors: items,
                                  topSuggestion: suggestions.first,
                                  daysCollected: days, daysNeeded: habitDaysNeeded)
    }

    static func grade(for score: Int) -> String {
        switch score {
        case 95...:   return "A+"
        case 85..<95: return "A"
        case 75..<85: return "B"
        case 60..<75: return "C"
        default:      return "D"
        }
    }

    // MARK: - 配件诊断

    static func accessory(data: BatteryData, d: BatteryHardwareDetail) -> AccessoryDiagnosis {
        guard data.isOnAC || d.hasAdapterData else {
            return AccessoryDiagnosis(isConnected: false,
                                      summary: L("insight.accessory.disconnected"),
                                      subtitle: L("insight.accessory.disconnected_hint"),
                                      checks: [], suggestion: nil)
        }

        var checks: [AccessoryCheck] = []
        var suggestion: String?

        // 功率：拿 PD 菜单里的最高档当设备可用上限，比硬编码机型功率靠得住
        let menuMax = d.usbHvcMenu.map { $0.voltage * $0.current / 1_000_000 }.max() ?? 0
        let watts = d.adapterWatts
        let powerOK = watts > 0 && (menuMax == 0 || watts >= menuMax)
        checks.append(AccessoryCheck(labelKey: "insight.accessory.power",
                                     passed: powerOK,
                                     detail: watts > 0 ? L("insight.accessory.power_detail", watts)
                                                       : L("insight.not_available")))
        if watts > 0 && menuMax > watts {
            suggestion = L("insight.accessory.tip_low_power", watts, menuMax)
        }

        // 电压协商
        let negotiated = d.adapterVoltage > 0 && d.adapterCurrent > 0
        checks.append(AccessoryCheck(
            labelKey: "insight.accessory.negotiation",
            passed: negotiated,
            detail: negotiated
                ? LNum("%.0fV / %.2fA", Double(d.adapterVoltage) / 1000, Double(d.adapterCurrent) / 1000)
                : L("insight.accessory.negotiation_fail")))
        if !negotiated { suggestion = suggestion ?? L("insight.accessory.tip_negotiation") }

        // PD 档位数（能协商出多档说明是规范的 PD 充电器）
        if !d.usbHvcMenu.isEmpty {
            checks.append(AccessoryCheck(labelKey: "insight.accessory.pd_profiles",
                                         passed: true,
                                         detail: L("insight.accessory.pd_profiles_detail", d.usbHvcMenu.count)))
        }

        // 这里刻意不做「是否被限流」的检查：ChargingCurrent==0 在「已充满保持」和
        // 「刚插上还没开始充」时都会出现，是正常状态；NotChargingReason 是无文档的
        // bitmask，推不出可靠结论。宁可少一项，也不给用户一个瞎猜的红叉。

        // adapterDescription 是 IOKit 原始字符串（实测 "pd charger"），小写英文且不
        // 本地化，直接显示很生硬。映射到已知类型，认不出来才回落原值。
        let type = localizedAdapterType(d.adapterDescription, hasPD: !d.usbHvcMenu.isEmpty)
        return AccessoryDiagnosis(
            isConnected: true,
            summary: watts > 0 ? L("insight.accessory.summary", watts, type) : type,
            subtitle: negotiated
                ? LNum("%.0fV / %.2fA · %d PD", Double(d.adapterVoltage) / 1000,
                       Double(d.adapterCurrent) / 1000, d.usbHvcMenu.count)
                : "",
            checks: checks,
            suggestion: suggestion)
    }

    /// 把 IOKit 的原始描述映射成本地化的充电器类型名。
    static func localizedAdapterType(_ raw: String, hasPD: Bool) -> String {
        let s = raw.lowercased()
        if s.contains("magsafe") { return L("insight.accessory.magsafe") }
        if s.contains("pd") || hasPD { return L("insight.accessory.pd") }
        return raw.isEmpty ? L("insight.accessory.usbc") : raw
    }

    // MARK: - 耗电分析

    static func power(data: BatteryData, d: BatteryHardwareDetail,
                      processes: [ProcessPowerInfo]) -> PowerAnalysis {
        // 优先用 BatteryData.SystemPower（直接是 W），退到 PowerTelemetry 的 mW，
        // 最后退到 |I|×V。三者都是真实读数，不做估算。
        var watts = d.systemPowerWatts
        if watts <= 0, d.systemLoad > 0 { watts = Double(d.systemLoad) / 1000.0 }
        if watts <= 0 { watts = data.currentPowerWatts }

        var hours: Double?
        if !data.isOnAC, watts > 0.1, d.appleRawCurrentCapacity > 0, data.voltage > 0 {
            let wh = Double(d.appleRawCurrentCapacity) * data.voltage / 1000.0
            hours = wh / watts
        }

        let top = Array(processes.prefix(5))
        // 只陈述事实：谁占 CPU 最多。不把 CPU% 换算成瓦特（换不出来）。
        var note: String?
        if let first = top.first, first.cpuPercent > 15 {
            // 实参顺序必须与格式串一致：%.1fW → %@ → %.0f%%。
            // String(format:) 是 C 变参，顺序错了会按错误类型读位模式。
            note = L("insight.power.note_top", watts, first.displayName, first.cpuPercent)
        } else if watts > 0 {
            note = L("insight.power.note_plain", watts)
        }

        return PowerAnalysis(currentWatts: watts,
                             level: .from(watts: watts),
                             estimatedHoursRemaining: hours,
                             topConsumers: top,
                             note: note)
    }

    // MARK: - 周报

    static func weekly(history: [ChargingSession], d: BatteryHardwareDetail,
                       socLog: SOCHistory) -> WeeklyHabitReport {
        let days = socLog.observedDays
        let weekAgo = Date().addingTimeInterval(-7 * 86400)
        let recent = history.filter { socLog.date(from: $0.date).map { $0 >= weekAgo } ?? false }
        return WeeklyHabitReport(
            chargeCount: recent.count,
            avgMaxSoc: socLog.averageMaxSoc ?? 0,
            avgMinSoc: socLog.averageMinSoc ?? 0,
            maxTemp: socLog.maxChargingTemp ?? 0,
            grade: grade(for: 100 - min(40, socLog.fullChargeHoldEvents * 8)),
            daysCollected: days,
            daysNeeded: weeklyDaysNeeded)
    }
}
