import Foundation
import AppKit

// InsightEngine / BatteryAgeEstimator / 硬件解析的边界测试。
// 由 QATests/TestKit/Scripts/run-test-app.sh insight 编译运行，不依赖 Xcode 也不依赖界面截图。

var failures = 0
func expect(_ cond: Bool, _ msg: String) {
    print((cond ? "  ✓ " : "  ✗ ") + msg)
    if !cond { failures += 1 }
}

// 断言里出现的中文字面量必须来自真实语言包。
// 这个进程里 Bundle.main 是固定 BatteryMonitor-QAHost.app，TestKit/Scripts/run-test-app.sh 会把
// Localization/Languages/*.json 拷进去；不拷的话 L() 只返回 key，而
// dashboardText 只读取语言包；显式选简体中文，避免结果随开发机系统语言漂移。
L10n.shared.select("zh-Hans")
precondition(L10n.shared.languages.count == 10,
             "语言包没进 BatteryMonitor-QAHost.app —— TestKit/Scripts/run-test-app.sh 是否漏拷 Resources/Languages？")
precondition(L10n.shared.effectiveCode == "zh-Hans",
             "未能选中 zh-Hans，实际 \(L10n.shared.effectiveCode)")

// MARK: - 构造样本

/// 一块健康电池：210 循环 / 88.7% 容量 / 压差 2mV / 无故障
func healthyDetail() -> BatteryHardwareDetail {
    var d = BatteryHardwareDetail()
    d.cycleCount = 210
    d.designCycleCount = 1000
    d.designCapacity = 4629
    d.appleRawMaxCapacity = 4107
    d.appleRawCurrentCapacity = 3977
    d.presentRawFields.formUnion(["AppleRawMaxCapacity", "AppleRawCurrentCapacity"])
    d.cellVoltages = [4387, 4384, 4382]
    d.weightedRa = [94, 105, 113]
    d.qmax = [4595, 4631, 4661]
    d.maximumTemperature = 39
    d.averageTemperature = 24.7
    d.systemPowerWatts = 12.5
    d.architecture = .appleSilicon
    return d
}

func data(from d: BatteryHardwareDetail, onAC: Bool = false) -> BatteryData {
    var b = BatteryData()
    b.hardwareDetail = d
    b.cycleCount = d.cycleCount
    b.maxCapacityPercent = Int(d.rawHealthPercent ?? 100)
    b.voltage = 12.9
    b.percent = 86
    b.isOnAC = onAC
    return b
}

func log(days: Int, cyclesFrom: Int, cyclesTo: Int,
         minSoc: Int = 24, maxSoc: Int = 92, fullHold: Int = 0) -> SOCHistory {
    var h = SOCHistory()
    guard days > 0 else { return h }
    for i in 0..<days {
        let day = SOCHistory.formatter.string(
            from: Date().addingTimeInterval(Double(-(days - 1) + i) * 86400))
        let c = cyclesFrom + (cyclesTo - cyclesFrom) * i / max(1, days - 1)
        h.records.append(DailyRecord(date: day, minSoc: minSoc, maxSoc: maxSoc,
                                     maxChargingTemp: 31, fullHoldSamples: fullHold,
                                     cycleCount: c))
    }
    return h
}

// MARK: - 1) 年龄估算

print("── 1) 电池年龄估算")
expect(BatteryAgeEstimator.estimate(cycleCount: 0, healthPercent: 94) == nil,
       "循环数为 0 时无法估算（返回 nil，不编造）")
expect(BatteryAgeEstimator.estimate(cycleCount: -5, healthPercent: 94) == nil,
       "负循环数也返回 nil")
if let e = BatteryAgeEstimator.estimate(cycleCount: 210, healthPercent: 94) {
    expect(e.totalMonths == 5 && !e.isDecodedFromHardware,
           "210 循环 ≈ 5 个月，且标记为非硬件解码 [\(e.totalMonths) 月]")
} else { expect(false, "210 循环应能估算") }
let fast = BatteryAgeEstimator.estimate(cycleCount: 700, healthPercent: 80)!
let slow = BatteryAgeEstimator.estimate(cycleCount: 700, healthPercent: 95)!
expect(fast.totalMonths < slow.totalMonths,
       "健康度低时估出的年龄更短（\(fast.totalMonths) < \(slow.totalMonths) 月）")

// Apple Silicon 的 ManufactureDate 是 ASCII 批号，必须走不到硬件解码分支
expect(BatteryAgeEstimator.decodeManufactureDate(58485394912051) == nil,
       "ASCII 批号（远超 0xFFFF）不被误当日期解码")
expect(BatteryAgeEstimator.decodeManufactureDate(0) == nil, "0 不被解码")
let sbs = ((2024 - 1980) << 9) | (3 << 5) | 15   // 2024-03-15
if let e = BatteryAgeEstimator.decodeManufactureDate(sbs) {
    expect(e.isDecodedFromHardware, "Intel SBS 打包日期能解码且标记为硬件解码")
} else { expect(false, "SBS 日期应能解码") }
expect(BatteryAgeEstimator.decodeManufactureDate((3000 - 1980) << 9) == nil,
       "未来日期被拒绝")
expect(BatteryAgeEstimator.resolve(manufactureDateRaw: 58485394912051,
                                   cycleCount: 210, healthPercent: 94) != nil,
       "resolve 在无法解码日期时退到经验估算")

// MARK: - 2) 温度单位兼容

print("── 2) 温度单位（Apple Silicon centi- vs Intel deci-）")
expect(abs(BatteryService.decodeTemperature(3079) - 30.79) < 0.01, "3079 → 30.79°C (centi)")
expect(abs(BatteryService.decodeTemperature(307) - 30.7) < 0.01, "307 → 30.7°C (deci)")
expect(abs(BatteryService.decodeTemperature(30) - 30.0) < 0.01, "30 → 30°C (直接值)")

// MARK: - 3) 派生指标

print("── 3) 派生指标")
let d = healthyDetail()
expect(d.cellVoltageDelta == 5, "压差 = max-min = 5 mV [\(d.cellVoltageDelta.map(String.init) ?? "nil")]")
expect(BatteryHardwareDetail().cellVoltageDelta == nil, "无电芯数据时压差为 nil 而非 0")
expect(abs((d.rawHealthPercent ?? 0) - 88.72) < 0.05, "容量保持率 4107/4629 ≈ 88.7%")
expect(d.adapterEfficiency == nil, "无输入功率时效率为 nil（不显示编造的效率）")
var noisy = d
noisy.systemPowerIn = 4160; noisy.adapterEfficiencyLoss = -104
expect(noisy.adapterEfficiency == nil, "损耗为负（实测噪声）时效率仍为 nil")
noisy.adapterEfficiencyLoss = 5000
expect(noisy.adapterEfficiency == nil, "损耗大于输入功率时也拒绝（物理不成立）")
noisy.adapterEfficiencyLoss = 40
expect(noisy.adapterEfficiency != nil, "损耗落在合理区间时才给结果")

// MARK: - 4) 诚实性守卫：数据不足时不编造

print("── 4) 数据不足时不编造（核心纪律）")
let fresh = InsightEngine.analyze(data: data(from: d), history: [], processes: [], socLog: SOCHistory())
expect(fresh.health.remainingLife.estimatedMonths == nil,
       "零观测时不给年份预估")
expect(fresh.health.remainingLife.remainingCycles != nil,
       "但给出剩余循环数（可由容量衰减推导）")
expect(fresh.habit.score == nil && !fresh.habit.isReady,
       "零观测时习惯评分为 nil，UI 显示「收集中」")
expect(!fresh.weekly.isReady, "零观测时周报未就绪")
expect(fresh.health.age != nil, "年龄估算不依赖观测历史，立即可用")

let observed = InsightEngine.analyze(data: data(from: d), history: [], processes: [],
                                     socLog: log(days: 20, cyclesFrom: 190, cyclesTo: 210))
expect(observed.health.remainingLife.estimatedMonths != nil,
       "观测满 \(InsightEngine.observationDaysNeeded) 天后才给年份")
expect(observed.habit.score != nil, "观测足够后习惯评分可用")
expect(observed.weekly.isReady, "观测足够后周报就绪")

let rate = log(days: 20, cyclesFrom: 190, cyclesTo: 210).observedCyclesPerDay
expect(rate != nil && abs(rate! - 1.0) < 0.1, "实测循环速率 ≈ 1.0 次/天 [\(rate ?? -1)]")
expect(log(days: 1, cyclesFrom: 200, cyclesTo: 200).observedCyclesPerDay == nil,
       "只有一天数据时不计算速率")
expect(log(days: 10, cyclesFrom: 200, cyclesTo: 200).observedCyclesPerDay == nil,
       "循环数没增长时不计算速率（避免除零/零速率外推出无限寿命）")

// MARK: - 5) 健康评分边界

print("── 5) 健康评分")
expect(fresh.health.score >= 80 && fresh.health.score <= 95,
       "健康电池得分落在 80–95 [\(fresh.health.score)]")
expect(fresh.health.level == .good || fresh.health.level == .excellent, "等级为 good/excellent")
expect(fresh.health.factors.count == 6, "六项诊断依据齐全 [\(fresh.health.factors.count)]")
expect(fresh.health.factors.allSatisfy { $0.status == .pass },
       "各项全绿（这块电池确实各项正常，不应有误报警告）")

var faulty = d
faulty.permanentFailureStatus = 1
let f1 = InsightEngine.analyze(data: data(from: faulty), history: [], processes: [], socLog: SOCHistory())
expect(f1.health.score <= 20, "有永久故障标志时评分压到 20 以下 [\(f1.health.score)]")
expect(f1.health.level == .critical, "等级为 critical")

var worn = d
worn.appleRawMaxCapacity = 3200      // 69%
worn.cycleCount = 950
worn.weightedRa = [260, 275, 290]
worn.maximumTemperature = 47
let f2 = InsightEngine.analyze(data: data(from: worn), history: [], processes: [], socLog: SOCHistory())
expect(f2.health.score < fresh.health.score, "老化电池得分低于健康电池 [\(f2.health.score) < \(fresh.health.score)]")
expect(f2.health.remainingLife.remainingCycles == nil || f2.health.remainingLife.remainingCycles! >= 0,
       "已低于退役阈值时剩余循环为 nil 或非负，不出现负数")

var noCells = BatteryHardwareDetail()
noCells.cycleCount = 300; noCells.designCapacity = 5000; noCells.appleRawMaxCapacity = 4500
let f3 = InsightEngine.analyze(data: data(from: noCells), history: [], processes: [], socLog: SOCHistory())
expect(f3.health.factors.count < 6, "拿不到电芯/温度数据时相应依据不显示，也不扣分")
expect(f3.health.score > 60, "缺字段不应导致评分被误压低 [\(f3.health.score)]")

// MARK: - 6) 配件诊断

print("── 6) 配件诊断")
let off = InsightEngine.accessory(data: data(from: d, onAC: false), d: d)
expect(!off.isConnected && off.checks.isEmpty, "未插电时不给检查项，整卡显示未连接")

var plugged = d
plugged.adapterWatts = 65
plugged.adapterVoltage = 20000
plugged.adapterCurrent = 3250
plugged.adapterDescription = "pd charger"
plugged.systemPowerIn = 16_200
plugged.usbHvcMenu = [.init(voltage: 5000, current: 3000), .init(voltage: 9000, current: 3000),
                      .init(voltage: 15000, current: 3000), .init(voltage: 20000, current: 3250)]
let on = InsightEngine.accessory(data: data(from: plugged, onAC: true), d: plugged)
expect(on.isConnected && on.checks.count >= 3, "插电后给出至少 3 项检查 [\(on.checks.count)]")
expect(on.checks.allSatisfy { $0.passed }, "65W 原装 PD 充电器应全部通过")
expect(!on.checks.contains { $0.labelKey.contains("efficiency") },
       "不含「充电效率」检查项（该数据不可信，已移除）")

var weak = plugged
weak.adapterWatts = 30
let low = InsightEngine.accessory(data: data(from: weak, onAC: true), d: weak)
expect(low.suggestion != nil, "充电器功率低于 PD 菜单上限时给出建议")

let adapterPointEnd = Date()
let adapterPoints = [12.4, 15.8, 16.2].enumerated().map { offset, inputPower in
    RealtimeDataPoint(
        timestamp: adapterPointEnd.addingTimeInterval(Double(-20 + offset * 10)),
        voltage: 12.9,
        amperage: 1_000,
        power: 8.4,
        temperature: 30.8,
        percent: 86,
        inputPower: inputPower,
        adapterVoltage: 20.0,
        adapterCurrent: 3.25,
        isOnAC: true
    )
}
let adapterHelp = DashboardHelp.adapterPower(
    DashboardMetricSnapshot(data: data(from: plugged, onAC: true), realtimeData: adapterPoints)
)
expect(adapterHelp.powerContract?.isConnected == true
       && adapterHelp.powerContract?.isNegotiated == true,
       "充电器弹窗区分已连接与 PD 协商成功")
expect(adapterHelp.powerContract?.equationText.contains("20.0 V") == true
       && adapterHelp.powerContract?.equationText.contains("3.25 A") == true
       && adapterHelp.powerContract?.equationText.contains("65.0 W") == true,
       "充电器弹窗拆解 20.0V × 3.25A = 65.0W")
// 每个采样点：整机 8.4W + 充入 (1000mA ÷ 1000 × 12.9V) = 12.9W → 21.3W。
// 关键是这三个点的 inputPower（SystemPowerIn）分别是 12.4/15.8/16.2，都没被采用——
// 那个字段实测会在插着电充着电时归零，一归零整张图就消失，这正是要防的回归。
expect(adapterHelp.powerContract?.trendPoints.count == 3
       && (adapterHelp.powerContract?.trendPoints.allSatisfy { abs($0.value - 21.3) < 0.001 } ?? false),
       "充电器弹窗的输入功率曲线取「整机功率 + 充入功率」推导，不取 SystemPowerIn")
let acFreePoints = adapterPoints.map {
    RealtimeDataPoint(timestamp: $0.timestamp, voltage: $0.voltage, amperage: $0.amperage,
                      power: $0.power, temperature: $0.temperature, percent: $0.percent,
                      inputPower: $0.inputPower, isOnAC: false)
}
expect(DashboardHelp.adapterPower(
    DashboardMetricSnapshot(data: data(from: plugged, onAC: true), realtimeData: acFreePoints)
).powerContract?.trendPoints.isEmpty == true,
       "拔电时段不画适配器输出——没有输出和输出 0W 是两回事")
expect(adapterHelp.rawFields.contains { $0.name == "Derived.NegotiatedPower" && $0.value.contains("65") },
       "额定功率既保留系统 Watts，也提供电压×电流校验值")

let explainedPowerFields = DashboardHelp.power(
    DashboardMetricSnapshot(data: data(from: d, onAC: false), realtimeData: adapterPoints)
).rawFields
expect(explainedPowerFields.count == 6
       && explainedPowerFields.allSatisfy { !$0.localizedExplanation.isEmpty }
       && explainedPowerFields.first(where: { $0.name == "Voltage" })?.localizedExplanation.contains("电压") == true
       && explainedPowerFields.first(where: { $0.name == "Amperage" })?.localizedExplanation.contains("电流") == true
       && explainedPowerFields.first(where: { $0.name == "SystemLoadAccumulatorCount" })?.localizedExplanation.contains("采样") == true,
       "功率抽屉的每个底层字段都有易懂中文解释，同时保留系统字段名")
let uncommonRawField = MetricRawField(name: "VendorDiagnosticCode", value: "7")
expect(!uncommonRawField.localizedExplanation.isEmpty
       && uncommonRawField.localizedExplanation != uncommonRawField.name,
       "新增或冷门诊断字段也会显示本地化兜底说明")

