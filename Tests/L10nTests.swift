import Foundation

func expect(_ cond: Bool, _ msg: String) {
    print((cond ? "  ✓ " : "  ✗ ") + msg)
    if !cond { failures += 1 }
}
var failures = 0
let l = L10n.shared

/// 四层核验台的 6 列文案落点。只声明 key，不声明中文原值——这里要验的就是
/// 「界面读的是 key 指向的译文」。用不带初始值的 `let x: String?`：带初始值的
/// 不可变属性会被合成的 init(from:) 跳过，永远读不到 JSON 里的值。
struct CatalogFieldKeys: Decodable {
    let path: String
    let groupKey: String?
    let unitKey: String?
    let meaningKey: String?
    let reliabilityKey: String?
    let recommendationKey: String?
    let noteKey: String?

    var declaredKeys: [(column: String, key: String)] {
        [("group", groupKey), ("unit", unitKey), ("meaning", meaningKey),
         ("reliability", reliabilityKey), ("recommendation", recommendationKey),
         ("note", noteKey)]
            .compactMap { column, key in
                guard let key, !key.isEmpty else { return nil }
                return (column, key)
            }
    }
}

struct CatalogPayload: Decodable {
    let fieldCount: Int
    let fields: [CatalogFieldKeys]
}

/// 语言包里的字面百分号必须写成 `%%`（约定见 Localization.swift 的 string()）。
/// 返回既不是 `%%`、后面也不跟合法说明符的那些裸 `%` 的位置。
///
/// 裸 `%` 不一定当场出错，但它是定时炸弹：译者把「80%」写成「80% du temps」，
/// 空格是合法 flag、`d` 是合法说明符，`% d` 于是被解析成真的 `%d`，该 key 的
/// 格式符签名与英文不再一致，被 validatedStrings **静默丢弃并回落英文** ——
/// 界面上没有任何报错，只是那一句变成了英文。现有防线（占位符签名逐包比对）
/// 只能发现签名已经不一致的，发现不了「今天恰好一致、明天一改就炸」的裸 `%`。
func bareLiteralPercentOffsets(_ value: String) -> [Int] {
    let chars = Array(value)
    let flags: Set<Character> = ["-", "+", " ", "#", "0"]
    let conversions: Set<Character> = ["d", "i", "o", "u", "x", "X", "e", "E", "f",
                                       "g", "G", "a", "A", "c", "s", "p", "n", "@", "%"]
    let lengthModifiers = ["hh", "ll", "h", "l", "L", "z", "j", "t"]
    var bare: [Int] = []
    var i = 0
    while i < chars.count {
        guard chars[i] == "%" else { i += 1; continue }
        var j = i + 1
        // 位置参数 %1$@
        var digits = j
        while digits < chars.count, chars[digits].isNumber { digits += 1 }
        if digits > j, digits < chars.count, chars[digits] == "$" { j = digits + 1 }
        while j < chars.count, flags.contains(chars[j]) { j += 1 }
        while j < chars.count, chars[j].isNumber || chars[j] == "." { j += 1 }
        for modifier in lengthModifiers {
            let expected = Array(modifier)
            if j + expected.count <= chars.count, Array(chars[j ..< (j + expected.count)]) == expected {
                j += expected.count
                break
            }
        }
        if j < chars.count, conversions.contains(chars[j]) {
            i = j + 1
        } else {
            bare.append(i)
            i += 1
        }
    }
    return bare
}

