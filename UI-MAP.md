# BatteryMonitor 界面地图

**用途**：从「界面上看到的东西」反查代码。改 UI 前先查这里，不要派 agent 满项目找。

本文件不定义项目协作规则，只管一件事：**页面 → 区域 → 文案 key + 动态变量 → 渲染文件 + 数据来源**。跨层算法、状态、复用消费者和测试链路由 `FEATURE-MAP.md` 负责。

## 五种查法

| 你手上有什么 | 怎么查 |
|---|---|
| 任意语言的一句界面文案 | `python3 Localization/build-language-packs.py lookup-text "Stable estimate"` → 拿到 key、源文件和使用处 |
| 界面上的一块东西（"续航时间对照"） | `grep "续航时间对照" UI-MAP.md` → 拿到该区域全部 key、变量、渲染位置、数据来源 |
| 一个 key | `python3 Localization/build-language-packs.py find p.runtime_stable_label` → 拿到归属、译文和使用处；再 grep 本文件看区域 |
| 一个变量名 | `grep "stableRuntimeMinutes" UI-MAP.md` → 拿到它被哪些界面显示（改算法前先看会影响谁） |
| 一个跨层功能 | `grep "feature:runtime.comparison" FEATURE-MAP.md` → 拿到 UI、canonical owner、上游状态、复用、本地化和测试 |

**路径省略前缀** `BatteryMonitor/`（例：`Views/DashboardOverviewPage.swift`）。表内行号只作近似导航，稳定锚点是区域名、key、变量、文件和符号；定位后用 `rg -n` 确认。界面结构变动后必须回来更新。

查询 key 的页面归属、权威源文件和字面引用：

```bash
python3 Localization/build-language-packs.py find KEY
```

## 跨层功能入口

只在任务命中时打开 `FEATURE-MAP.md` 对应 ID：

| 界面概念 | Feature ID |
|---|---|
| 三套续航对照 | `feature:runtime.comparison` |
| 系统续航 / 拔电预测历史 | `feature:runtime.history` |
| 公开续航基准 | `feature:runtime.benchmark` |
| 当前整机功率 | `feature:power.current` |
| 适配器输出功率 | `feature:power.adapter-output` |
| 电池充电功率 | `feature:power.battery-charging` |
| 充电速度 | `feature:charging.speed` |
| 能量流向 | `feature:power.flow` |
| 健康度口径 | `feature:capacity.health` |
| 容量拆解 | `feature:capacity.breakdown` |
| 完整硬件字段 | `feature:hardware.catalog` |
| 进程负载上下文 | `feature:process.load-context` |
| 四类洞察 | `feature:diagnostics.insights` |
| 四层系统核验台 | `feature:system.workbench` |
| 24 小时遥测历史 | `feature:telemetry.history` |
| 菜单栏指标 | `feature:menu.metrics` |
| 指标问号面板 | `feature:help.metric` |
| 运行时本地化 | `feature:localization.runtime` |

---

## 总览页（侧边栏第 1 项）

| 区域 | 文案 key | 动态变量 | 渲染位置 | 数据来源 |
|---|---|---|---|---|
| 页头（标题/副标题 + 语言选择器 + 外观选择器） | `app.title` `app.subtitle` `p.menu_language` `lang.system` | `modelIdentifier` `localization.languages/currentName/isFollowingSystem/effectiveCode` | `Views/DashboardOverviewPage.swift:22-29` | `Models/BatteryData.swift:69` `Services/Localization.swift`（`L10n.shared`） |
| 电量大字 | —（纯格式化） | `percentText` `percent` | `Views/DashboardOverviewPage.swift:62-66` | `Views/MenuBarPresentation.swift:25-27` `Models/BatteryData.swift:47` |
| 续航时间对照（系统主卡 + 稳健/短时两行 + 缺额定电量提示） | `shell.runtime_comparison` `p.runtime_system_label` `p.runtime_stable_label` `p.runtime_current_label` `p.runtime_unavailable` `shell.derived_runtime_unavailable` `shell.system_runtime_basis` `shell.apple_runtime_unavailable` `shell.apple_runtime_waiting` `shell.stable_runtime_collecting` `shell.stable_runtime_basis` `shell.stable_runtime_basis_seconds` `shell.instant_runtime_waiting` `shell.current_runtime_basis` | `systemRuntimeMinutes` `stableRuntimeMinutes` `currentLoadRuntimeMinutes` `designEnergyWh` `stablePowerSpanSeconds` `recentStablePowerSamples` `currentPowerWatts` `timeRemainingMinutes` | `Views/DashboardOverviewPage.swift:65-271` | `Models/DashboardMetricSnapshot.swift`（同名派生属性）`Models/BatteryData.swift`（`timeRemainingMinutes`）→ `feature:runtime.comparison` |
| 能量流向图（三节点 + 三条边 + 图下说明） | `shell.flow_battery` `shell.flow_adapter` `shell.flow_mac` `shell.not_connected` `shell.flow_derived` `shell.flow_idle` `shell.flow_forecast_measured` `shell.flow_forecast_derived` | `batteryToMac` `adapterToBattery` `adapterToMac` `macConsumption` `adapterRatedWatts` `origin` `isIdle` `batteryPercent` `chargeSpeed` | `Views/PowerFlowDiagram.swift:46-201` | `Models/PowerFlow.swift:45,48,52,54,56,57,125` |
| 流向图无障碍摘要 | `shell.flow_a11y_battery_to_mac` `shell.flow_a11y_adapter_to_battery` `shell.flow_a11y_adapter_to_mac` `shell.flow_idle` | `batteryToMac` `adapterToBattery` `adapterToMac` `chargeGainText` | `Views/PowerFlowDiagram.swift:228-253` | `Models/PowerFlow.swift:45-52` |
| 电池状态面板（状态标题 + 电流/充满还需 + 读数时间戳） | `shell.charging` `shell.state_full` `shell.state_plugged_idle` `shell.state_plugged_discharging` `shell.on_battery` `shell.battery_current` `shell.time_to_full` | `batteryCurrentMilliamps` `timeToFullMinutes` `rawFieldReadAt` `percent` | `Views/DashboardOverviewPage.swift:285-377` | `Models/DashboardMetricSnapshot.swift:73,113,268` |
| 指标横排七卡（含 sparkline / field / cadence） | `menu.metric.power` `shell.power_hint` `shell.adapter` `shell.adapter_output_power` `shell.charge_power` `menu.metric.temperature` `menu.metric.cycles` `menu.metric.health` `shell.charging` | `currentPowerWatts` `chargerWattage` `adapterOutputPowerWatts` `chargingPowerText` `temperatureCelsius` `cycleCount` `healthPercent` `isOnAC` `isCharging` `rawFieldReadAt` `realtimeData` | `Views/DashboardOverviewPage.swift:388-542` | `Models/DashboardMetricSnapshot.swift:24,42,133,153` `Models/BatteryData.swift:56-60` |
| 指标卡辅助文案（连接/充电/范围/健康标签） | `shell.adapter_connected` `shell.not_connected` `shell.whole_mac_input` `shell.not_charging` `shell.temp_range` `shell.cycle_reference` `shell.health_good` `shell.health_fair` `shell.health_attention` | `isOnAC` `isCharging` `healthPercent` | `Views/DashboardOverviewPage.swift:416-457,544-549` | `Models/BatteryData.swift:48-49` `Models/DashboardMetricSnapshot.swift:153` |
| 底部状态横幅（圆标 + 主副标题 + 刷新状态） | `shell.status_attention` `shell.status_good` `shell.status_subtitle` `p.live_10s` `p.live_paused` | `needsAttention` `healthPercent` `temperatureCelsius` `isLiveRefreshEnabled` | `Views/DashboardOverviewPage.swift:551-588` | `Models/DashboardMetricSnapshot.swift:153` `Models/BatteryData.swift:60` |

