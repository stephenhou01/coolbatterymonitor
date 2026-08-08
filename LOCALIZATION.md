# BatteryMonitor 本地化操作手册

**用途**：修改用户可见文案、语言包、`InfoPlist.strings` 或 system field catalog 前，先完整阅读本文件。

## 唯一权威与数据流

所有内置界面文案的唯一编辑权威是：

```text
Localization/Sources/**/*.json
```

源文件按“页面 → 页面区块”组织；跨页面复用文案放 `shared/`，结构化字段目录放 `catalogs/`。生成器把源文件转成 App 实际装载的十个语言包：

```text
Localization/Sources/**/*.json
              │
              ▼
Localization/build-language-packs.py
              │
              ▼
Localization/Languages/*.json
              │
       ┌──────┴──────┐
       ▼             ▼
   SwiftUI App     HTML 原型
```

`Localization/Languages/*.json` 是生成产物，不直接编辑。HTML 原型与 SwiftUI App 读取同一批生成语言包，不再维护 `EXTRA` / `APP_EXTRA`。

## 页面分类

```text
Sources/
├── app-shell/       侧边栏、页面入口和窗口级导航
├── overview/        总览：电池状态、能量流向、续航对照
├── technical/       技术参数页的九个区块
├── trends/          实时监控、进程、充放电历史
├── diagnostics/     洞察卡片和系统异常
├── settings/        外观、语言、刷新、隐私
├── menubar/         状态项和弹出面板
├── shared/          跨页面公共动作和帮助框架
└── catalogs/        系统字段等结构化数据目录
```

归属规则：

1. 以“哪个产品概念拥有这句话”为准，不以 HTML / App 的历史来源分类。
2. 帮助面板或菜单栏只是复用某个指标时，文案仍留在指标所属页面；只有公共帮助框架进入 `shared/help.json`。
3. 被多个页面真正共同拥有的动作、状态和辅助功能文案进入 `shared/core.json`。
4. `system.catalog.*` 固定归 `catalogs/system-fields.json`。
5. 页面移动时不批量重命名 key，只移动源条目；key 是稳定接口。

## 查询 key

手上已有 key 时，不要满项目猜测归属，使用：

```bash
python3 Localization/build-language-packs.py find p.trend_fitted
```

它会返回：

- 所属页面/区块；
- 权威源文件；
- 简体中文和英文译文；
- Swift、测试、HTML、`UI-MAP.md` 中发现的字面引用。

按子串查询会返回多个匹配项。查看全部分类及数量：

```bash
python3 Localization/build-language-packs.py list
```

## 从界面文案反查代码

手上只有界面里看到的中文、英文或其他内置语言文案时，先运行：

```bash
python3 Localization/build-language-packs.py lookup-text "Stable estimate"
```

它会对十种语言做 Unicode、大小写、空白和字面百分号归一化查询，并按“完全匹配 → 前缀匹配 → 子串匹配”返回：

- 稳定 key；
- 命中的语言与译文；
- 权威页面源文件；
- Swift、TestKit、HTML 和 `UI-MAP.md` 中发现的字面引用。

结果太多时限定语言或数量：

```bash
python3 Localization/build-language-packs.py lookup-text "power" --language en --limit 10
```

拿到 key 和使用处后，只打开命中的 `UI-MAP.md` 区域、`FEATURE-MAP.md` 功能链与具体代码文件；不要为找一句话通读十个生成语言包。

## 修改已有 key

1. 用 `find` 定位唯一源文件。
2. 只修改该源文件中对应 key 的十种译文。
3. 生成运行时语言包：

```bash
python3 Localization/build-language-packs.py write
```

4. 检查源与产物无漂移：

```bash
python3 Localization/build-language-packs.py check
```

旧命令 `python3 Localization/sync-prototype-strings.py` 仅作为兼容入口保留，会转发到新的 `write` 命令；新流程不要再依赖旧文件名。