let phase2 = ProcessInfo.processInfo.environment["PHASE"] == "2"
if !phase2 {
print("── 1) bundle 内置包全部装载")
expect(l.languages.count == 10, "10 个语言包 [实际 \(l.languages.count)]")
expect(l.languages.map(\.code) == ["en","zh-Hans","zh-Hant","ja","ko","de","es","fr","it","pt"],
       "按 _meta.order 排序: \(l.languages.map(\.code))")
expect(l.languages.map(\.name).joined(separator: "/") ==
       "English/简体中文/繁體中文/日本語/한국어/Deutsch/Español/Français/Italiano/Português",
       "endonym 正确（非英文）")

print("── 2) 查询与 fallback")
l.select("de")
expect(l.string("app.title") == "Batterie-Monitor", "德语查询: \(l.string("app.title"))")
expect(l.string("nonexistent.key") == "nonexistent.key", "未知 key 回落 key 本身")
l.select("zh-Hans")
expect(l.string("app.title") == "电池监控中心", "中文查询: \(l.string("app.title"))")
expect(l.string("p.menu_time") == "还能用多久"
       && l.string("p.menu_open") == "打开完整看板"
       && l.string("p.menu_close") == "收起菜单栏面板"
       && l.string("p.menu_quit") == "完全退出 BatteryMonitor",
       "菜单栏核心文案已进入原生语言包")
l.select("fr")
expect(l.string("p.menu_time") == "Autonomie restante",
       "法语已有原生译文，不再回落英文: \(l.string("p.menu_time"))")
// 英文 fallback 机制本身由上面第 2 组的 nonexistent.key 一条覆盖；
// 原先这里用 fr 的 p.menu_time 反证 fallback，该 key 现已译出，前提不复存在。

print("── 2b) 外观、主壳与菜单栏配置文案覆盖全部语言包")
let shellAndMenuKeys = [
    "appearance.system", "appearance.light", "appearance.dark",
    "shell.overview", "shell.technical", "shell.trends", "shell.diagnostics", "shell.settings",
    "shell.sidebar_subtitle", "shell.local_only", "shell.power_connected", "shell.on_battery",
    "shell.power_hint", "shell.adapter", "shell.adapter_connected", "shell.not_connected",
    "shell.adapter_output_power", "shell.whole_mac_input",
    "shell.charge_power", "shell.charging", "shell.not_charging", "shell.temp_range",
    "shell.cycle_reference", "shell.health_good", "shell.health_fair", "shell.health_attention",
    "shell.status_attention", "shell.status_good", "shell.status_subtitle",
    "shell.technical_subtitle", "shell.trends_subtitle", "shell.diagnostics_subtitle",
    "shell.diagnosing", "shell.system_anomalies", "shell.settings_subtitle", "shell.appearance",
    "shell.live_refresh", "shell.privacy_note", "shell.dynamic_trends", "shell.last_minutes",
    "shell.instant_power", "shell.current", "shell.top_processes", "shell.cpu_context",
    "proc.cpu_scale_note", "proc.cpu_per_core_note", "proc.memory_rss_note",
    "shell.runtime_comparison", "shell.instant_runtime", "shell.instant_runtime_note",
    "shell.instant_runtime_waiting", "shell.apple_runtime", "shell.apple_runtime_unavailable",
    "shell.apple_runtime_waiting", "shell.apple_runtime_collecting",
    "shell.apple_runtime_recent", "shell.apple_runtime_recent_last",
    "shell.system_runtime_basis", "shell.stable_runtime_basis",
    "shell.stable_runtime_basis_seconds",
    "shell.stable_runtime_collecting", "shell.current_runtime_basis",
    "shell.derived_runtime_unavailable", "shell.state_full",
    "shell.state_plugged_idle", "shell.state_plugged_discharging", "p.field_cadence_on_plug",
    "shell.battery_current", "shell.time_to_full",
    "shell.flow_adapter", "shell.flow_battery", "shell.flow_mac", "shell.flow_idle",
    "shell.flow_derived", "shell.flow_forecast_measured", "shell.flow_forecast_derived",
    "shell.flow_a11y_battery_to_mac",
    "shell.flow_a11y_adapter_to_battery", "shell.flow_a11y_adapter_to_mac",
    // 概览卡的三个口径标题必须和问号面板同名，所以也纳入必查
    "p.runtime_system_label", "p.runtime_stable_label", "p.runtime_current_label",
    "menu.config.title", "menu.config.second_metric", "menu.config.status_hint", "menu.config.metric_choice", "menu.config.customize", "menu.config.empty",
    "menu.config.drag_to_reorder", "menu.config.add_more", "menu.config.manage_in_dashboard",
    "menu.config.show", "menu.config.hide", "menu.config.move_up", "menu.config.move_down",
    "menu.config.restore_defaults", "menu.metric.runtime", "menu.metric.power",
    "menu.metric.temperature", "menu.metric.health", "menu.metric.cycles", "menu.metric.current",
    "menu.metric.charge_power", "menu.metric.charge_speed",
    "menu.process.none", "menu.process.latest_real_sample", "p.menu_settings",
    "p.menu_close", "p.menu_language", "p.menu_quit",
    "p.help_summary_adapter_power", "p.help_source_adapter_power",
    "p.adapter_status_title", "p.adapter_status_disconnected", "p.adapter_status_disconnected_note",
    "p.adapter_status_negotiated", "p.adapter_status_waiting", "p.adapter_status_ready_badge",
    "p.adapter_status_waiting_badge", "p.adapter_equation_waiting", "p.adapter_contract_match",
    "p.adapter_contract_diff", "p.adapter_contract_partial", "p.adapter_voltage",
    "p.adapter_current", "p.adapter_rated_power", "p.adapter_input_trend",
    "p.adapter_input_trend_note", "p.adapter_trend_waiting",
    "p.trend_history", "p.trend_last_10min", "p.trend_last_1h", "p.trend_last_24h",
    "p.trend_range", "p.trend_waiting", "p.trend_note_power",
    "p.trend_note_charge", "p.trend_note_adapter_output", "p.trend_note_temperature",
    "p.help_summary_adapter_output_power", "p.help_source_adapter_output_power",
    "p.help_summary_charging_power", "p.help_source_charging_power",
    "p.help_summary_cycle_count", "p.help_source_cycle_count",
    "p.runtime_system_read_live", "p.runtime_raw_unavailable", "p.runtime_unavailable",
    "p.runtime_system_on_ac_estimate", "p.runtime_system_on_ac_note",
    "p.runtime_system_unavailable_estimate", "p.runtime_system_unavailable_note",
    "p.help_raw", "p.raw_explain_system_power", "p.raw_explain_system_load",
    "p.raw_explain_battery_voltage", "p.raw_explain_battery_current",
    "p.raw_explain_accumulated_load", "p.raw_explain_sample_count",
    "p.raw_explain_capacity", "p.raw_explain_time", "p.raw_explain_temperature",
    "p.raw_explain_cell", "p.raw_explain_resistance", "p.raw_explain_adapter",
    "p.raw_explain_cycle", "p.raw_explain_state", "p.raw_explain_reference",
    "p.raw_explain_derived", "p.raw_explain_generic",
    "p.raw_explain_time_remaining", "p.raw_explain_avg_time_to_empty",
    "p.raw_explain_model_design_energy", "p.raw_explain_median_power",
    "p.raw_explain_valid_samples", "p.raw_explain_sample_age",
    "p.raw_explain_current_capacity_raw", "p.raw_explain_max_capacity",
    "p.raw_explain_design_capacity",
    "p.system_source_gauge", "p.system_source_others", "p.system_others_cadence",
    "p.field_read_at", "p.field_read_at_gauge", "p.field_read_at_gauge_due",
    "p.field_read_at_event",
    "p.field_read_at_unavailable", "p.field_constant",
    "p.field_spec_static", "p.field_age_seconds",
    "p.field_age_minutes", "p.field_age_hours",
    "p.current_max_desc", "p.capacity_accessibility_four", "p.capacity_accessibility_gap",
    "p.duration_accessibility", "system.field.new.meaning",
    "system.field.new.recommendation", "system.field.new.note",
    "system.reliability.public", "system.reliability.legacy", "system.reliability.private",
    "system.group.temperature", "system.group.capacity", "system.group.power",
    "system.group.fault", "system.group.raw", "system.anomaly.permanent_failure",
    "system.anomaly.health_not_normal", "system.anomaly.thermal_critical",
    "system.anomaly.thermal_serious", "system.anomaly.battery_warning_final",
    "system.anomaly.battery_warning_early", "system.anomaly.cell_spread_warning",
    "system.anomaly.cell_spread_attention", "system.anomaly.temperature_high",
    "system.anomaly.temperature_low", "system.anomaly.diagnostic_nonzero",
]
let bundledPackURLs = Bundle.main.urls(forResourcesWithExtension: "json", subdirectory: "Languages") ?? []
let bundledPacks = bundledPackURLs.compactMap { try? JSONDecoder().decode(LanguagePack.self, from: Data(contentsOf: $0)) }
expect(bundledPacks.count == 10, "直接读取 10 个 bundle JSON 包验证 key 完整性")
for pack in bundledPacks.sorted(by: { $0.meta.order < $1.meta.order }) {
    let missing = shellAndMenuKeys.filter { pack.strings[$0]?.isEmpty != false }
    expect(missing.isEmpty, "\(pack.meta.code): 外观/主壳/菜单栏配置 key 齐全\(missing.isEmpty ? "" : "，缺少 \(missing)")")
}
let rawExplanationKeys = shellAndMenuKeys.filter { $0.hasPrefix("p.raw_explain_") }
if let english = bundledPacks.first(where: { $0.meta.code == "en" }) {
    for pack in bundledPacks where pack.meta.code != "en" {
        let untranslated = rawExplanationKeys.filter { pack.strings[$0] == english.strings[$0] }
        expect(untranslated.isEmpty,
               "\(pack.meta.code): 底层字段说明使用本土语言\(untranslated.isEmpty ? "" : "，仍为英文 \(untranslated)")")
    }
}
l.select("zh-Hans")
expect(l.string("menu.config.title") == "弹出面板指标"
       && l.string("menu.config.second_metric") == "顶部状态栏"
       && l.string("menu.config.status_hint") == "固定显示电量，再选择一个实时指标"
       && l.string("menu.config.metric_choice") == "第二项显示"
       && l.string("menu.process.latest_real_sample") == "使用最近一次真实采样",
       "简体中文菜单栏配置文案准确")
l.select("fr")
expect(l.string("menu.config.restore_defaults") == "Rétablir les réglages par défaut"
       && l.string("menu.metric.runtime") == "Autonomie restante",
       "新增菜单配置提供法语原生译文")
l.select("ja")
expect(l.string("system.group.temperature") == "温度／熱状態"
       && l.string("p.duration_accessibility").contains("時間"),
       "动态系统字段与辅助功能说明提供日语原生译文")
l.select("zh-Hans")
expect(l.string("p.help_raw") == "字段说明与原始值"
       && l.string("p.raw_explain_battery_voltage").contains("电池组")
       && l.string("p.raw_explain_sample_count").contains("采样次数"),
       "展开指标的字段说明使用易懂的简体中文")

print("── 2c) 四层核验台 464 行表格的 6 列走语言包（数据驱动，无白名单）")
// 白名单会腐烂：加一个字段却忘了加进名单，测试照绿。所以直接以 catalog 自身
// 声明的 *Key 为待验集合 —— 加字段时它自动纳入，漏配 key 时它自动变红。
if let catalogURL = Bundle.main.url(forResource: "SystemFieldCatalog", withExtension: "json"),
   let catalog = try? JSONDecoder().decode(CatalogPayload.self, from: Data(contentsOf: catalogURL)) {
    expect(catalog.fields.count == catalog.fieldCount,
           "catalog 自洽: fieldCount \(catalog.fieldCount) == fields \(catalog.fields.count)")
    let declared = catalog.fields.flatMap(\.declaredKeys)
    let distinctKeys = Set(declared.map(\.key))
    expect(!distinctKeys.isEmpty, "catalog 声明了 \(declared.count) 个 *Key（distinct \(distinctKeys.count)）")
    // 每个 field 至少要有 meaning 与 group 两列可本地化，否则那两列会退回中文原值
    let missingCore = catalog.fields.filter { field in
        (field.meaningKey ?? "").isEmpty || (field.groupKey ?? "").isEmpty
    }
    expect(missingCore.isEmpty,
           "每个 field 都有 meaningKey 与 groupKey\(missingCore.isEmpty ? "" : "，缺失 \(missingCore.prefix(5).map(\.path))")")
    for pack in bundledPacks.sorted(by: { $0.meta.order < $1.meta.order }) {
        // 目标是「界面上这一格显示的是译文」，所以两条都要：key 必须解析出值
        // （解析不到时 raw() 回落 key 本身），且值不能是空串（空串会渲染成空白格）。
        let unresolved = distinctKeys.filter { key in
            guard let value = pack.strings[key] else { return true }
            return value.isEmpty || value == key
        }
        expect(unresolved.isEmpty,
               "\(pack.meta.code): catalog 的 \(distinctKeys.count) 个 key 全部解析出非空译文\(unresolved.isEmpty ? "" : "，未解析 \(unresolved.sorted().prefix(6))")")
    }
    // 抽样确认取值链条真的通到界面语言，而不是恰好各包都写了英文
    l.select("ko")
    expect(l.string("system.catalog.group.temperature") == "온도",
           "ko 的字段分组是韩语: \(l.string("system.catalog.group.temperature"))")
    l.select("de")
    expect(l.string("system.catalog.group.temperature") == "Temperatur",
           "de 的字段分组是德语: \(l.string("system.catalog.group.temperature"))")
    l.select("zh-Hant")
    expect(l.string("system.catalog.unit.minutes") == "分鐘",
           "zh-Hant 的单位用繁体: \(l.string("system.catalog.unit.minutes"))")
    // 单位列里的百分号同样受 %% 约定管辖，还原后必须是单个 %
    expect(l.string("system.catalog.unit.percent") == "%",
           "百分号单位还原成单个 %: [\(l.string("system.catalog.unit.percent"))]")
} else {
    expect(false, "读不到 bundle 内的 SystemFieldCatalog.json —— run-fixed-qa.sh 是否漏拷？")
}

print("── 2d) 术语抽样（防回归）")
l.select("zh-Hant")
expect(l.string("proc.group_count").contains("個行程") && !l.string("proc.group_count").contains("個程序"),
       "繁中 process 译作「行程」而非「程序」: \(l.string("proc.group_count"))")
expect(l.string("proc.cpu_system") == "未歸因負載",
       "繁中准确标注为未归因负载: \(l.string("proc.cpu_system"))")

print("── 3) 数字格式化带 locale")
l.select("de")
expect(l.format("status.charging", [17.25, 65]).contains("17,2"), "德语逗号小数: \(l.format("status.charging", [17.25, 65]))")
l.select("en")
expect(l.format("status.charging", [17.25, 65]).contains("17.2"), "英语点号小数: \(l.format("status.charging", [17.25, 65]))")

print("── 3b) %% 转义与散文里的百分号")
l.select("zh-Hans")
let tip = l.string("insight.habit.tip_avoid_overnight")
expect(!tip.contains("%%"), "单参 L() 把 %% 还原成 % [\(tip.suffix(24))]")
expect(tip.contains("80%"), "还原后是单个百分号")
expect(!tip.hasPrefix("You often"), "中文包该 key 未被格式符校验器误丢弃回落英文")
for code in ["en","zh-Hans","ja","de","fr"] {
    l.select(code)
    let all = ["insight.habit.tip_avoid_overnight","insight.habit.tip_full_cycle",
               "insight.habit.tip_optimized_charging","tip.health","tip.cycles",
               "hist.rate_chart","rt.y_percent","proc.cpu_live","proc.col_cpu"]
    expect(all.allSatisfy { !l.string($0).contains("%%") },
           "\(code): 所有含百分号的展示文案都无 %% 残留")
    // proc.col_cpu 是纯 "CPU%%"，还原后必须剩一个百分号而不是空
    expect(l.string("proc.col_cpu").contains("%"),
           "\(code): CPU 列头还原后保留单个百分号 [\(l.string("proc.col_cpu"))]")
}
// 带参路径仍须正常：%% 交给 String(format:) 还原，且实参不被吃掉
l.select("zh-Hans")
let d1 = l.format("insight.habit.depth_detail", [22, 92])
expect(d1.contains("22") && d1.contains("92") && !d1.contains("%%"),
       "带参 key 的 %% 由 String(format:) 还原且实参正确 [\(d1)]")

print("── 3c) 全包裸百分号扫描（占位符签名比对之外的最后一个空洞）")
// 上面 3b 验的是「%% 能正确还原」，这里验的是「字面百分号确实都写成了 %%」。
// 两者不重叠：一个裸 % 今天可以恰好通过签名比对，明天译者在它后面多写一个字母
// 就变成真说明符，该 key 被静默丢弃回落英文。
for pack in bundledPacks.sorted(by: { $0.meta.order < $1.meta.order }) {
    var offenders: [String] = []
    for (key, value) in pack.strings where !bareLiteralPercentOffsets(value).isEmpty {
        offenders.append(key)
    }
    expect(offenders.isEmpty,
           "\(pack.meta.code): 字面百分号一律写成 %%\(offenders.isEmpty ? "" : "，裸 % 出现在 \(offenders.sorted().prefix(8))")")
}
// 自检：扫描器本身必须认得出裸 % 与转义 %%，否则上面那组断言是空的
expect(bareLiteralPercentOffsets("80% 左右") == [2], "扫描器认出裸 %")
expect(bareLiteralPercentOffsets("末尾裸 %") == [4], "扫描器认出结尾的裸 %")
expect(bareLiteralPercentOffsets("80%% 左右").isEmpty, "扫描器放过 %%")
expect(bareLiteralPercentOffsets("%.1f W · %d%%").isEmpty, "扫描器放过合法说明符与 %%")
expect(bareLiteralPercentOffsets("%1$@ 于 %2$d").isEmpty, "扫描器认得位置参数 %1$@")
// 这一条就是整组断言存在的理由：同一个字面百分号，中文「80% 左右」后面跟汉字
// 算裸 %，英文「80% overnight」里空格是 flag、o 是八进制说明符，被解析成真的
// `% o`。两个包的格式符签名于是不一致，该 key 被 validatedStrings 静默丢弃。
expect(bareLiteralPercentOffsets("80% overnight").isEmpty,
       "「% o」会被解析成说明符 —— 正因如此裸 % 必须一律禁掉，不能只靠签名比对")

print("── 4) 选择不存在的语言 → 回落跟随系统")
l.select("xx-NOPE")
expect(l.isFollowingSystem, "select(不存在的 code) 后 isFollowingSystem == true")
expect(l.languages.map(\.code).contains(l.effectiveCode), "协商出的 effectiveCode 在可用列表内: \(l.effectiveCode)")

print("── 5) 跟随系统可回退")
l.select("ja")
expect(!l.isFollowingSystem && l.effectiveCode == "ja", "显式选中 ja")
l.select(nil)
expect(l.isFollowingSystem, "select(nil) 回到跟随系统")

print(failures == 0 ? "\n✅ 第一阶段全部通过" : "\n❌ \(failures) 项失败")
exit(failures == 0 ? 0 : 1)
}

