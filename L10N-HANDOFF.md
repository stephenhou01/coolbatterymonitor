# 多语言补全 — 交接状态

> 临时交接文件。**Phase 0–4 全部完成**，剩下的只有产品决策和一次真机目视。
> 那两项一了，本文件即可删除（删除是红线，需你点头）。
> 最后更新：2026-08-07

## 一句话状态

**Phase 0–4 完成并实测通过，后续页面化本地化重构也已落地。** 当前 1069 个 key，零漏翻；四层核验台 464 行 × 6 列全部走语言包（147 个 distinct key）；测试与发布校验已加固到「加字段忘配 key 会变红」的程度。

---

## 已完成

### Phase 0 — 排雷与建工具
- **排掉一个会让全部翻译白做的雷**：当时 2948 条「漏翻」里 95% 不由 JSON 决定，而由两个 Python 源字典控制。该双权威结构已在 2026-08-07 的页面化重构中移除，当前流程见 `LOCALIZATION.md`。
- 回填 3 个已漂移的 key + `p.help_raw` 6 个语言会被冲掉的现有译文。**sync 待改动数 30 → 0**（本次复核仍为 0）。

### Phase 1–2 — 主语言包 2948 条
9 个 subagent 并行翻译后合并。`ko` 466、`fr` 469+9keep、`es`/`pt` 各 465+8、`it` 468+3、`zh-Hant` 412、`de` 83+9、`ja` 83。
- `zh-Hant` 走「ICU 简转繁 + 43 条台湾用词/误转修正表 + subagent 审校」，不从英文重译。
- 统一繁中现有译文 13 条（`proc.*` 是真误译：「個程序」→「個行程」，已加进 L10nTests 防回归）。

### Phase 3 — 字段目录（四层核验台那 464 行表）
- `SystemFieldCatalog.json` 6 个中文属性去重 147 条：**5 条复用现有 key** + 新增 **142 个 `system.catalog.*`**。每条 field 补 6 个 `*Key`（共 2361 个），**中文原值一字未动**。
- `SystemDataSnapshot.swift` 加 6 个 `localizedXxx`（规则 `key.isEmpty ? raw : hardwareText(key, raw)`）；`SystemDataWorkbenchView.swift` 4 处渲染改 localized，搜索域改为 `path`/`value`/`source` + 当前语言的 5 列。

### Phase 4 — 伴生文档与测试加固（本轮）
| 文件 | 改了什么 |
|---|---|
| `UI-MAP.md` | 四层核验台行补全 6 类 catalog key 与数量、数据来源、`localizedXxx` 取值链、当前行号；「已知不一致与陷阱」新增 2 条（搜索改按界面语言匹配、中文原值不许删） |
| `LOCALIZATION.md` | 集中记录 key 归属判断、源字典 sync、百分号两套规则、catalog 6 列的改法与生成器守卫；`SystemDataSnapshot.swift` 行注明 `*Key` 与「原值不许删 / 必须用 var」；`QATests/` 不可删清单加 `L10nTranslation/` |
| `Tests/L10nTests.swift` | 新增 **2c** catalog key 数据驱动校验（以 catalog 自身声明的 `*Key` 为待验集合，**无白名单**，加字段自动纳入）、**2d** 繁中术语抽样、**3c** 全包裸 `%` 扫描 + 6 条扫描器自检 |
| `Tests/run-l10n-tests.sh` | 把 `SystemFieldCatalog.json` 一并拷进测试 app（2c 要读它） |
| `Localization/Languages/*.json` | 7 个 key × 10 包共 **60 处**字面 `%` 补成 `%%`（见下「本轮唯一的数据改动」） |
| `Scripts/verify-release.sh` | catalog 段加 4 条断言（`*Key` 全包解析、distinct == 147、unit 原值耦合守卫、group 原值耦合守卫）；`build_number` 断言由写死 `"4"` 改成「非空纯数字」 |
| `Scripts/generate-system-field-catalog.py` | 加载 `Scripts/system-field-catalog-keys.json`（147 条映射，新建、git 跟踪）输出 `*Key`；**未命中即拒绝写文件并 exit 1** |

### 后续重构 — 页面化唯一源（2026-08-07）