var wholeMacInputData = data(from: plugged, onAC: true)
wholeMacInputData.hardwareDetail.presentRawFields.formUnion([
    "PowerTelemetryData.SystemPowerIn",
    "PowerTelemetryData.VoltageIn",
    "PowerTelemetryData.CurrentIn",
    "PowerTelemetryData.AdapterEfficiencyLoss",
    "AppleRawBatteryVoltage",
    "InstantAmperage",
    "Amperage",
])
wholeMacInputData.hardwareDetail.packVoltage = 12_466
wholeMacInputData.hardwareDetail.appleRawBatteryVoltage = 12_466
wholeMacInputData.hardwareDetail.instantAmperage = 0
wholeMacInputData.hardwareDetail.smoothedAmperage = 0
wholeMacInputData.hardwareDetail.systemVoltageIn = 20_000
wholeMacInputData.hardwareDetail.systemCurrentIn = 3_250
wholeMacInputData.isCharging = false
wholeMacInputData.amperage = 0
wholeMacInputData.hardwareDetail.systemPowerWatts = 16.2
let powerFlowSnapshot = DashboardMetricSnapshot(data: wholeMacInputData, realtimeData: adapterPoints)
let adapterOutputHelp = DashboardHelp.adapterOutputPower(powerFlowSnapshot)
// 插电、不充电：适配器出的就是整机吃的，两条出边只剩一条
expect(abs((powerFlowSnapshot.adapterOutputPowerWatts ?? -1) - 16.2) < 0.001
       && adapterOutputHelp.result.contains("16.2 W"),
       "插电不充电时适配器输出 = 整机功率 16.2W")
expect(adapterOutputHelp.rawFields.contains { $0.name == "PowerTelemetryData.SystemPowerIn" },
       "适配器输出功率抽屉保留 SystemPowerIn 底层字段")
// 用户报的那个 bug 的回归：SystemPowerIn 归零时，卡片和曲线都不许消失
var zeroTelemetryData = wholeMacInputData
zeroTelemetryData.hardwareDetail.systemPowerIn = 0
zeroTelemetryData.isCharging = true
zeroTelemetryData.amperage = 1_000
zeroTelemetryData.hardwareDetail.instantAmperage = 1_000
let zeroTelemetrySnapshot = DashboardMetricSnapshot(data: zeroTelemetryData, realtimeData: adapterPoints)
// 16.2W 整机 + 12.466V × 1.0A = 12.466W 充入 → 28.666W
expect(abs((zeroTelemetrySnapshot.adapterOutputPowerWatts ?? -1) - 28.666) < 0.001,
       "SystemPowerIn 归零时适配器输出仍然算得出来 [\(String(describing: zeroTelemetrySnapshot.adapterOutputPowerWatts))]")
expect(DashboardHelp.adapterOutputPower(zeroTelemetrySnapshot).trend?.points.count == 3,
       "SystemPowerIn 归零不会把趋势图整张抹掉——这正是用户看到「折线图没有了」的成因")
expect(!DashboardHelp.adapterOutputPower(zeroTelemetrySnapshot).formula.contains("SystemPowerIn"),
       "公式如实写成推导式，不再声称直读 SystemPowerIn")

let idleChargingHelp = DashboardHelp.chargingPower(powerFlowSnapshot)
expect(powerFlowSnapshot.batteryChargingPowerWatts == 0
       && idleChargingHelp.result == "0 W",
       "12.466V × 0A = 0W；插电但未充电时明确显示零")
expect(!idleChargingHelp.rawFields.contains { $0.name == "PowerTelemetryData.SystemPowerIn" }
       && idleChargingHelp.rawFields.contains { $0.name == "AppleRawBatteryVoltage" }
       && idleChargingHelp.rawFields.contains { $0.name == "InstantAmperage" },
       "充电功率只使用电池侧电压和电流，不再混入 SystemPowerIn")

var chargingData = wholeMacInputData
chargingData.isCharging = true
chargingData.amperage = 2_000
chargingData.hardwareDetail.instantAmperage = 2_000
chargingData.hardwareDetail.smoothedAmperage = 1_950
let chargingSnapshot = DashboardMetricSnapshot(data: chargingData, realtimeData: adapterPoints)
expect(abs((chargingSnapshot.batteryChargingPowerWatts ?? -1) - 24.932) < 0.001,
       "正向充电时按 12.466V × 2.000A = 24.932W 计算电池侧功率")

let disconnectedAdapterHelp = DashboardHelp.adapterPower(
    DashboardMetricSnapshot(data: data(from: d, onAC: false), realtimeData: adapterPoints)
)
expect(disconnectedAdapterHelp.powerContract?.isConnected == false
       && disconnectedAdapterHelp.powerContract?.trendValue == "—",
       "拔电时充电器状态明确显示未连接，不把旧输入样本当成当前值")
expect(disconnectedAdapterHelp.rawFields.allSatisfy { $0.value == "—" },
       "拔电时消失的 AdapterDetails 字段显示不可用，不把默认0伪装成实测值")

// MARK: - 7) 耗电分析

print("── 7) 耗电分析")
// 68% ≈ 占满 2/3 个核，超过 40% 阈值，走 note_top 分支。
// 阈值是按真实 CPU 读数定的；不要把它改回 32.4 这种「timebase 修复前的低估值」，
// 否则这条测试会退化成在验证 note_plain。
let procs = [ProcessPowerInfo(pid: 1, name: "/Applications/Google Chrome.app/Google Chrome",
                              cpuPercent: 68.0, memoryMB: 900)]
let pOnBattery = InsightEngine.power(data: data(from: d, onAC: false), d: d, processes: procs)
expect(pOnBattery.estimatedHoursRemaining != nil, "电池供电时给出续航预估")
expect(pOnBattery.currentWatts > 0, "功耗为真实读数 [\(pOnBattery.currentWatts)W]")
let pOnAC = InsightEngine.power(data: data(from: d, onAC: true), d: d, processes: procs)
expect(pOnAC.estimatedHoursRemaining == nil, "AC 供电时不给续航预估")
expect(pOnBattery.note?.contains("Google Chrome") == true,
       "有高占用进程时点名该进程 [\(pOnBattery.note ?? "nil")]")
// 提示里只能出现真实读数，不能出现编造的「省 X W」
if let n = pOnBattery.note {
    expect(!n.contains("1.8") , "提示不含编造的节省瓦特数")
}
// 低于阈值时只陈述总功耗，不点名任何进程、不建议关掉它
let lightProcs = [ProcessPowerInfo(pid: 1, name: "/Applications/Google Chrome.app/Google Chrome",
                                   cpuPercent: 3.2, memoryMB: 900)]
let pLight = InsightEngine.power(data: data(from: d, onAC: false), d: d, processes: lightProcs)
expect(pLight.note != nil && pLight.note?.contains("Google Chrome") != true,
       "低占用时只报总功耗，不点名进程 [\(pLight.note ?? "nil")]")
expect(InsightEngine.power(data: data(from: d), d: d, processes: []).topConsumers.isEmpty,
       "无进程数据时不崩，top 列表为空")

// MARK: - 8) 硬件表格隐藏规则

print("── 8) 硬件表格隐藏规则")
let gFull = HardwareDetailView.build(plugged)
let gBare = HardwareDetailView.build(BatteryHardwareDetail())
expect(gFull.contains { $0.titleKey == "hw.group.charger" }, "插电时显示充电器组")
expect(!gBare.contains { $0.titleKey == "hw.group.charger" }, "空数据时充电器组整组隐藏")
expect(!gBare.contains { $0.titleKey == "hw.group.cells" }, "无电芯数据时电芯组整组隐藏")
expect(gFull.reduce(0) { $0 + $1.rows.count } > 24, "完整 fixture 字段数 > 24（真机实测 51）[\(gFull.reduce(0){$0+$1.rows.count})]")
expect(gBare.allSatisfy { !$0.rows.isEmpty }, "不出现空分组")

// MARK: - 9) SOC 历史记录

print("── 9) SOC 历史")
var h = SOCHistory()
h.record(percent: 80, cycleCount: 210, temperature: 30, isCharging: true, isFullyCharged: false, isOnAC: true)
h.record(percent: 60, cycleCount: 210, temperature: 32, isCharging: true, isFullyCharged: false, isOnAC: true)
expect(h.records.count == 1, "同一天多次采样只保留一条记录")
expect(h.records[0].minSoc == 60 && h.records[0].maxSoc == 80, "同日记录取区间 min/max")
expect(h.records[0].maxChargingTemp == 32, "充电期间取最高温")
h.record(percent: 100, cycleCount: 211, temperature: 28, isCharging: false, isFullyCharged: true, isOnAC: true)
expect(h.records[0].fullHoldSamples == 1, "满充且插电时累计满充存放采样")
expect(h.records[0].cycleCount == 211, "循环数取当日最大值")

// MARK: - 10) 官方机型规格与续航派生

print("── 10) 官方规格与续航派生")
if let spec = BatteryModelSpecification.lookup(modelIdentifier: "Mac16,12") {
    expect(abs(spec.designEnergyWh - 53.8) < 0.001, "Mac16,12 设计能量为53.8Wh")
    expect(spec.officialWebHours == 15 && spec.officialVideoHours == 18,
           "Mac16,12 官方网页/视频续航为15h/18h")
    expect(spec.testCPUCoreCount == 10 && spec.testGPUCoreCount == 8
           && spec.testMemoryGB == 16 && spec.testStorageGB == 256,
           "官方测试配置完整")
} else { expect(false, "Mac16,12 必须能命中官方规格") }
expect(BatteryModelSpecification.lookup(modelIdentifier: "UnknownMac") == nil,
       "未知机型不伪造官方规格")

var runtimeData = BatteryData()
runtimeData.modelIdentifier = "Mac16,12"
runtimeData.hardwareDetail.designCapacity = 4629
runtimeData.hardwareDetail.appleRawMaxCapacity = 4082
runtimeData.hardwareDetail.appleRawCurrentCapacity = 3322
runtimeData.hardwareDetail.presentRawFields.insert("AppleRawCurrentCapacity")
runtimeData.hardwareDetail.accumulatedSystemLoad = 1_183_465_630
runtimeData.hardwareDetail.systemLoadAccumulatorCount = 134_998
runtimeData.currentPowerWatts = 15.67
expect(abs((runtimeData.currentFullEnergyWh ?? 0) - 47.44) < 0.05,
       "当前满充能量按官方Wh与FCC比例换算")
expect(runtimeData.systemHealth == runtimeData.systemHealthPercent,
       "主数据健康度只暴露系统统一口径")
expect(abs((runtimeData.remainingEnergyWh ?? 0) - 38.61) < 0.05,
       "当前剩余能量按官方Wh与当前mAh换算")
expect(runtimeData.unplugEstimateMinutes == 148,
       "拔电预计 = 剩余Wh ÷ 当前系统功耗 [\(runtimeData.unplugEstimateMinutes ?? -1)min]")
expect(abs((runtimeData.officialImpliedPowerWatts ?? 0) - 3.587) < 0.01,
       "官方网页测试隐含平均功耗约3.59W")
expect(abs((runtimeData.sameLoadRuntimeHours ?? 0) - 13.23) < 0.05,
       "当前电池在官方相同负载下约13.2小时")
expect(abs((runtimeData.averageTelemetryPowerWatts ?? 0) - 8.7665) < 0.01,
       "累计遥测平均功耗公式正确")
expect(runtimeData.officialImpliedPower == runtimeData.officialImpliedPowerWatts
       && runtimeData.sameLoadRuntime == runtimeData.sameLoadRuntimeHours
       && runtimeData.averageTelemetryPower == runtimeData.averageTelemetryPowerWatts,
       "产品指标API与带单位别名保持同一口径")

var exaggeratedDerivedData = runtimeData
exaggeratedDerivedData.currentPowerWatts = 0.6
expect(exaggeratedDerivedData.unplugEstimateMinutes == nil,
       "推导续航超过24小时也不展示夸张结果")

runtimeData.timeRemainingMinutes = 155
runtimeData.hardwareDetail.timeRemainingRaw = 155
runtimeData.hardwareDetail.avgTimeToEmpty = 160
let runtimeSampleEnd = Date()
let stablePowers = [10.0, 12.0, 13.0, 14.0, 40.0]
let stablePoints = [
    RealtimeDataPoint(timestamp: runtimeSampleEnd.addingTimeInterval(-700),
                      voltage: 12.3, amperage: -800, power: 1,
                      temperature: 30, percent: 72),
] + stablePowers.enumerated().map { offset, power in
    RealtimeDataPoint(timestamp: runtimeSampleEnd.addingTimeInterval(Double(-30 * offset)),
                      voltage: 12.3, amperage: -800, power: power,
                      temperature: 30, percent: 72)
}
let runtimeSnapshot = DashboardMetricSnapshot(data: runtimeData, realtimeData: stablePoints)
expect(runtimeSnapshot.recentStablePowerSamples.count == 5,
       "稳健估算只采用最近10分钟的有效功耗样本")
expect(abs((runtimeSnapshot.stablePowerWatts ?? 0) - 13) < 0.001,
       "稳健功耗使用中位数，瞬时高负载不会拉偏")
expect(runtimeSnapshot.stableRuntimeMinutes == 178,
       "稳健续航 = 剩余能量 ÷ 最近10分钟功耗中位数")
expect(runtimeSnapshot.currentLoadRuntimeMinutes == 148,
       "当前负载续航继续使用此刻SystemPower")
let runtimeHelp = DashboardHelp.runtime(runtimeSnapshot)
expect(runtimeHelp.comparisonResults.map(\.id) == [
    "runtime.system", "runtime.stable", "runtime.current-load",
], "续航问号同时展示系统时间、稳健估算和当前负载估算")
expect(runtimeHelp.comparisonResults.first?.value == "2 h 35 m",
       "macOS系统时间是三项里的主要结果")
// 三张卡各自先说清「它回答什么问题」，再说机制；机制里的频次必须报电量计的
// 60 秒实测节拍，不能再报我们自己的 10 秒轮询，否则同屏两个数字互相矛盾。
let systemNote = runtimeHelp.comparisonResults.first?.note ?? ""
expect(systemNote.contains("和菜单栏同一个数字")
       && systemNote.contains("TimeRemaining / AvgTimeToEmpty")
       && systemNote.contains("电量计约 60 秒刷新一次")
       && !systemNote.contains("每 10 秒"),
       "系统时间卡先说它是菜单栏同一个数字，频次报 60 秒节拍 [\(systemNote)]")
expect(runtimeSnapshot.latestStablePowerSampleTime == runtimeSampleEnd,
       "稳健估算的读取时间取窗口内最新的有效功耗样本")
let stableNote = runtimeHelp.comparisonResults.first { $0.id == "runtime.stable" }?.note ?? ""
expect(stableNote.contains("按最近这段时间的用法还能撑多久")
       && stableNote.contains("最新样本读取于")
       && stableNote.contains("5 个有效样本"),
       "稳健估算卡先说它回答什么问题，再给样本证据 [\(stableNote)]")
let currentNote = runtimeHelp.comparisonResults.first { $0.id == "runtime.current-load" }?.note ?? ""
expect(currentNote.contains("如果一直像现在这样用")
       && currentNote.contains("最敏感")
       && currentNote.contains("秒前"),
       "当前负载卡说明它最敏感也最容易偏，并给出样本年龄 [\(currentNote)]")

let insufficientSnapshot = DashboardMetricSnapshot(
    data: runtimeData,
    realtimeData: Array(stablePoints.suffix(4))
)
expect(insufficientSnapshot.stableRuntimeMinutes == nil,
       "不足5个样本时不把瞬时读数包装成稳健估算")

var staleRuntimeData = runtimeData
staleRuntimeData.lastUpdated = Date().addingTimeInterval(-121)
let staleRuntimeSnapshot = DashboardMetricSnapshot(
    data: staleRuntimeData,
    realtimeData: stablePoints
)
expect(staleRuntimeSnapshot.currentLoadRuntimeMinutes == nil,
       "当前功耗样本超过120秒时停止当前负载预测")
