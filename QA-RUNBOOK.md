# BatteryMonitor QA 操作手册

> **唯一现行 QA 文档。** 任何编译主 App、运行测试、启动验收、生成 QA 截图或执行发布验证之前，必须完整阅读本文件。其他审查报告只能作为历史证据，不能定义当前命令或安全边界。

## 三层目录与权威关系

`QATests/` 分成三个用途明确的区域：

- `QATests/TestKit/` 受 Git 跟踪，保存测试入口、测试源码、稳定 fixture、公开配置示例和 Runner 脚本，是可复现测试定义的唯一权威。
- `QATests/Run/` 被 Git 忽略，只保存固定路径测试 App、DerivedData、隔离 HOME、日志和本次运行产物。这一层可再生，但仍禁止递归删除。
- `QATests/Personal/` 被 Git 忽略且**不可默认删除**，保存维护者签名配置、真实设备证据、归档、截图和翻译审计历史。

Runner 必须直接编译当前 `BatteryMonitor/` 生产源码。TestKit 可以提供入口、harness、mock 和 fixture，但不得保存一份修改过的生产代码并把它当成正式 App 的验证结果。

## 本机配置

维护者把：

```text
QATests/TestKit/Config/QAConfig.example.plist
```

复制为：

```text
QATests/Personal/Config/QAConfig.local.plist
```

再填写预期项目根目录、Team ID 和 Apple Development 签名身份。该本机文件是具体路径与签名值的唯一权威：不得暂存、提交、写进公开 Markdown，脚本也不得硬编码它的值。

没有本机配置的公开仓库检出，只允许使用 `CODE_SIGNING_ALLOWED=NO` 做纯编译检查，并必须报告：**仅编译，未生成固定 UserTest、未签名、未运行验收。**

## 全局安全边界

- 新编译的测试 App、二进制、DerivedData、日志、截图和 QA 产物只能进入固定、可见的 `QATests/Run/`。
- 禁止把可执行产物放进 `.build/`、其他隐藏目录、`/tmp`、`/private/var/folders`、`mktemp` 随机目录或下载目录。
- 测试 App、Bundle ID 和可执行文件必须使用稳定、能体现 BatteryMonitor 与测试用途的名称；禁止 `T.app`、单字母程序和随机名称。
- macOS 测试 App 或二进制必须使用配置指定的有效 Apple Development 身份；禁止执行未签名或 ad-hoc 签名产物。
- 每次执行前必须先通过 `codesign --verify --deep --strict`，并独立记录 `spctl --assess --type execute --verbose=4`。
- 固定开发构建未公证时，`spctl rejected` 可以记录后继续；`codesign` 失败、`spctl` 返回非预期错误，或路径、Bundle ID、Team ID、签名身份不匹配时必须停止。
- 云壳或其他安全软件实际弹窗或阻断时，不得自动点击、模拟点击、关闭软件、移除安全属性或绕过防护。
- 自动化脚本不得读取或改写用户真实的 `Application Support/BatteryMonitor` 数据，只能使用 `QATests/Run/` 下的隔离 HOME。

## 固定 QA Host：自动化测试唯一入口

唯一运行型测试命令：

```bash
./QATests/TestKit/Scripts/run-test-app.sh all
```

可把 `all` 换成 `icon`、`insight` 或 `l10n`。固定 App 为：

```text
QATests/Run/AutomationHost/BatteryMonitor-QAHost.app
Bundle ID: com.stephen.BatteryMonitor.QAHost
```

每个阶段必须：

1. 正常关闭旧 QA Host；
2. 把该阶段新编译的测试可执行文件原位覆盖到同一固定 App；
3. 重新签名并核对固定路径、Bundle ID、Team ID、签名身份；
4. 依次执行 `codesign` 与 `spctl`；
5. 运行阶段测试；
6. 无论成功、失败、中断或脚本退出，都关闭 QA Host。

UserTest 不得充当自动化 Runner；自动化始终只走这个入口。

## 固定 UserTest：主 App 编译与交互验收

固定 App 为：