---

## 技术参数页（侧边栏第 2 项）

**界面可见标题与项目文件地图里的内部说法不是一套词**，下表用可见标题。

| 区域（界面可见标题） | 文案 key | 动态变量 | 渲染位置 | 数据来源 |
|---|---|---|---|---|
| 页头「技术参数」 | `shell.technical_subtitle` | `DashboardDestination.technical.title` `batteryData` `realtimeData` `runtimeSamples` | `Views/DashboardTechnicalPage.swift:14` | `Services/BatteryService.swift:12` |
| 还能用多久 | `p.remaining` `p.unplug_kicker` `p.src_note` `p.unplug_badge` `p.system_charge` `p.priority_health` `p.priority_power` `p.priority_temp` | `displayedRuntimeMinutes` `percent` `isOnAC` `healthPercent` `currentPowerWatts` `usualPowerWatts` `peakPowerWatts` `temperatureCelsius` `temperatureHistoryText` | `Views/RemainingTimeHeroSection.swift:5`（header 11） | `Models/DashboardMetricSnapshot.swift`（同名派生属性）→ `feature:runtime.comparison` |
| 公开基准 × 这台电脑 | `p.runtime_audit_tag` `p.runtime_audit_title` `p.audit_official` `p.audit_same_load` `p.audit_actual` `p.audit_cause` `p.audit_method` `p.audit_conditions` `p.audit_*` | `specification.designEnergyWh` `specification.officialWebHours` `specification.officialVideoHours` `currentFullEnergyWh` `remainingEnergyWh` `currentPowerWatts` `unplugEstimateMinutes` `detail.chipModel` `modelIdentifier` | `Views/RuntimeBenchmarkSection.swift:5`（header 22） | `Models/BatteryModelSpecification.swift` + `Models/DashboardMetricSnapshot.swift`（同名属性）→ `feature:runtime.benchmark` |
| 当前功耗与程序活动 | `p.power_center_title` `p.current_power_short` `p.window_average` `p.window_peak` `p.active_processes` `proc.col_cpu` `proc.cpu_machine` `proc.cpu_visible` `proc.cpu_system` `proc.cpu_system_note` `proc.cpu_scale_note` | `currentPowerWatts` `chartPoints` `peak` `average` `topProcesses` `systemCPU` `hasSampled` `detail.systemPowerWatts` `detail.systemLoad` | `Views/PowerCenterSection.swift:7`（header 39） | `Services/ProcessMonitorService.swift:7,14` `Models/BatteryData.swift:193` |
| 系统剩余时间记录 / 拔电后的预计续航 | `p.unplug_trend` `p.remaining_trend` `p.dual_head` `p.unplug_head` `p.chart_time` `p.chart_hours` `p.no_history` `p.learn_summary` `p.learn_*` | `chartSamples`（`persistedRuntimeSamples` + `sessionRuntimeSamples`）`unplugEstimateMinutes` `lastUpdated` `point.hours` `isForecast` | `Views/RemainingTimeHistorySection.swift:6`（header 39） | `Models/RuntimeSample.swift:6` `Services/BatteryService.swift:15` |
| 你买的容量去哪了 | `p.where_title` `p.eq_capacity_title` `p.eq_usage_title` `p.design_capacity` `p.current_max` `p.current_actual` `p.used_since_full` `p.capacity_gap` `p.seg_*` | `designCapacity` `fullChargeCapacity` `currentCapacity` `usedSinceFull` `longTermCapacityGap` `inaccessibleCapacity` `truePermanentLoss` `detail.qmax` | `Views/CapacityBreakdownSection.swift:5`（header 22） | `Models/DashboardMetricSnapshot.swift`（同名派生属性）`Models/BatteryHardwareDetail.swift`（`qmax`）→ `feature:capacity.breakdown` |
| 其余 4 项关键指标 | `p.spec_other_title` `p.spec_other_sub` `insight.factor.balance` `insight.factor.resistance` `insight.factor.cycles` `hw.m.pack_voltage` `p.spec_metric` `p.good_range` `p.spec_*` | `detail.cellVoltages` `detail.resistance` `detail.cycleCount` `voltageVolts` `voltageHistoryText` | `Views/MetricReferenceSection.swift:5`（header 75） | `Models/BatteryHardwareDetail.swift:44,166` `Models/DashboardMetricSnapshot.swift:315` |
| 判断电池是不是老化 / 剩余时间为什么会跳（两张说明卡） | `p.aging_judge_title` `p.aging_judge_lead` `p.aging_judge_body` `p.aging_proof` `p.time_jump_title` `p.time_jump_lead` `p.time_jump_body` `p.time_jump_proof` | `detail.cycleCount` `longTermCapacityGap` `detail.chargeDeficitPerCycle` | `Views/ConsumerExplanationSection.swift:5`（卡片 17、34） | `Models/BatteryHardwareDetail.swift:150,166` `Models/DashboardMetricSnapshot.swift:173` |
| 完整硬件参数与逐项解释 | `p.geek` `p.hw_intro_title` `p.hw_search` `p.range` `hw.field` `hw.value` `hw.unit` `hw.meaning` `hw.rel` `hw.column.*` `hw.group.*` | `totalCount` `visibleCount` `hardwareDetail.architecture` `group.metrics.count` `metric.field/value/unit/meaning/referenceRange/valueStars/reliability` | `Views/CompleteHardwareDetailView.swift:67`（titleBar 134、表头 230） | `Views/CompleteHardwareMetricCatalog.swift:6` —— **74 个字段 / 9 组**，group 定义在 `562-570` |
| 所有系统数据 · 四层核验台 | 界面外壳：`p.system_data_title` `p.system_data_source` `p.system_data_available` `p.system_data_anomaly` `p.system_data_search` `p.system_data_field` `p.system_data_value` `p.system_data_value_level` `p.system_tab_meaningful` `p.system_*`<br>**表格内容（464 行 × 6 列）不写在视图里**，来自 catalog 每条 field 的 `groupKey`/`unitKey`/`meaningKey`/`noteKey`/`reliabilityKey`/`recommendationKey` → `system.catalog.group.*`(17) `system.catalog.unit.*`(21) `system.catalog.meaning.*`(46) `system.catalog.note.*`(51) `system.catalog.reliability.*`(3) `system.catalog.recommendation.*`(4)，共 142 个新 key；另复用 5 个现成 key `system.group.capacity` `system.group.fault` `system.group.power` `system.group.raw` `system.reliability.private`（distinct 合计 147） | `snapshot.fields` `snapshot.fields.count` `availableCount` `anomalyCount` `visibleCount` `searchText` `gaugeReadAt`（`hardwareDetail.gaugeUpdateTime`）`isLive`；单元格取值一律走 `metadata.localizedGroup/localizedUnit/localizedMeaning/localizedReliability/localizedNote/localizedRecommendation` | `Views/SystemDataWorkbenchView.swift:21`（标题 102、表头 215、单元格 243/248/260/264） | `BatteryMonitor/Resources/SystemFieldCatalog.json`（464 字段，每条带 6 个 `*Key`）`Models/SystemDataSnapshot.swift:43-65,183` `Services/BatteryService.swift:12` |