let runtimeFieldExplanations = runtimeHelp.rawFields.map(\.localizedExplanation)
expect(Set(runtimeFieldExplanations).count == runtimeHelp.rawFields.count,
       "续航卡的每个底层字段都有自己的说明，不共用一句通用话术")
func runtimeFieldExplanation(_ name: String) -> String {
    runtimeHelp.rawFields.first { $0.name == name }?.localizedExplanation ?? ""
}
expect(runtimeFieldExplanation("Derived.StableWindowMedianPower").contains("中位数")
       && !runtimeFieldExplanation("Derived.StableWindowMedianPower").contains("当前"),
       "窗口功耗中位数不能被描述成当前功率")
expect(runtimeFieldExplanation("Derived.StableWindowSamples").contains("样本数"),
       "有效样本数字段说明的是样本个数，不是派生中间值")
expect(runtimeFieldExplanation("Derived.CurrentPowerSampleAge").contains("秒"),
       "功率样本年龄字段说明的是距今秒数")
expect(runtimeFieldExplanation("AppleRawCurrentCapacity").contains("mAh")
       && runtimeFieldExplanation("DesignCapacity").contains("设计容量"),
       "剩余电量原始读数与出厂设计容量分开描述")

print("── 5b) 底层字段的读取时间与更新频次")
func runtimeField(_ name: String) -> MetricRawField? {
    runtimeHelp.rawFields.first { $0.name == name }
}
expect(runtimeHelp.readAt == .ourRead(runtimeData.lastUpdated),
       "没有电量计 UpdateTime 时卡片级读取时间退回本次轮询时刻，并标明出处")
expect(runtimeField("AppleRawCurrentCapacity")?.updateClass == .live
       && runtimeField("AppleRawCurrentCapacity")?.readAt == nil,
       "IOKit 实时字段默认走卡片级读取时间")
expect(runtimeField("DesignCapacity")?.effectiveUpdateClass == .constant,
       "出厂设计容量按名字识别为固定值，不再挂读取频次（ioreg 实测 24 秒内不变）")
expect(runtimeField("AppleRawCurrentCapacity")?.effectiveUpdateClass == .live,
       "剩余电量读数不能被误判成固定值")
expect(MetricFieldFreshness.text(for: runtimeField("DesignCapacity")!,
                                 cardReadAt: .ourRead(runtimeData.lastUpdated),
                                 now: Date()) == "出厂固定值，不随使用变化",
       "固定值显示自己不随使用变化，而不是读取时间")
expect(runtimeField("ModelDesignEnergy")?.updateClass == .modelSpec,
       "内置机型规格电量不能被标成每10秒读一次的实时值")
expect(runtimeField("Derived.CurrentPowerSampleAge")?.updateClass == MetricFieldUpdateClass.untimed,
       "值本身就是读数年龄的字段不再叠加一行秒数")
expect(runtimeField("Derived.StableWindowMedianPower")?.readAt == .ourRead(runtimeSampleEnd)
       && runtimeField("Derived.StableWindowSamples")?.readAt == .ourRead(runtimeSampleEnd),
       "稳健窗口的两行用窗口内最新样本时刻，不用本次轮询时刻")

// 时间说明的三条渲染分支
let liveCaption = MetricFieldFreshness.text(
    for: runtimeField("AppleRawCurrentCapacity")!,
    cardReadAt: .ourRead(runtimeData.lastUpdated),
    now: runtimeData.lastUpdated.addingTimeInterval(3)
) ?? ""
// 频次必须报电量计的实测节拍（60 秒），不能报我们自己的轮询间隔（10 秒）——
// 两轮 5 分钟 ioreg 采样共 300 个样本，所有字段变化间隔最小 58 秒。
expect(liveCaption.contains("读取") && !liveCaption.contains("更新（")
       && liveCaption.contains("3 秒前")
       && liveCaption.contains("电量计约 60 秒刷新一次")
       && !liveCaption.contains("10 秒"),
       "文案报电量计 60 秒节拍，不报 10 秒轮询间隔 [\(liveCaption)]")
expect(MetricFieldFreshness.gaugeRefreshSeconds == 60
       && Int(BatteryService.liveRefreshInterval) == 10,
       "电量计节拍与本地轮询间隔是两个独立常量，不能互相顶替")

print("── 5b2) 分钟原始值附带小时换算，和上方结果行呼应")
// 上方主结果显示 "2 h 30 m"，字段行的 150 min 必须用同一套渲染，否则两个数字
// 看起来像两回事。
expect(runtimeField("TimeRemaining")?.value == "155 min (2 h 35 m)",
       "分钟读数附上与上方结果同格式的小时换算 [\(runtimeField("TimeRemaining")?.value ?? "nil")]")
var shortRuntimeData = runtimeData
shortRuntimeData.hardwareDetail.timeRemainingRaw = 45
let shortHelp = DashboardHelp.runtime(DashboardMetricSnapshot(data: shortRuntimeData, realtimeData: stablePoints))
expect(shortHelp.rawFields.first { $0.name == "TimeRemaining" }?.value == "45 min",
       "不足一小时不加「0 h」的噪音")
var minuteSentinelData = runtimeData
minuteSentinelData.hardwareDetail.timeRemainingRaw = 65535
let minuteSentinelHelp = DashboardHelp.runtime(DashboardMetricSnapshot(data: minuteSentinelData, realtimeData: stablePoints))
expect(minuteSentinelHelp.rawFields.first { $0.name == "TimeRemaining" }?.value == "不可用",
       "哨兵值仍然只显示不可用，不做换算")

print("── 5c) 读取时间取自电量计自报的 UpdateTime")
// 合理性闸门：坏值一律当作没有，不能硬转成 1970 年让所有读数看着无限陈旧
expect(BatteryService.gaugeDate(0) == nil
       && BatteryService.gaugeDate(-1) == nil
       && BatteryService.gaugeDate(nil) == nil
       && BatteryService.gaugeDate(1_000) == nil,
       "UpdateTime 为 0/负数/过小时视为不可用")
expect(BatteryService.gaugeDate(Int(Date().timeIntervalSince1970) + 3_600) == nil,
       "UpdateTime 落在未来一小时视为不可用（时钟异常）")
let sane = Int(Date().timeIntervalSince1970) - 30
expect(BatteryService.gaugeDate(sane).map { Int($0.timeIntervalSince1970) } == sane,
       "合理的 UpdateTime 原样转成时刻")

// 实测场景回归：电量计 15:48:45 发布，我们 15:49:29 才读到 —— 数据真实年龄 44 秒。
// 换用电量计时刻前，这里会显示「0 秒前」，那是在拿我们的动作冒充数据新鲜度。
var gaugeData = runtimeData
let pollMoment = Date()
gaugeData.lastUpdated = pollMoment
gaugeData.hardwareDetail.gaugeUpdateTime = pollMoment.addingTimeInterval(-44)
let gaugeSnapshot = DashboardMetricSnapshot(data: gaugeData, realtimeData: stablePoints)
expect(gaugeSnapshot.rawFieldReadAt == .gauge(pollMoment.addingTimeInterval(-44)),
       "有 UpdateTime 时读取时间用电量计发布时刻，并标明它来自电量计")
let gaugeHelp = DashboardHelp.runtime(gaugeSnapshot)
let gaugeCaption = MetricFieldFreshness.text(
    for: gaugeHelp.rawFields.first { $0.name == "AppleRawCurrentCapacity" }!,
    cardReadAt: gaugeHelp.readAt,
    now: pollMoment
) ?? ""
// 知道电量计相位后，有用的数字是「下次什么时候来」。但报的必须是**你能看到**的时刻，
// 不是电量计发布的时刻：电量计在 60 − 44 = 16 秒后发布，而我们 10 秒轮询一次，
// 这个新值要到第 20 秒那次轮询才会进到界面上。报 16 等于承诺一次用户看不到的刷新。
// 这就是 secondsUntilVisibleRefresh 名字里 visible 的意思，别把它改回 16。
// 上次刷新时刻必须同时保留，否则用户无法判断这批数字有多旧。
expect(gaugeCaption.contains("还有约 20 秒刷新") && gaugeCaption.contains("上次"),
       "已知相位时倒计时到下次「能看到」的刷新，并保留上次刷新时刻 [\(gaugeCaption)]")
expect(!gaugeCaption.contains("0 秒前"),
       "不能再把我们轮询到现在的 0 秒当成数据新鲜度")
// 睡眠唤醒或节拍被事件重置后，倒计时不能数成负数
let overdueCaption = MetricFieldFreshness.text(
    for: gaugeHelp.rawFields.first { $0.name == "AppleRawCurrentCapacity" }!,
    cardReadAt: .gauge(pollMoment.addingTimeInterval(-90)),
    now: pollMoment
) ?? ""
expect(overdueCaption.contains("预计随时刷新") && !overdueCaption.contains("-"),
       "超过一个节拍仍未刷新时改说随时刷新，不出现负秒数 [\(overdueCaption)]")
expect(gaugeSnapshot.currentPowerAgeSeconds >= 44,
       "功率样本年龄同样从电量计时刻起算 [\(gaugeSnapshot.currentPowerAgeSeconds)]")
// 电量计满一个周期（60 秒）+ 轮询滞后仍要留在 120 秒门槛内，否则「当前负载估算」会消失
var worstCaseData = runtimeData
worstCaseData.lastUpdated = Date()
worstCaseData.hardwareDetail.gaugeUpdateTime = Date().addingTimeInterval(-70)
let worstCase = DashboardMetricSnapshot(data: worstCaseData, realtimeData: stablePoints)
expect(worstCase.currentPowerAgeSeconds <= 120 && worstCase.currentLoadRuntimeMinutes != nil,
       "电量计 60 秒节拍 + 10 秒轮询滞后仍在 120 秒门槛内 [\(worstCase.currentPowerAgeSeconds)s]")

// 适配器身份字段不走电量计节拍：实测拔电后 2 秒内就消失
var gaugeAdapterData = runtimeData
gaugeAdapterData.isOnAC = true
gaugeAdapterData.hardwareDetail.gaugeUpdateTime = Date().addingTimeInterval(-50)
gaugeAdapterData.hardwareDetail.adapterWatts = 65
gaugeAdapterData.hardwareDetail.adapterVoltage = 20_000
gaugeAdapterData.hardwareDetail.adapterCurrent = 3_250
gaugeAdapterData.hardwareDetail.presentRawFields.insert("AdapterDetails.Watts")
let gaugeAdapterHelp = DashboardHelp.adapterPower(DashboardMetricSnapshot(data: gaugeAdapterData, realtimeData: stablePoints))
let gaugeWattsField = gaugeAdapterHelp.rawFields.first { $0.name == "AdapterDetails.Watts" }
expect(gaugeWattsField?.updateClass == .eventDriven,
       "适配器额定瓦数标为事件驱动，不挂电量计节拍")
expect(gaugeWattsField?.readAt == .ourRead(gaugeAdapterData.lastUpdated),
       "事件驱动字段用我们自己的读取时刻，不用电量计发布时刻（否则会把它标早 50 秒）")
let gaugeWattsCaption = MetricFieldFreshness.text(for: gaugeWattsField!, cardReadAt: gaugeAdapterHelp.readAt,
                                             now: gaugeAdapterData.lastUpdated) ?? ""
expect(gaugeWattsCaption.contains("插拔时立即变化") && !gaugeWattsCaption.contains("电量计"),
       "适配器字段说明插拔即时生效，不提电量计 [\(gaugeWattsCaption)]")
expect(runtimeField("PackReserve") == nil, "PackReserve 不在续航卡，固定值判定改用直接构造验证")
expect(MetricRawField(name: "PackReserve", value: "127").effectiveUpdateClass == .constant,
       "PackReserve 按实测（两轮共 600 秒恒定）识别为出厂固定值")
expect(MetricRawField(name: "BatteryData.Qmax", value: "4595").effectiveUpdateClass == .live,
       "Qmax 是电量计学习值，长期会变，不能标成固定值")

// 插电时系统结构性不给值，要说明原因而不是让「不可用」看起来像读取失败
var acRuntimeData = runtimeData
acRuntimeData.isOnAC = true
acRuntimeData.hardwareDetail.timeRemainingRaw = 65535
let acHelp = DashboardHelp.runtime(DashboardMetricSnapshot(data: acRuntimeData, realtimeData: stablePoints))
let acTimeField = acHelp.rawFields.first { $0.name == "TimeRemaining" }
expect(acTimeField?.availability == .notProvidedOnAC, "插电时 TimeRemaining 标记为系统不提供")
let acCaption = MetricFieldFreshness.text(for: acTimeField!, cardReadAt: .ourRead(acRuntimeData.lastUpdated),
                                          now: acRuntimeData.lastUpdated) ?? ""
expect(acCaption.contains("插电时系统不提供此值") && !acCaption.contains("刷新一次"),
       "插电不可用时说明原因，且不再提刷新频次（没有值就谈不上频次）[\(acCaption)]")
let batteryTimeField = runtimeField("TimeRemaining")
expect(batteryTimeField?.availability == nil,
       "拔电时 TimeRemaining 不带不可用标记")
expect(MetricFieldFreshness.text(for: runtimeField("ModelDesignEnergy")!,
                                 cardReadAt: .ourRead(runtimeData.lastUpdated),
                                 now: Date()) == "内置机型规格，不随时间变化",
       "机型规格字段说明自己不随时间变化")
expect(MetricFieldFreshness.text(for: runtimeField("Derived.CurrentPowerSampleAge")!,
                                 cardReadAt: .ourRead(runtimeData.lastUpdated),
                                 now: Date()) == nil,
       "标记为 untimed 的字段不渲染时间行")
let noClockField = MetricRawField(name: "X", value: "1", readAt: nil)
expect(MetricFieldFreshness.text(for: noClockField, cardReadAt: nil, now: Date()) == nil,
       "拿不到任何读取时间时整行不显示，不编造时间")

// 秒数分档边界
expect(MetricFieldFreshness.ageText(seconds: 0) == "0 秒"
       && MetricFieldFreshness.ageText(seconds: 59) == "59 秒"
       && MetricFieldFreshness.ageText(seconds: 60) == "1 分钟"
       && MetricFieldFreshness.ageText(seconds: 3599) == "59 分钟"
       && MetricFieldFreshness.ageText(seconds: 3600) == "1 小时",
       "秒/分钟/小时分档在 60 与 3600 秒处切换")
expect(MetricFieldFreshness.seconds(from: runtimeData.lastUpdated,
                                    to: runtimeData.lastUpdated.addingTimeInterval(-5)) == 0,
       "时钟回拨时年龄取 0，不出现负秒数")
let staleCurrentNote = DashboardHelp.runtime(staleRuntimeSnapshot)
    .comparisonResults.first { $0.id == "runtime.current-load" }?.note ?? ""
expect(staleCurrentNote.contains("上次读取于") && staleCurrentNote.contains("已过"),
       "样本过期时备注改说上次读取时间和已过秒数 [\(staleCurrentNote)]")

var pluggedRuntimeData = runtimeData
pluggedRuntimeData.isOnAC = true
let pluggedHelp = DashboardHelp.runtime(
    DashboardMetricSnapshot(data: pluggedRuntimeData, realtimeData: stablePoints)
)
expect(pluggedHelp.comparisonResults.first?.value == "不可用"
       && pluggedHelp.comparisonResults.dropFirst().allSatisfy { $0.value != "—" },
       "插电时系统时间明确不可用，但两项拔电计算值仍可对照")
expect(pluggedHelp.comparisonResults.first?.note.contains("当前接电") == true
       && pluggedHelp.comparisonResults.first?.note.contains("不提供放电剩余时间") == true,
       "插电不可用时备注明确说明状态和原因")