- 全部 1069 个 key 已迁移到 `Localization/Sources/`，按页面和页面区块分成 23 个源文件；跨页面内容进入 `shared/`，结构化字段进入 `catalogs/`。
- `Localization/Sources/**/*.json` 成为唯一编辑权威，`Localization/Languages/*.json` 改为生成产物。
- `Prototype/build-prototype.py` 已移除 321-key `EXTRA`；`Localization/sync-prototype-strings.py` 已移除 307-key `APP_EXTRA`，只保留兼容转发入口。
- `Localization/build-language-packs.py` 提供 `find` / `list` / `check` / `write`，并校验重复 key、十语言完整性、C 格式符和 `{name}` 占位符。
- 迁移时逐 key 对照当前十个语言包，1069 × 10 的译文值零变化。

#### 本轮唯一的数据改动：60 处字面百分号补 `%%`
`Localization.swift` 的约定是语言包里字面百分号写 `%%`，但 7 个 key 从来没遵守（`rt.y_percent` `hist.rate_chart` `hist.rate_unit` `proc.cpu_live` `tip.cycles` `tip.health` `tip.charge_rate`）。它们今天恰好无害，因为 `%` 后面的字符在 10 个包里都不构成说明符。**但英文「80% overnight」里空格是合法 flag、`o` 是八进制说明符，会被解析成真的 `% o`** —— 译者一改措辞，签名与英文不一致，`validatedStrings` 就静默丢弃该 key 回落英文，界面上没有任何报错。补齐后 3c 那组断言不需要任何白名单。

工具：`QATests/L10nTranslation/normalize-literal-percent.py`（幂等，`--check` 只报不写）。每处改写都断言「还原后的显示文本」与「格式符签名」逐字节不变，60 处全部通过。

## 验证结果（全部本轮实测）

| 项 | 结果 |
|---|---|
| `./Tests/run-l10n-tests.sh` | **两阶段全部通过**。新增断言实测：catalog 147 key × 10 包 unresolved 0；10 包裸 `%` 0；ko「온도」/ de「Temperatur」/ zh-Hant「分鐘」/ 百分号单位还原成单个 `%`；繁中「個行程」 |
| `python3 QATests/L10nTranslation/audit.py` | 1064 key，缺失/多余/空值/占位符/字符集 **全 0**；`untranslated` ⊆ `keep-registry.json`（逐语言差集为空） |
| sync dry-run（627 key × 10 包） | **待改动 0**，JSON 与源字典无漂移 |
| **`./Scripts/verify-release.sh` 整脚本** | **`exit 0`，全部通过** —— 含测试脚本安全边界、发布配置、AppIcon 全尺寸与透明度、plist、语言包 + catalog 12 道断言、Xcode 工程、Release 编译、以及末尾两套测试。454 条 `✓`，0 条 `✗`。日志：`QATests/BuildValidation/verify-release-run.log` |
| `./Tests/run-insight-tests.sh` | **全部通过**（此前 6 项失败，见下「已知阻塞」） |
| `Scripts/generate-system-field-catalog.py` 往返测试 | 用现网 catalog 反推 workbook 输入重跑，产物与 `BatteryMonitor/Resources/SystemFieldCatalog.json` **字节完全一致**（含全部 2361 个 `*Key`）；注入 2 个未映射中文值后**拒绝写文件、exit 1** |
| `xcodebuild -configuration Release` | **BUILD SUCCEEDED**，universal（x86_64 + arm64），包内 10 个语言包 + catalog，147 key 在包内 10 包中 unresolved 0 |
| `swiftc -typecheck`（Localization + L10nTests） | 通过 |

---

## 已知阻塞 — 已全部清掉

历史上这三条都被记成「既有缺陷、建议单独立项」，实际是同一个根因串起来的：**`verify-release.sh` 从第 9 行就退出，所以后面所有关卡一次都没跑到过**，两处过期断言因此长期没人发现。

1. ~~ripgrep 没装导致 `verify-release.sh` 预检失败~~ → 6 处 `rg` 全换成 `grep -E`（POSIX ERE，系统自带），不装全局依赖。
2. ~~`build_number` 写死 `"4"`~~ → 改成「非空纯数字」，一致性交给「app 的 CFBundleVersion 必须等于 project.yml」那条。
3. ~~README 断言找 `universal \`arm64\` + \`x86_64\` app`~~ → 那句话在 `4e25f65`（双语 README）里被改写成 `Apple silicon and Intel Macs`，断言没跟着改。**断言跟着 README 走，没有反过来改文档。**
4. ~~`run-insight-tests.sh` 6 项必然失败~~ → 其中 **4 项**确实是不拷语言包（`L()` 只返回 key，而同批断言里的 `dashboardText(_:fallback:)` 仍返回中文兜底，两条路径对不上）；脚本补拷语言包 + catalog，测试开头 `select("zh-Hans")` 并加 `precondition` 兜住漏拷。**另 2 项与本地化无关，是测试期望过期，详见下。**

