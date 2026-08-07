import Foundation

enum SystemDataLayer: Int, CaseIterable, Identifiable {
    case powerSources = 1
    case smartBattery = 2
    case legacyIOPM = 3
    case processInfo = 4

    var id: Int { rawValue }

    var sourceName: String {
        switch self {
        case .powerSources: return "IOPowerSources"
        case .smartBattery: return "AppleSmartBattery / IORegistry"
        case .legacyIOPM: return "IOPMCopyBatteryInfo"
        case .processInfo: return "ProcessInfo"
        }
    }
}
struct SystemFieldMetadata: Codable, Equatable, Identifiable {
    let layer: Int
    let source: String
    let group: String
    let path: String
    let declaredType: String
    let unit: String
    let meaning: String
    let reliability: String
    let recommendation: String
    let valueStars: Int
    let note: String

    /// Language-pack keys for the six display attributes above. Optional so an
    /// older catalog file still decodes. The Chinese values stay put: they are the
    /// zh-Hans copy *and* the tokens that `isMeaningfulByDefault` and
    /// `SystemFieldValueConversion` compare against, so they must not be replaced.
    /// `var` with a default, not `let` — a `let` carrying an initial value is skipped
    /// by the synthesized `init(from:)`, which would silently leave every key nil no
    /// matter what the catalog says. The default lets the two call sites in
    /// SystemDataCollector that build metadata for macOS-added fields at runtime omit
    /// keys entirely: they already pass localized text, and `display` reads an absent
    /// key as "the raw value is the answer".
    var groupKey: String? = nil
    var unitKey: String? = nil
    var meaningKey: String? = nil
    var reliabilityKey: String? = nil
    var recommendationKey: String? = nil
    var noteKey: String? = nil

    var id: String { "\(source)|\(path)" }

    /// Runtime-discovered fields (added by macOS after the workbook) arrive with
    /// no key but with already-localized text, so an empty key means "the raw
    /// value is the answer". One rule covers both kinds of field.
    private static func display(_ key: String?, _ raw: String) -> String {
        guard let key, !key.isEmpty else { return raw }
        return hardwareText(key, raw)
    }

    var localizedGroup: String { Self.display(groupKey, group) }
    var localizedUnit: String { Self.display(unitKey, unit) }
    var localizedMeaning: String { Self.display(meaningKey, meaning) }
    var localizedReliability: String { Self.display(reliabilityKey, reliability) }
    var localizedRecommendation: String { Self.display(recommendationKey, recommendation) }
    var localizedNote: String { Self.display(noteKey, note) }

    /// Useful by default means that the workbook rated the field at least two
    /// stars. Identifiers stay out of the first view so screenshots do not leak
    /// serial numbers; they remain visible under their source and “all” tabs.
    var isMeaningfulByDefault: Bool {
        let lowerPath = path.lowercased()
        let isPrivateIdentifier = ["serial", "uuid", "machineid", "hardwareid"]
            .contains(where: lowerPath.contains)
        return valueStars >= 2
            && !isPrivateIdentifier
            && !["标识", "身份", "Identity"].contains(group)
    }
}

enum SystemFieldAnomalyLevel: Int, Comparable, Equatable {
    case none = 0
    case attention = 1
    case warning = 2
    case critical = 3

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

struct SystemFieldReading: Identifiable, Equatable {
    let metadata: SystemFieldMetadata
    let value: String
    let runtimeType: String
    let isAvailable: Bool
    let anomalyLevel: SystemFieldAnomalyLevel
    let anomalyReason: String
    /// When this reading was collected, so the help drawer can state the read
    /// time instead of leaving it blank. Defaults to nil for older call sites.
    var readAt: Date? = nil

    var id: String { metadata.id }
    /// Resolved through a set built once with the catalog. The underlying test
    /// lowercases the path and allocates two array literals every time it runs,
    /// and the workbench asks it for all 464 rows several times per redraw.
    /// Fields macOS added after the workbook are never in the set, which is the
    /// right answer: they are rated one star and so are never meaningful by
    /// default anyway.
    var isMeaningful: Bool {
        SystemFieldCatalog.meaningfulIDs.contains(metadata.id) || anomalyLevel > .none
    }

    /// One definition of the panel's identity so the row that opens it and the
    /// code that refreshes it cannot drift apart.
    var helpID: String { "system-field|\(id)" }