// 第二阶段：由 PHASE=2 触发，此时 Application Support 里已铺好覆盖包
if phase2 {
    print("── 6) 覆盖层生效")
    l.select("de")
    expect(l.string("app.title") == "ÜBERSCHRIEBEN-OK",
           "Application Support 的 de.json 覆盖了 bundle 内置: \(l.string("app.title"))")
    expect(l.string("stat.health") == "HEALTH-OVERRIDE", "覆盖包的第二个 key 也生效")
    expect(l.string("stat.cycles") == "Zyklen", "覆盖包里未改动的 key 保持原值: \(l.string("stat.cycles"))")

    print("── 7) 坏格式符护栏")
    l.select("it")
    expect(l.string("app.title") == "IT-OVERRIDE-OK", "签名合法的 key 被保留: \(l.string("app.title"))")
    let bad = l.string("status.charging")
    expect(!bad.hasPrefix("ROTTO"), "签名非法的 status.charging 被丢弃")
    expect(bad == "Carica %.1fW · Adattatore %dW", "并保留可信内置意大利语: \(bad)")
    // 真正的安全性验证：用 Double+Int 实参调用，若坏格式串没被拦会读错位模式
    let out = l.format("status.charging", [17.25, 65])
    expect(out.contains("17,2") && out.contains("65"), "带 Double 实参格式化安全，且数字仍按用户选的 it locale: \(out)")

    print("── 8) 超大外部语言包护栏")
    l.select("pt")
    expect(l.string("app.title") == "Monitor de Bateria",
           "超过大小限制的外部 pt.json 被拒绝并保留内置语言包")

    print(failures == 0 ? "\n✅ 第二阶段全部通过" : "\n❌ 第二阶段 \(failures) 项失败")
    exit(failures == 0 ? 0 : 1)
}
