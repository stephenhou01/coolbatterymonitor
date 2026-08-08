# BatteryMonitor 代码职责地图

**用途**：已知文件、类型或职责时，快速定位权威代码。界面可见内容先查 `UI-MAP.md`；跨 UI、算法、采集、持久化和复用消费者的功能链先查 `FEATURE-MAP.md`。

本文件只保存稳定的文件和符号职责，不保存容易漂移的精确行号。定位后使用：

```bash
rg -n 'TypeName|memberName' BatteryMonitor QATests/TestKit
```

## 分层边界

| 层 | 目录 | 放什么 |
|---|---|---|
| App 入口 | `BatteryMonitor/BatteryMonitorApp.swift` | App 生命周期、服务注入、窗口与菜单栏入口 |
| Models | `BatteryMonitor/Models/` | 领域数据、纯计算、无 SwiftUI 的适配器 |
| Services | `BatteryMonitor/Services/` | IOKit 采集、跨样本状态、定时发布、持久化、设置、本地化 |
| Views | `BatteryMonitor/Views/` | SwiftUI 页面、组件、Presentation 与用户交互 |
| Theme | `BatteryMonitor/Theme/` | 颜色、图标、通用视觉 token 与动效修饰器 |
| Resources | `BatteryMonitor/Resources/` | 系统字段 catalog 等运行时资源 |
| Localization | `Localization/Sources/` | 十语言内置文案唯一编辑权威 |
| Tests | `QATests/TestKit/` | 受 Git 跟踪的测试入口、harness、fixture 与 Runner |

只依赖当前 `BatteryData` 快照、可随取随算的值放 `DashboardMetricSnapshot`；依赖时间窗口、历史状态、定时发布或持久化的值放 `BatteryService`。View 只选择和格式化，不维护第二套业务状态。

## Models

| 文件 | 稳定职责 |
|---|---|
| `BatteryMonitor/Models/BatteryData.swift` | `BatteryData` 主快照、`ChargingSession`、10 秒 `RealtimeDataPoint`、状态枚举 |
| `BatteryMonitor/Models/BatteryHardwareDetail.swift` | IOKit 原始字段解析结果、`presentRawFields`、系统/裸健康度与硬件派生 |
| `BatteryMonitor/Models/BatteryModelSpecification.swift` | 机型到设计能量、公开续航基准的查表 |
| `BatteryMonitor/Models/ChargeSpeedEstimate.swift` | 充电速度：实测窗口优先、功率推算兜底、剩余空间与充满时间钳位 |
| `BatteryMonitor/Models/DashboardMetricSnapshot.swift` | 全看板共享的单快照无状态派生：功率、充电电流、容量拆解、三套续航 |
| `BatteryMonitor/Models/PowerFlow.swift` | 适配器、电池、整机三条能量边及来源诚实性 |
| `BatteryMonitor/Models/ProcessInfo.swift` | 进程、聚合应用、CPU 历史的数据结构 |
| `BatteryMonitor/Models/RuntimeSample.swift` | 剩余时间样本有效性与 56 秒去重 |
| `BatteryMonitor/Models/SystemDataSnapshot.swift` | 四层核验台的数据结构、本地化字段元数据、默认有用筛选与单位转换 |
| `BatteryMonitor/Models/TelemetryHistoryArchive.swift` | 实时点合并、固定桶、缺口分段和图表历史保留 |

### 容易混淆的数值口径

- 健康度：`BatteryHardwareDetail.systemHealthPercent` 包含 `PackReserve`，用于对齐系统显示；`rawHealthPercent` 是裸 FCC ÷ 设计容量。
- 剩余时间：系统直接值、当前负载推算、近 10 分钟中位功率稳健推算三套都可能正确；插电时显示的是拔电预测。
- 排查数字：先看 `DashboardMetricSnapshot` 选用口径，再看 `BatteryService` 的跨样本状态，最后看 `BatteryService+Hardware` 的原始字段和单位转换。

## Services

| 文件 | 稳定职责 |
|---|---|
| `BatteryMonitor/Services/AppearanceSettings.swift` | 浅色/深色选择；旧 `system` 偏好迁移 |
| `BatteryMonitor/Services/BatteryService.swift` | 主轮询、实时环形缓冲、充电速度、会话、续航/遥测历史与洞察调度 |
| `BatteryMonitor/Services/BatteryService+Hardware.swift` | IOKit、IOPowerSources、AppleSmartBattery 实际读取与字段解码 |
| `BatteryMonitor/Services/InsightEngine.swift` | 健康、习惯、配件与功耗的消费者洞察和评分 |
| `BatteryMonitor/Services/Localization.swift` | `L()`、`LNum()`、`L10n`、内置包与外部逐 key 覆盖 |
| `BatteryMonitor/Services/MenuBarSettings.swift` | `MenuBarMetric`、`MenuBarTrendMetric`、可见性、顺序与持久化 |
| `BatteryMonitor/Services/ProcessMonitorService.swift` | 进程采样、应用聚合、可见/隐藏刷新节奏、CPU 基线 |
| `BatteryMonitor/Services/ProcessTable.swift` | 进程表解析与低层进程信息辅助 |
| `BatteryMonitor/Services/SOCHistory.swift` | 90 天每日电量快照持久化 |
| `BatteryMonitor/Services/SystemCPULoad.swift` | 整机 CPU 与可见进程负载口径 |
| `BatteryMonitor/Services/SystemDataCollector.swift` | 四层证据采集、464 字段 catalog 合并和异常判定 |