    var help: MetricHelpContent {
        let unavailable = dashboardText("p.system_data_unavailable", fallback: "本次快照系统没有返回这个字段。")
        let summary = isAvailable ? metadata.localizedMeaning : unavailable
        let localizedNote = metadata.localizedNote
        let note = localizedNote.isEmpty ? summary : "\(summary)\n\n\(localizedNote)"
        return MetricHelpContent(
            id: helpID,
            title: metadata.path,
            summary: note,
            result: valueWithUnit,
            rawFields: [.init(name: metadata.path, value: value, unit: metadata.localizedUnit)],
            formula: "\(metadata.source) → \(metadata.path)",
            substitution: "\(metadata.path) → \(valueWithUnit)",
            source: "\(metadata.localizedReliability) · \(metadata.localizedRecommendation)",
            readAt: readAt.map(MetricReadStamp.ourRead)
        )
    }

    var valueWithUnit: String {
        let unit = metadata.localizedUnit
        guard !unit.isEmpty, value != "—" else { return value }
        return "\(value) \(unit)"
    }

    /// Raw reading with a human-scale conversion appended where the raw unit is
    /// hard to read: minutes into hours, mA/mV into A/V, the platform-scaled
    /// temperature into ℃. Only 12 of the 464 catalogued fields carry such a
    /// unit; everything else is returned untouched rather than padded with an
    /// empty conversion. The raw number always stays first — this is an evidence
    /// table, and the conversion is an aid, not a replacement.
    var convertedValue: String {
        guard let suffix = SystemFieldValueConversion.suffix(for: value, unit: metadata.unit) else {
            return value
        }
        return "\(value) (\(suffix))"
    }
}

enum SystemFieldValueConversion {
    static func suffix(for value: String, unit: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        guard trimmed != "—", !trimmed.isEmpty else { return nil }
        switch unit {
        case "分钟":
            // Reject the gauge's sentinels and IOPowerSources' -1 "still
            // calculating" rather than rendering 1092 hours.
            guard let minutes = Int(trimmed), RuntimeSample.isValid(minutes: minutes) else { return nil }
            return "\(minutes / 60) h \(String(format: "%02d", minutes % 60)) m"
        case "秒":
            guard let seconds = Int(trimmed), seconds >= 60, seconds <= 86_400 else { return nil }
            return "\(seconds / 60) min"
        case "mA":
            guard let milliamps = Double(trimmed) else { return nil }
            return LNum("%.2f A", milliamps / 1000)
        case "mV":
            guard let millivolts = Double(trimmed) else { return nil }
            return LNum("%.2f V", millivolts / 1000)
        case "原始温标":
            // The scale differs by platform, which is exactly why the raw number
            // is unreadable; reuse the decoder the rest of the app trusts.
            guard let raw = Int(trimmed), raw != 0 else { return nil }
            return LNum("%.1f ℃", BatteryService.decodeTemperature(raw))
        default:
            return nil
        }
    }
}

struct SystemDataSnapshot: Equatable {
    var timestamp = Date.distantPast
    var fields: [SystemFieldReading] = []

    var availableCount: Int { fields.lazy.filter(\.isAvailable).count }
    var anomalyCount: Int { fields.lazy.filter { $0.anomalyLevel > .none }.count }
}

private struct SystemFieldCatalogPayload: Codable {
    let schemaVersion: Int
    let fieldCount: Int
    let sourceWorkbook: String
    let fields: [SystemFieldMetadata]
}

enum SystemFieldCatalog {
    static let fields: [SystemFieldMetadata] = {
        let candidates = [
            Bundle.main.url(forResource: "SystemFieldCatalog", withExtension: "json"),
            Bundle.main.url(forResource: "SystemFieldCatalog", withExtension: "json", subdirectory: "Resources"),
        ]
        guard let url = candidates.compactMap({ $0 }).first,
              let data = try? Data(contentsOf: url),
              let payload = try? JSONDecoder().decode(SystemFieldCatalogPayload.self, from: data),
              payload.schemaVersion == 1 else { return [] }
        return payload.fields
    }()

    /// Built once alongside the catalog so the per-row test is a set lookup.
    static let meaningfulIDs: Set<String> = Set(
        fields.lazy.filter(\.isMeaningfulByDefault).map(\.id)
    )
}
