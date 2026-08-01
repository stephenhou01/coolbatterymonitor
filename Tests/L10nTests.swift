import Foundation

func expect(_ cond: Bool, _ msg: String) {
    print((cond ? "  ✓ " : "  ✗ ") + msg)
    if !cond { failures += 1 }
}
var failures = 0
let l = L10n.shared

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
expect(l.string("p.menu_time") == "Time until empty",
       "原型未单独翻译的语言沿用明确的英文 fallback")

print("── 2b) 外观、主壳与菜单栏配置文案覆盖全部语言包")
let shellAndMenuKeys = [
    "appearance.system", "appearance.light", "appearance.dark",
    "shell.overview", "shell.technical", "shell.trends", "shell.diagnostics", "shell.settings",
    "shell.sidebar_subtitle", "shell.local_only", "shell.power_connected", "shell.on_battery",
    "shell.power_hint", "shell.adapter", "shell.adapter_connected", "shell.not_connected",
    "shell.charge_power", "shell.charging", "shell.not_charging", "shell.temp_range",
    "shell.cycle_reference", "shell.health_good", "shell.health_fair", "shell.health_attention",
    "shell.status_attention", "shell.status_good", "shell.status_subtitle",
    "shell.technical_subtitle", "shell.trends_subtitle", "shell.diagnostics_subtitle",
    "shell.diagnosing", "shell.system_anomalies", "shell.settings_subtitle", "shell.appearance",
    "shell.live_refresh", "shell.privacy_note", "shell.dynamic_trends", "shell.last_minutes",
    "shell.instant_power", "shell.current", "shell.top_processes", "shell.cpu_context",
    "menu.config.title", "menu.config.second_metric", "menu.config.customize", "menu.config.empty",
    "menu.config.drag_to_reorder", "menu.config.add_more", "menu.config.manage_in_dashboard",
    "menu.config.show", "menu.config.hide", "menu.config.move_up", "menu.config.move_down",
    "menu.config.restore_defaults", "menu.metric.runtime", "menu.metric.power",
    "menu.metric.temperature", "menu.metric.health", "menu.metric.cycles", "menu.metric.current",
    "menu.process.none", "menu.process.latest_real_sample", "p.menu_settings",
    "p.menu_close", "p.menu_language", "p.menu_quit",
    "p.help_summary_adapter_power", "p.help_source_adapter_power",
    "p.help_summary_charging_power", "p.help_source_charging_power",
    "p.help_summary_cycle_count", "p.help_source_cycle_count",
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
l.select("zh-Hans")
expect(l.string("menu.config.title") == "显示指标"
       && l.string("menu.config.second_metric") == "顶部第二项"
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
               "hist.rate_chart","rt.y_percent","proc.cpu_live"]
    expect(all.allSatisfy { !l.string($0).contains("%%") },
           "\(code): 所有含百分号的展示文案都无 %% 残留")
}
// 带参路径仍须正常：%% 交给 String(format:) 还原，且实参不被吃掉
l.select("zh-Hans")
let d1 = l.format("insight.habit.depth_detail", [22, 92])
expect(d1.contains("22") && d1.contains("92") && !d1.contains("%%"),
       "带参 key 的 %% 由 String(format:) 还原且实参正确 [\(d1)]")

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
    expect(bad == "Charging at %.1fW · Adapter %dW", "并回落到 en: \(bad)")
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
