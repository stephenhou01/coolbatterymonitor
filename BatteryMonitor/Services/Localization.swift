import Foundation
import Observation

// MARK: - Localization System
//
// 翻译内容不在这个文件里 —— 语言包是 Localization/Languages/*.json，作为 folder
// reference 打进 bundle 的 Contents/Resources/Languages/。加一种语言 = 丢一个
// JSON 文件，这里一行都不用改。
//
// 装载有两个来源，后者覆盖前者：
//   1. bundle 内的 Languages/
//   2. Application Support/BatteryMonitor/Languages/（沙盒容器内，与 history_cache.json
//      同目录）—— 往这里丢 JSON 可以改译文/加语言而不用重新构建。
//
// 运行时切换语言靠 Observation：@Observable 是基于读取的追踪，body 求值期间读到
// `override` 就自动建立依赖。所以 L() 内部读单例即可让所有用到译文的 View 重算，
// 不需要 View 声明属性包装器，也不需要 .id() 砸 identity（那会重置动画 @State，
// 让电量环塌到 0%）。

struct LanguagePack: Decodable {
    struct Meta: Decodable {
        let code: String
        let name: String        // endonym：语言用自己的写法（简体中文 / 日本語），不用英文
        var order: Int = 999    // 菜单排序。endonym 无法互相比较，所以顺序也放在数据里
    }
    let meta: Meta
    let strings: [String: String]

    private enum CodingKeys: String, CodingKey { case meta = "_meta", strings }
}

@Observable
final class L10n {
    static let shared = L10n()

    /// 唯一被观察的存储属性。nil = 跟随系统。
    /// L() 经 effectiveCode 读它，从而在任意 body 求值时自动建立依赖。
    private(set) var override: String?

    // 以下均为非观察存储：init 后不可变。绝不能让它们可观察或做懒加载 ——
    // 否则首次 L() 会在 view update 期间写入被观察属性，造成无限失效循环。
    @ObservationIgnored private let packs: [String: LanguagePack]
    @ObservationIgnored private let systemCode: String

    private static let prefKey = "app.language.override"
    private static let fallback = "en"

    // MARK: - Derived state

    var effectiveCode: String { override ?? systemCode }
    var isFollowingSystem: Bool { override == nil }
    var currentName: String { packs[effectiveCode]?.meta.name ?? effectiveCode }

