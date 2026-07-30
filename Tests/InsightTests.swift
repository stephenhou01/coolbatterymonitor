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

print("\n" + (failures == 0 ? "✅ 全部通过" : "❌ \(failures) 项失败"))
exit(failures == 0 ? 0 : 1)
