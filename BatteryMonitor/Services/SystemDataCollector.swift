import Foundation
import IOKit
import IOKit.ps
import IOKit.pwr_mgt

/// Reads four independent macOS layers and merges their live values with the
/// metadata generated from the user's complete workbook. The workbook's sample
/// values never enter this path.
enum SystemDataCollector {
    private struct FlatValue {
        let display: String
        let type: String
        let number: Double?
        let numbers: [Double]?
        let boolean: Bool?
        let text: String?
    }

    static func collect(registry suppliedRegistry: [String: Any]? = nil) -> SystemDataSnapshot {
        var values: [String: FlatValue] = [:]

        collectPowerSources(into: &values)
        let registry = suppliedRegistry ?? BatteryService.readRegistry()
        if let registry {
            flatten(registry, source: SystemDataLayer.smartBattery.sourceName, into: &values)
        }
        collectLegacyIOPM(into: &values)
        collectProcessInfo(into: &values)

        // One read time for the whole pass, shared by the snapshot and by every
        // reading in it, so the workbench and the help drawer cannot disagree.
        let collectedAt = Date()
        var remaining = values
        var readings = SystemFieldCatalog.fields.map { metadata -> SystemFieldReading in
            let flat = remaining.removeValue(forKey: key(metadata.source, metadata.path))
            let anomaly = anomaly(for: metadata, value: flat)
            return SystemFieldReading(
                metadata: metadata,
                value: flat?.display ?? "—",
                runtimeType: flat?.type ?? metadata.declaredType,
                isAvailable: flat != nil,
                anomalyLevel: anomaly.level,
                anomalyReason: anomaly.reason,
                readAt: collectedAt
            )
        }

        // New OS releases can add fields that are not in the July workbook.
        // They are shown immediately in the source/all tabs without pretending
        // that an undocumented field has a known definition.
        for (compoundKey, flat) in remaining {
            let parts = compoundKey.split(separator: "|", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { continue }
            let source = parts[0]
            let path = parts[1]
            let metadata = SystemFieldMetadata(
                layer: layerNumber(for: source),
                source: source,
                group: inferredGroup(path),
                path: path,
                declaredType: flat.type,
                unit: "",
                meaning: dashboardText(
                    "system.field.new.meaning"
                ),
                reliability: sourceReliability(source),
                recommendation: dashboardText("system.field.new.recommendation"),
                valueStars: 1,
                note: dashboardText(
                    "system.field.new.note"
                )
            )
            let anomaly = anomaly(for: metadata, value: flat)
            readings.append(SystemFieldReading(
                metadata: metadata,
                value: flat.display,
                runtimeType: flat.type,
                isAvailable: true,
                anomalyLevel: anomaly.level,
                anomalyReason: anomaly.reason,
                readAt: collectedAt
            ))
        }

        // Plain comparison rather than localizedStandardCompare: these are IOKit
        // key paths, always ASCII, never shown as a sorted list the user reads as
        // prose. Measured on the real 464 paths, ICU collation cost 2.9 ms per
        // poll against 0.2 ms here — on the main thread, ten times a minute, for
        // an ordering no one can tell apart.
        readings.sort {
            if $0.metadata.layer != $1.metadata.layer { return $0.metadata.layer < $1.metadata.layer }
            return $0.metadata.path < $1.metadata.path
        }
        return SystemDataSnapshot(timestamp: collectedAt, fields: readings)
    }

    /// Narrow regression seams for Foundation's NSNumber/CFBoolean bridging and
    /// the conservative anomaly rules. Production callers use `collect`.
    static func normalizedValueForTesting(_ value: Any) -> (display: String, type: String) {
        let normalized = describe(value)
        return (normalized.display, normalized.type)
    }

    static func anomalyLevelForTesting(path: String, value: Any) -> Int {
        let metadata = SystemFieldMetadata(
            layer: 2, source: SystemDataLayer.smartBattery.sourceName,
            group: "测试", path: path, declaredType: "Unknown", unit: "",
            meaning: "", reliability: "", recommendation: "", valueStars: 1, note: ""
        )
        return anomaly(for: metadata, value: describe(value)).level.rawValue
    }

    // MARK: - Four live layers

    private static func collectPowerSources(into values: inout [String: FlatValue]) {
        let source = SystemDataLayer.powerSources.sourceName
        let blob = IOPSCopyPowerSourcesInfo().takeRetainedValue()
        let list = IOPSCopyPowerSourcesList(blob).takeRetainedValue() as [CFTypeRef]
        for (index, item) in list.enumerated() {
            guard let dictionary = IOPSGetPowerSourceDescription(blob, item)?.takeUnretainedValue() as? [String: Any] else { continue }
            flatten(dictionary, prefix: "PowerSources[\(index)]", source: source, into: &values)
        }

        if let adapter = IOPSCopyExternalPowerAdapterDetails()?.takeRetainedValue() as? [String: Any] {
            flatten(adapter, prefix: "ExternalPowerAdapter", source: source, into: &values)
        }

        if let powerType = IOPSGetProvidingPowerSourceType(blob)?.takeUnretainedValue() as String? {
            insert(powerType, path: "QuickInfo.ProvidingPowerSourceType", source: source, into: &values)
        }
        let estimate = IOPSGetTimeRemainingEstimate()
        insert(Int(estimate.rounded()), path: "QuickInfo.TimeRemainingEstimateSeconds", source: source, into: &values)

        let warning = IOPSGetBatteryWarningLevel()
        insert(Int(warning.rawValue), path: "QuickInfo.BatteryWarningLevel", source: source, into: &values)
        let warningName: String
        switch warning {
        case kIOPSLowBatteryWarningEarly: warningName = "early"
        case kIOPSLowBatteryWarningFinal: warningName = "final"
        default: warningName = "none"
        }
        insert(warningName, path: "QuickInfo.BatteryWarningLevelName", source: source, into: &values)
    }

    private static func collectLegacyIOPM(into values: inout [String: FlatValue]) {
        let source = SystemDataLayer.legacyIOPM.sourceName
        var unmanaged: Unmanaged<CFArray>?
        let result = IOPMCopyBatteryInfo(mach_port_t(MACH_PORT_NULL), &unmanaged)
        insert(Int(result), path: "IOReturn", source: source, into: &values)
        if let array = unmanaged?.takeRetainedValue() as? [Any], !array.isEmpty {
            if array.count == 1, let dictionary = array[0] as? [String: Any] {
                flatten(dictionary, prefix: "BatteryInfo", source: source, into: &values)
            } else {
                flatten(array, prefix: "BatteryInfo", source: source, into: &values)
            }
        }
    }

    private static func collectProcessInfo(into values: inout [String: FlatValue]) {
        let source = SystemDataLayer.processInfo.sourceName
        let process = ProcessInfo.processInfo
        insert(process.isLowPowerModeEnabled, path: "isLowPowerModeEnabled", source: source, into: &values)
        insert(process.thermalState.rawValue, path: "thermalStateRaw", source: source, into: &values)
        let thermal: String
        switch process.thermalState {
        case .nominal: thermal = "nominal"
        case .fair: thermal = "fair"
        case .serious: thermal = "serious"
        case .critical: thermal = "critical"
        @unknown default: thermal = "unknown"
        }
        insert(thermal, path: "thermalState", source: source, into: &values)
        insert(Notification.Name.NSProcessInfoPowerStateDidChange.rawValue,
               path: "powerStateNotification", source: source, into: &values)
        insert(ProcessInfo.thermalStateDidChangeNotification.rawValue,
               path: "thermalStateNotification", source: source, into: &values)
    }

    // MARK: - Generic flattening

    private static func flatten(
        _ value: Any,
        prefix: String = "",
        source: String,
        into values: inout [String: FlatValue]
    ) {
        if let dictionary = value as? [String: Any] {
            if dictionary.isEmpty, !prefix.isEmpty {
                insert(dictionary, path: prefix, source: source, into: &values)
                return
            }
            for entry in dictionary.sorted(by: { $0.key < $1.key }) {
                let path = prefix.isEmpty ? entry.key : "\(prefix).\(entry.key)"
                flatten(entry.value, prefix: path, source: source, into: &values)
            }
            return
        }

        if let dictionary = value as? NSDictionary {
            var converted: [String: Any] = [:]
            for (key, item) in dictionary { converted[String(describing: key)] = item }
            flatten(converted, prefix: prefix, source: source, into: &values)
            return
        }

        if let array = value as? [Any] {
            if array.contains(where: { $0 is NSDictionary || $0 is [String: Any] }) {
                for (index, item) in array.enumerated() {
                    flatten(item, prefix: "\(prefix)[\(index)]", source: source, into: &values)
                }
            } else {
                insert(array, path: prefix, source: source, into: &values)
            }
            return
        }

        insert(value, path: prefix, source: source, into: &values)
    }

    private static func insert(_ value: Any, path: String, source: String, into values: inout [String: FlatValue]) {
        guard !path.isEmpty else { return }
        values[key(source, path)] = describe(value)
    }

    private static func describe(_ value: Any) -> FlatValue {
        if let value = value as? Data {
            let prefix = value.prefix(24).map { String(format: "%02x", $0) }.joined()
            let suffix = value.count > 24 ? "…" : ""
            return FlatValue(display: "\(value.count) B · 0x\(prefix)\(suffix)", type: "Data",
                             number: nil, numbers: nil, boolean: nil, text: nil)
        }
        if let value = value as? String {
            return FlatValue(display: value.isEmpty ? "\"\"" : value, type: "String", number: nil,
                             numbers: nil, boolean: nil, text: value)
        }
        if let value = value as? NSNumber {
            // Objective-C dictionaries bridge both CFBoolean and all numeric
            // values through NSNumber. `as? Bool` accepts numeric zero/one as
            // well, so use the Core Foundation type ID to avoid rendering a
            // 0 mA current or 0-minute estimate as "false".
            if CFGetTypeID(value) == CFBooleanGetTypeID() {
                let boolean = value.boolValue
                return FlatValue(display: boolean ? "true" : "false", type: "Boolean", number: nil,
                                 numbers: nil, boolean: boolean, text: nil)
            }
            let number = value.doubleValue
            let isInteger = floor(number) == number && number <= Double(Int64.max) && number >= Double(Int64.min)
            return FlatValue(display: isInteger ? String(value.int64Value) : String(format: "%.6g", number),
                             type: isInteger ? "Integer" : "Double", number: number,
                             numbers: nil, boolean: nil, text: nil)
        }
        if let value = value as? Bool {
            return FlatValue(display: value ? "true" : "false", type: "Boolean", number: nil,
                             numbers: nil, boolean: value, text: nil)
        }
        if let value = value as? [Any] {
            let described = value.map(describe)
            let numbers = described.compactMap(\.number)
            let display = "[" + described.map(\.display).joined(separator: ", ") + "]"
            return FlatValue(display: display, type: "Array", number: nil,
                             numbers: numbers.count == value.count ? numbers : nil,
                             boolean: nil, text: nil)
        }
        if let value = value as? [String: Any] {
            return FlatValue(display: value.isEmpty ? "{}" : "{\(value.count) keys}", type: "Dictionary",
                             number: nil, numbers: nil, boolean: nil, text: nil)
        }
        return FlatValue(display: String(describing: value), type: String(describing: type(of: value)),
                         number: nil, numbers: nil, boolean: nil, text: nil)
    }

    // MARK: - Conservative anomaly rules

    private static func anomaly(
        for metadata: SystemFieldMetadata,
        value: FlatValue?
    ) -> (level: SystemFieldAnomalyLevel, reason: String) {
        guard let value else { return (.none, "") }
        let path = metadata.path
        let lowerText = value.text?.lowercased() ?? ""

        if path.hasSuffix("PermanentFailureStatus"), let number = value.number, number != 0 {
            return (.critical, dashboardText("system.anomaly.permanent_failure"))
        }
        if path.hasSuffix("BatteryHealth"), !["good", "normal"].contains(lowerText) {
            return (.critical, dashboardText("system.anomaly.health_not_normal"))
        }
        if path == "thermalState" {
            if lowerText == "critical" {
                return (.critical, dashboardText("system.anomaly.thermal_critical"))
            }
            if lowerText == "serious" {
                return (.warning, dashboardText("system.anomaly.thermal_serious"))
            }
        }
        if path.hasSuffix("BatteryWarningLevel"), let number = value.number, number >= 3 {
            return (.critical, dashboardText("system.anomaly.battery_warning_final"))
        }
        if path.hasSuffix("BatteryWarningLevel"), let number = value.number, number >= 2 {
            return (.warning, dashboardText("system.anomaly.battery_warning_early"))
        }
        if path.hasSuffix("CellVoltage"), let numbers = value.numbers,
           let minimum = numbers.min(), let maximum = numbers.max() {
            let spread = maximum - minimum
            if spread > 50 {
                return (.warning, dashboardText("system.anomaly.cell_spread_warning"))
            }
            if spread > 20 {
                return (.attention, dashboardText("system.anomaly.cell_spread_attention"))
            }
        }
        if path == "Temperature", let raw = value.number {
            let celsius = raw > 1000 ? raw / 100 : raw > 100 ? raw / 10 : raw
            if celsius >= 45 {
                return (.warning, dashboardText("system.anomaly.temperature_high"))
            }
            if celsius < 0 {
                return (.attention, dashboardText("system.anomaly.temperature_low"))
            }
        }
        if (path.hasSuffix("BatteryCellDisconnectCount") || path.hasSuffix("QmaxDisqualificationReason")),
           let number = value.number, number != 0 {
            return (.attention, dashboardText("system.anomaly.diagnostic_nonzero"))
        }
        return (.none, "")
    }

    private static func key(_ source: String, _ path: String) -> String { "\(source)|\(path)" }

    private static func layerNumber(for source: String) -> Int {
        SystemDataLayer.allCases.first(where: { $0.sourceName == source })?.rawValue ?? 99
    }

    private static func sourceReliability(_ source: String) -> String {
        switch source {
        case SystemDataLayer.powerSources.sourceName, SystemDataLayer.processInfo.sourceName:
            return dashboardText("system.reliability.public")
        case SystemDataLayer.legacyIOPM.sourceName:
            return dashboardText("system.reliability.legacy")
        default:
            return dashboardText("system.reliability.private")
        }
    }

    private static func inferredGroup(_ path: String) -> String {
        let lower = path.lowercased()
        if lower.contains("temperature") || lower.contains("thermal") {
            return dashboardText("system.group.temperature")
        }
        if lower.contains("capacity") || lower.contains("soc") {
            return dashboardText("system.group.capacity")
        }
        if lower.contains("power") || lower.contains("current") || lower.contains("voltage") {
            return dashboardText("system.group.power")
        }
        if lower.contains("fail") || lower.contains("error") {
            return dashboardText("system.group.fault")
        }
        return dashboardText("system.group.raw")
    }
}