**仍未做（不影响上面）**：三个测试脚本仍用 `.build/` + ad-hoc 签名并直接执行新产物，项目测试安全规则禁止无人值守执行。本轮都是在你在场并明确同意的前提下跑的。合规迁移待单独立项。

### 那 2 项与本地化无关的失败：实现是对的，测试期望过期

交接文件原先把 6 项一并归给「不拷语言包」，这个归因不准确。

1. **电量计倒计时报 20 秒而不是 16。** 测试注释按「60 − 44 = 16」推算，那是**电量计发布**的时刻；`secondsUntilVisibleRefresh` 报的是**你能看到**的时刻 —— 新值在第 16 秒发布，而主轮询 10 秒一次，要到第 20 秒那一拍才进界面。报 16 等于承诺一次用户看不到的刷新。函数名里的 `visible` 就是这个意思。**已把期望改成 20 并写明理由，防止后人改回去。**
2. **`timeToFullMinutes` 返回 nil 而不是 72。** 样本 `heroCharging` 只设了 `isOnAC` 和 `instantAmperage`，还在 1261 行被置成 `isFullyCharged = true`，**`data.isCharging` 始终是 false**。上面那批断言用 `heroState()`／`BatteryPowerState`（由实测电流推断充电），而 `timeToFullMinutes` 和 `batteryChargingPowerWatts` 读的是系统原始标志位 `data.isCharging` —— 拿前者的样本测后者，测的其实是「没充电时返回 nil」，跟断言想说的正好相反。**已在样本上显式 `isCharging = true`。**

**顺带暴露一个口径分歧，值得单独评估：「是否在充电」有两套判断** —— `BatteryPowerState` 由实测电流推断，`DashboardMetricSnapshot` 的两个派生值读原始标志位。插电但电流为 0（涓流结束、系统优化充电暂停）时两者会给出不同答案。本次没动任何实现。

---

## 剩余待做

### 1. 真机目视验证（需你操作）
可双击的测试 App：**`QATests/BatteryMonitor-UserTest_20260806_20_33.app`**
- 切到 `ko` / `de`，看技术参数页「所有系统数据 · 四层核验台」的 **含义 / 单位 / 分组 / 可靠性** 四列是否变成目标语言。
- 用当前语言的词搜一下（如 de 输入 `Temperatur`），确认能命中；再用中文词搜，**应当搜不到**（这是预期变化）。
- 两个 snapshot harness 硬编码 `select("zh-Hans")`，看不到多语言效果，所以只能人工看。

### 2. 待你决策（都属产品口径，本次一律没动）
1. **英文 `Value` 有歧义** —— `hw.column.value` / `hw.column.product_value` / `p.system_data_value_level` 三处。查证是「有用程度」（代码里拼在星级前面），不是「数值」。三个语言的 subagent 独立提出。各语言已按「有用度」译，建议英文源改成 `Usefulness` 或 `Value rating`。
2. **既有 pt 译文 7 处欧葡/巴葡混用**（`odómetro`/`fabrico`/`percentagem`/`Repor predefinições`/`está a carregar` 等）。本次新译按巴葡，旧的没改，会同屏出现两种风格。
3. **繁中「當前」46 处、「閾值」与「門檻」并存**。是否整包台湾化属产品决策，审校 subagent 没单方面改。
4. **字段目录数据侧该收敛**：`unit` 列有 7 个值其实不是单位（级别/代码/状态码/枚举/编码值/原始值/原始整数）；`group` 分类源数据就有重复（`容量` vs `容量/充电`、`电气` vs `电气/功耗`）。翻译只能照译，**收敛是数据侧的事**，建议单独立项。

---

## 下次接手必读的坑