var sentinelRuntimeData = pluggedRuntimeData
sentinelRuntimeData.hardwareDetail.timeRemainingRaw = 65_535
sentinelRuntimeData.hardwareDetail.avgTimeToEmpty = 65_535
let sentinelHelp = DashboardHelp.runtime(
    DashboardMetricSnapshot(data: sentinelRuntimeData, realtimeData: stablePoints)
)
expect(sentinelHelp.comparisonResults.first?.value == "不可用",
       "无效实时字段不再回填历史系统时间")
expect(sentinelHelp.rawFields.prefix(2).allSatisfy {
    $0.value == "不可用" && $0.unit.isEmpty
} && !sentinelHelp.substitution.contains("65535"),
"极限原始值只显示不可用，不再暴露65535")
expect(sentinelHelp.comparisonResults.first?.note.contains("2 h 28 m") == true
       && sentinelHelp.comparisonResults.first?.note.contains("仅作拔电参考") == true,
       "接电时系统时间不可用，并把实测功耗结果明确标成拔电参考")

var exaggeratedRuntimeData = runtimeData
exaggeratedRuntimeData.isOnAC = false
exaggeratedRuntimeData.timeRemainingMinutes = 62_840
exaggeratedRuntimeData.hardwareDetail.timeRemainingRaw = 62_840
exaggeratedRuntimeData.hardwareDetail.avgTimeToEmpty = 65_535
let exaggeratedHelp = DashboardHelp.runtime(
    DashboardMetricSnapshot(data: exaggeratedRuntimeData, realtimeData: stablePoints)
)
expect(exaggeratedHelp.comparisonResults.first?.value == "不可用",
       "超过24小时的实时系统值不显示成夸张时长")
expect(!exaggeratedHelp.substitution.contains("62840"),
       "公式代入区也不暴露超过24小时的极端原始数")

// MARK: - 10.1) 四层系统数据的类型与异常规则

print("── 10.1) 四层系统数据类型与异常规则")
let numericZero = SystemDataCollector.normalizedValueForTesting(NSNumber(value: 0))
expect(numericZero.display == "0" && numericZero.type == "Integer",
       "NSNumber(0) 保持整数，不能误桥成 false")
let boolFalse = SystemDataCollector.normalizedValueForTesting(kCFBooleanFalse as Any)
expect(boolFalse.display == "false" && boolFalse.type == "Boolean",
       "CFBoolean(false) 保持布尔类型")
expect(SystemDataCollector.anomalyLevelForTesting(
        path: "PermanentFailureStatus", value: NSNumber(value: 1)) == 3,
       "永久故障非零进入严重异常")
expect(SystemDataCollector.anomalyLevelForTesting(
        path: "BatteryData.CellVoltage", value: [4300, 4230, 4290]) == 2,
       "电芯压差超过50mV进入警告")
expect(SystemDataCollector.anomalyLevelForTesting(
        path: "Amperage", value: NSNumber(value: -1200)) == 0,
       "正常负放电电流不误报异常")
expect(BatteryService.liveRefreshInterval == 10
       && ProcessMonitorService.liveRefreshInterval == 10,
       "功率、字段与进程上下文统一每10秒刷新")
expect(ProcessMonitorService.refreshInterval(hasHighFrequencyConsumer: true) == 10
       && ProcessMonitorService.refreshInterval(hasHighFrequencyConsumer: false) == 60,
       "进程明细可见时10秒刷新，全部隐藏时降到60秒")
expect(!ProcessMonitorService.shouldResetBaseline(lastSamplingStartedAt: 100,
                                                  nextSamplingStartedAt: 250)
       && ProcessMonitorService.shouldResetBaseline(lastSamplingStartedAt: 100,
                                                    nextSamplingStartedAt: 251),
       "采样间隔超过150秒后重建CPU基线，不把暂停期平均值冒充当前值")

let idleApps = [
    ProcessPowerInfo(pid: 101, name: "Notes", cpuPercent: 0, memoryMB: 80),
    ProcessPowerInfo(pid: 102, name: "Safari", cpuPercent: 0, memoryMB: 420,
                     isForeground: true),
    ProcessPowerInfo(pid: 103, name: "Preview", cpuPercent: 0, memoryMB: 110),
]
let rankedIdleApps = ProcessPowerInfo.rankedForDisplay(idleApps, limit: 3)
expect(rankedIdleApps.count == 3,
       "空闲应用的真实0% CPU样本仍保留，不能被阈值清空")
expect(rankedIdleApps.first?.displayName == "Safari",
       "CPU相同时当前前台应用优先展示")
let mixedApps = idleApps + [
    ProcessPowerInfo(pid: 104, name: "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
                     cpuPercent: 8.4, memoryMB: 650)
]
expect(ProcessPowerInfo.rankedForDisplay(mixedApps, limit: 3).first?.displayName == "Google Chrome",
       "真实CPU较高的可识别应用排在首位")
expect(ProcessMonitorService.sanitizedCPUPercent(.nan) == 0
       && ProcessMonitorService.sanitizedCPUPercent(-12) == 0,
       "进程采样遇到非有限值或负CPU时归零")
expect(ProcessMonitorService.sanitizedCPUPercent(9_999, logicalCoreCount: 8) == 800,
       "进程CPU按逻辑核心数限制异常上界")

// pti_total_user/system 是 mach absolute time tick，不是纳秒。传固定 timebase 断言，
// 这样测试结果不依赖跑测试那台机器的架构。
// Apple Silicon: tbfrequency 24 MHz ⇒ numer/denom = 125/3 ⇒ 1 tick = 41.666… ns
let appleSiliconTicksToNs = 1_000.0 / 24.0
let oneCoreThreeSeconds = ProcessMonitorService.cpuPercent(
    ticksDelta: 72_000_000, seconds: 3, ticksToNanoseconds: appleSiliconTicksToNs)
expect(abs(oneCoreThreeSeconds - 100) < 0.01,
       "24MHz timebase 下单核满载3秒=100% [\(oneCoreThreeSeconds)]")
// 同一批 tick 若当成纳秒处理就是 2.4%，正是修复前的症状 —— 锁住这个回归
expect(abs(ProcessMonitorService.cpuPercent(ticksDelta: 72_000_000, seconds: 3,
                                            ticksToNanoseconds: 1) - 2.4) < 0.01,
       "把 tick 当纳秒会低估成 2.4%，这是修复前的错误行为")
let intelOneCore = ProcessMonitorService.cpuPercent(
    ticksDelta: 3_000_000_000, seconds: 3, ticksToNanoseconds: 1)
expect(abs(intelOneCore - 100) < 0.01,
       "Intel timebase(1:1) 下单核满载3秒=100% [\(intelOneCore)]")
expect(ProcessMonitorService.cpuPercent(ticksDelta: 100, seconds: 0) == 0
       && ProcessMonitorService.cpuPercent(ticksDelta: 100, seconds: -1) == 0,
       "采样间隔非正时不产生无穷大")
expect(ProcessMonitorService.machTicksToNanoseconds > 0,
       "本机 timebase 换算系数有效 [\(ProcessMonitorService.machTicksToNanoseconds)]")

// 显示名只剥尾部 .app，不做全局子串替换（否则 com.apple.* 会被打烂）
expect(ProcessPowerInfo(pid: 1, name: "com.apple.WebKit.WebContent",
                        cpuPercent: 1, memoryMB: 1).displayName == "com.apple.WebKit.WebContent",
       "反向域名式进程名不被 .app 替换打烂")
expect(ProcessPowerInfo(pid: 1, name: "/Applications/Safari.app",
                        cpuPercent: 1, memoryMB: 1).displayName == "Safari",
       "尾部 .app 后缀正常剥离")

// 进度条绝对刻度：满格 = 占满一个核，不再按列表最大值归一化
expect(ProcessRow.barFraction(cpuPercent: 1.7) < 0.02,
       "空闲进程画短条，不再因为是列表最大值就画满格")
expect(ProcessRow.barFraction(cpuPercent: 100) == 1
       && ProcessRow.barFraction(cpuPercent: 850) == 1,
       "达到或超过单核满载时封顶在满格")
expect(ProcessRow.barFraction(cpuPercent: .nan) == 0
       && ProcessRow.barFraction(cpuPercent: -5) == 0,
       "非有限值和负值不产生异常条宽")
expect(ProcessRow.cpuText(412.34).contains("412") && !ProcessRow.cpuText(412.34).contains(".3"),
       "三位数读数去掉小数位以免撑爆固定宽度 [\(ProcessRow.cpuText(412.34))]")

// 进程归组：把子进程折进最近的祖先 GUI app
func tableEntry(_ pid: Int32, _ ppid: Int32, _ comm: String) -> ProcessTable.Entry {
    ProcessTable.Entry(pid: pid, ppid: ppid, comm: comm, startTime: 1_785_776_700)
}
// Chromium 式 fork 树：Chrome 主进程(1527) → 三个 helper
// Terminal(55435) → zsh(75268) → claude(75285)，跨两层也要归到 Terminal
// com.apple.WebKit.WebContent(900) ppid 是 1，归不进任何 app —— 实测本机 458/547 都是这样
// 自己(4460) 和自己的子进程(4461) 整棵子树必须消失
let fixtureTable = [
    tableEntry(1527, 1, "Google Chrome"),
    tableEntry(1535, 1527, "Google Chrome He"),
    tableEntry(1536, 1527, "Google Chrome He"),
    tableEntry(1537, 1535, "Google Chrome He"),
    tableEntry(55435, 1, "Terminal"),
    tableEntry(75268, 55435, "zsh"),
    tableEntry(75285, 75268, "claude"),
    tableEntry(900, 1, "com.apple.WebKit.WebContent"),
    tableEntry(4460, 1, "BatteryMonitor"),
    tableEntry(4461, 4460, "xpcproxy"),
]
let fixtureRoots = ProcessTable.rollUp(entries: fixtureTable,
                                       appPids: [1527, 55435, 4460],
                                       excludingSubtreeOf: 4460)
expect(fixtureRoots[1535] == 1527 && fixtureRoots[1536] == 1527 && fixtureRoots[1537] == 1527,
       "Chromium 式 helper（含隔一层的孙进程）全部折进 Chrome 主进程")
expect(fixtureRoots[75285] == 55435 && fixtureRoots[75268] == 55435,
       "跨 zsh 两层的 claude 归到 Terminal [\(String(describing: fixtureRoots[75285]))]")
expect(fixtureRoots[900] == 900,
       "ppid==1 的 XPC helper 自己成组，不硬塞给某个 app")
expect(fixtureRoots[4460] == nil && fixtureRoots[4461] == nil,
       "本进程整棵子树被剪掉，不把自己的采样开销算进排行")
expect(fixtureRoots[1527] == 1527 && fixtureRoots[55435] == 55435,
       "app 主进程自己就是组根")

// ppid 成环和自环必须终止，不能挂死采样线程
let cyclicTable = [tableEntry(10, 11, "a"), tableEntry(11, 10, "b"), tableEntry(0, 0, "kernel_task")]
let cyclicRoots = ProcessTable.rollUp(entries: cyclicTable, appPids: [], excludingSubtreeOf: 99999)
expect(cyclicRoots.count == 3 && cyclicRoots[10] == 10 && cyclicRoots[0] == 0,
       "ppid 成环/自环时归组终止且每个进程自成一组")
expect(ProcessTable.rollUp(entries: [], appPids: [1], excludingSubtreeOf: 1).isEmpty,
       "空进程表不崩")

// groupKey 决定 SwiftUI 行身份，必须稳定且唯一
let sameNameA = ProcessPowerInfo(pid: 10, name: "claude", cpuPercent: 1, memoryMB: 1)
let sameNameB = ProcessPowerInfo(pid: 11, name: "claude", cpuPercent: 1, memoryMB: 1)
expect(sameNameA.id != sameNameB.id,
       "未指定 groupKey 时同名进程的行身份仍然唯一（默认走 pid，不走 name）")
let aggregated = ProcessPowerInfo(pid: 1527, name: "/Applications/Google Chrome.app",
                                  cpuPercent: 16.1, memoryMB: 2048,
                                  groupKey: "app:com.google.Chrome",
                                  processCount: 21, topChildName: "Google Chrome Helper (Renderer)")
expect(aggregated.id == "app:com.google.Chrome" && aggregated.processCount == 21
       && aggregated.topChildName == "Google Chrome Helper (Renderer)",
       "聚合行携带 groupKey / 进程数 / 最重子进程名")
expect(ProcessPowerInfo(pid: 1, name: "x", cpuPercent: 1, memoryMB: 1, processCount: 0).processCount == 1,
       "进程数下界为 1，不出现 0 个进程的行")

// 全机 CPU：整机口径 vs 每核口径。混算会让「未归因负载」恒为 0
let loadA = SystemCPULoad.Sample(user: 1000, system: 500, idle: 8500, nice: 0)
let loadB = SystemCPULoad.Sample(user: 1200, system: 600, idle: 8700, nice: 0)
let busy = SystemCPULoad.busyPercent(from: loadA, to: loadB)
// Δuser 200 + Δsys 100 = 300 忙，Δidle 200 ⇒ 300/500 = 60%
expect(busy != nil && abs(busy! - 60) < 0.01, "整机忙碌 = 非 idle tick / 总 tick [\(busy ?? -1)]")
expect(SystemCPULoad.busyPercent(from: loadA, to: loadA) == nil,
       "两次快照之间 tick 没动时返回 nil，不显示 0%")
// natural_t 是 UInt32，约 50 天 uptime 后回绕；差值必须用 &- 才不会算出天文数字
let nearMax = SystemCPULoad.Sample(user: UInt32.max - 100, system: 0, idle: 0, nice: 0)
let wrapped = SystemCPULoad.Sample(user: 99, system: 0, idle: 101, nice: 0)
let wrapBusy = SystemCPULoad.busyPercent(from: nearMax, to: wrapped)
expect(wrapBusy != nil && abs(wrapBusy! - 66.4) < 0.5,
       "UInt32 回绕时差值仍然正确（200 忙 / 301 总）[\(wrapBusy ?? -1)]")

// 这是原方案里的真错误：10 核机上「整机 30%」减「Chrome 300%」会得负数
expect(abs(SystemCPULoad.machinePercent(perCorePercent: 300, coreCount: 10) - 30) < 0.01,
       "每核 300%（占满 3 个核）在 10 核机上等于整机 30%")
expect(SystemCPULoad.machinePercent(perCorePercent: 300, coreCount: 0) <= 100,
       "核心数为 0 时不除零、不超过 100%")
let snapshot10 = SystemCPUSnapshot(machineBusy: 28.0, visiblePerCorePercent: 74.0, coreCount: 10)
expect(abs(snapshot10.visiblePercent - 7.4) < 0.01,
       "可读进程每核合计 74% → 整机 7.4% [\(snapshot10.visiblePercent)]")
expect(snapshot10.systemPercent != nil && abs(snapshot10.systemPercent! - 20.6) < 0.01,
       "未归因负载 = 整机 28.0 − 可读 7.4 = 20.6 [\(String(describing: snapshot10.systemPercent))]")
// 换算前后必须都不出现负数：可见合计可能因为采样窗口错位略超整机
let overshoot = SystemCPUSnapshot(machineBusy: 5.0, visiblePerCorePercent: 900.0, coreCount: 10)
expect(overshoot.systemPercent == 0, "可读合计超过整机时未归因负载夹到 0，不显示负数")
expect(SystemCPUSnapshot(machineBusy: nil, visiblePerCorePercent: 74, coreCount: 10).systemPercent == nil,
       "还没有整机读数时未归因负载也是 nil，UI 显示「—」")
expect(SystemCPUSnapshot.unavailable.machineBusyPercent == nil,
       "首次采样前整机读数不可用")

// 副标题：聚合行报「最重子进程 · 进程数」，单进程行只报内存
let grouped = ProcessPowerInfo(pid: 55435, name: "/Applications/Utilities/Terminal.app",
                               cpuPercent: 31.6, memoryMB: 512,
                               groupKey: "app:com.apple.Terminal",
                               processCount: 10, topChildName: "claude")