### 九个 section 的装配顺序（`Views/FinalDashboardView.swift`，`LazyVStack` 起于 30）

| # | Section | 行号 |
|---|---|---|
| 1 | `RemainingTimeHeroSection` | 31 |
| 2 | `RuntimeBenchmarkSection`（条件 `snapshot.specification != nil`） | 33-39 |
| 3 | `PowerCenterSection` | 41-51 |
| 4 | `RemainingTimeHistorySection` | 53-57 |
| 5 | `CapacityBreakdownSection` | 59 |
| 6 | `MetricReferenceSection` | 60 |
| 7 | `ConsumerExplanationSection` | 61 |
| 8 | `CompleteHardwareDetailView` | 62 |
| 9 | `SystemDataWorkbenchView` | 63-70 |

---

## 趋势页（侧边栏第 3 项）

| 区域 | 文案 key | 动态变量 | 渲染位置 | 数据来源 |
|---|---|---|---|---|
| 页头 | `shell.trends_subtitle` | `DashboardDestination.trends.title` | `Views/DashboardTrendsPage.swift:12-15` | `Views/DashboardShellView.swift:3-31` |
| 实时监控图 + 十指标切换 + 10分钟/1小时/24小时时间窗 + hover 读数 | `rt.title` `rt.collecting` `rt.time` `p.live_10s` `p.trend_last_*` `p.trend_fitted` `rt.y_*` | `selectedMetric` `selectedRange` `historySource` `visiblePoints` `hoveredPoint` `metricValue` `chartColor` `yAxisLabel` | `Views/RealtimeMonitorView.swift` | `Services/BatteryService.swift`（`realtimeData` + `archivedRealtimeData`）→ `Models/BatteryData.swift` `Models/TelemetryHistoryArchive.swift` |
| 图下方四个小统计卡（`StatMiniCard`） | `rt.power` `rt.voltage` `rt.amperage` `rt.temperature` `p.help_summary_power` `tip.voltage` `tip.amperage` `tip.temperature` | `currentPowerWatts` `voltage` `amperage` `temperatureCelsius` `tempColor` | `Views/RealtimeMonitorView.swift:233-264` | `Models/BatteryData.swift:53-55,60` |
| 系统剩余时间记录图（`RuntimeHistorySummaryCard`） | `p.remaining_trend` `p.no_history` | `samples` `points` `hovered` `selectedDate` `fallbackMinutes` `minutesRemaining` | `Views/DashboardTrendsPage.swift:52-114` | `Services/BatteryService.swift:15`（`runtimeSamples`）→ `Models/RuntimeSample.swift:7-9`；fallback `Models/BatteryData.swift:52` |
| 耗电应用列表（刷新 / 空态 / 加载态） | `proc.title` `proc.refresh` `proc.cpu_live` `proc.empty` `proc.loading` `proc.group_subtitle` `proc.group_count` | `processes` `hasSampled` `displayName` `cpuPercent` `memoryMB` `energyImpact` `processCount` `topChildName` | `Views/ProcessListView.swift:9-206` | `Services/ProcessMonitorService.swift:7`（`topProcesses`）→ `Models/ProcessInfo.swift:7-25` |
| 进程行展开后的 CPU 迷你趋势图（`CPUSparkline`） | `proc.cpu_trend` `tip.cpu` `proc.peak` `proc.avg` `proc.collecting` `p.live_10s` | `history` `peak` `avg` `isExpanded` | `Views/ProcessListView.swift:211-292` | `Models/ProcessInfo.swift:13`（`cpuHistory`） |
| 充放电历史卡 + 会话明细行 | `hist.title` `hist.refresh` `hist.analyzing` `hist.empty` `hist.empty_hint` `hist.rate_unit` `hist.duration` | `sessions` `isLoading` `session.date/startTime/endTime/startPercent/endPercent/ratePerHour/durationMinutes/note` | `Views/HistoryChartView.swift:9-83,136-207` | `Services/BatteryService.swift:9,16` → `Models/BatteryData.swift:143-152` |
| 充电速率柱状图（`rateChart`） | `hist.rate_chart` `tip.charge_rate` | `maxRate` `animatedBars` `session.ratePerHour` `session.date` | `Views/HistoryChartView.swift:85-133` | `Models/BatteryData.swift:145,151` |

### 实时监控图可选指标（`RealtimeMonitorView.MetricType`，`Views/RealtimeMonitorView.swift:12-34`）

数据源全部挂在 `RealtimeDataPoint`（`Models/BatteryData.swift`）。

| 成员 | 取值 | 颜色 | 单位 | Y 轴 key | tooltip key |
|---|---|---|---|---|---|
| `.voltage` | `point.voltage` (:196) | accentPurple | V | `rt.y_voltage` | `tip.voltage` |
| `.amperage` | `point.amperage` (:197) | chargingCyan | mA | `rt.y_amperage` | `tip.amperage` |
| `.power`（默认选中） | `point.power` (:198) | chargingBlue | W | `rt.y_power` | `p.help_summary_power` |
| `.temperature` | `point.temperature` (:199) | batteryYellow | ℃ | `rt.y_temperature` | `tip.temperature` |
| `.percent` | `Double(point.percent)` (:200) | batteryGreen | % | `rt.y_percent` | `tip.percent` |
| `.adapterRatedPower` | `point.adapterRatedPower`，缺失时 `adapterVoltage × adapterCurrent` | batteryYellow | W | 动态标题 | `p.help_summary_adapter_power` |
| `.adapterOutputPower` | `point.adapterOutputPower` | chargingCyan | W | 动态标题 | `p.help_summary_adapter_output_power` |
| `.chargingPower` | `point.chargingPower` | batteryGreen | W | 动态标题 | `p.help_summary_charging_power` |
| `.cycleCount` | `point.cycleCount` | accentPurple | 次 | 动态标题 | `p.help_summary_cycle_count` |
| `.health` | `point.healthPercent` | batteryGreen | % | 动态标题 | `p.help_summary_health` |