    /// 菜单用：按 order 升序，order 相同再按 endonym 的本地化排序兜底。
    var languages: [LanguagePack.Meta] {
        packs.values.map(\.meta).sorted {
            $0.order != $1.order
                ? $0.order < $1.order
                : $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    // MARK: - Lookup

    func string(_ key: String) -> String {
        let code = effectiveCode    // ← 依赖就在这一行建立
        return packs[code]?.strings[key]
            ?? packs[Self.fallback]?.strings[key]
            ?? key
    }

    /// 带参版本。必须传 locale：不传等价 POSIX，`%.1f` 永远输出 12.5，而
    /// fr/de/es/pt/it 的小数分隔符是逗号，应为 12,5。
    func format(_ key: String, _ args: [CVarArg]) -> String {
        String(format: string(key), locale: Locale(identifier: effectiveCode), arguments: args)
    }

    /// 只从 Menu/Button 的 action 调用 —— 绝不在 body 求值期间调用。
    /// 传 nil 回到跟随系统。
    func select(_ code: String?) {
        if let code, packs[code] != nil {
            UserDefaults.standard.set(code, forKey: Self.prefKey)
            override = code
        } else {
            UserDefaults.standard.removeObject(forKey: Self.prefKey)
            override = nil
        }
    }

    // MARK: - Init

    private init() {
        let loaded = Self.loadPacks()
        packs = loaded
        systemCode = Self.negotiate(available: Array(loaded.keys))
        // 存过的语言包若已被删除，静默回落到跟随系统
        let saved = UserDefaults.standard.string(forKey: Self.prefKey)
        override = saved.flatMap { loaded[$0] != nil ? $0 : nil }
    }

    // MARK: - Loading

    /// 用户自备的语言包目录（沙盒容器内，无需授权）。
    static var userLanguagesDir: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("BatteryMonitor/Languages", isDirectory: true)
    }

    private static func loadPacks() -> [String: LanguagePack] {
        var result: [String: LanguagePack] = [:]

        // 1) bundle 内置
        if let urls = Bundle.main.urls(forResourcesWithExtension: "json", subdirectory: "Languages") {
            for url in urls { insert(url, into: &result) }
        }
        // 2) 用户目录覆盖同 code 的包
        if let dir = userLanguagesDir,
           let urls = try? FileManager.default.contentsOfDirectory(at: dir,
                                                                   includingPropertiesForKeys: nil) {
            for url in urls where url.pathExtension == "json" { insert(url, into: &result) }
        }

        // 校验格式符签名。语言包是外部输入，而 String(format:) 是 C 变参 ——
        // 格式串与实参类型不匹配是内存不安全的（把 %.1f 写成 %d 会去读 Double
        // 的位模式）。以 en 为基准，签名不符的 key 丢弃，查询时自动回落 en。
        if let base = result[fallback] {
            for (code, pack) in result where code != fallback {
                let safe = pack.strings.filter { key, value in
                    guard let ref = base.strings[key] else { return true }
                    return formatSignature(value) == formatSignature(ref)
                }
                if safe.count != pack.strings.count {
                    result[code] = LanguagePack(meta: pack.meta, strings: safe)
                }
            }
        }
        return result
    }

    private static func insert(_ url: URL, into result: inout [String: LanguagePack]) {
        guard let data = try? Data(contentsOf: url),
              let pack = try? JSONDecoder().decode(LanguagePack.self, from: data),
              pack.meta.code == url.deletingPathExtension().lastPathComponent
        else { return }     // 解码失败或 code 与文件名不符 → 忽略该包，不影响其余
        result[pack.meta.code] = pack
    }

    private static let specifier = try! NSRegularExpression(
        pattern: #"%(?:\d+\$)?[-+ #0]*[\d.]*(?:hh|h|ll|l|L|z|j|t)?([diouxXeEfgGaAcspn@%])"#)

    /// 提取格式符序列，`%%` 是转义的百分号不计入。
    private static func formatSignature(_ s: String) -> [String] {
        let ns = s as NSString
        return specifier.matches(in: s, range: NSRange(location: 0, length: ns.length))
            .map { ns.substring(with: $0.range(at: 1)) }
            .filter { $0 != "%" }
    }

    // MARK: - System language negotiation

    /// 用类方法 Bundle.preferredLocalizations(from:) —— 它拿候选列表去匹配用户 OS
    /// 层的语言偏好，能正确处理 pt-BR→pt / en-GB→en / zh-Hans-CN→zh-Hans。
    /// 不能用 Bundle.main.preferredLocalizations 或 Locale.current：那两个的结果
    /// 已被 app 自身的 .lproj 集合过滤过，将来丢进一个没有对应 .lproj 的语言包
    /// 会选不中。
    private static func negotiate(available: [String]) -> String {
        guard !available.isEmpty else { return fallback }
        if let match = Bundle.preferredLocalizations(from: available).first { return match }
        return available.contains(fallback) ? fallback : available.sorted()[0]
    }
}

// MARK: - Global accessors
// 签名与重写前逐字节一致，所以 81 处调用点无需改动。

func L(_ key: String) -> String { L10n.shared.string(key) }

func L(_ key: String, _ args: CVarArg...) -> String { L10n.shared.format(key, args) }

/// 纯数字/单位的格式化（格式串写死在代码里，不进语言包）。
/// 必须走这里而不是裸 String(format:)：不传 locale 等价 POSIX，"%.1f" 永远输出
/// 21.4，而德语该显示 21,4 —— 否则同一屏会出现「Entladung 21,4W」和「21.4W」
/// 两种写法。读 effectiveCode 也顺带让这些数字在切换语言时一起重算。
func LNum(_ format: String, _ args: CVarArg...) -> String {
    String(format: format,
           locale: Locale(identifier: L10n.shared.effectiveCode),
           arguments: args)
}
