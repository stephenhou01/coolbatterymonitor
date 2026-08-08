# BatteryMonitor 纵向功能链地图

**用途**：已知“界面上看到的功能”或准备修改一个数字/交互时，用稳定的 `feature:<id>` 一次找到 UI、算法权威、采集/状态、复用消费者、本地化源和测试入口。

只读当前任务命中的一行，再打开其中列出的具体文件；不要默认通读全部地图。已知界面区域先查 `UI-MAP.md`，已知文件职责先查 `CODE-MAP.md`。

## 阅读约定

- `文件#符号` 是稳定锚点，不依赖会漂移的行号；用 `rg -n '符号' 文件` 精确定位。
- **权威计算**只能有一个。View 可以选择和格式化，不能复制业务公式。
- **复用消费者**用于判断修改影响面；动权威计算前至少检查这一列。
- **本地化源**是 `Localization/Sources/` 下的编辑范围，生成包不得直接修改。
- 表中测试只列最接近的入口；完整运行、安全和签名规则只见 `QA-RUNBOOK.md`。

## 续航与历史

| Feature ID | UI 入口 | 权威计算 / 选择 | 采集、状态、持久化 | 复用消费者 | 本地化源 | 测试入口 |
|---|---|---|---|---|---|---|
| `feature:runtime.comparison` | `BatteryMonitor/Views/DashboardOverviewPage.swift#DashboardOverviewPage`；`BatteryMonitor/Views/RemainingTimeHeroSection.swift#RemainingTimeHeroSection` | `BatteryMonitor/Models/DashboardMetricSnapshot.swift#systemRuntimeMinutes`、`#stableRuntimeMinutes`、`#currentLoadRuntimeMinutes`、`#displayedRuntimeMinutes` | `BatteryMonitor/Services/BatteryService+Hardware.swift#parseHardwareDetail` 提供系统值与原始功率；`BatteryMonitor/Services/BatteryService.swift#realtimeData` 提供稳健窗口 | 总览、技术页、菜单栏、帮助抽屉、实时趋势 | `Localization/Sources/overview/runtime-comparison.json`；`technical/remaining-time.json`；`shared/help.json` | `QATests/TestKit/Sources/Insight/main.swift`；`Snapshots/OverviewMetricSnapshotHarness.swift` |
| `feature:runtime.history` | `BatteryMonitor/Views/RemainingTimeHistorySection.swift#RemainingTimeHistorySection`；`BatteryMonitor/Views/DashboardTrendsPage.swift#DashboardTrendsPage` | `BatteryMonitor/Models/RuntimeSample.swift#isValid` 与 `#minimumSamplingInterval` | `BatteryMonitor/Services/BatteryService.swift#runtimeSamples`、`#saveRuntimeHistoryIfNeeded` | 技术页历史图、趋势页汇总、续航帮助 | `Localization/Sources/technical/runtime-history.json`；`trends/realtime-monitor.json` | `QATests/TestKit/Sources/Insight/main.swift` |
| `feature:runtime.benchmark` | `BatteryMonitor/Views/RuntimeBenchmarkSection.swift#RuntimeBenchmarkSection` | `BatteryMonitor/Models/BatteryModelSpecification.swift#BatteryModelSpecification` | 当前机型和电池快照来自 `BatteryService` | 技术页、续航帮助 | `Localization/Sources/technical/runtime-benchmark.json`；`shared/help.json` | `QATests/TestKit/Sources/Insight/main.swift` |

## 功率、充电与能量流