时间窗与问号面板共用 `MetricHelpTrendRange`：`.tenMinutes`（默认，1 分钟一桶，10 点）／`.oneHour`（3 分钟一桶，20 点）／`.twentyFourHours`（36 分钟一桶，40 点）。三档都只显示已封闭的固定均值桶，因此图表最快 1 分钟推进，不会跟随后台 10 秒轮询提前变化。短缺口最多拟合 2 桶/1 桶并标 `p.trend_fitted`；更长离线时段拆成不同 `segmentID`，不连线。

---

## 诊断页（侧边栏第 4 项）

| 区域 | 文案 key | 动态变量 | 渲染位置 | 数据来源 |
|---|---|---|---|---|
| 健康诊断卡 `HealthDiagnosisCard`（评分环 = `health.score`，等级色 = `health.level`） | `insight.section.health` `insight.level.excellent` `insight.collapse` `insight.expand_factors` `insight.life.label` `insight.life.months` `insight.age.label` `insight.factor.cycles` | `diagnosis.score/level/headline/factors/remainingLife/age` `showFactors` | `Views/InsightCards.swift:5-187`（环 103-112；挂载 `DashboardDiagnosticsPage.swift:16`） | `Services/InsightEngine.swift:60-66`（`BatteryInsight.health` :145） |
| 充电习惯卡 `ChargingHabitCard`（评分条 = `habit.score`/100，等级字母 = `habit.grade`） | `insight.section.habit` `insight.collecting` `insight.days_left` | `habit.score/grade/behaviors/topSuggestion/daysCollected/daysNeeded` | `Views/InsightCards.swift:261-295`（挂载 `:17`） | `Services/InsightEngine.swift:76-83`（`.habit` :146） |
| 配件诊断卡 `AccessoryCard`（无环，状态由 `isConnected` + `checks.passed` 决定） | `insight.section.accessory` | `accessory.isConnected/summary/subtitle/checks/suggestion` | `Views/InsightCards.swift:320-376`（挂载 `:18`） | `Services/InsightEngine.swift:93-98`（`.accessory` :147） |
| 功耗分析卡 `PowerAnalysisCard`（无环，进度条 = 每进程 `cpuPercent`，主色 = `power.level`） | `insight.section.power` `insight.power.eta` `insight.power.on_ac` `proc.col_cpu` | `analysis.currentWatts/level/estimatedHoursRemaining/topConsumers/note` `displayName` `cpuPercent` `energyImpact` | `Views/InsightCards.swift:380-448`（挂载 `:19`） | `Services/InsightEngine.swift:125-130`（`.power` :148） |
| 系统异常汇总卡 `SystemAnomalySummaryCard`（计数徽标 = `anomalies.count`，最多列 8 条） | `shell.system_anomalies` `p.system_no_anomaly` | `anomalies.count` `field.metadata.path` `field.anomalyReason` `field.valueWithUnit` `field.anomalyLevel` `dataVersion` `selectedHelp` | `Views/DashboardDiagnosticsPage.swift:42-113`（调用 21-22） | `Models/SystemDataSnapshot.swift`（`systemDataSnapshot`，取用点 `:44`） |
| 页头 + 加载占位 | `shell.diagnostics` `shell.diagnostics_subtitle` `shell.diagnosing` | `batteryService.insight` | `Views/DashboardDiagnosticsPage.swift:10-13,24-31` | `Services/InsightEngine.swift:144-149` |

---

## 设置页（侧边栏第 5 项）

| 区域 | 文案 key | 动态变量 | 渲染位置 | 数据来源 |
|---|---|---|---|---|
| 页头 | `shell.settings` `shell.settings_subtitle` | — | `Views/DashboardSettingsPage.swift:11-14` | `Views/DashboardShellView.swift:12-20` |
| 外观模式设置行（只提供浅色/深色） | `shell.appearance` | `appearance.mode` `AppearanceMode.selectableCases` `mode.title` `mode.symbol` | `Views/DashboardSettingsPage.swift:15-17` | `Services/AppearanceSettings.swift:8,14,33,41,56,81` |
| 语言设置行 | `p.menu_language` `lang.system` | `localization.currentName/languages/isFollowingSystem/effectiveCode` | `Views/DashboardSettingsPage.swift:18-21` | `Services/Localization.swift`（`L10n.shared`） |
| 实时更新开关 | `shell.live_refresh` `p.live_10s` `p.live_paused` | `isLiveRefreshEnabled` `setLiveRefreshEnabled` | `Views/DashboardSettingsPage.swift:23-34`（`setLiveRefresh` 154-157） | `Services/BatteryService.swift` |
| 隐私说明条 | `shell.privacy_note` | —（静态文案，无数据源） | `Views/DashboardSettingsPage.swift:35-43` | — |
| 菜单栏面板指标勾选（顶部状态配置 + 动态趋势两组开关） | `menu.config.title` `menu.config.manage_in_dashboard` `shell.dynamic_trends` | `visibleMetrics` `visibleTrendMetrics` `MenuBarMetric.allCases` `MenuBarTrendMetric.allCases` `metric.title` `metric.symbol` `batteryData` `chargeSpeed` | `Views/DashboardSettingsPage.swift:52-137`（调用 22） | `Services/MenuBarSettings.swift:7,19,62,69,105-106,134,167` |

---

## 窗口外壳

| 区域 | 文案 key | 动态变量 | 渲染位置 | 数据来源 |
|---|---|---|---|---|
| 侧边栏 `DashboardSidebar`（`DashboardDestination` 五成员 overview/technical/trends/diagnostics/settings） | `shell.overview` `shell.technical` `shell.trends` `shell.diagnostics` `shell.settings` `app.title` `shell.sidebar_subtitle` `shell.local_only` | `selection` `destination.title` `destination.symbol` `DashboardDestination.allCases` | `Views/DashboardShellView.swift:33-116`（枚举与标题 3-31） | `Views/ContentView.swift:4-11,26-29`（`DashboardNavigation.shared.destination`） |
| 页头组件 `DashboardPageHeader`（title/subtitle/trailing） | — | `title` `subtitle` `trailing` | `Views/DashboardShellView.swift:118-143` | 调用方传入 |
| 外观选择器 `AppearanceModePicker`（浅色/深色两段式，`showLabels` 控文字） | — | `appearance.mode` `AppearanceMode.selectableCases` `mode.title` `mode.symbol` `showLabels` | `Views/DashboardShellView.swift:145-184` | `Services/AppearanceSettings.swift:8,14,33,41,56,81` |
| 语言选择器 `LanguageSelectionMenu`（fullWidth / iconOnly 两形态） | `lang.system` `p.menu_language` | `localization.languages/currentName/isFollowingSystem/effectiveCode` | `Views/DashboardShellView.swift:186-241` | `Services/Localization.swift`（`L10n.shared`，取用点 `:191`） |
| 窗口内容路由 `ContentView`（侧边栏 + 分页 + `MetricHelpDrawer` 抽屉 + 外观桥接） | — | `navigation.destination` `selectedMetricHelp` `appeared` `appearance.mode` `batteryData.lastUpdated` `topProcesses` | `Views/ContentView.swift:13-82` | `Views/ContentView.swift:4-11`（`DashboardNavigation`） |