### 刷新节奏

| 节拍 | 权威符号 |
|---|---|
| 10 秒电池、派生值、系统核验台 | `BatteryService.liveRefreshInterval` |
| 10 秒可见进程；隐藏消费者 60 秒 | `ProcessMonitorService.liveRefreshInterval` / `backgroundRefreshInterval` |
| 150 秒采样空档后重置 CPU 基线 | `ProcessMonitorService.baselineResetInterval` |
| 30 秒洞察重算；切语言立即刷新 | `BatteryService` 洞察调度 |
| 56 秒续航样本去重 | `RuntimeSample.minimumSamplingInterval` |
| 5 分钟历史批量落盘；退出强制 flush | `BatteryService.runtimePersistenceInterval` |

## Views：入口与五个页面

| 文件 | 稳定职责 |
|---|---|
| `BatteryMonitor/Views/ContentView.swift` | 窗口根视图、页面路由、帮助抽屉和外观桥接 |
| `BatteryMonitor/Views/DashboardShellView.swift` | 侧边栏、页面头、语言/外观选择器、`BatteryPowerState` |
| `BatteryMonitor/Views/DashboardOverviewPage.swift` | 电量、三套续航、能量流、电池状态、七指标和状态横幅 |
| `BatteryMonitor/Views/DashboardTechnicalPage.swift` | 技术参数页外壳 |
| `BatteryMonitor/Views/FinalDashboardView.swift` | 技术参数页九个 section 的装配与共用卡片样式 |
| `BatteryMonitor/Views/DashboardTrendsPage.swift` | 实时趋势、续航历史、进程排行和充放电历史 |
| `BatteryMonitor/Views/DashboardDiagnosticsPage.swift` | 四类洞察与系统异常汇总 |
| `BatteryMonitor/Views/DashboardSettingsPage.swift` | 外观、语言、刷新、隐私与菜单栏配置 |

## Views：技术参数页

| 文件 | 稳定职责 |
|---|---|
| `BatteryMonitor/Views/RemainingTimeHeroSection.swift` | 顶部剩余时间主卡 |
| `BatteryMonitor/Views/RuntimeBenchmarkSection.swift` | 公开续航基准与本机负载对比 |
| `BatteryMonitor/Views/RemainingTimeHistorySection.swift` | 系统剩余时间与拔电预测历史 |
| `BatteryMonitor/Views/PowerCenterSection.swift` | 当前功率曲线与进程活动 |
| `BatteryMonitor/Views/CapacityBreakdownSection.swift` | 设计、FCC、当前、不可用与永久损耗 |
| `BatteryMonitor/Views/MetricReferenceSection.swift` | 电芯、内阻、循环和电压参考 |
| `BatteryMonitor/Views/ConsumerExplanationSection.swift` | 老化与剩余时间跳变解释 |
| `BatteryMonitor/Views/CompleteHardwareDetailView.swift` | 74 行硬件字段表的搜索、分组和渲染 |
| `BatteryMonitor/Views/CompleteHardwareMetricCatalog.swift` | 74 行硬件字段目录数据与解释 |
| `BatteryMonitor/Views/SystemDataWorkbenchView.swift` | 464 字段四层核验台 |

## Views：能量流、菜单栏与帮助

| 文件 | 稳定职责 |
|---|---|
| `BatteryMonitor/Views/PowerFlowDiagram.swift` | 三节点布局、瓦数标签与说明 |
| `BatteryMonitor/Views/PowerFlowEdge.swift` | 边几何、脉冲、速度换算与窗口可见性 |
| `BatteryMonitor/Views/MenuBarPresentation.swift` | 菜单栏电池标量取值与格式化的唯一出口；总览只复用少数格式器 |
| `BatteryMonitor/Views/MenuBarStatusItem.swift` | 状态项 label 与顶部状态配置卡 |
| `BatteryMonitor/Views/MenuBarDashboardView.swift` | 弹出面板、指标、趋势、进程、编辑和拖拽 |
| `BatteryMonitor/Views/DashboardHelp.swift` | `DashboardHelp` 共用构造器、字段与趋势辅助 |
| `BatteryMonitor/Views/DashboardHelp+Power.swift` | 当前功率、适配器额定/输出、充电功率帮助 |
| `BatteryMonitor/Views/DashboardHelp+Capacity.swift` | 电量、健康、循环、温度、容量、电芯、内阻、电压帮助 |
| `BatteryMonitor/Views/DashboardHelp+Runtime.swift` | 三套续航、公开基准和历史帮助 |
| `BatteryMonitor/Views/MetricHelpContent.swift` | 帮助结果、对比、趋势和 PD 合约的数据结构 |
| `BatteryMonitor/Views/MetricHelpModels.swift` | 原始字段、读取时刻、更新分类和新鲜度 |
| `BatteryMonitor/Views/MetricHelpView.swift` | 帮助按钮、抽屉、趋势图与本地化渲染 |