```text
QATests/Run/UserTest/BatteryMonitor-UserTest.app
Bundle ID: com.stephen.BatteryMonitor
```

配置了本机 QA 的维护者机器，只要 BatteryMonitor 主 App 编译成功，就必须通过唯一脚本把该次构建原位更新到固定 UserTest；不能只留下 DerivedData 内产物，也不得创建时间戳副本。

脚本自己编译并更新，但不启动：

```bash
./QATests/TestKit/Scripts/build-user-test.sh --configuration Debug --no-launch
```

安装刚构建的 App 并启动交互验收：

```bash
./QATests/TestKit/Scripts/build-user-test.sh \
  --source-app /absolute/path/to/BatteryMonitor.app \
  --configuration Debug \
  --launch
```

编译前只读预检：

```bash
./QATests/TestKit/Scripts/build-user-test.sh --preflight
```

预检只允许精确识别固定 UserTest 可执行路径，发送正常退出信号并最多等待 5 秒；仍未退出就停止，不得升级成强制结束，也不得误停其他同名 App、QA Host 或命令行进程。

只改文档、只做静态检查或脚本语法检查、以及 TestKit 自身夹具编译，不触发 UserTest 更新。完成 App 源码编辑并成功构建后，维护者机器应使用 `--launch` 启动固定 App；`spctl rejected` 本身不阻断，安全软件实际阻止启动时必须如实报告。

## 本地化与发布验证

文案修改的静态检查：

```bash
python3 Localization/build-language-packs.py check
python3 Scripts/check-doc-maps.py
```

文案修改的运行型检查：

```bash
./QATests/TestKit/Scripts/run-test-app.sh l10n
```

发布前本地完整验证：

```bash
./Scripts/verify-release-app.sh
```

发布验证必须复用固定 TestKit 入口，DerivedData 位于 `QATests/Run/ReleaseCheck/`。它不会执行 Archive、公证上传、App Store 上传或公开发布，也不代表已经具备上传就绪的全新 Archive。

仓库脚本不得依赖宿主 App、交互 shell 或 Homebrew 注入的 `rg`；安全和发布关卡使用系统自带 `grep -E`。报告验证结果前必须核对整条命令的当次退出码和当次日志，不能用旧日志、抽出的局部检查或历史 `exit 0` 代替。

## 交付报告

主 App 编译或启动验收后，必须分别报告：

- 固定 UserTest 的绝对路径；
- Debug 或 Release；
- 实际架构；
- `codesign` 结果；
- `spctl` 结果；
- 是否成功启动，以及运行中的可执行文件是否来自固定 UserTest；
- 是否替换正式主程序——正常答案应是“没有，只更新 QATests 内的固定测试 App”。

只有固定 App 已成功启动，或已明确记录安全软件的实际运行阻断时，才能写“已完成运行验收”或“运行验收受阻”。纯编译通过不能写成已经运行验证。

## 清理与不可再生材料

`QATests/Run/` 逻辑上可再生，但仓库仍禁止递归删除和批量扩大删除目标。清理时必须解析明确路径，逐项处理；优先使用可恢复方式。

`QATests/Personal/` 绝不能作为缓存整体清理。尤其保留：

- `Evidence/Telemetry/` 中支撑 `PowerFlow.swift`、电量计节拍与适配器口径的原始采样；
- `Release/Archives/*.xcarchive` 与对应 dSYM；
- `Release/Screenshots/`；
- `Evidence/TranslationAudit/` 的审计工具、keep registry、catalog 映射和旧源证据。

同版本号可能存在不同二进制。判断真正送审的 archive，要检查是否包含 `Submissions/<UUID>`。

## 维护规则

- QA 路径、Runner 或配置结构变化时，只更新本文件和对应脚本；不得再创建第二份现行 QA Markdown。
- `README.md`、`README.zh-CN.md` 和 `LOCALIZATION.md` 只保留最小命令并链接本文件，不复制完整流程。
- 修改本文件、地图或入口规则后运行 `python3 Scripts/check-doc-maps.py`。