---

## 菜单栏（状态项 + 弹出面板）

| 区域 | 文案 key | 动态变量 | 渲染位置 | 数据来源 |
|---|---|---|---|---|
| 状态项 label `MenuBarStatusLabel` | —（纯格式化，文案来自 `metric.title` / `timeTitle`） | `percentText` `secondaryMetric` `statusValue` `chargeSpeed` | `Views/MenuBarStatusItem.swift:3-15` | `Views/MenuBarPresentation.swift:99-129` |
| 状态项时间标题 / 来源说明（`timeTitle` `sourceText`） | `p.menu_unplug` `p.menu_time` `p.menu_direct` `p.menu_forecast` `p.menu_waiting` `p.menu_unplug_short` | `isForecast` `runtimeMinutes` `isOnAC` `unplugEstimateMinutes` `timeRemainingMinutes` | `Views/MenuBarDashboardView.swift:158` | `Views/MenuBarPresentation.swift:33-46` |
| 顶部状态栏配置卡 `MenuBarTopStatusConfigurationView` | `menu.config.second_metric` `menu.config.status_hint` `menu.config.metric_choice` | `secondaryMetric` `choicePreviewText` `compact` | `Views/MenuBarStatusItem.swift:19-141` | `Services/MenuBarSettings.swift:104-132` |
| 面板头部 + 电量条 + 底部入口 | `app.title` `p.menu_close` `p.menu_quit` `p.system_charge` `p.menu_open` `p.menu_settings` `p.refresh_now` `p.pause_refresh` | `percentText` `chargeFraction` `sourceText` `isLiveRefreshEnabled` | `Views/MenuBarDashboardView.swift:128-252,683-741` | `Views/MenuBarPresentation.swift:25-54` |
| 弹出面板指标行 `metricValueRow` | `menu.config.title` `menu.config.empty` `menu.metric.runtime` `menu.metric.power` `menu.metric.temperature` `menu.metric.cycles` `menu.metric.health` `menu.metric.current` `menu.metric.charge_power` `menu.metric.charge_speed` | `visibleMetrics` `metric.icon` `presentation.title(for:)` `presentation.value(for:)` | `Views/MenuBarDashboardView.swift:254-368` | `Views/MenuBarPresentation.swift:83-98` |
| 趋势区 `trendSection` / `trendRow` / `MenuSparkline` | `shell.dynamic_trends` `shell.last_minutes` `menu.config.restore_defaults` `shell.instant_power` `p.menu_time` `shell.current` `menu.config.drag_to_reorder` | `visibleTrendMetrics` `trendValues` `trendValue` `trendColor` `realtimeData` `runtimeSamples` | `Views/MenuBarDashboardView.swift:456-601,818-850` | `Views/MenuBarDashboardView.swift:608-626` + `Services/BatteryService.swift:10,15` |
| 进程区 `processSection` | `shell.top_processes` `shell.cpu_context` `menu.process.none` `p.process_collecting` | `topProcesses` `hasSampled` `displayName` `cpuPercent` `energyImpact` | `Views/MenuBarDashboardView.swift:638-686,781-820` | `Views/MenuBarDashboardView.swift:668-676`（直连 `ProcessMonitorService`） |
| 指标编辑（自定义 / 隐藏 / 添加更多） | `menu.config.customize` `menu.config.hide` `menu.config.add_more` `menu.config.manage_in_dashboard` `menu.config.empty` | `isCustomizing` `setVisible` `setTrendVisible` `showMetricSettings` | `Views/MenuBarDashboardView.swift:261-299,318-334,414-441` | `Services/MenuBarSettings.swift:134-176,201-207` |
| 拖拽排序（指标行 + 趋势行手势） | `menu.config.drag_to_reorder` | `draggedMetric` `dragOriginIndex` `draggedTrendMetric` `trendDragOriginIndex` `customizableMetricRowHeight`(44) | `Views/MenuBarDashboardView.swift:335-350,374-412,532-547,568-601` | `Services/MenuBarSettings.swift:145-165,178-190` |

### `MenuBarMetric` 全部成员（`Services/MenuBarSettings.swift:7-57`）

| 成员 | 文案 key | 取值来源 | 格式化位置 |
|---|---|---|---|
| `runtime` | `menu.metric.runtime`（标题被 `presentation.title(for:)` 覆盖为 `p.menu_time` / `p.menu_unplug`） | `timeRemainingMinutes`（放电）／ `unplugEstimateMinutes`（AC，`Models/BatteryData.swift:109`） | `MenuBarPresentation.durationText` `:138`；状态项前缀 `p.menu_unplug_short` `:105` |
| `power` | `menu.metric.power` | `currentPowerWatts`（`Models/BatteryData.swift:55`） | `powerText` `:57` ／ 状态项 `LNum("%.1fW")` `:109` |
| `temperature` | `menu.metric.temperature` | `temperatureCelsius`（`Models/BatteryData.swift:60`） | `temperatureText` `:58` ／ `:111` |
| `cycles` | `menu.metric.cycles` | `cycleCount`（`Models/BatteryData.swift:57`） | `cycleCount.formatted()` `:92` ／ `"\(cycleCount)×"` `:113` |
| `health` | `menu.metric.health` | `systemHealthPercent ?? maxCapacityPercent`（`Models/BatteryData.swift:78` / `:58`） | `healthPercent` + `healthText` `:52-56` ／ `:115` |
| `current` | `menu.metric.current` | `amperage`（mA，`Models/BatteryData.swift:53`） | `LNum("%.2f A", amperage/1000)` `:94` ／ `:117` |
| `chargingPower` | `menu.metric.charge_power` | `DashboardMetricSnapshot(data:realtimeData:[])`（`MenuBarPresentation.swift:63-65`） | `DashboardMetricSnapshot.chargingPowerText` `Models/DashboardMetricSnapshot.swift:133` ／ `chargingPowerCompactText` `:140` |
| `chargeSpeed` | `menu.metric.charge_speed` | `BatteryService.chargeSpeed`（`Services/BatteryService.swift:24`）经 `ChargeSpeedEstimate.gainPercent(overMinutes:)`（`Models/ChargeSpeedEstimate.swift:69`） | `chargeSpeedText(separator:)` `:74-81`；horizons 5/10 分钟定义在 `:70` |