expect(ProcessRow.subtitle(for: grouped).contains("claude")
       && ProcessRow.subtitle(for: grouped).contains("10"),
       "聚合行副标题点名最重子进程和进程数 [\(ProcessRow.subtitle(for: grouped))]")
let groupedNoChild = ProcessPowerInfo(pid: 1, name: "/Applications/Foo.app", cpuPercent: 1,
                                      memoryMB: 100, processCount: 4)
expect(!ProcessRow.subtitle(for: groupedNoChild).contains("PID")
       && ProcessRow.subtitle(for: groupedNoChild).contains("4"),
       "无够重子进程时只报进程数，且不再显示无意义的 PID [\(ProcessRow.subtitle(for: groupedNoChild))]")
let single = ProcessPowerInfo(pid: 1, name: "/Applications/Foo.app", cpuPercent: 1, memoryMB: 100)
expect(!ProcessRow.subtitle(for: single).contains("1 "),
       "单进程行不硬凑「1 个进程」这种废话 [\(ProcessRow.subtitle(for: single))]")

print("── 10b) 外观与菜单栏配置持久化")
let preferenceSuiteName = "com.stephen.BatteryMonitor.tests.presentation"
let preferenceDefaults = UserDefaults(suiteName: preferenceSuiteName)!
preferenceDefaults.removePersistentDomain(forName: preferenceSuiteName)

let appearancePreferences = AppearanceSettings(defaults: preferenceDefaults, defaultMode: .light)
expect(appearancePreferences.mode == .light
       && preferenceDefaults.string(forKey: "app.appearance.mode") == AppearanceMode.light.rawValue,
       "首次启动把系统外观解析成可见的浅色或深色选项")
appearancePreferences.select(.dark)
expect(AppearanceSettings(defaults: preferenceDefaults).mode == .dark,
       "深色外观选择可持久化并由新实例恢复")
appearancePreferences.select(.light)
expect(AppearanceSettings(defaults: preferenceDefaults).mode == .light,
       "浅色外观选择可覆盖深色并持久化")
preferenceDefaults.set(AppearanceMode.system.rawValue, forKey: "app.appearance.mode")
let migratedAppearance = AppearanceSettings(defaults: preferenceDefaults, defaultMode: .dark)
expect(migratedAppearance.mode == .dark
       && preferenceDefaults.string(forKey: "app.appearance.mode") == AppearanceMode.dark.rawValue,
       "旧版跟随系统偏好会迁移成当前系统对应的具体颜色")

let menuPreferences = MenuBarSettings(defaults: preferenceDefaults)
expect(menuPreferences.secondaryMetric == .runtime,
       "顶部状态栏默认显示电量 + 剩余时间")
expect(menuPreferences.visibleMetrics == MenuBarSettings.defaultVisibleMetrics,
       "菜单栏弹层默认指标顺序稳定")
expect(menuPreferences.visibleTrendMetrics == MenuBarSettings.defaultVisibleTrendMetrics,
       "动态趋势默认显示功率、续航和电流")
menuPreferences.selectSecondaryMetric(.power)
menuPreferences.setVisible(.runtime, visible: false)
menuPreferences.move(.health, by: -2)
menuPreferences.move(.cycles, to: 0)
menuPreferences.setTrendVisible(.runtime, visible: false)
menuPreferences.moveTrend(.current, to: 0)
let restoredMenuPreferences = MenuBarSettings(defaults: preferenceDefaults)
expect(restoredMenuPreferences.secondaryMetric == .power,
       "顶部第二指标可切换为当前功率并持久化")
expect(!restoredMenuPreferences.visibleMetrics.contains(.runtime)
       && restoredMenuPreferences.visibleMetrics.first == .cycles
       && restoredMenuPreferences.visibleMetrics.firstIndex(of: .health) == 2,
       "弹层指标可隐藏、按钮移动与拖放移动，并保持用户顺序")
expect(restoredMenuPreferences.visibleTrendMetrics == [.current, .power],
       "动态趋势可删除、拖放调整顺序，并保持用户设置")
restoredMenuPreferences.setTrendVisible(.current, visible: false)
restoredMenuPreferences.setTrendVisible(.power, visible: false)
expect(MenuBarSettings(defaults: preferenceDefaults).visibleTrendMetrics.isEmpty,
       "删除全部动态趋势后仍保持空列表，不会在下次打开时意外恢复")
restoredMenuPreferences.resetTrends()
expect(MenuBarSettings(defaults: preferenceDefaults).visibleTrendMetrics == MenuBarSettings.defaultVisibleTrendMetrics,
       "动态趋势为空时可恢复默认列表")

DashboardNavigation.shared.destination = .settings
expect(DashboardNavigation.shared.destination == .settings,
       "添加更多指标可把完整看板直接导航到设置页")
DashboardNavigation.shared.destination = .overview
preferenceDefaults.removePersistentDomain(forName: preferenceSuiteName)

print("── 10c) 主指标图标语义与系统兼容")
let metricIcons = BatteryMetricIcon.allCases
expect(metricIcons.count == Set(metricIcons.map(\.symbol)).count,
       "主指标各自使用可辨识的独立 SF Symbol")
let unavailableMetricSymbols = metricIcons.filter {
    NSImage(systemSymbolName: $0.symbol, accessibilityDescription: nil) == nil
}
expect(unavailableMetricSymbols.isEmpty,
       "所有主指标图标均能由当前 macOS 解析\(unavailableMetricSymbols.isEmpty ? "" : "：\(unavailableMetricSymbols.map(\.rawValue))")")
let unavailableFallbackSymbols = metricIcons.filter {
    NSImage(systemSymbolName: $0.fallbackSymbol, accessibilityDescription: nil) == nil
}
expect(unavailableFallbackSymbols.isEmpty,
       "macOS 14 兼容回退图标不会留下空白占位\(unavailableFallbackSymbols.isEmpty ? "" : "：\(unavailableFallbackSymbols.map(\.rawValue))")")
expect(MenuBarMetric.allCases.allSatisfy { $0.symbol == $0.icon.symbol },
       "菜单栏、总览与详情页共用同一套指标图标映射")

// MARK: - 11) 系统时间与功耗口径

print("── 11) 系统时间与功耗口径")
expect(BatteryService.preferredSystemTimeRemaining(isOnAC: false,
        timeRemaining: 148, avgTimeToEmpty: 150) == 148,
       "电池供电优先TimeRemaining")
expect(BatteryService.preferredSystemTimeRemaining(isOnAC: false,
        timeRemaining: 65_535, avgTimeToEmpty: 150) == 150,
       "TimeRemaining=65535时退到有效AvgTimeToEmpty")
expect(BatteryService.preferredSystemTimeRemaining(isOnAC: false,
        timeRemaining: 1_441, avgTimeToEmpty: 150) == 150,
       "超过24小时的TimeRemaining退到可信AvgTimeToEmpty")
expect(BatteryService.preferredSystemTimeRemaining(isOnAC: false,
        timeRemaining: 0, avgTimeToEmpty: 65_535) == nil,
       "0与65535都不是有效分钟")
expect(BatteryService.preferredSystemTimeRemaining(isOnAC: true,
        timeRemaining: 148, avgTimeToEmpty: 150) == nil,
       "插电时不把电量计值作为系统剩余续航")

let persistenceBase = Date(timeIntervalSince1970: 1_000)
expect(!BatteryService.shouldPersistRuntimeHistory(
    dirty: false, lastSaved: nil, now: persistenceBase),
       "没有新续航样本时不落盘")
expect(BatteryService.shouldPersistRuntimeHistory(
    dirty: true, lastSaved: nil, now: persistenceBase),
       "首次有效续航样本及时落盘")
expect(!BatteryService.shouldPersistRuntimeHistory(
    dirty: true, lastSaved: persistenceBase, now: persistenceBase.addingTimeInterval(299)),
       "五分钟内的新样本只留在内存，避免频繁写盘")
expect(BatteryService.shouldPersistRuntimeHistory(
    dirty: true, lastSaved: persistenceBase, now: persistenceBase.addingTimeInterval(300)),
       "累计五分钟后批量持久化续航历史")
expect(BatteryService.shouldPersistRuntimeHistory(
    dirty: true, lastSaved: persistenceBase, now: persistenceBase, force: true),
       "暂停或退出时强制冲刷未保存续航历史")

var powerDetail = BatteryHardwareDetail()
powerDetail.systemPowerWatts = 15.67
powerDetail.systemLoad = 22_568
expect(abs(BatteryService.preferredPowerWatts(hardwareDetail: powerDetail,
        amperage: -1307, voltage: 12.306) - 15.67) < 0.001,
       "功耗首选BatteryData.SystemPower")
powerDetail.systemPowerWatts = 0
expect(abs(BatteryService.preferredPowerWatts(hardwareDetail: powerDetail,
        amperage: -1307, voltage: 12.306) - 22.568) < 0.001,
       "SystemPower缺失时使用SystemLoad")
powerDetail.systemLoad = 0
expect(abs(BatteryService.preferredPowerWatts(hardwareDetail: powerDetail,
        amperage: -1307, voltage: 12.306) - 16.083) < 0.01,
       "两种系统功耗都缺失时才用I×V")

// MARK: - 12) 新增IOKit原始字段解析

print("── 12) 新增IOKit原始字段解析")
var batteryDictionary: [String: Any] = [
    "CellVoltage": [4113, 4106, 4101], "Qmax": [4595, 4631, 4661],
    "WeightedRa": [88, 101, 108], "PresentDOD": [22, 22, 22],
    "CellWom": [0, 0], "ChemicalWeightedRa": 0,
    "FccComp1": 4082, "FccComp2": 4082,
    "ChemID": 29961, "AlgoChemID": 29961,
    "ManufactureDate": 58_485_394_912_051, "DateOfFirstUse": 0,
    "QmaxDisqualificationReason": 0, "SystemPower": 15.67,
]
for i in 0..<15 { batteryDictionary[String(format: "Ra%02d", i)] = 70 + i }
let registry: [String: Any] = [
    "CycleCount": 211, "DesignCapacity": 4629, "DesignCycleCount9C": 1000,
    "NominalChargeCapacity": 4209, "AppleRawMaxCapacity": 4082,
    "AppleRawCurrentCapacity": 3322, "PackReserve": 127,
    "CurrentCapacity": 86, "MaxCapacity": 100,
    "TimeRemaining": 148, "AvgTimeToEmpty": 150, "AvgTimeToFull": 65_535,
    "BatteryInvalidWakeSeconds": 30,
    "Voltage": 12319, "AppleRawBatteryVoltage": 12318, "Temperature": 3089,
    "VirtualTemperature": 3124,
    "BatteryInstalled": true, "built-in": true,
    "BatteryData": batteryDictionary,
    "PowerTelemetryData": [
        "SystemLoad": 22_568, "BatteryPower": -22_568,
        "SystemPowerIn": 65_000, "VoltageIn": 20_000, "CurrentIn": 3_250,
        "AdapterEfficiencyLoss": 0,
        "AccumulatedSystemLoad": 1_183_465_630,
        "SystemLoadAccumulatorCount": 134_998,
        "AccumulatedWallEnergyEstimate": 274_276_329,
    ],
    "CarrierMode": [
        "CarrierModeHighVoltage": 4100,
        "CarrierModeLowVoltage": 3600,
        "CarrierModeStatus": 0,
    ],
    "PortControllerInfo": [[
        "PortControllerAttachCount": 12,
        "PortControllerDetachCount": 12,
        "PortControllerCapMismatch": 0,
        "PortControllerElectionFailReason": 0,
    ]],
]
let parsed = BatteryService.parseHardwareDetail(registry, fallbackCycleCount: 0)
expect(parsed.fccComp1 == 4082 && parsed.fccComp2 == 4082,
       "FccComp1/FccComp2完整解析")
expect(parsed.cellWom == [0, 0] && parsed.chemicalWeightedRa == 0,
       "有效0与字段缺失可以区分")
expect(parsed.raCurve?.count == 15 && parsed.raCurve?.first == 70 && parsed.raCurve?.last == 84,
       "Ra00–Ra14按顺序完整解析")
expect(parsed.timeRemainingRaw == 148 && parsed.avgTimeToEmpty == 150
       && parsed.avgTimeToFull == 65_535 && parsed.batteryInvalidWakeSeconds == 30,
       "三个续航字段与唤醒窗口保留原值")
expect(parsed.voltageRaw == 12319 && parsed.appleRawBatteryVoltage == 12318
       && parsed.temperatureRaw == 3089 && parsed.virtualTemperatureRaw == 3124,
       "电压双口径与两种原始温度没有被折叠")
expect(abs(parsed.virtualTemperature - 31.24) < 0.001,
       "VirtualTemperature原始值同时转换为摄氏度")
expect(parsed.systemVoltageIn == 20_000 && parsed.systemCurrentIn == 3_250,
       "VoltageIn/CurrentIn使用真机字段名")
expect(parsed.accumulatedSystemLoad == 1_183_465_630
       && parsed.systemLoadAccumulatorCount == 134_998,
       "累计功耗分子与采样数完整解析")
expect(parsed.carrierMode?.highVoltage == 4100 && parsed.carrierMode?.status == 0,
       "CarrierMode有效0状态被保留")
expect(parsed.portControllers.first?.attachCount == 12
       && parsed.portControllers.first?.capabilityMismatch == 0,
       "端口插拔与协商失败计数被保留")
expect(parsed.algorithmChemistryID == 29961 && parsed.manufactureDateRaw == 58_485_394_912_051
       && parsed.dateOfFirstUseRaw == 0 && parsed.qmaxDisqualificationReason == 0,
       "化学ID、批号、首次使用与Qmax校验码完整解析")
expect(parsed.batteryInstalled == true && parsed.isBuiltIn == true,
       "安装/内置布尔字段完整解析")
expect(parsed.presentRawFields.contains("BatteryData.SystemPower")
       && parsed.presentRawFields.contains("PowerTelemetryData.AdapterEfficiencyLoss")
       && parsed.presentRawFields.contains("CarrierMode.CarrierModeStatus"),
       "真实存在且值可为0的字段会记录存在性")
expect(!parsed.presentRawFields.contains("PermanentFailureStatus")
       && !parsed.presentRawFields.contains("ChargerData.NotChargingReason"),
       "缺失字段不会因模型默认0而伪装成实测0")
expect(parsed.usedSinceFullCapacity == 760,
       "本次已用 = FCC − 当前容量")
expect(parsed.unusableCharge == 513 && parsed.permanentChemicalLoss == 34,
       "长期差额可拆为 Qmax−FCC 与 Design−Qmax")

var invalidQmax = healthyDetail()
invalidQmax.qmax = [4_700, 4_710, 4_720]
expect(invalidQmax.unusableCharge == nil && invalidQmax.permanentChemicalLoss == nil,
       "Qmax 超出 Design 时不拆分长期容量差额")
invalidQmax.qmax = [4_000, 4_010, 4_020]
expect(invalidQmax.unusableCharge == nil && invalidQmax.permanentChemicalLoss == nil,
       "Qmax 低于 FCC 时不拆分长期容量差额")

var missingCurrentCapacity = healthyDetail()
missingCurrentCapacity.presentRawFields.remove("AppleRawCurrentCapacity")
expect(missingCurrentCapacity.usedSinceFullCapacity == nil,
       "当前容量字段缺失时不把默认0误判为全部用掉")

// MARK: - 13) 56秒系统续航历史

print("── 13) 56秒系统续航历史")
let t0 = Date(timeIntervalSince1970: 1_000)
let r0 = RuntimeSample(timestamp: t0, minutesRemaining: 148, percent: 86)
let r55 = RuntimeSample(timestamp: t0.addingTimeInterval(55), minutesRemaining: 147, percent: 85)
let r56 = RuntimeSample(timestamp: t0.addingTimeInterval(56), minutesRemaining: 147, percent: 85)
expect(RuntimeSample.isValid(minutes: 1) && RuntimeSample.isValid(minutes: 1_440)
       && !RuntimeSample.isValid(minutes: 0) && !RuntimeSample.isValid(minutes: 1_441)
       && !RuntimeSample.isValid(minutes: 65_535),
       "产品展示的系统剩余时间有效范围严格为1...1440分钟")
