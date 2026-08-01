import Foundation

// InsightEngine / BatteryAgeEstimator / 硬件解析的边界测试。
// 由 Tests/run-insight-tests.sh 编译运行，不依赖 Xcode 也不依赖界面截图。

var failures = 0
func expect(_ cond: Bool, _ msg: String) {
    print((cond ? "  ✓ " : "  ✗ ") + msg)
    if !cond { failures += 1 }
}

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

// MARK: - 7) 耗电分析

print("── 7) 耗电分析")
let procs = [ProcessPowerInfo(pid: 1, name: "/Applications/Google Chrome.app/Google Chrome",
                              cpuPercent: 32.4, memoryMB: 900)]
let pOnBattery = InsightEngine.power(data: data(from: d, onAC: false), d: d, processes: procs)
expect(pOnBattery.estimatedHoursRemaining != nil, "电池供电时给出续航预估")
expect(pOnBattery.currentWatts > 0, "功耗为真实读数 [\(pOnBattery.currentWatts)W]")
let pOnAC = InsightEngine.power(data: data(from: d, onAC: true), d: d, processes: procs)
expect(pOnAC.estimatedHoursRemaining == nil, "AC 供电时不给续航预估")
expect(pOnBattery.note != nil, "有高占用进程时给出提示")
// 提示里只能出现真实读数，不能出现编造的「省 X W」
if let n = pOnBattery.note {
    expect(!n.contains("1.8") , "提示不含编造的节省瓦特数")
}
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

print("── 10b) 外观与菜单栏配置持久化")
let preferenceSuiteName = "com.stephen.BatteryMonitor.tests.presentation"
let preferenceDefaults = UserDefaults(suiteName: preferenceSuiteName)!
preferenceDefaults.removePersistentDomain(forName: preferenceSuiteName)

let appearancePreferences = AppearanceSettings(defaults: preferenceDefaults)
expect(appearancePreferences.mode == .system, "外观默认跟随系统")
appearancePreferences.select(.dark)
expect(AppearanceSettings(defaults: preferenceDefaults).mode == .dark,
       "深色外观选择可持久化并由新实例恢复")
appearancePreferences.select(.light)
expect(AppearanceSettings(defaults: preferenceDefaults).mode == .light,
       "浅色外观选择可覆盖深色并持久化")

let menuPreferences = MenuBarSettings(defaults: preferenceDefaults)
expect(menuPreferences.secondaryMetric == .runtime,
       "顶部状态栏默认显示电量 + 剩余时间")
expect(menuPreferences.visibleMetrics == MenuBarSettings.defaultVisibleMetrics,
       "菜单栏弹层默认指标顺序稳定")
menuPreferences.selectSecondaryMetric(.power)
menuPreferences.setVisible(.runtime, visible: false)
menuPreferences.move(.health, by: -2)
menuPreferences.move(.cycles, to: 0)
let restoredMenuPreferences = MenuBarSettings(defaults: preferenceDefaults)
expect(restoredMenuPreferences.secondaryMetric == .power,
       "顶部第二指标可切换为当前功率并持久化")
expect(!restoredMenuPreferences.visibleMetrics.contains(.runtime)
       && restoredMenuPreferences.visibleMetrics.first == .cycles
       && restoredMenuPreferences.visibleMetrics.firstIndex(of: .health) == 2,
       "弹层指标可隐藏、按钮移动与拖放移动，并保持用户顺序")

DashboardNavigation.shared.destination = .settings
expect(DashboardNavigation.shared.destination == .settings,
       "添加更多指标可把完整看板直接导航到设置页")
DashboardNavigation.shared.destination = .overview
preferenceDefaults.removePersistentDomain(forName: preferenceSuiteName)

// MARK: - 11) 系统时间与功耗口径

print("── 11) 系统时间与功耗口径")
expect(BatteryService.preferredSystemTimeRemaining(isOnAC: false,
        timeRemaining: 148, avgTimeToEmpty: 150) == 148,
       "电池供电优先TimeRemaining")
expect(BatteryService.preferredSystemTimeRemaining(isOnAC: false,
        timeRemaining: 65_535, avgTimeToEmpty: 150) == 150,
       "TimeRemaining=65535时退到有效AvgTimeToEmpty")
expect(BatteryService.preferredSystemTimeRemaining(isOnAC: false,
        timeRemaining: 0, avgTimeToEmpty: 65_535) == nil,
       "0与65535都不是有效分钟")
expect(BatteryService.preferredSystemTimeRemaining(isOnAC: true,
        timeRemaining: 148, avgTimeToEmpty: 150) == nil,
       "插电时不把电量计值作为系统剩余续航")

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
expect(RuntimeSample.isValid(minutes: 1) && RuntimeSample.isValid(minutes: 65_534)
       && !RuntimeSample.isValid(minutes: 0) && !RuntimeSample.isValid(minutes: 65_535),
       "系统剩余时间有效范围严格为1...65534")
expect(RuntimeSample.shouldAppend(r0, after: nil), "首个有效样本可写入")
expect(!RuntimeSample.shouldAppend(r55, after: r0), "55秒不重复写入")
expect(RuntimeSample.shouldAppend(r56, after: r0), "满56秒才写入下一点")
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

print("\n" + (failures == 0 ? "✅ 全部通过" : "❌ \(failures) 项失败"))
exit(failures == 0 ? 0 : 1)