### `MenuBarTrendMetric` 全部成员（`Services/MenuBarSettings.swift:62-87`）

| 成员 | 文案 key | sparkline 序列 | 右侧数值 |
|---|---|---|---|
| `power` | `shell.instant_power` | `realtimeData.suffix(32).map(\.power)` | `presentation.powerText`（`MenuBarDashboardView.swift:606` / `:617`） |
| `runtime` | `p.menu_time` | `runtimeSamples.suffix(32).map(\.minutesRemaining)` | `presentation.runtimeText`（`:608` / `:619`） |
| `current` | `shell.current` | `realtimeData.suffix(32).map(\.amperage)` | **本地** `LNum("%.2f A", Double(data.amperage)/1000)`（`:610` / `:621`） |

---

## 问号帮助面板（横跨多页，`enum DashboardHelp`）

面板内容结构见下一节。触发点列的是 `grep` 到的调用位置。

| 面板 | 主要文案 key | 关键变量 | 原始字段 | 定义位置 | 触发点 |
|---|---|---|---|---|---|
| `power` | `p.priority_power` `p.help_summary_power` `p.trend_history` `p.trend_last_10min` `p.trend_last_1h` `p.trend_last_24h` `p.trend_range` `p.trend_note_power` `p.trend_waiting` | `currentPowerWatts` `detail.systemPowerWatts` `detail.systemLoad` `voltage` `amperage` `detail.accumulatedSystemLoad` `detail.averageTelemetryPowerWatts` `selectedTrendRange` | `BatteryData.SystemPower` `PowerTelemetryData.SystemLoad` `Voltage` `Amperage` `AccumulatedSystemLoad` `SystemLoadAccumulatorCount` | `Views/DashboardHelp+Power.swift:6` | `DashboardOverviewPage.swift:415` `PowerCenterSection.swift:43` `RemainingTimeHeroSection.swift:170` |
| `adapterPower` | `p.adapter_status_title` `p.help_summary_adapter_power` `p.help_source_adapter_power` `p.adapter_status_*` `p.adapter_contract_*` `p.adapter_input_trend*` `p.adapter_equation_waiting` `p.adapter_voltage` `p.adapter_current` `p.adapter_rated_power` | `detail.adapterWatts` `chargerWattage` `detail.adapterVoltage` `detail.adapterCurrent` `detail.systemPowerIn` `detail.usbHvcMenu` `detail.adapterDescription` `detail.hasAdapterData` `adapterOutputPowerWatts` `batteryPowerWatts` | `AdapterDetails.Watts` `.AdapterVoltage` `.Current` `Derived.NegotiatedPower` `PowerTelemetryData.SystemPowerIn` `AdapterDetails.UsbHvcMenu` `.Description` | `Views/DashboardHelp+Power.swift:53` | `DashboardOverviewPage.swift:421` |
| `chargingPower` | `shell.charge_power` `p.help_summary_charging_power` `p.help_source_charging_power` `p.trend_note_charge` | `voltageVolts` `batteryChargingCurrentMilliamps` `batteryChargingPowerWatts` `detail.packVoltage` `detail.appleRawBatteryVoltage` `detail.instantAmperage` `detail.smoothedAmperage` | `AppleRawBatteryVoltage` `Voltage` `Derived.BatteryPackVoltage` `InstantAmperage` `Amperage` `IsCharging` | `Views/DashboardHelp+Power.swift:162` | `DashboardOverviewPage.swift:439` |
| `adapterOutputPower` | `shell.adapter_output_power` `p.help_summary_adapter_output_power` `p.help_source_adapter_output_power` `p.raw_power_in_explain` `p.raw_voltage_in_explain` `p.raw_current_in_explain` `p.raw_adapter_loss_explain` `p.trend_note_adapter_output` | `adapterOutputPowerWatts` `currentPowerWatts` `batteryPowerWatts` `detail.systemPowerIn` `detail.systemVoltageIn` `detail.systemCurrentIn` `detail.adapterEfficiencyLoss` | `PowerTelemetryData.SystemPowerIn` `.VoltageIn` `.CurrentIn` `.AdapterEfficiencyLoss` | `Views/DashboardHelp+Power.swift:214` | `DashboardOverviewPage.swift:433` |
| `stateOfCharge` | `p.system_charge` `p.help_summary_soc` `p.help_direct` | `percent` `detail.currentCapacityRaw` `detail.appleRawCurrentCapacity` `detail.appleRawMaxCapacity` | `CurrentCapacity` `AppleRawCurrentCapacity` `AppleRawMaxCapacity` | `Views/DashboardHelp+Capacity.swift:5` | `RemainingTimeHeroSection.swift:77` |
| `health` | `p.priority_health` `p.help_summary_health` | `healthPercent` `fullChargeCapacity` `detail.packReserve` `designCapacity` | `AppleRawMaxCapacity` `PackReserve` `DesignCapacity` | `Views/DashboardHelp+Capacity.swift:23` | `DashboardOverviewPage.swift:457` `RemainingTimeHeroSection.swift:156` |
| `cycleCount` | `menu.metric.cycles` `p.help_summary_cycle_count` `p.help_source_cycle_count` `p.help_direct` | `detail.cycleCount` `cycleCount` `detail.designCycleCount` | `CycleCount` `DesignCycleCount9C` | `Views/DashboardHelp+Capacity.swift:40` | `DashboardOverviewPage.swift:451` |
| `temperature` | `p.priority_temp` `p.help_summary_temperature` `p.trend_note_temperature` | `detail.temperatureRaw` `temperatureCelsius` `RealtimeDataPoint.temperature` | `Temperature` | `Views/DashboardHelp+Capacity.swift:74` | `DashboardOverviewPage.swift:445` `RemainingTimeHeroSection.swift:183` |
| `capacityOverview` | `p.where_title` `p.help_summary_capacity` | `designCapacity` `fullChargeCapacity` `currentCapacity` `qmaxCapacityForBreakdown` `inaccessibleCapacity` `truePermanentLoss` `usedSinceFull` `longTermCapacityGap` | `DesignCapacity` `AppleRawMaxCapacity`(FCC) `AppleRawCurrentCapacity` `min(Qmax)` | `Views/DashboardHelp+Capacity.swift:116` | `CapacityBreakdownSection.swift:26` |
| `designCapacity` | `p.design_capacity` `p.help_summary_design_capacity` `p.help_direct` | `designCapacity` | `DesignCapacity` | `Views/DashboardHelp+Capacity.swift:148` | `CapacityBreakdownSection.swift:65,223` |
| `currentMax` | `p.current_max` `p.help_summary_full_capacity` `p.help_direct` | `fullChargeCapacity` | `AppleRawMaxCapacity` | `Views/DashboardHelp+Capacity.swift:154` | `CapacityBreakdownSection.swift:71,83,233` |
| `currentActual` | `p.current_actual` `p.current_actual_desc` | `currentCapacity` `detail.appleRawCurrentCapacity` `fullChargeCapacity` | `AppleRawCurrentCapacity` `AppleRawMaxCapacity` | `Views/DashboardHelp+Capacity.swift:160` | `CapacityBreakdownSection.swift:89,243` |
| `usedSinceFull` | `p.used_since_full` `p.help_summary_used` | `usedSinceFull` `fullChargeCapacity` `currentCapacity` | `AppleRawMaxCapacity` `AppleRawCurrentCapacity` | `Views/DashboardHelp+Capacity.swift:174` | `CapacityBreakdownSection.swift:86,254` |
| `capacityGap` | `p.capacity_gap` `p.capacity_gap_summary` | `longTermCapacityGap` `designCapacity` `fullChargeCapacity` | `DesignCapacity` `AppleRawMaxCapacity`(FCC) | `Views/DashboardHelp+Capacity.swift:188` | `CapacityBreakdownSection.swift:68,113,286` |
| `inaccessibleCapacity` | `p.seg_un` `p.unusable_ex` | `qmaxCapacityForBreakdown` `inaccessibleCapacity` `fullChargeCapacity` | `min(Qmax)` `AppleRawMaxCapacity`(FCC) | `Views/DashboardHelp+Capacity.swift:202` | `CapacityBreakdownSection.swift:116,265` |
| `permanentLoss` | `p.seg_age` `p.seg_age_d` | `qmaxCapacityForBreakdown` `truePermanentLoss` `longTermCapacityGap` `fullChargeCapacity` `designCapacity` | `DesignCapacity` `min(Qmax)` | `Views/DashboardHelp+Capacity.swift:218` | `CapacityBreakdownSection.swift:119,275` |
| `specOverview` | `p.spec_other_title` `p.spec_source_note` `p.help_direct` | `rawFieldReadAt`（三行 label-only，`updateClass = .untimed`） | IOKit live fields、`LifetimeData` | `Views/DashboardHelp+Capacity.swift:234` | `MetricReferenceSection.swift:79` |
| `cellBalance` | `insight.factor.balance` `p.help_summary_balance` | `detail.cellVoltages` `detail.cellVoltageDelta` | `BatteryData.CellVoltage` | `Views/DashboardHelp+Capacity.swift:252` | `MetricReferenceSection.swift:29` |
| `resistance` | `insight.factor.resistance` `p.help_summary_resistance` | `detail.weightedRa` | `BatteryData.WeightedRa` | `Views/DashboardHelp+Capacity.swift:268` | `MetricReferenceSection.swift:43` |
| `cycles` | `insight.factor.cycles` `p.help_summary_cycles` | `detail.cycleCount` `detail.designCycleCount` `detail.cycleUsage` | `CycleCount` `DesignCycleCount9C` | `Views/DashboardHelp+Capacity.swift:284` | `MetricReferenceSection.swift:55` |
| `packVoltage` | `hw.m.pack_voltage` `p.help_summary_voltage` | `voltageVolts` `detail.voltageRaw` `detail.packVoltage` `detail.appleRawBatteryVoltage` `detail.minimumPackVoltage` `detail.maximumPackVoltage` | `Voltage` `AppleRawBatteryVoltage` `LifetimeData.MinimumPackVoltage` `.MaximumPackVoltage` | `Views/DashboardHelp+Capacity.swift:300` | `MetricReferenceSection.swift:68` |
| `runtime` | `p.runtime_compare_title` `p.runtime_compare_summary` `p.runtime_compare_source` `p.runtime_system_*` `p.runtime_stable_*` `p.runtime_current_*` `p.chart_waiting` `p.runtime_unavailable` `p.runtime_raw_unavailable` | `systemRuntimeMinutes` `stableRuntimeMinutes` `currentLoadRuntimeMinutes` `designEnergyWh` `remainingEnergyWh` `stablePowerWatts` `recentStablePowerSamples` `latestStablePowerSampleTime` `currentPowerAgeSeconds` `detail.timeRemainingRaw` `detail.avgTimeToEmpty` | `TimeRemaining` `AvgTimeToEmpty` `ModelDesignEnergy` `AppleRawCurrentCapacity` `DesignCapacity` `Derived.Recent10mMedianPower` `Derived.Recent10mValidSamples` `BatteryData.SystemPower` `Derived.CurrentPowerSampleAge` | `Views/DashboardHelp+Runtime.swift:5` | `RemainingTimeHeroSection.swift:15,55` `DashboardOverviewPage.swift:70` |
| `officialBenchmark` | `p.runtime_audit_tag` `p.audit_conditions` | `spec.designEnergyWh` `spec.officialWebHours` `spec.officialVideoHours` `spec.sourceName` `spec.sourceURL` `currentFullEnergyWh` `modelIdentifier` | 机型标识 `modelIdentifier`、Apple 官方 design energy／wireless web／streaming video、`AppleRawMaxCapacity` `DesignCapacity` | `Views/DashboardHelp+Runtime.swift:153` | `RuntimeBenchmarkSection.swift:26` |
| `runtimeHistory` | `p.unplug_trend` `p.forecast_only` `p.remaining_trend` `p.help_summary_time_history` `p.help_direct` | `isForecast` `unplugEstimateMinutes` `remainingEnergyWh` `currentPowerWatts` `timeRemainingMinutes` `detail.timeRemainingRaw` `detail.avgTimeToEmpty` | `remainingEnergy` `SystemPower` `TimeRemaining` `AvgTimeToEmpty` | `Views/DashboardHelp+Runtime.swift:176` | `RemainingTimeHistorySection.swift:45` |
| `directCapacity` | `p.help_direct` | 共用构造器，**不是独立面板** | — | `Views/DashboardHelp.swift:8` | 无外部调用；`+Capacity.swift:149,155` 内部复用 |