expect(RuntimeSample.shouldAppend(r0, after: nil), "首个有效样本可写入")
expect(!RuntimeSample.shouldAppend(r55, after: r0), "55秒不重复写入")
expect(RuntimeSample.shouldAppend(r56, after: r0), "满56秒才写入下一点")
let usageNow = t0.addingTimeInterval(70 * 60)
let usageSamples = [
    RuntimeSample(timestamp: usageNow.addingTimeInterval(-70 * 60), minutesRemaining: 180, percent: 80),
    RuntimeSample(timestamp: usageNow.addingTimeInterval(-69 * 60), minutesRemaining: 179, percent: 80),
    RuntimeSample(timestamp: usageNow.addingTimeInterval(-60 * 60), minutesRemaining: 170, percent: 76),
    RuntimeSample(timestamp: usageNow.addingTimeInterval(-59 * 60), minutesRemaining: 169, percent: 76),
    RuntimeSample(timestamp: usageNow.addingTimeInterval(-58 * 60), minutesRemaining: 168, percent: 75),
]
expect(RuntimeSample.observedUsageDuration(in: usageSamples, now: usageNow) == 3 * 60,
       "实际使用时长只累计连续采样区间，不把9分钟空档算作电池使用")
expect(RuntimeSample.observedUsageDuration(
    in: usageSamples,
    now: usageNow.addingTimeInterval(25 * 60 * 60)
) == 0, "近24小时之外的旧系统读数不计入近期实际使用")
expect(SOCHistory.fullHoldSamplesPerEvent == 32,
       "56秒采样下约32个满充样本对应30分钟")
if let encoded = try? JSONEncoder().encode([r0, r56]),
   let decoded = try? JSONDecoder().decode([RuntimeSample].self, from: encoded) {
    expect(decoded == [r0, r56], "RuntimeSample列表可JSON持久化往返")
} else { expect(false, "RuntimeSample JSON编解码不应失败") }

// MARK: - 14) 菜单栏剩余时间口径

print("── 14) 菜单栏剩余时间口径")
var menuBattery = data(from: healthyDetail(), onAC: false)
menuBattery.timeRemainingMinutes = 248
menuBattery.currentPowerWatts = 40
var menuPresentation = MenuBarPresentation(data: menuBattery)
expect(menuPresentation.runtimeMinutes == 248 && !menuPresentation.isForecast,
       "电池供电时菜单栏直接采用macOS的248分钟，不被当前功率二次改写")
expect(MenuBarPresentation.durationText(menuPresentation.runtimeMinutes) == "4h 08m",
       "菜单栏分钟数格式化为小时和分钟")
var textOnlyStatusBattery = menuBattery
textOnlyStatusBattery.percent = 60
textOnlyStatusBattery.timeRemainingMinutes = 246
let textOnlyStatus = MenuBarPresentation(data: textOnlyStatusBattery)
    .menuBarText(secondaryMetric: .runtime)
expect(textOnlyStatus == "60% (4h 06m)",
       "顶部状态项只展示电量与所选指标文字，不混入电池或充电图标")
let choicePreviews = MenuBarMetric.allCases.map {
    MenuBarPresentation(data: textOnlyStatusBattery).choicePreviewText(for: $0)
}
expect(zip(MenuBarMetric.allCases, choicePreviews).allSatisfy { pair in
    let (metric, preview) = pair
    return preview.contains(metric.title)
        && preview.contains(MenuBarPresentation(data: textOnlyStatusBattery)
            .menuBarText(secondaryMetric: metric))
}, "顶部指标下拉的每一项同时展示指标名称与对应状态栏预览")

var menuAC = menuBattery
menuAC.isOnAC = true
menuAC.modelIdentifier = "Mac16,12"
menuAC.timeRemainingMinutes = 999
menuAC.currentPowerWatts = 10
menuPresentation = MenuBarPresentation(data: menuAC)
expect(menuPresentation.isForecast
       && menuPresentation.runtimeMinutes == menuAC.unplugEstimateMinutes
       && menuPresentation.runtimeMinutes != 999,
       "插电时不沿用系统剩余时间，改用明确标注的拔电预计")

var menuWaiting = menuBattery
menuWaiting.timeRemainingMinutes = nil
menuPresentation = MenuBarPresentation(data: menuWaiting)
expect(menuPresentation.runtimeMinutes == nil
       && MenuBarPresentation.durationText(menuPresentation.runtimeMinutes) == "—",
       "系统尚未给出剩余时间时显示等待态，不编造数字")

// MARK: - 15) 概览卡：四种电源状态与两项新读数

print("── 15) 概览卡电源状态与电流/充满时间")
var heroDetail = healthyDetail()
heroDetail.presentRawFields.insert("InstantAmperage")
heroDetail.instantAmperage = -2150

func heroState(_ d: BatteryData) -> BatteryPowerState {
    BatteryPowerState.resolve(DashboardMetricSnapshot(data: d, realtimeData: []))
}
// 电量计休息时的读数：不足半瓦，判定要落回标志位
var restingDetail = healthyDetail()
restingDetail.presentRawFields.insert("InstantAmperage")
restingDetail.instantAmperage = -12

var disheroCharging = data(from: heroDetail, onAC: false)
expect(heroState(disheroCharging) == .discharging, "未接电源判为放电中")

var heroCharging = data(from: heroDetail, onAC: true)
heroCharging.hardwareDetail.instantAmperage = 1800
expect(heroState(heroCharging) == .charging, "实测正电流即判为充电中")
heroCharging.isFullyCharged = true
expect(heroState(heroCharging) == .charging,
       "充电末端标志说已充满、电流仍在进，以电流为准判充电中")

var heroFull = data(from: restingDetail, onAC: true)
heroFull.isFullyCharged = true
expect(heroState(heroFull) == .full, "电流归零且报告充满判为已充满")

var heroTaperCharging = data(from: restingDetail, onAC: true)
heroTaperCharging.isCharging = true
expect(heroState(heroTaperCharging) == .charging,
       "电流已收尾但 IsCharging 仍为真时落回标志，判充电中")

var heroIdle = data(from: restingDetail, onAC: true)
expect(heroState(heroIdle) == .pluggedIdle,
       "接电、电流在静止带内、未充满判为插电未充电")

var heroPluggedDrain = data(from: heroDetail, onAC: true)
expect(heroState(heroPluggedDrain) == .pluggedDischarging,
       "接电但电池仍在放电时给出独立状态，不再和「未充电」混为一谈")

// 带符号电流：优化充电停在 80% 时实测为 −694 mA，符号必须保留
heroIdle.hardwareDetail.instantAmperage = -694
let idleSnapshot = DashboardMetricSnapshot(data: heroIdle, realtimeData: [])
expect(idleSnapshot.batteryCurrentMilliamps == -694,
       "插电未充电时电流保留负号，暴露电池仍在放电 [\(idleSnapshot.batteryCurrentMilliamps.map(String.init) ?? "nil")]")
expect(idleSnapshot.batteryChargingCurrentMilliamps == 0,
       "旧的充电电流访问器仍返回 0，两者语义不同不可互相替代")

var chargingCurrentData = heroCharging
chargingCurrentData.hardwareDetail.instantAmperage = 1820
expect(DashboardMetricSnapshot(data: chargingCurrentData, realtimeData: []).batteryCurrentMilliamps == 1820,
       "充电时为正值")

var heroSmoothedOnly = data(from: healthyDetail(), onAC: false)
heroSmoothedOnly.hardwareDetail.presentRawFields.insert("Amperage")
heroSmoothedOnly.hardwareDetail.smoothedAmperage = -1500
heroSmoothedOnly.hardwareDetail.instantAmperage = 9999    // 未标记 present，必须被忽略
expect(DashboardMetricSnapshot(data: heroSmoothedOnly, realtimeData: []).batteryCurrentMilliamps == -1500,
       "只有 Amperage 时用平滑值，不读未上报的 InstantAmperage")

var heroNoCurrent = data(from: BatteryHardwareDetail(), onAC: false)
heroNoCurrent.amperage = 0
expect(DashboardMetricSnapshot(data: heroNoCurrent, realtimeData: []).batteryCurrentMilliamps == nil,
       "字段全缺时返回 nil，不用 0 冒充读数")

// 充满时间：AvgTimeToFull 是未过滤原始值
var heroToFull = heroCharging
// 必须显式打开 isCharging。上面那批断言用的是 heroState()／BatteryPowerState，
// 它由实测电流推断充电；而 timeToFullMinutes 读的是系统给的 data.isCharging 原始
// 标志位（同 batteryChargingPowerWatts）。heroCharging 只设了 isOnAC 和
// instantAmperage，还在 1261 行被置成 isFullyCharged —— 拿它当「正在充电」的样本，
// 测的其实是「没在充电时返回 nil」，跟断言想说的事情正好相反。
heroToFull.isCharging = true
heroToFull.isFullyCharged = false
heroToFull.hardwareDetail.avgTimeToFull = 72
expect(DashboardMetricSnapshot(data: heroToFull, realtimeData: []).timeToFullMinutes == 72,
       "充电中的合理充满时间透传")
heroToFull.hardwareDetail.avgTimeToFull = 65535
expect(DashboardMetricSnapshot(data: heroToFull, realtimeData: []).timeToFullMinutes == nil,
       "65535 哨兵挡掉")
heroToFull.hardwareDetail.avgTimeToFull = 20000
expect(DashboardMetricSnapshot(data: heroToFull, realtimeData: []).timeToFullMinutes == nil,
       "超过 24 小时的荒谬值挡掉")
var heroNotCharging = heroFull
heroNotCharging.hardwareDetail.avgTimeToFull = 72
expect(DashboardMetricSnapshot(data: heroNotCharging, realtimeData: []).timeToFullMinutes == nil,
       "未充电时不给充满时间")

// 未知机型：两个派生口径必须同时为空，概览卡据此走通宽提示而不是两张「—」
var heroUnknownModel = data(from: healthyDetail(), onAC: false)
heroUnknownModel.modelIdentifier = "Mac99,99"   // 不在内置机型表里 → specification 为 nil
let unknownSnapshot = DashboardMetricSnapshot(data: heroUnknownModel, realtimeData: [])
expect(unknownSnapshot.designEnergyWh == nil
       && unknownSnapshot.stableRuntimeMinutes == nil
       && unknownSnapshot.currentLoadRuntimeMinutes == nil,
       "机型缺额定电量时两个派生口径同时为空")

print("── 14b) 能量流向：三条边的判定与守恒")
// 数字取自 QATests/Personal/Evidence/Telemetry/telemetry-plugged-*.log 的真实采样。
// 方向一律由 Amperage×Voltage 决定，不用 PowerTelemetryData —— 同一拍里那组字段
// 报过 1.5 W 的整机负载、插着电的 0 W 适配器输入，和库仑计差 3 倍的电池功率。
func flowSnapshot(milliamps: Int?, millivolts: Int, loadWatts: Double,
                  onAC: Bool, watts: Int = 65) -> DashboardMetricSnapshot {
    var detail = healthyDetail()
    if let milliamps {
        detail.presentRawFields.insert("InstantAmperage")
        detail.instantAmperage = milliamps
    } else {
        detail.presentRawFields.remove("InstantAmperage")
        detail.presentRawFields.remove("Amperage")
        detail.instantAmperage = 0
        detail.smoothedAmperage = 0
    }
    detail.packVoltage = millivolts
    detail.systemPowerWatts = loadWatts
    var flowData = data(from: detail, onAC: onAC)
    flowData.amperage = 0            // 让 batteryCurrentMilliamps 只能走 detail 字段
    flowData.chargerWattage = onAC ? watts : 0
    return DashboardMetricSnapshot(data: flowData, realtimeData: [])
}
func flowFor(milliamps: Int?, millivolts: Int, loadWatts: Double,
             onAC: Bool, watts: Int = 65) -> PowerFlow {
    PowerFlow.resolve(flowSnapshot(milliamps: milliamps, millivolts: millivolts,
                                   loadWatts: loadWatts, onAC: onAC, watts: watts))
}
func near(_ a: Double?, _ b: Double, _ label: String) -> Bool {
    guard let a else { return false }
    return abs(a - b) < 0.02
}

// ① 拔电：电池是唯一可能的来源，那条边恒等于整机功率，不去问电流
let flowBattery = flowFor(milliamps: -993, millivolts: 11778, loadWatts: 9.20, onAC: false)
expect(near(flowBattery.batteryToMac, 9.20, "")
       && flowBattery.adapterToMac == nil && flowBattery.adapterToBattery == nil
       && flowBattery.adapterRatedWatts == nil,
       "拔电：只有电池→电脑一条边，适配器两条边不存在")
// −993 mA × 11.778 V = −11.70 W，而整机是 9.20 W：两个读数在不同电轨上，差 2.5 W。
// 拔电时按整机功率画，箭头和「这台 Mac」那个数才对得上。
expect(near(flowBattery.batteryToMac, flowBattery.macConsumption ?? -1, ""),
       "拔电：电池边与整机功率完全相等，不受 V×I 与系统侧读数的电轨差影响")
// 拔电瞬间电量计还攥着拔电前的充电电流：ExternalConnected 立刻翻，Amperage 要等下一拍。
// 实测出现过「未连接电源 + 2.88 A 充入」，旧实现会把三条边全灭掉。
let flowStalePositive = flowFor(milliamps: 2880, millivolts: 11700, loadWatts: 13.5, onAC: false)
expect(near(flowStalePositive.batteryToMac, 13.5, "")
       && flowStalePositive.adapterToBattery == nil && !flowStalePositive.isIdle,
       "拔电后电流字段仍是陈旧正值时，电池边照常画出整机功率 [\(flowStalePositive)]")
expect(flowSnapshot(milliamps: 2880, millivolts: 11700,
                    loadWatts: 13.5, onAC: false).batteryCurrentMilliamps == nil,
       "拔电却读到正电流只可能是陈旧值，电流行显示「—」而不是显示一个不可能的读数")
expect(flowSnapshot(milliamps: -707, millivolts: 12190,
                    loadWatts: 11.08, onAC: false).batteryCurrentMilliamps == -707,
       "拔电时正常的负电流照常显示")
expect(flowSnapshot(milliamps: 2880, millivolts: 11700,
                    loadWatts: 13.5, onAC: true).batteryCurrentMilliamps == 2880,
       "接着电源时正电流是真的充电，不能被当成陈旧值抹掉")

// ② 插电、电池休息：只有充电器→电脑
let flowIdlePlugged = flowFor(milliamps: 2, millivolts: 11751, loadWatts: 13.114, onAC: true)
expect(near(flowIdlePlugged.adapterToMac, 13.114, "")
       && flowIdlePlugged.adapterToBattery == nil && flowIdlePlugged.batteryToMac == nil,
       "插电不充电：只有充电器→电脑，电池两条边都不亮")

// ③ 充电（实测 t=39：+3905 mA @ 11.779 V = 46.0 W 进电池）
let flowCharging = flowFor(milliamps: 3905, millivolts: 11779, loadWatts: 11.58, onAC: true)
expect(near(flowCharging.adapterToBattery, 46.0, "") && near(flowCharging.adapterToMac, 11.58, ""),
       "充电：充电器分出 46.0W 给电池、11.58W 给电脑 [\(flowCharging)]")
expect(abs((flowCharging.adapterToMac ?? 0) + (flowCharging.adapterToBattery ?? 0) - 57.6) < 0.05,
       "两条出边之和 57.6W 未超过 65W 额定（守恒且物理可信）")