| Feature ID | UI 入口 | 权威计算 / 选择 | 采集、状态、持久化 | 复用消费者 | 本地化源 | 测试入口 |
|---|---|---|---|---|---|---|
| `feature:power.current` | 总览“当前功率”、技术页功率中心、菜单栏与趋势图 | `BatteryMonitor/Models/DashboardMetricSnapshot.swift#currentPowerWatts` | `BatteryMonitor/Services/BatteryService+Hardware.swift#parseHardwareDetail`；`BatteryMonitor/Services/BatteryService.swift#realtimeData` | `DashboardOverviewPage`、`PowerCenterSection`、`RealtimeMonitorView`、`MenuBarPresentation`、功率帮助 | `Localization/Sources/overview/battery-status.json`；`technical/power-center.json`；`trends/realtime-monitor.json`；`shared/help.json` | `QATests/TestKit/Sources/Insight/main.swift`；总览 snapshot harness |
| `feature:power.adapter-output` | 能量流适配器边、适配器输出帮助 | `BatteryMonitor/Models/DashboardMetricSnapshot.swift#adapterOutputPowerWatts` | IOKit 原始字段由 `BatteryMonitor/Services/BatteryService+Hardware.swift#parseHardwareDetail` 解码 | `PowerFlow.resolve`、`DashboardHelp.adapterOutputPower` | `Localization/Sources/overview/power-flow.json`；`shared/help.json` | `QATests/TestKit/Sources/Insight/main.swift` |
| `feature:power.battery-charging` | 总览“电池充电功率”、菜单栏指标、能量流 | `BatteryMonitor/Models/DashboardMetricSnapshot.swift#batteryChargingPowerWatts` 与 `#batteryChargingCurrentMilliamps` | 电池电压、电流和充电状态由硬件采集提供 | 总览七卡、`MenuBarPresentation`、`PowerFlow.resolve`、充电功率帮助 | `Localization/Sources/overview/battery-status.json`；`menubar/dashboard.json`；`shared/help.json` | `QATests/TestKit/Sources/Insight/main.swift`；总览 snapshot harness |
| `feature:charging.speed` | 总览速度卡、菜单栏指标 | `BatteryMonitor/Models/ChargeSpeedEstimate.swift#resolve` | `BatteryMonitor/Services/BatteryService.swift#chargeSpeed` 按轮询发布，使用历史样本和剩余空间 | 总览、菜单栏状态/面板 | `Localization/Sources/overview/battery-status.json`；`menubar/dashboard.json` | `QATests/TestKit/Sources/Insight/main.swift` |
| `feature:power.flow` | `BatteryMonitor/Views/PowerFlowDiagram.swift#PowerFlowDiagram` | `BatteryMonitor/Models/PowerFlow.swift#resolve` | 输入只来自共享 `DashboardMetricSnapshot`；边动效在 `BatteryMonitor/Views/PowerFlowEdge.swift#PowerFlowAnimatedEdge` | 总览能量流、功率帮助的口径说明 | `Localization/Sources/overview/power-flow.json`；`shared/help.json` | `QATests/TestKit/Sources/Insight/main.swift` |

## 容量、健康与硬件

| Feature ID | UI 入口 | 权威计算 / 选择 | 采集、状态、持久化 | 复用消费者 | 本地化源 | 测试入口 |
|---|---|---|---|---|---|---|
| `feature:capacity.health` | 总览健康卡、技术参数、诊断、菜单栏 | 对齐系统：`BatteryMonitor/Models/BatteryHardwareDetail.swift#systemHealthPercent`；裸值：`#rawHealthPercent`；页面选择：`BatteryMonitor/Models/DashboardMetricSnapshot.swift#healthPercent` | FCC、设计容量、`PackReserve` 由 `BatteryMonitor/Services/BatteryService+Hardware.swift#parseHardwareDetail` 提供 | 总览、容量拆解、硬件表、洞察、菜单栏、帮助 | `Localization/Sources/overview/battery-status.json`；`technical/capacity-breakdown.json`；`diagnostics/insights.json`；`shared/help.json` | `QATests/TestKit/Sources/Insight/main.swift` |
| `feature:capacity.breakdown` | `BatteryMonitor/Views/CapacityBreakdownSection.swift#CapacityBreakdownSection` | `BatteryMonitor/Models/DashboardMetricSnapshot.swift#currentCapacity`、`#inaccessibleCapacity`、`#truePermanentLoss` | 容量原始字段来自硬件详情；无额外 View 状态 | 技术页、容量帮助、洞察解释 | `Localization/Sources/technical/capacity-breakdown.json`；`shared/help.json` | `QATests/TestKit/Sources/Insight/main.swift` |
| `feature:hardware.catalog` | `BatteryMonitor/Views/CompleteHardwareDetailView.swift#CompleteHardwareDetailView` | 行定义：`BatteryMonitor/Views/CompleteHardwareMetricCatalog.swift#CompleteHardwareMetricCatalog`；存在性：`BatteryMonitor/Models/BatteryHardwareDetail.swift#presentRawFields` | 采集/解码：`BatteryMonitor/Services/BatteryService+Hardware.swift#parseHardwareDetail` | 技术页完整字段表、帮助原始字段 | `Localization/Sources/technical/hardware-details.json` | `QATests/TestKit/Sources/Insight/main.swift`；本地化 TestKit |

## 进程、诊断与系统核验