### `DashboardHelp` 的工具成员（不是面板，写新面板时会用到）

`Views/DashboardHelp.swift` —— `trendPoints` 读 `DashboardMetricSnapshot.trendRealtimeData`：有 10 秒原始点的区间优先原始点，较旧区间才用永久 3 分钟档案，避免同一批读数被重复加权。`Views/MetricHelpContent.swift` 的 `MetricHelpTrendRange` 统一提供 10 分钟（默认，10 个 1 分钟桶）/1 小时（20 个 3 分钟桶）/24 小时（40 个 36 分钟桶），只显示已封闭桶；短缺口标为拟合，长缺口断线。`Services/BatteryService.swift` 每五分钟及正常退出时保存最近 24 小时原始点，同时把三分钟汇总按本地日期写入 `Application Support/BatteryMonitor/TelemetryHistory/YYYY-MM-DD.json`；历史日文件永久保留，界面只载入最近 24 小时。

### `MetricHelpContent` 结构（写新面板照这个形状）

稳定入口：`Views/MetricHelpContent.swift` 的 `MetricHelpContent`；纵向链路见 `feature:help.metric`。

- **必填**：`id`（面板唯一 ID，也是 drawer 刷新的比对键）、`title`、`summary`、`result`、`rawFields: [MetricRawField]`、`formula`、`substitution`（代入数字后的算式）、`source`
- **可选**：`readAt: MetricReadStamp?`（整卡共用读取时间）、`comparisonResults: [MetricHelpResult]`（并列对照，`runtime` 用了 3 个）、`powerContract: MetricPowerContract?`（PD 协商块，仅 `adapterPower`）、`trend: MetricHelpTrend?`
- **配套**：`MetricHelpResult`(id/title/value/note/style: `.primary|.stable|.current`，`:20`)、`MetricHelpTrend`(title/latestText/note/unit/tint/points/ceiling/baselineAtZero/waitingText，`:37`，`isPlottable` 要求 ≥2 点)、`MetricHelpTrendPoint`(`:28`)、`MetricPowerContract`(`:62`)