expect(flowCharging.batteryToMac == nil, "充电时电池不同时对外放电")

// ④ 插电但电池仍放电：两条入边之和必须精确等于整机消耗
let flowMixed = flowFor(milliamps: -100, millivolts: 12000, loadWatts: 14.314, onAC: true)
expect(near(flowMixed.batteryToMac, 1.2, "") && near(flowMixed.adapterToMac, 13.114, ""),
       "适配器带不动时，充电器与电池同时向电脑供电 [\(flowMixed)]")
expect(abs((flowMixed.adapterToMac ?? 0) + (flowMixed.batteryToMac ?? 0)
           - (flowMixed.macConsumption ?? 0)) < 0.001,
       "两条入边之和等于整机消耗（守恒）")

// ⑤ 静止：极小读数不画成 0.0W 的箭头
let flowQuiet = flowFor(milliamps: -3, millivolts: 12000, loadWatts: 0.03, onAC: false)
expect(flowQuiet.isIdle, "毫瓦级噪声不渲染成一条边 [\(flowQuiet)]")

// ⑥ 完全没有电流字段：整机功率还在，但方向不可知 → 不编一条电池边
let flowPartial = flowFor(milliamps: nil, millivolts: 12000, loadWatts: 14.0, onAC: true)
expect(flowPartial.origin == .partial
       && flowPartial.batteryToMac == nil && flowPartial.adapterToBattery == nil
       && near(flowPartial.adapterToMac, 14.0, ""),
       "无电流字段：只画充电器→电脑，电池边留空而不是假设为零 [\(flowPartial)]")

print("── 14c) 状态文字与流向图必须同源")
// 旧实现的状态取 IOPowerSources 的 IsCharging、电流取 IORegistry 的 Amperage，
// 两套 API 不同步时会并排显示「未充电」和「+3.95 A」。
expect(BatteryPowerState.resolve(flowSnapshot(milliamps: 3905, millivolts: 11779,
                                              loadWatts: 11.58, onAC: true)) == .charging,
       "实测正电流即判为充电中，不依赖 IsCharging 标志")
expect(BatteryPowerState.resolve(flowSnapshot(milliamps: -993, millivolts: 11778,
                                              loadWatts: 9.20, onAC: true)) == .pluggedDischarging,
       "插着电但电池在放电时给出独立状态，不再笼统显示「未充电」")
expect(BatteryPowerState.resolve(flowSnapshot(milliamps: -20, millivolts: 12000,
                                              loadWatts: 9.20, onAC: true)) == .pluggedIdle,
       "半瓦以内的漂移算休息，不误报成放电")
expect(BatteryPowerState.resolve(flowSnapshot(milliamps: -993, millivolts: 11778,
                                              loadWatts: 9.20, onAC: false)) == .discharging,
       "拔电时仍是「正在使用电池」")
// 同一快照喂给两边，状态和图不可能互相打架
let contradictionCheck = flowSnapshot(milliamps: 3905, millivolts: 11779,
                                      loadWatts: 11.58, onAC: true)
expect(BatteryPowerState.resolve(contradictionCheck) == .charging
       && PowerFlow.resolve(contradictionCheck).adapterToBattery != nil
       && PowerFlow.resolve(contradictionCheck).batteryToMac == nil,
       "判为充电中时，图上必然是充电器→电池亮、电池→电脑灭")

print("── 14d) 刷新倒计时：锚在数据更新时刻，落在我们的轮询格上")
// 0.5 秒粒度实测（QATests/Personal/Evidence/Telemetry/gauge-beat-*.log）：连续五次发布的间隔是
// 59、60、4、60、10 秒，两次短的都伴随 CurrentCapacity 跳变。节拍是 60，事件只让它提前。
let beatBase = Date(timeIntervalSince1970: 1_785_776_703)
// 电量计在 base+60 发布，我们在 base+4 轮询过，所以下一次能看到是 base+64
let gridStamp = MetricReadStamp.gauge(beatBase, polledAt: beatBase.addingTimeInterval(4),
                                      interval: 60)
expect(MetricFieldFreshness.secondsUntilVisibleRefresh(gridStamp,
                                                       now: beatBase.addingTimeInterval(30)) == 34,
       "倒计时算到我们下一次轮询，而不是电量计发布那一刻 [\(MetricFieldFreshness.secondsUntilVisibleRefresh(gridStamp, now: beatBase.addingTimeInterval(30)))]")
expect(MetricFieldFreshness.secondsUntilVisibleRefresh(gridStamp,
                                                       now: beatBase.addingTimeInterval(64)) == 0,
       "归零的那一刻正是屏幕上的值真的换掉的那一刻")
// 这正是用户看到的现象：倒计时走完，值又过了十秒才动
expect(MetricFieldFreshness.secondsUntilVisibleRefresh(gridStamp,
                                                       now: beatBase.addingTimeInterval(60)) == 4,
       "旧算法在这一刻已经归零，新算法还剩 4 秒——差的就是轮询滞后")
// 没有轮询时刻的旧调用点退回原行为
let plainStamp = MetricReadStamp.gauge(beatBase, interval: 60)
expect(MetricFieldFreshness.secondsUntilVisibleRefresh(plainStamp,
                                                       now: beatBase.addingTimeInterval(60)) == 0,
       "缺轮询时刻时退回「发布即归零」，不臆造滞后")
// 时钟跳变时投影不能失控
let skewed = MetricReadStamp.gauge(beatBase, polledAt: beatBase.addingTimeInterval(-9_000),
                                   interval: 60)
expect(MetricFieldFreshness.secondsUntilVisibleRefresh(skewed, now: beatBase) <= 70,
       "轮询时刻离谱时投影被钳在发布后一个轮询周期内 [\(MetricFieldFreshness.secondsUntilVisibleRefresh(skewed, now: beatBase))]")

// 学到的是节拍，不是上一次间隔
func detailWithGauge(_ epoch: TimeInterval, interval: TimeInterval? = nil) -> BatteryHardwareDetail {
    var d = BatteryHardwareDetail()
    d.gaugeUpdateTime = Date(timeIntervalSince1970: epoch)
    d.gaugePublishInterval = interval
    return d
}
let beat59 = BatteryService.learnedGaugeInterval(current: Date(timeIntervalSince1970: 1_785_776_703),
                                                 previous: detailWithGauge(1_785_776_644))
expect(beat59 == 59, "首次观测到 59 秒间隔即采纳为节拍 [\(String(describing: beat59))]")
let eventPublish = BatteryService.learnedGaugeInterval(
    current: Date(timeIntervalSince1970: 1_785_776_767),
    previous: detailWithGauge(1_785_776_763, interval: 60))
expect(eventPublish == 60,
       "电量变化触发的 4 秒提前发布不能当成节拍，沿用 60 [\(String(describing: eventPublish))]")
let samePoll = BatteryService.learnedGaugeInterval(
    current: Date(timeIntervalSince1970: 1_785_776_763),
    previous: detailWithGauge(1_785_776_763, interval: 60))
expect(samePoll == 60, "同一拍的重复轮询沿用已学到的节拍")
let afterSleep = BatteryService.learnedGaugeInterval(
    current: Date(timeIntervalSince1970: 1_785_780_000),
    previous: detailWithGauge(1_785_776_763, interval: 60))
expect(afterSleep == 60, "休眠唤醒后的超长间隔不采纳")

print("── 14d2) 问号面板趋势图的悬浮读数")
let hoverBase = Date(timeIntervalSince1970: 1_785_776_700)
let hoverPoints = (0..<6).map {
    MetricHelpTrendPoint(timestamp: hoverBase.addingTimeInterval(Double($0) * 10), value: 9.0 + Double($0))
}
// 吸附到真实采样点，不在两点之间插值——读数上的每个数字都必须是测到的
let snapped = MetricHelpDrawer.nearestTrendPoint(hoverPoints, to: hoverBase.addingTimeInterval(23))
expect(snapped?.timestamp == hoverBase.addingTimeInterval(20) && snapped?.value == 11.0,
       "指针落在 23 秒处吸附到 20 秒那个采样点 [\(String(describing: snapped))]")
let snappedLeft = MetricHelpDrawer.nearestTrendPoint(hoverPoints, to: hoverBase.addingTimeInterval(-999))
expect(snappedLeft?.timestamp == hoverBase, "指针在序列左侧时吸附到第一个点")
let snappedRight = MetricHelpDrawer.nearestTrendPoint(hoverPoints, to: hoverBase.addingTimeInterval(999))
expect(snappedRight?.timestamp == hoverBase.addingTimeInterval(50), "指针在序列右侧时吸附到最后一个点")
expect(MetricHelpDrawer.nearestTrendPoint([], to: hoverBase) == nil, "空序列不返回读数")
expect(MetricHelpDrawer.nearestTrendPoint(hoverPoints, to: nil) == nil,
       "没有选中位置时不画读数，不能默认落在最后一个点上变成常驻标记")
let hoverText = MetricHelpDrawer.trendHoverText(hoverPoints[2])
expect(!hoverText.contains(":") || hoverText.filter { $0 == ":" }.count == 1,
       "时间到分钟为止，不显示秒 [\(hoverText)]")
expect(hoverText.contains("11.0"), "读数带上该点的功率值 [\(hoverText)]")
expect(hoverText.hasSuffix("W"), "默认单位是瓦 [\(hoverText)]")
expect(MetricHelpDrawer.trendHoverText(hoverPoints[2], unit: "℃").hasSuffix("℃"),
       "温度曲线的读数带摄氏度，不硬写成瓦")

// 三档范围共用同一份 24 小时原始序列；默认档必须始终是 10 分钟。
// 图表展示的是已封闭分桶，不是后台 10 秒轮询点。
expect(MetricHelpTrendRange.allCases.first == .tenMinutes,
       "问号面板趋势默认仍是最近 10 分钟")
expect(BatteryService.maxRealtimePoints == 8_641,
       "十秒采样缓存完整覆盖 24 小时（含首尾点）")
let trendBase = Date(timeIntervalSince1970: 0)
let dayTrendPoints = (0...8_640).map { offset in
    MetricHelpTrendPoint(
        timestamp: trendBase.addingTimeInterval(Double(offset) * BatteryService.liveRefreshInterval),
        value: offset == 4_321 ? 999 : Double(offset % 37)
    )
}
let tenMinuteTrend = MetricHelpTrendRange.tenMinutes.chartPoints(from: dayTrendPoints, maximumCount: 10_000)
expect(tenMinuteTrend.count == 10,
       "最近 10 分钟固定显示 10 个一分钟均值点 [\(tenMinuteTrend.count)]")
let oneHourTrend = MetricHelpTrendRange.oneHour.chartPoints(from: dayTrendPoints, maximumCount: 10_000)
expect(oneHourTrend.count == 20,
       "最近 1 小时固定显示 20 个三分钟均值点 [\(oneHourTrend.count)]")
let downsampledDayTrend = MetricHelpTrendRange.twentyFourHours.chartPoints(from: dayTrendPoints)
expect(downsampledDayTrend.count == 40,
       "最近 24 小时自动按 36 分钟间隔显示 40 点 [\(downsampledDayTrend.count)]")
expect(abs(oneHourTrend[1].timestamp.timeIntervalSince(oneHourTrend[0].timestamp) - 180) < 0.001,
       "1 小时相邻展示点严格间隔 3 分钟")
expect(abs(tenMinuteTrend[1].timestamp.timeIntervalSince(tenMinuteTrend[0].timestamp) - 60) < 0.001,
       "10 分钟相邻展示点严格间隔 1 分钟")
expect(abs(downsampledDayTrend[1].timestamp.timeIntervalSince(downsampledDayTrend[0].timestamp) - 2_160) < 0.001,
       "24 小时相邻展示点自动间隔 36 分钟")
for range in MetricHelpTrendRange.allCases {
    let boundary = range.duration
    let before = dayTrendPoints.filter { $0.timestamp <= trendBase.addingTimeInterval(boundary + 10) }
    let after = dayTrendPoints.filter { $0.timestamp <= trendBase.addingTimeInterval(boundary + 20) }
    expect(range.chartPoints(from: before) == range.chartPoints(from: after),
           "\(range.rawValue) 的未封闭桶内新增 10 秒轮询点不应让图表提前更新")
}
let fittedFixture = [
    MetricHelpTrendPoint(timestamp: trendBase, value: 10),
    MetricHelpTrendPoint(timestamp: trendBase.addingTimeInterval(9 * 60), value: 16),
    MetricHelpTrendPoint(timestamp: trendBase.addingTimeInterval(12 * 60), value: 16),
]
let fittedTrend = MetricHelpTrendRange.oneHour.chartPoints(from: fittedFixture)
expect(fittedTrend.contains(where: { $0.quality == .fitted }),
       "一个短缺口会拟合，并明确标记为拟合点")
let longGapFixture = [
    MetricHelpTrendPoint(timestamp: trendBase, value: 10),
    MetricHelpTrendPoint(timestamp: trendBase.addingTimeInterval(30 * 60), value: 16),
    MetricHelpTrendPoint(timestamp: trendBase.addingTimeInterval(33 * 60), value: 16),
]
let segmentedTrend = MetricHelpTrendRange.oneHour.chartPoints(from: longGapFixture)
expect(Set(segmentedTrend.map(\.segmentID)).count == 2,
       "长时间没有采样时折线断开，不把离线时段伪造成连续数据")
let realtimeRoundTripData = try! JSONEncoder().encode(adapterPoints)
let realtimeRoundTrip = try! JSONDecoder().decode([RealtimeDataPoint].self, from: realtimeRoundTripData)
expect(realtimeRoundTrip.count == adapterPoints.count
       && realtimeRoundTrip.last?.power == adapterPoints.last?.power,
       "24 小时实时采样可编码并在重启后恢复")
var legacyRealtimeJSONObject = try! JSONSerialization.jsonObject(with: realtimeRoundTripData) as! [[String: Any]]
for index in legacyRealtimeJSONObject.indices {
    legacyRealtimeJSONObject[index].removeValue(forKey: "sampleCount")
    legacyRealtimeJSONObject[index].removeValue(forKey: "adapterRatedPower")
    legacyRealtimeJSONObject[index].removeValue(forKey: "adapterOutputPower")
    legacyRealtimeJSONObject[index].removeValue(forKey: "chargingPower")
    legacyRealtimeJSONObject[index].removeValue(forKey: "cycleCount")
    legacyRealtimeJSONObject[index].removeValue(forKey: "healthPercent")
}
let legacyRealtimeData = try! JSONSerialization.data(withJSONObject: legacyRealtimeJSONObject)
let legacyRealtimeDecoded = try? JSONDecoder().decode([RealtimeDataPoint].self, from: legacyRealtimeData)
expect(legacyRealtimeDecoded?.first?.sampleCount == 1,
       "升级后仍能读取旧版实时历史，新增字段缺失时按一个真实样本处理")
let archiveBase = RealtimeDataPoint(timestamp: hoverBase, voltage: 13, amperage: 100,
                                    power: 10, temperature: 30, percent: 80,
                                    cycleCount: 200, healthPercent: 95)
let archiveNext = RealtimeDataPoint(timestamp: hoverBase.addingTimeInterval(10), voltage: 13.2,
                                    amperage: 300, power: 14, temperature: 32, percent: 80,
                                    cycleCount: 200, healthPercent: 95)
let archiveBucket = TelemetryHistoryArchive.appending(
    archiveNext,
    to: TelemetryHistoryArchive.appending(archiveBase, to: [])
)
expect(archiveBucket.count == 1 && archiveBucket[0].sampleCount == 2
       && abs(archiveBucket[0].power - 12) < 0.001,
       "永久档案把同一三分钟桶压成带真实样本数的均值")