| Feature ID | UI 入口 | 权威计算 / 选择 | 采集、状态、持久化 | 复用消费者 | 本地化源 | 测试入口 |
|---|---|---|---|---|---|---|
| `feature:process.load-context` | `BatteryMonitor/Views/ProcessListView.swift#ProcessListView`；功率中心；菜单栏进程区 | 排序/聚合：`BatteryMonitor/Models/ProcessInfo.swift#rankedForDisplay`；整机口径：`BatteryMonitor/Services/SystemCPULoad.swift#SystemCPULoad` | `BatteryMonitor/Services/ProcessMonitorService.swift#fetchProcesses` 与 `#topProcesses` | 趋势页、技术页、菜单栏、`BatteryMonitor/Services/BatteryService.swift#updateProcesses` 洞察上下文 | `Localization/Sources/trends/process-list.json`；`technical/power-center.json`；`menubar/dashboard.json` | `QATests/TestKit/Sources/Insight/main.swift` |
| `feature:diagnostics.insights` | `BatteryMonitor/Views/InsightCards.swift#HealthDiagnosisCard` 等四类卡 | `BatteryMonitor/Services/InsightEngine.swift#InsightEngine` | `BatteryMonitor/Services/BatteryService.swift#insight` 每 30 秒或切语言重算；输入含 SOC 历史和进程上下文 | 诊断页、状态提示 | `Localization/Sources/diagnostics/insights.json` | `QATests/TestKit/Sources/Insight/main.swift` |
| `feature:system.workbench` | `BatteryMonitor/Views/SystemDataWorkbenchView.swift#SystemDataWorkbenchView` | 元数据/换算：`BatteryMonitor/Models/SystemDataSnapshot.swift#SystemFieldCatalog` 与 `#SystemFieldValueConversion` | `BatteryMonitor/Services/SystemDataCollector.swift#collect`；`BatteryMonitor/Services/BatteryService.swift#systemDataSnapshot` | 技术页核验台、诊断异常汇总 | `Localization/Sources/technical/system-workbench.json`；`catalogs/system-fields.json`；`diagnostics/system-anomalies.json` | 本地化 TestKit；`Scripts/generate-system-field-catalog.py` |
| `feature:telemetry.history` | 实时监控 10 分钟 / 1 小时 / 24 小时 | `BatteryMonitor/Models/TelemetryHistoryArchive.swift#appending`、`#retainedForCharts`、`#mergedHistory` | `BatteryMonitor/Services/BatteryService.swift#archivedRealtimeData` 与 `#saveTelemetryArchiveIfNeeded` | `RealtimeMonitorView`、帮助抽屉趋势 | `Localization/Sources/trends/realtime-monitor.json`；`shared/help.json` | `QATests/TestKit/Sources/Insight/main.swift` |

## 菜单栏、帮助与本地化

| Feature ID | UI 入口 | 权威计算 / 选择 | 状态 / 持久化 | 复用消费者 | 本地化源 | 测试入口 |
|---|---|---|---|---|---|---|
| `feature:menu.metrics` | 状态栏 label、弹出面板、设置页指标编辑 | 枚举/顺序：`BatteryMonitor/Services/MenuBarSettings.swift#MenuBarMetric`；格式化：`BatteryMonitor/Views/MenuBarPresentation.swift#value` | `BatteryMonitor/Services/MenuBarSettings.swift#visibleMetrics`、`#visibleTrendMetrics` 写 `UserDefaults` | `MenuBarStatusItem`、`MenuBarDashboardView`、`DashboardSettingsPage`、`AppTheme` 图标 | `Localization/Sources/menubar/dashboard.json`；`settings/preferences.json` | `QATests/TestKit/Sources/Insight/main.swift`；菜单栏 snapshot harness；本地化 TestKit |
| `feature:help.metric` | 所有指标旁的问号与抽屉 | 内容结构：`BatteryMonitor/Views/MetricHelpContent.swift#MetricHelpContent`；共用构造：`BatteryMonitor/Views/DashboardHelp.swift#DashboardHelp`；渲染：`BatteryMonitor/Views/MetricHelpView.swift#MetricHelpDrawer` | 趋势来自 `BatteryService` 遥测；读取时刻来自 `BatteryMonitor/Views/MetricHelpModels.swift#MetricReadStamp` | 总览、技术页、菜单栏的多个指标 | `Localization/Sources/shared/help.json` 及对应页面源文件 | `QATests/TestKit/Sources/Insight/main.swift`；本地化 TestKit |
| `feature:localization.runtime` | 语言选择器和全部用户可见文案 | `BatteryMonitor/Services/Localization.swift#L10n`、`#string`、`#format`、`#select` | 内置包逐 key 回退；外部包只能覆盖已有 key | 所有 View、洞察、字段 catalog、HTML 原型 | 唯一编辑权威为 `Localization/Sources/**/*.json`；生成物为 `Localization/Languages/*.json` | `python3 Localization/build-language-packs.py check`；本地化 TestKit |

## 修改顺序

1. 在 `UI-MAP.md` 找到界面区域及 `feature:<id>`。
2. 只读本表命中行，先打开“权威计算 / 选择”，再按需要打开上游状态和 UI。
3. 修改前检查“复用消费者”；同一公式不得在另一个 View 或 Presentation 重新实现。
4. 用户可见文案必须完整阅读 `LOCALIZATION.md`，先查 key/译文再改源文件。
5. 按“测试入口”选择最小验证；运行 App 前完整阅读 `QA-RUNBOOK.md`。

## 维护约定

- 新增跨层功能时使用小写点分 ID，例如 `feature:charging.efficiency`；ID 一旦被 `UI-MAP.md` 引用就不要随意改名。
- 权威算法、上游状态、复用消费者或测试入口变化时更新对应一行；不要加入精确行号。
- `UI-MAP.md` 只保存界面区域和 Feature ID，不复制本表的纵向链路。
- 修改地图后运行 `python3 Scripts/check-doc-maps.py`。