### 三个字段元数据类型各自负责什么

| 类型 | 位置 | 职责 |
|---|---|---|
| `MetricRawField` | `Views/MetricHelpModels.swift:72` | 一行底层字段：name/value/unit/explanation + `updateClass`（更新频率轴）+ `readAt`（本行独立时间，nil 回落卡片）+ `availability`（`.notProvidedOnAC` 等结构性无值）。`effectiveUpdateClass` 按名字把 `designcapacity` / `designcyclecount9c` / `packreserve` 自动降为 `.constant`；`localizedExplanation` 在 call site 没写说明时由 `MetricRawFieldExplanation.text(for:)`（`:114`，`p.raw_explain_*` 一整套）兜底。**`id` 故意不含 `readAt`**，避免每秒重建行、丢失文本选中 |
| `MetricReadStamp` | `Views/MetricHelpModels.swift:35` | 「读取时刻 + 来自哪只时钟」：`at`、`isGaugePublished`（电量计自己的 UpdateTime 还是我们的轮询）、`polledAt`、`interval`（观测到的电量计发布周期）。工厂 `.gauge(_:polledAt:interval:)` / `.ourRead(_:)`。**`==` 只比 `at` 和 `isGaugePublished`**，防止 `polledAt` 每次轮询都让下游"看起来变了" |
| `MetricFieldFreshness` | `Views/MetricHelpModels.swift:226` | 渲染字段下方那行「何时读取／多久刷新」。`gaugeRefreshSeconds = 60`；`text(for:cardReadAt:now:)` 按 `effectiveUpdateClass` 分支（`.untimed` 返回 nil、`.modelSpec`/`.constant` 静态措辞、`.eventDriven`/`.live` 给时间或倒计时）；`secondsUntilVisibleRefresh` 把电量计发布时刻投影到我们的轮询网格，让"0 秒"真的等于屏幕上数字会变。key：`p.field_read_at` `p.field_read_at_gauge` `p.field_read_at_gauge_due` `p.field_read_at_event` `p.field_read_at_unavailable` `p.field_spec_static` `p.field_constant` `p.field_age_seconds/minutes/hours` |

---

## 已知不一致与陷阱

改到这些地方之前先看这一节。

| 问题 | 位置 | 说明 |
|---|---|---|
| `MenuBarPresentation` **不只服务菜单栏** | `Views/DashboardOverviewPage.swift:62` | 总览页电量大字复用 `presentation.percentText`，充电功率复用 `DashboardMetricSnapshot` 的共享格式器；其余七卡按总览语境直接格式化。改 presentation 不等于全看板都会同步变化 |
| 趋势序列不经过 presentation | `Views/MenuBarDashboardView.swift:608-616` | presentation 只提供菜单栏标量出口，sparkline 直接读 `batteryService.realtimeData` / `runtimeSamples`，属结构性绕过 |
| 进程数据不经过 presentation | `Views/MenuBarDashboardView.swift:676` | `LNum("%.1f%% CPU", process.cpuPercent)` 直接取 `ProcessMonitorService` |
| 界面可见标题 ≠ 项目内部说法 | 技术参数页九个 section | 文件地图记的是"顶部剩余时间主卡""容量拆解"，界面上写的是"还能用多久""你买的容量去哪了"。**按界面文字搜项目内部说法可能搜不到**，用本文件 |
| `runtime` 有两个同名成员 | `Views/DashboardHelp.swift:169` vs `Views/DashboardHelp+Runtime.swift:5` | 一个是面板 `runtime(_ s:)`，一个是格式化工具 `runtime(minutes:)` |
| 四层核验台的搜索**按当前界面语言匹配**，不再搜中文原值 | `Views/SystemDataWorkbenchView.swift:55-69` | 搜索域 = `path`/`value`/`source`（英文标识符，任何语言下都能搜）+ 当前语言的 `localizedGroup`/`localizedMeaning`/`localizedNote`/`localizedUnit`/`localizedReliability`。**界面切到 `ko` 后用中文词搜不到任何东西**（本地化前搜的是 catalog 的中文原值）。原值仍留在 JSON 里，但只供 `isMeaningfulByDefault` 与 `SystemFieldValueConversion` 做令牌比对，不参与搜索 |
| catalog 的中文原值**不是死数据，不许删** | `BatteryMonitor/Resources/SystemFieldCatalog.json` | `group`/`unit`/`meaning` 等中文原值同时是 zh-Hans 文案与上述两处令牌比对的输入。删掉原值只留 `*Key`，界面照常显示，但「默认有用」筛选和单位换算会静默失效。`Scripts/verify-release-app.sh` 有两条耦合守卫专防这件事 |

准确表述：**`MenuBarPresentation` 是菜单栏电池标量取值与格式化的唯一出口**（`percentText` `runtimeText` `healthText` `powerText` `temperatureText` `chargingPowerText` `chargeSpeedText` + `value(for:)` / `statusValue(for:)`）。总览页仅复用 `percentText` 和共享的充电功率格式器；趋势序列、进程数据和总览其余指标不经过它。

---

## 维护约定

- **界面结构变了就回来改这张表**，否则它比没有更糟。
- 新增区域时按现有列顺序补一行：区域 / 文案 key / 动态变量 / 渲染位置 / 数据来源。**区域名用界面上的可见文字**，不用内部说法——这张表的用途就是从看到的东西反查代码。
- 补完 key 之后跑一次存在性校验（见顶部命令），不要把不存在的 key 写进来。
- 行号会随改动漂移。**只有区域名、key 名、变量名是稳定的锚点**；行号当近似值用，定位后靠 grep 符号确认。
- 新增或改名跨层 Feature ID 时同步更新 `FEATURE-MAP.md`，并运行 `python3 Scripts/check-doc-maps.py`。
