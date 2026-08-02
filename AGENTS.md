# BatteryMonitor Agent Instructions

## 适用范围与项目确认

- 本文件适用于 `/Users/stephen/Desktop/BatteryMonitor` 及其全部子目录。
- 开始工作前运行 `pwd`，确认当前项目是 `/Users/stephen/Desktop/BatteryMonitor`。
- `/Users/stephen/Documents/BatteryMonitor` 是另一个同名项目，不属于本项目，不得混用其代码、结论或构建产物。
- 先阅读 `README.md` 和 `project.yml`，再判断架构、构建方式或发布状态。
- 默认使用中文沟通；代码、类型、变量、文件名和命令使用英文。

## 保护用户现有工作

- 修改前检查 `git status` 和相关文件的 `git diff`。
- 工作区中已有的修改属于用户；不得覆盖、回退、整理或顺手改写与当前任务无关的内容。
- 只修改完成当前任务所必需的文件。遇到重叠修改时先保留用户意图，无法安全合并再向用户说明。
- 禁止使用 `git reset --hard`、`git clean`、强制 checkout、强制推送或其他可能丢失现有修改的操作。

## 工程权威与目录职责

- 这是原生 macOS SwiftUI 应用，最低系统版本为 macOS 14。
- `project.yml` 是 Xcode 工程配置的唯一权威来源。
- `BatteryMonitor.xcodeproj` 由 XcodeGen 生成，不直接手工修改 `project.pbxproj`。
- 修改 `project.yml` 或源文件清单后运行 `xcodegen generate`。
- App 入口是 `BatteryMonitor/BatteryMonitorApp.swift`。
- `BatteryMonitor/Services/` 负责数据采集、分析、设置、本地化和持久化。
- `BatteryMonitor/Models/` 负责领域模型和数据结构。
- `BatteryMonitor/Views/` 负责 SwiftUI 界面。
- `Localization/Languages/` 保存运行时语言包。
- `index.html` 是 App Store 使用的隐私政策和支持页面，不得删除或重命名。

## 产品、隐私与数据边界

- 保持 App Sandbox、Hardened Runtime，以及 Apple silicon 和 Intel 兼容性。
- 未经用户明确批准，不得增加网络访问、遥测、分析 SDK、用户追踪或数据上传。
- 电池数据主要来自 IOKit、IOPowerSources 和 AppleSmartBattery。
- 明确区分系统直接提供的数据、实测数据、派生数据和预测结果；不得把推导值描述成系统原始值或硬件实测值。
- 进程模块只提供 CPU、内存等负载上下文，不得伪造或推算单个进程的耗电瓦数。
- 正式 App 的数据采集不得依赖 shell 命令或新增常驻辅助进程，除非用户明确批准架构变更。

## 本地化规则

- 用户界面翻译存放在 `Localization/Languages/*.json`，不要把翻译正文写回 Swift 源码。
- 所有语言包必须保持一致的 key 集合，并与英文语言包保持兼容的格式化占位符类型和数量。
- 外部覆盖语言包应按 key 合并，内置语言包作为逐项回退，不能用不完整的外部包替换整个内置包。
- 新增或修改用户可见文本时，同步更新所有语言包和相关测试。
- Finder、Dock 和菜单栏显示名称由对应的 `.lproj/InfoPlist.strings` 管理。

## 删除与破坏性操作

- 禁止批量或递归删除文件和目录。
- 禁止使用 `rm -rf`、`del /s`、`rd /s`、`rmdir /s`、`Remove-Item -Recurse`。
- 需要删除时，只能针对一个经过核实的明确文件路径，并且必须先获得用户确认。
- 如果任务需要删除多个文件或整个目录，停止操作并请用户手动处理。
- 不得删除用户真实的 `Application Support/BatteryMonitor` 数据。

## 本机测试与云壳安全边界