1. **只修改 `Localization/Sources/`，不直接修改生成语言包。** 先用 `python3 Localization/build-language-packs.py find <KEY>` 定位页面源文件，修改后运行 `write` 与 `check`。
2. **百分号现在只有一套规则**：源文件和生成语言包里的字面百分号都写 `%%`；真实 `%@` / `%d` / `%.1f` 保持格式契约。生成器先拦截，`validatedStrings` 与 `L10nTests` 再做运行时和测试侧防护。
3. **Swift Codable 陷阱**：`let x: T? = nil` 带初始值的不可变属性会被合成的 `init(from:)` **跳过**，JSON 里的值永远读不进来。必须用 `var`。实证：`QATests/L10nTranslation/codable-probe.swift`。
4. **ICU 简转繁不是全对**：`发布→發佈` 错（台湾用「發布」）、`启→啓` 是异体字（标准字形「啟」）。已进修正表。`制→製`(製造)、`顯著` 是对的。
5. **`ast` 的 `col_offset` 是 UTF-8 字节偏移**，不是字符偏移。改含中文的 Python 源码要全程按字节切片。
6. **`API Error: 400 模型提供方错误`** 在单个 subagent 上下文吃太大时触发（471 条那个挂了，466 条的没挂）。拆成每批 150–160 条。已挂的会话敲 `/compact` 也会失败，直接换新会话。
7. **catalog 的中文原值不是死数据。** 它同时是 zh-Hans 文案与 `isMeaningfulByDefault`、`SystemFieldValueConversion` 的令牌比对输入。只留 `*Key` 删原值，界面照常显示，但「默认有用」筛选和单位换算会静默失效。`verify-release.sh` 有 2 条耦合守卫专防这件事。
8. **`audit.py` 的 `pctdiff` 从 5 涨到 8 是预期的，不是回归。** ja/ko 的 `tip.charge_rate` 等本来就比英文多一个字面百分号，属措辞差异；补 `%%` 之前它是裸 `%`，不被 `%%` 计数看见，补完才显形。audit 本身把 pctdiff 单列、不计入缺陷。

## 工具清单（全在 `QATests/L10nTranslation/`）

| 文件 | 作用 |
|---|---|
| `audit.py` | **独立裁判**，全程未被改动过。key 完整性/占位符签名/ICU 简繁/未翻译分层 |
| `source_dict.py` | 历史双 Python 字典的精准读写工具；页面化重构后仅作审计凭据，不再用于日常文案修改 |
| `merge-translations.py` | 主语言包译文合并，9 道校验全在合并侧 |
| `merge-catalog.py` | 字段目录 142 条合并，含 emoji/字节数/纯符号单位守卫 |
| `normalize-literal-percent.py` | 字面 `%` → `%%`，幂等，`--check` 只报不写；每处改写断言显示文本与格式符签名不变 |
| `hans2hant-batch.py` + `termlist-zh-Hant.json` | 简转繁 + 43 条台湾用词与 ICU 误转修正，长词优先 |
| `keep-registry.json` | **有意保留英文的条目及逐条理由**。验收口径：audit 的 `untranslated` 必须 ⊆ 它 |
| `catalog-final-map.json` | 中文原值 → key 映射（147 条）。**已固化为 git 跟踪的 `Scripts/system-field-catalog-keys.json`**，生成器读后者 |
| `codable-probe.swift` | Swift Codable 默认值行为实证 |

## git 状态与提交建议

建议分开提交（第 5 组不是本次的）：
1. `Localization/Sources/` + `Localization/build-language-packs.py` + `Prototype/build-prototype.py` + `Localization/sync-prototype-strings.py` + `LOCALIZATION.md` — 页面化唯一源与 HTML/App 统一生成链路
2. `Localization/Languages/*.json` 10 个包 — 生成产物 + 繁中 13 条用词统一 + 60 处 `%%` 规范化
3. `BatteryMonitor/Resources/SystemFieldCatalog.json` + `Models/SystemDataSnapshot.swift` + `Views/SystemDataWorkbenchView.swift` + `Scripts/generate-system-field-catalog.py` + `Scripts/system-field-catalog-keys.json` — 字段目录本地化（**必须一起进退**：生成器、映射表和产物是一套）
4. `Tests/L10nTests.swift` + `Tests/run-l10n-tests.sh` + 本地协作规则 + `UI-MAP.md` — 本地化测试加固与文档
5. `Scripts/verify-release.sh` + `Tests/run-insight-tests.sh` + `Tests/InsightTests.swift` — **修复整条发布验证链**（`rg`→`grep -E`、两处过期断言、insight 测试补语言包 + 两处过期期望）。与本地化正交，单独一个提交更容易回溯
6. `Tools/README.md`、`Tools/analyze-session-tokens.py` — **你自己原有的未提交改动，与本次无关**

`QATests/` 被 `.gitignore` 覆盖，工具与产物不进 git。全程未做任何 git 写操作。
