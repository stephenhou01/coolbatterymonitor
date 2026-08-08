import Foundation
import Observation

// MARK: - Localization System
//
// 翻译内容不在这个文件里 —— 编辑权威是按页面拆分的 Localization/Sources/**/*.json；
// Localization/build-language-packs.py 将它们生成到 Localization/Languages/*.json，
// 再作为 folder reference 打进 bundle 的 Contents/Resources/Languages/。这里不写译文。
//
// 装载有两个来源，后者按 key 覆盖前者：
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
    private static let defaultCode = "en"
    private static let maxPackBytes = 2 * 1_024 * 1_024
    private static let maxStringCount = 5_000
    private static let maxKeyLength = 200
    private static let maxValueLength = 20_000
    private static let maxLanguageNameLength = 100

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

    /// 语言包里的原文，`%%` 未还原。只给 format(_:_:) 用。
    private func raw(_ key: String) -> String {
        let code = effectiveCode    // ← 依赖就在这一行建立
        return packs[code]?.strings[key]
            ?? packs[Self.defaultCode]?.strings[key]
            ?? key
    }

    /// 直接展示用。把 `%%` 还原成 `%` —— 语言包里的字面百分号统一写成 `%%`
    /// （否则散文里的裸 `%` 会被格式符校验器当成说明符：`"100% overnight"` 的
    /// `%` 后面跟空格再跟 `o`，`o` 是八进制说明符，签名算出 ["o"]，而中文
    /// 「80% 左右」后面是汉字签名为空 —— 签名不一致会导致该 key 被丢弃回落英文）。
    /// 这条路径不走 String(format:)，所以必须自己还原。
    func string(_ key: String) -> String {
        raw(key).replacingOccurrences(of: "%%", with: "%")
    }

    /// 带参版本。用 raw() 而非 string()：`%%` 要留给 String(format:) 自己还原。
    /// 必须传 locale：不传等价 POSIX，`%.1f` 永远输出 12.5，而 fr/de/es/pt/it
    /// 的小数分隔符是逗号，应为 12,5。
    func format(_ key: String, _ args: [CVarArg]) -> String {
        String(format: raw(key), locale: Locale(identifier: effectiveCode), arguments: args)
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
        var bundled: [String: LanguagePack] = [:]

        // 1) bundle 内置。单独保存，外部 en.json 不能取代格式参数的可信基准。
        if let urls = Bundle.main.urls(forResourcesWithExtension: "json", subdirectory: "Languages") {
            let sortedURLs = urls.map { $0 as URL }
                .sorted(by: { $0.lastPathComponent < $1.lastPathComponent })
            for url in sortedURLs {
                guard let pack = decodePack(url) else { continue }
                bundled[pack.meta.code] = pack
            }
        }

        guard let trustedEnglish = bundled[defaultCode] else {
            // 没有可信英文基准时仍允许 app 启动，但不装载外部语言包。
            return bundled
        }

        var result: [String: LanguagePack] = [:]
        for (code, pack) in bundled {
            if code == defaultCode {
                result[code] = pack
            } else {
                result[code] = LanguagePack(
                    meta: pack.meta,
                    strings: validatedStrings(pack.strings, against: trustedEnglish.strings)
                )
            }
        }

        // 2) 用户目录按 key 合并。同 code 的部分包只覆盖它提供的键，未提供的键
        // 保留内置译文；坏格式符只丢弃对应键，不牵连同包其他安全译文。
        if let dir = userLanguagesDir,
           let urls = try? FileManager.default.contentsOfDirectory(
               at: dir,
               includingPropertiesForKeys: [.fileSizeKey],
               options: [.skipsHiddenFiles]
           ) {
            for url in urls
                .filter({ $0.pathExtension.lowercased() == "json" })
                .sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                guard let userPack = decodePack(url) else { continue }
                let safeOverrides = validatedStrings(
                    userPack.strings,
                    against: trustedEnglish.strings
                )
                guard !safeOverrides.isEmpty else { continue }

                if let current = result[userPack.meta.code] {
                    var merged = current.strings
                    merged.merge(safeOverrides) { _, replacement in replacement }
                    // 对内置语言保留稳定的名称和菜单顺序，只覆盖文案。
                    result[userPack.meta.code] = LanguagePack(meta: current.meta, strings: merged)
                } else {
                    // 新语言允许是部分包；缺失键按查询规则回落到英文。
                    result[userPack.meta.code] = LanguagePack(
                        meta: userPack.meta,
                        strings: safeOverrides
                    )
                }
            }
        }

        return result
    }

    private static func decodePack(_ url: URL) -> LanguagePack? {
        guard let fileSize = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              fileSize <= maxPackBytes,
              let data = try? Data(contentsOf: url, options: .mappedIfSafe),
              data.count <= maxPackBytes,
              let pack = try? JSONDecoder().decode(LanguagePack.self, from: data),
              pack.meta.code == url.deletingPathExtension().lastPathComponent,
              !pack.meta.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              pack.meta.name.count <= maxLanguageNameLength,
              pack.strings.count <= maxStringCount,
              pack.strings.allSatisfy({ key, value in
                  !key.isEmpty && key.count <= maxKeyLength && value.count <= maxValueLength
              })
        else { return nil }
        return pack
    }

    private static func validatedStrings(
        _ strings: [String: String],
        against trustedEnglish: [String: String]
    ) -> [String: String] {
        strings.filter { key, value in
            guard let reference = trustedEnglish[key] else {
                // 未知 key 没有可信的调用点参数定义；只接受不消耗 C 变参的文本。
                return formatSignature(value).isEmpty
            }
            return formatSignature(value) == formatSignature(reference)
        }
    }

    // 位置参数和长度修饰符都是 ABI 的一部分，不能只比较最终的 d/f/@。
    // 例如英文 `%.1f … %d` 若被改成 `%2$.1f … %1$d`，说明符序列仍是 f,d，
    // 但第一个位置实际会按 Double 读取传入的 Int，必须在装载时拒绝。
    private static let specifier = try? NSRegularExpression(
        pattern: #"%(?:(\d+)\$)?[-+ #0']*[\d.]*(hh|h|ll|l|L|z|j|t)?([diouxXeEfgGaAcspn@%])"#
    )

    /// 提取格式参数契约。`%%` 是转义的百分号不计入。
    /// 返回项示例：`f`、`d`、`2$f`、`lld`。
    private static func formatSignature(_ s: String) -> [String] {
        guard let specifier else { return [] }
        let ns = s as NSString
        return specifier.matches(in: s, range: NSRange(location: 0, length: ns.length))
            .compactMap { match in
                let conversion = ns.substring(with: match.range(at: 3))
                guard conversion != "%" else { return nil }
                let position: String
                if match.range(at: 1).location != NSNotFound {
                    position = ns.substring(with: match.range(at: 1)) + "$"
                } else {
                    position = ""
                }
                let length: String
                if match.range(at: 2).location != NSNotFound {
                    length = ns.substring(with: match.range(at: 2))
                } else {
                    length = ""
                }
                return position + length + conversion
            }
    }

    // MARK: - System language negotiation

    /// 用类方法 Bundle.preferredLocalizations(from:) —— 它拿候选列表去匹配用户 OS
    /// 层的语言偏好，能正确处理 pt-BR→pt / en-GB→en / zh-Hans-CN→zh-Hans。
    /// 不能用 Bundle.main.preferredLocalizations 或 Locale.current：那两个的结果
    /// 已被 app 自身的 .lproj 集合过滤过，将来丢进一个没有对应 .lproj 的语言包
    /// 会选不中。
    private static func negotiate(available: [String]) -> String {
        guard !available.isEmpty else { return defaultCode }
        if let match = Bundle.preferredLocalizations(from: available).first { return match }
        return available.contains(defaultCode) ? defaultCode : available.sorted()[0]
    }
}

// MARK: - Global accessors
// 签名与重写前逐字节一致，所以调用点无需改动。

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