- 所有新编译的测试 App、二进制、日志、截图和相关 QA 产物必须放在项目根目录下固定、可见的 `QATests/` 目录。
- 不得把可执行测试产物放在 `.build/`、其他点号开头的隐藏目录、`/tmp`、`/private/var/folders`、`mktemp` 随机目录、下载目录或其他来源不明确的位置。
- 测试目录、App、Bundle ID 和可执行文件必须使用稳定、能体现 `BatteryMonitor` 与测试用途的正式名称；禁止使用 `T.app`、单字母可执行文件或随机字符串名称。
- macOS 测试 App 或二进制必须使用项目对应的有效签名；禁止执行未签名或 ad-hoc 签名产物。
- 执行前必须依次运行 `codesign --verify --deep --strict` 和 `spctl --assess --type execute --verbose=4`。
- 任一检查失败或 `spctl` 返回 `rejected` 时停止执行并报告，不得把 `codesign` 通过等同于系统或云壳已经信任。
- 无人值守执行只允许使用已完成 Apple 公证，或已由公司安全管理员按固定路径、Bundle ID、Team ID 和签名身份加入可信规则的测试 Runner。
- 不要在每轮测试中重新生成或替换已获信任的 Runner；二进制改变后必须视为新的待验证产物。
- 云壳或其他安全软件弹窗时，不得自动点击“仍要运行”、模拟点击、关闭安全软件、移除安全属性或绕过防护。
- 若缺少固定可见目录、正式名称、有效签名、公证或管理员可信规则，停止运行测试；允许继续进行不会启动新产物的静态检查和编译检查。
- `QATests/` 中的生成产物和日志默认不提交 Git；除非用户明确要求，不得暂存或提交这些文件。

## 当前测试脚本注意事项

- 运行任何 `Tests/run-*.sh` 前先阅读脚本，确认它没有创建隐藏路径、随机路径、非正式名称或 ad-hoc 签名的可执行文件。
- 当前测试脚本和 `Scripts/verify-release.sh` 可能仍使用 `.build/`、短名称或 ad-hoc 签名，并会直接执行新编译产物；在完成安全迁移并通过云壳可信规则前，不得用于无人值守执行。
- 可以进行只编译、不启动产物的验证；DerivedData 和生成物应定向到 `QATests/BuildValidation/` 等可见固定目录。
- 测试受云壳阻断时，准确报告“编译通过、运行时测试待人工或管理员授权”，不得声称全部测试通过。

## 发布边界

- 未经用户明确授权，不修改版本号、构建号、签名身份、Entitlements、发布配置或 App Store Connect 状态。
- 未经用户明确授权，不执行 Archive、Notary Service 上传、App Store 上传、部署或公开发布。
- 普通 Build、测试或 `Scripts/verify-release.sh` 通过不等于可发布；必须明确完成全新 Archive 及对应发布检查后，才能作出发布就绪结论。

## 交付要求

- 结论先行，说明修改内容、原因和影响范围。
- 列出实际运行的验证命令与结果，明确区分已验证、未验证和推断。
- 每次编译成功后，必须把供用户手动测试的 App 放到 `QATests/` 下固定、可见且名称明确的路径；不得只留下 DerivedData 内的隐藏构建产物。
- 每次交付编译结果时，必须同时提供：可点击的绝对 `.app` 路径、一条可直接复制执行的 `open "/absolute/path/BatteryMonitor-UserTest.app"` 命令、构建类型、架构、签名状态，以及“是否已经替换正式主程序”的明确结论。
- 如果磁盘上的最新构建晚于当前运行进程，必须提醒用户退出旧进程并重新打开；未提供直接可执行路径和重启说明，不得把任务表述为已可测试。
- 用户只要求审查或优化建议时保持只读；按 P1、P2、P3 排序，并提供文件、行号和具体修复方向。
- 大范围重构、跨模块改动、数据结构迁移或发布相关变更，先给出方案和验证计划，等待用户确认后再实施。
