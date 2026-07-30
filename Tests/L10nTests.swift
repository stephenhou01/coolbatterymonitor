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

print("── 3) 数字格式化带 locale")
l.select("de")
expect(l.format("status.charging", [17.25, 65]).contains("17,2"), "德语逗号小数: \(l.format("status.charging", [17.25, 65]))")
l.select("en")
expect(l.format("status.charging", [17.25, 65]).contains("17.2"), "英语点号小数: \(l.format("status.charging", [17.25, 65]))")

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

    print(failures == 0 ? "\n✅ 第二阶段全部通过" : "\n❌ 第二阶段 \(failures) 项失败")
    exit(failures == 0 ? 0 : 1)
}