## 新增或移动 key

- 新 key 使用点分命名，放进对应页面/区块源文件。
- 十种语言必须全部提供非空值，英文定义格式符和命名占位符契约。
- Swift 中通过 `L()` / `LNum()` 读取，不把翻译正文写入 Swift。不得给 `dashboardText`、`hardwareText` 或其他包装器增加 `fallback:` 参数或位置式正文；缺 key 时补 `Localization/Sources/`，不能在 Swift 调用点兜底。
- HTML 原型需要新 key 时也加入对应产品页面源文件，不新建“HTML 专属字典”。
- key 改归属时，从旧源文件完整移动到新源文件；生成器会拒绝重复 key 和语言缺失。

## 批量管理

页面文件就是天然批次。例如：

```text
Localization/Sources/trends/                 整个趋势页
Localization/Sources/technical/power-center.json
Localization/Sources/catalogs/system-fields.json
```

批量翻译或审校时只处理目标目录/文件，不需要加载其他页面。生成器最终统一检查：

- 语言集合是否恰好为十种；
- key 是否重复；
- 所有译文是否非空；
- C 格式符的位置、长度修饰符、类型和顺序；
- `{power}` 等命名占位符集合；
- 十个运行时语言包是否与源文件一致。

## 百分号与格式符

源文件和生成语言包使用同一套最终表示：

- 字面百分号写 `%%`；
- 真实格式符写 `%@`、`%d`、`%.1f` 等；
- `{power}` 等命名占位符在所有语言中必须保持一致。

不再存在“Python 字典写单 `%`、JSON 写双 `%%`”的两套规则。格式符写错时，生成器会在写入语言包前失败；运行时 `Localization.swift` 仍保留第二层防护。

## System field catalog

`BatteryMonitor/Resources/SystemFieldCatalog.json` 的 `group` / `unit` / `meaning` / `reliability` / `recommendation` / `note` 通过对应 `*Key` 从语言包取译文。

- `system.catalog.*` 的十种译文统一维护在 `Localization/Sources/catalogs/system-fields.json`。
- 新增字段、修改 catalog 中文原值或新增映射时，同时更新 `Scripts/system-field-catalog-keys.json`，再运行：

  ```bash
  python3 Scripts/generate-system-field-catalog.py \
    /absolute/path/to/workbook-data.json \
    BatteryMonitor/Resources/SystemFieldCatalog.json
  ```

  `workbook-data.json` 是外部 artifact-tool 导出，不在公开仓库中。没有获得该明确输入时，不得猜测来源、不得直接改生成后的 catalog 来伪装成可重建流程；应停止 catalog 结构修改并向用户索取导出文件。普通文案修改不需要这个外部输入。
- 生成器遇到未映射的中文原值必须拒绝写文件并非零退出。
- catalog 的中文原值必须保留；它们同时是 zh-Hans 文案，也是 `isMeaningfulByDefault` 和 `SystemFieldValueConversion` 的令牌比对输入。

## 其他文案体系

- Finder、Dock 和菜单栏显示名称由 `BatteryMonitor/*.lproj/InfoPlist.strings` 管理，不走页面源文件流程。
- 外部覆盖语言包仍按 key 合并，内置语言包逐项回退；不得用不完整的外部包替换整个内置包。

## 验证

文案修改的最小验证：

```bash
python3 Localization/build-language-packs.py check
./QATests/TestKit/Scripts/run-test-app.sh l10n
```

第二条命令属于维护者本机运行型测试，需要被 Git 忽略的
`QATests/Personal/Config/QAConfig.local.plist`；没有本机 QA 配置的公开仓库检出只运行第一条静态检查。
固定路径、签名和运行边界以 `QA-RUNBOOK.md` 为准。

发布前完整验证：

```bash
./Scripts/verify-release-app.sh
```

必须根据命令实际退出码报告结果；单独抽取某个检查段通过，不等于整个脚本通过。