let retentionNow = hoverBase.addingTimeInterval(24 * 60 * 60)
let retentionFixture = [
    RealtimeDataPoint(timestamp: retentionNow.addingTimeInterval(-24 * 60 * 60 - 1),
                      voltage: 13, amperage: 0, power: 8, temperature: 30, percent: 100),
    RealtimeDataPoint(timestamp: retentionNow.addingTimeInterval(-24 * 60 * 60),
                      voltage: 13, amperage: 0, power: 9, temperature: 30, percent: 100),
    RealtimeDataPoint(timestamp: retentionNow,
                      voltage: 13, amperage: 0, power: 10, temperature: 30, percent: 100),
]
let retainedFixture = BatteryService.retainedRealtimeSamples(retentionFixture, now: retentionNow)
expect(retainedFixture.map(\.power) == [9, 10],
       "重启恢复时只保留最近 24 小时，边界点保留、过期点丢弃")

// 每个「有真实序列」的问号面板都必须带图；没有序列的不许硬画
let trendSnapshot = DashboardMetricSnapshot(data: wholeMacInputData, realtimeData: adapterPoints)
let panelsWithTrend: [(String, MetricHelpContent)] = [
    ("当前功率", DashboardHelp.power(trendSnapshot)),
    ("充电功率", DashboardHelp.chargingPower(trendSnapshot)),
    ("适配器输出功率", DashboardHelp.adapterOutputPower(trendSnapshot)),
    ("电池温度", DashboardHelp.temperature(trendSnapshot)),
]
for (name, panel) in panelsWithTrend {
    expect(panel.trend?.isPlottable == true,
           "\(name) 的问号面板带得出趋势图 [\(panel.trend?.points.count ?? -1) 点]")
}
expect(DashboardHelp.temperature(trendSnapshot).trend?.unit == "℃"
       && DashboardHelp.temperature(trendSnapshot).trend?.baselineAtZero == false,
       "温度曲线用摄氏度且不从 0 起，否则几度的波动会被压平")
expect(DashboardHelp.power(trendSnapshot).trend?.baselineAtZero == true,
       "功率曲线从 0 起，「一半的瓦数」就该看起来是一半")
// 十分钟缓冲区里它们是一条纹丝不动的直线，画出来等于假装有分辨率
expect(DashboardHelp.cycleCount(trendSnapshot).trend == nil
       && DashboardHelp.health(trendSnapshot).trend == nil,
       "循环次数和健康度不配趋势图")
// 缓冲区还没攒够两点时退回提示，不画一条只有一个点的线
expect(DashboardHelp.power(
    DashboardMetricSnapshot(data: wholeMacInputData, realtimeData: Array(adapterPoints.prefix(1)))
).trend?.isPlottable == false, "只有一个采样点时不画线，显示正在积累")

print("── 14e) 指标卡趋势线")
expect(MetricSparkline.normalised([]).isEmpty && MetricSparkline.normalised([7.0]).isEmpty,
       "少于两个点不画线")
expect(MetricSparkline.normalised([10, 20, 30]) == [0, 0.5, 1], "三点线性归一化到 0…1")
expect(MetricSparkline.normalised([11.00, 11.02, 10.99]) == [0.5, 0.5, 0.5],
       "极窄区间按平线画在中间高度，不把 0.03W 的抖动放大成山脉")
expect(MetricSparkline.normalised([1, Double.nan, 3, 5]).count == 3, "非有限值被剔除")

print("── 15a) 帮助面板改成按需构造后的两个身份约束")
// 诊断页那一行用 helpID 判断「开着的是不是我」，它必须和 help.id 完全相同，
// 否则实时刷新会静默失效（面板卡在打开那一刻的数字）。
let anomalyReading = SystemFieldReading(
    metadata: SystemFieldMetadata(layer: 2, source: "AppleSmartBattery / IORegistry",
                                  group: "电气", path: "InstantAmperage", declaredType: "Int",
                                  unit: "mA", meaning: "", reliability: "", recommendation: "",
                                  valueStars: 2, note: ""),
    value: "-1400", runtimeType: "Int", isAvailable: true,
    anomalyLevel: .attention, anomalyReason: ""
)
expect(anomalyReading.helpID == anomalyReading.help.id,
       "行的 helpID 与它构造出的面板 id 一致，实时刷新才认得出自己")
// ReferenceMetric 的 id 曾经取自 help.id，等于为了认行而构造整个面板；改用标题后
// 仍必须唯一，否则 ForEach 会错乱。
let referenceTitles = [
    L("insight.factor.balance"), L("insight.factor.resistance"),
    L("insight.factor.cycles"), L("p.design_capacity"),
]
expect(Set(referenceTitles).count == referenceTitles.count,
       "参考指标表的标题互不重复，可以充当行标识 [\(referenceTitles)]")

print("── 15b) 有意义字段的预计算集合与逐行判定一致")
// 把每帧重算改成集合查表后，两条路径必须给出完全相同的结果，否则「有意义」标签页会静默漏字段
let mismatched = SystemFieldCatalog.fields.filter {
    SystemFieldCatalog.meaningfulIDs.contains($0.id) != $0.isMeaningfulByDefault
}
expect(mismatched.isEmpty,
       "预计算集合与 isMeaningfulByDefault 对全部 \(SystemFieldCatalog.fields.count) 个字段结果一致"
       + (mismatched.isEmpty ? "" : "，不一致 \(mismatched.map(\.path))"))

print("── 16) 工作台 464 行的换算值")
// 原始值永远在前，换算只是辅助——这是证据表，不能用换算替换实测值
expect(SystemFieldValueConversion.suffix(for: "207", unit: "分钟") == "3 h 27 m",
       "分钟换算成小时分钟，与结果卡同格式")
expect(SystemFieldValueConversion.suffix(for: "65535", unit: "分钟") == nil,
       "分钟字段的 65535 哨兵不换算")
expect(SystemFieldValueConversion.suffix(for: "-1", unit: "分钟") == nil,
       "IOPowerSources 的 -1「计算中」不换算成负小时")
expect(SystemFieldValueConversion.suffix(for: "-1400", unit: "mA") == "-1.40 A",
       "mA 换算保留负号 [\(SystemFieldValueConversion.suffix(for: "-1400", unit: "mA") ?? "nil")]")
expect(SystemFieldValueConversion.suffix(for: "12461", unit: "mV") == "12.46 V", "mV 换算成 V")
expect(SystemFieldValueConversion.suffix(for: "3046", unit: "原始温标")?.contains("30.5") == true,
       "原始温标走与全局一致的温度解码 [\(SystemFieldValueConversion.suffix(for: "3046", unit: "原始温标") ?? "nil")]")
expect(SystemFieldValueConversion.suffix(for: "true", unit: "布尔") == nil
       && SystemFieldValueConversion.suffix(for: "4629", unit: "mAh") == nil
       && SystemFieldValueConversion.suffix(for: "80", unit: "%") == nil,
       "没有换算价值的单位不硬凑")
expect(SystemFieldValueConversion.suffix(for: "—", unit: "mA") == nil,
       "无值时不换算")

let conversionField = SystemFieldReading(
    metadata: SystemFieldMetadata(layer: 2, source: "AppleSmartBattery / IORegistry",
                                  group: "续航", path: "TimeRemaining", declaredType: "Int",
                                  unit: "分钟", meaning: "", reliability: "", recommendation: "",
                                  valueStars: 3, note: ""),
    value: "207", runtimeType: "Int", isAvailable: true,
    anomalyLevel: .none, anomalyReason: ""
)
expect(conversionField.convertedValue == "207 (3 h 27 m)",
       "工作台单元格是原始值在前、换算在括号里 [\(conversionField.convertedValue)]")

// 同一个数字在概览卡和问号面板里必须同名
let labelHelp = DashboardHelp.runtime(runtimeSnapshot)
expect(labelHelp.comparisonResults.map(\.title) == [
    L("p.runtime_system_label"), L("p.runtime_stable_label"), L("p.runtime_current_label"),
], "概览卡与问号面板共用同一组口径标题")

// MARK: - 充电速度预测

print("── 充电速度预测：实测优先、功率兜底、两道钳位")

/// 构造一串充电中的实时样本。`capacities` 从旧到新，间隔 `step` 秒。
func chargingSamples(_ capacities: [Int?], step: TimeInterval = 10,
                     endingAt end: Date, onAC: Bool = true) -> [RealtimeDataPoint] {
    let count = capacities.count
    return capacities.enumerated().map { index, capacity in
        RealtimeDataPoint(
            timestamp: end.addingTimeInterval(-Double(count - 1 - index) * step),
            voltage: 12.9, amperage: 2500, power: 12, temperature: 31, percent: 60,
            isOnAC: onAC, rawCurrentCapacity: capacity
        )
    }
}

let speedNow = Date(timeIntervalSince1970: 1_770_000_000)
var chargingBattery = data(from: healthyDetail(), onAC: true)
chargingBattery.isCharging = true
chargingBattery.percent = 60
chargingBattery.hardwareDetail.instantAmperage = 2500
chargingBattery.hardwareDetail.presentRawFields.insert("InstantAmperage")

// FCC 4107 mAh。120 秒内涨 100 mAh = 2.435% → 1.2175 %/min
let measuredSamples = chargingSamples([3900, 3900, 4000], step: 60, endingAt: speedNow)
let measured = ChargeSpeedEstimate.resolve(data: chargingBattery,
                                           samples: measuredSamples, now: speedNow)
expect(measured?.source == .measured,
       "有 120 秒且电量计确实变化的窗口时走实测口径 [\(String(describing: measured?.source))]")
if let measured {
    let expectedRate = 100.0 / 4107.0 * 100 / 2
    expect(abs(measured.percentPerMinute - expectedRate) < 0.001,
           "实测速率 = Δ容量÷FCC÷分钟数 [\(measured.percentPerMinute) vs \(expectedRate)]")
    expect(abs(measured.gainPercent(overMinutes: 10)
               - measured.gainPercent(overMinutes: 5) * 2) < 0.001,
           "未触发钳位时线性外推，10 分钟正好是 5 分钟的两倍")
}

// 电量计约 56 秒才发布一次，10 秒轮询会把同一个值重复十几遍。端点必须按
// 「值变过」来取，否则会把明明在充电的机器算成 0。
let stalledSamples = chargingSamples([3900, 3900, 3900, 3900, 3900, 3900, 3900, 4000, 4000,
                                      4000, 4000, 4000, 4000], step: 10, endingAt: speedNow)
let stalled = ChargeSpeedEstimate.resolve(data: chargingBattery,
                                          samples: stalledSamples, now: speedNow)
expect(stalled?.source == .measured && (stalled?.percentPerMinute ?? 0) > 0,
       "重复值不清零：跳过未刷新的样本，用真正变化过的那一对做端点")

// 窗口不够长 → 退回功率推算，而不是拿 20 秒的抖动当速率
let shortWindow = chargingSamples([3900, 4000], step: 20, endingAt: speedNow)
let shortResult = ChargeSpeedEstimate.resolve(data: chargingBattery,
                                              samples: shortWindow, now: speedNow)
expect(shortResult?.source == .derived,
       "窗口短于 110 秒时退回功率推算 [\(String(describing: shortResult?.source))]")
if let shortResult {
    let expectedDerived = 2500.0 / 4107.0 * 100 / 60
    expect(abs(shortResult.percentPerMinute - expectedDerived) < 0.001,
           "功率推算速率 = 充电电流÷FCC÷60 [\(shortResult.percentPerMinute)]")
}

expect(ChargeSpeedEstimate.resolve(data: chargingBattery, samples: [], now: speedNow)?.source
       == .derived, "刚插电没有历史样本时仍能给出功率推算值")

// 拔插过一次：跨越会话边界的样本不能拿来算
let brokenSession = [
    RealtimeDataPoint(timestamp: speedNow.addingTimeInterval(-120), voltage: 12.9,
                      amperage: 0, power: 12, temperature: 31, percent: 58,
                      isOnAC: false, rawCurrentCapacity: 3900),
    RealtimeDataPoint(timestamp: speedNow, voltage: 12.9, amperage: 2500, power: 12,
                      temperature: 31, percent: 60, isOnAC: true, rawCurrentCapacity: 4000),
]
expect(ChargeSpeedEstimate.resolve(data: chargingBattery,
                                   samples: brokenSession, now: speedNow)?.source == .derived,
       "样本跨越拔电边界时不做差分，退回功率推算")

// 用户截图那一幕：96%、大功率进电，剩余空间只有 4%
var nearFull = chargingBattery
nearFull.percent = 96
let nearFullEstimate = ChargeSpeedEstimate.resolve(data: nearFull, samples: [], now: speedNow)
expect(nearFullEstimate?.headroomPercent == 4, "剩余空间 = 100 − 当前电量")
expect(nearFullEstimate.map { $0.gainPercent(overMinutes: 10) == 4 } == true,
       "满电附近按剩余空间封顶，不会预测出超过 4% 的进电量")
expect(nearFullEstimate.map { $0.percentPerMinute * 10 > 4 } == true,
       "这一幕的线性外推本来会超出剩余空间——确认钳位真的起了作用，不是恰好没超")

// 系统说这段时间内会充满，就按剩余空间给满，不再线性外推
var quickFinish = nearFull
quickFinish.hardwareDetail.avgTimeToFull = 3
if let q = ChargeSpeedEstimate.resolve(data: quickFinish, samples: [], now: speedNow) {
    expect(q.timeToFullMinutes == 3 && q.gainPercent(overMinutes: 5) == 4,
           "AvgTimeToFull ≤ 预测区间时直接给出全部剩余空间")
} else {
    expect(false, "充满还需 3 分钟时仍应给出充电速度预测")
}

var notCharging = chargingBattery
notCharging.isCharging = false
notCharging.amperage = 0
notCharging.hardwareDetail.instantAmperage = 0
notCharging.hardwareDetail.smoothedAmperage = 0
expect(ChargeSpeedEstimate.resolve(data: notCharging, samples: measuredSamples,
                                   now: speedNow) == nil,
       "没在充电时不给速度，交由界面退回裸电量")

var fullBattery = chargingBattery
fullBattery.percent = 100
expect(ChargeSpeedEstimate.resolve(data: fullBattery, samples: measuredSamples,
                                   now: speedNow) == nil,
       "已满电时不显示 +0%，返回 nil")

// MARK: - 两个新菜单栏指标

print("── 菜单栏新增：电池充电功率与电池充电速度")

let chargePresentation = MenuBarPresentation(data: chargingBattery, chargeSpeed: measured)
expect(chargePresentation.statusValue(for: .chargingPower)?.hasSuffix("W") == true,
       "充电功率状态项以 W 结尾 [\(String(describing: chargePresentation.statusValue(for: .chargingPower)))]")
let speedStatus = chargePresentation.statusValue(for: .chargeSpeed)
expect(speedStatus?.contains("/5m") == true && speedStatus?.contains("/10m") == true,
       "充电速度状态项同时给出 5 分钟与 10 分钟 [\(String(describing: speedStatus))]")

// 未充电态：功率按产品决策显示 0W，速度退回裸电量
let idlePresentation = MenuBarPresentation(data: notCharging, chargeSpeed: nil)
expect(idlePresentation.statusValue(for: .chargingPower) == "0W",
       "没充电时充电功率是 0W，宽度稳定不跳变 [\(String(describing: idlePresentation.statusValue(for: .chargingPower)))]")
expect(idlePresentation.statusValue(for: .chargeSpeed) == nil
       && idlePresentation.menuBarText(secondaryMetric: .chargeSpeed)
       == idlePresentation.percentText,
       "没充电时充电速度不占位，菜单栏只剩电量")

// 菜单栏和主看板卡片必须共用同一个充电功率格式化
let sharedSnapshot = DashboardMetricSnapshot(data: chargingBattery, realtimeData: [])
expect(chargePresentation.value(for: .chargingPower) == sharedSnapshot.chargingPowerText,
       "面板行与概览卡的充电功率文本同源，不会漂移")

print("\n" + (failures == 0 ? "✅ 全部通过" : "❌ \(failures) 项失败"))
exit(failures == 0 ? 0 : 1)