## Views：趋势、诊断与通用组件

| 文件 | 稳定职责 |
|---|---|
| `BatteryMonitor/Views/RealtimeMonitorView.swift` | 十指标实时图、三档时间窗、hover 和统计卡 |
| `BatteryMonitor/Views/ProcessListView.swift` | 应用聚合列表、CPU 小趋势与刷新 |
| `BatteryMonitor/Views/HistoryChartView.swift` | 充放电会话柱图和明细 |
| `BatteryMonitor/Views/InsightCards.swift` | 健康、习惯、配件、功耗四类卡片 |
| `BatteryMonitor/Views/MetricSparkline.swift` | 无坐标轴迷你趋势线 |
| `BatteryMonitor/Views/BatteryGaugeView.swift` | **无生产引用**的旧圆形表盘；修改前先确认 |
| `BatteryMonitor/Views/HardwareDetailView.swift` | 旧界面无生产引用，但 `HardwareDetailView.build` 仍被 Insight TestKit 使用 |

## Theme 与资源

| 文件 | 稳定职责 |
|---|---|
| `BatteryMonitor/Theme/AppTheme.swift` | 配色、`BatteryMetricIcon`、降级符号和 `MetricGlyph` |
| `BatteryMonitor/Theme/AppTheme+Cyber.swift` | 扫描线等动效修饰器与 Reduce Motion 范例 |
| `BatteryMonitor/Resources/SystemFieldCatalog.json` | 464 字段元数据生成产物；中文原值与六个 `*Key` 都有运行时作用 |
| `BatteryMonitor/BatteryMonitor.entitlements` | App Sandbox 等正式权限边界 |

## TestKit 与脚本

| 文件/目录 | 稳定职责 |
|---|---|
| `QATests/TestKit/Sources/Icon/main.swift` | AppIcon alpha/尺寸运行测试入口 |
| `QATests/TestKit/Sources/Insight/main.swift` | 模型、服务、帮助内容和回归逻辑测试入口 |
| `QATests/TestKit/Sources/Localization/main.swift` | 十语言、覆盖包、格式符与 catalog 测试入口 |
| `QATests/TestKit/Sources/Snapshots/MenuBarSnapshotHarness.swift` | 菜单栏视觉 fixture |
| `QATests/TestKit/Sources/Snapshots/OverviewMetricSnapshotHarness.swift` | 总览指标视觉 fixture |
| `QATests/TestKit/Scripts/run-test-app.sh` | 固定 QA Host 的唯一运行型测试入口 |
| `QATests/TestKit/Scripts/build-user-test.sh` | 固定 UserTest 的预检、构建、安装、签名与启动 |
| `QATests/TestKit/Scripts/load-qa-config.sh` | 安全读取本机 plist，不把它当 shell 执行 |
| `Scripts/verify-release-app.sh` | 本地发布前完整验证；不归档、不上传 |
| `Scripts/generate-system-field-catalog.py` | 用外部 workbook JSON 重建系统字段 catalog |
| `Scripts/check-doc-maps.py` | 校验入口大小、地图覆盖、feature ID、路径与符号锚点 |

完整 QA 安全边界只见 `QA-RUNBOOK.md`；本地化完整流程只见 `LOCALIZATION.md`。

## 常见改动路由

| 改动 | 先查 |
|---|---|
| 看到某个界面区域 | `UI-MAP.md`，再按 `feature:<id>` 下钻 `FEATURE-MAP.md` |
| 某个数字不对 | `FEATURE-MAP.md` 的 canonical owner，再查采集和全部消费者 |
| 新增菜单栏指标 | `feature:menu.metrics` |
| 新增跨刷新状态 | `BatteryService`；先确认不能由 `DashboardMetricSnapshot` 随取随算 |
| 修改用户可见文案 | 完整阅读 `LOCALIZATION.md`，只改 `Localization/Sources/` |
| 修改 QA、构建或运行 | 完整阅读唯一 `QA-RUNBOOK.md` |
| 新增动效 | `AppTheme+Cyber.swift` 和 `PowerFlowEdge.swift`；必须处理 Reduce Motion、窗口不可见与暂停刷新 |

## 维护约定

- 新增、删除、改名或搬运 Swift 文件后更新本文件，并运行 `python3 Scripts/check-doc-maps.py`。
- 单个 Swift 文件超过约 600 行时评估按顶层类型或内聚子视图拆分；不要把会快速漂移的精确行数和例外清单写进地图。
- 巨型 View 不能为了行数把 `private` 成员机械放开；优先提取真正内聚的独立子视图。
- `project.yml` 使用目录 glob；新增文件后仍需重新运行 `xcodegen generate`，但不要手改 `project.pbxproj`。
