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

    var id: String { "\(source)|\(path)" }

    /// Useful by default means that the workbook rated the field at least two
    /// stars. Identifiers stay out of the first view so screenshots do not leak
    /// serial numbers; they remain visible under their source and “all” tabs.
    var isMeaningfulByDefault: Bool {
        valueStars >= 2 && group != "标识"
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

    var id: String { metadata.id }
    var isMeaningful: Bool { metadata.isMeaningfulByDefault || anomalyLevel > .none }

    var help: MetricHelpContent {
        let unavailable = dashboardText("p.system_data_unavailable", fallback: "本次快照系统没有返回这个字段。")
        let summary = isAvailable ? metadata.meaning : unavailable
        let note = metadata.note.isEmpty ? summary : "\(summary)\n\n\(metadata.note)"
        return MetricHelpContent(
            id: "system-field|\(id)",
            title: metadata.path,
            summary: note,
            result: valueWithUnit,
            rawFields: [.init(name: metadata.path, value: value, unit: metadata.unit)],
            formula: "\(metadata.source) → \(metadata.path)",
            substitution: "\(metadata.path) → \(valueWithUnit)",
            source: "\(metadata.reliability) · \(metadata.recommendation)"
        )
    }

    var valueWithUnit: String {
        guard !metadata.unit.isEmpty, value != "—" else { return value }
        return "\(value) \(metadata.unit)"
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
}
