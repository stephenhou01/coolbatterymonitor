import Foundation
import SwiftUI

// MARK: - Question-mark definitions and lowest-level formulas

enum DashboardHelp {

    static func directCapacity(id: String, title: String, summary: String, fieldName: String, value: Int,
                                       readAt: MetricReadStamp?) -> MetricHelpContent {
        content(
            id: id, title: title, summary: summary, result: "\(value.formatted()) mAh",
            fields: [field(fieldName, value, "mAh")],
            formula: dashboardText("p.help_direct", fallback: "无公式：直接读取系统字段。"),
            substitution: "\(fieldName) → \(value) mAh",
            source: "AppleSmartBattery IOKit field.",
            readAt: readAt,
        )
    }

    /// Ten minutes of samples at most — that is the live buffer's own horizon,
    /// and claiming more would be inventing history the app never recorded.
    /// Non-finite readings are dropped rather than plotted.
    static func trendPoints(
        _ s: DashboardMetricSnapshot,
        _ value: (RealtimeDataPoint) -> Double?
    ) -> [MetricHelpTrendPoint] {
        guard let end = s.realtimeData.map(\.timestamp).max() else { return [] }
        let start = end.addingTimeInterval(-10 * 60)
        return s.realtimeData.suffix(60).compactMap { point in
            guard point.timestamp >= start,
                  let reading = value(point), reading.isFinite else { return nil }
            return MetricHelpTrendPoint(timestamp: point.timestamp, value: reading)
        }
    }

    /// Battery-side power for one sample, sign intact: positive is charge going
    /// in, negative is the pack supplying the machine.
    private static func batteryWatts(_ point: RealtimeDataPoint) -> Double {
        point.amperage / 1000.0 * point.voltage
    }

    /// What the adapter is putting out, derived exactly the way the overview's
    /// flow diagram derives it: Mac load plus whatever is going into the
    /// battery. Not `SystemPowerIn` — that field is measured dropping to 0 while
    /// plugged in, which used to delete every sample in the window and leave the
    /// chart empty.
    static func adapterOutputWatts(_ point: RealtimeDataPoint) -> Double? {
        guard point.isOnAC else { return nil }
        return max(0, point.power) + max(0, batteryWatts(point))
    }

    /// Power flowing into the pack. Discharge is recorded as 0 rather than
    /// dropped, so a charge that stops shows as a line falling to the floor
    /// instead of a gap.
    static func chargeWatts(_ point: RealtimeDataPoint) -> Double {
        max(0, batteryWatts(point))
    }

    static func trendTitle() -> String {
        dashboardText("p.trend_last_10min", fallback: "最近 10 分钟")
    }

    static func trendWaiting() -> String {
        dashboardText("p.trend_waiting", fallback: "正在积累历史数据")
    }

    static func content(
        id: String,
        title: String,
        summary: String,
        result: String,
        fields: [MetricRawField],
        formula: String,
        substitution: String,
        source: String,
        readAt: MetricReadStamp? = nil,
        results: [MetricHelpResult] = [],
        powerContract: MetricPowerContract? = nil,
        trend: MetricHelpTrend? = nil
    ) -> MetricHelpContent {
        MetricHelpContent(
            id: id,
            title: title,
            summary: summary,
            result: result,
            rawFields: fields,
            formula: formula,
            substitution: substitution,
            source: source,
            readAt: readAt,
            comparisonResults: results,
            powerContract: powerContract,
            trend: trend
        )
    }

    static func field(
        _ name: String,
        _ value: String,
        _ unit: String = "",
        _ explanation: String = "",
        updateClass: MetricFieldUpdateClass = .live,
        readAt: MetricReadStamp? = nil
    ) -> MetricRawField {
        MetricRawField(name: name, value: value.isEmpty ? "—" : value, unit: unit, explanation: explanation,
                       updateClass: updateClass, readAt: readAt)
    }

    static func field<T: BinaryInteger>(
        _ name: String,
        _ value: T?,
        _ unit: String = "",
        _ explanation: String = "",
        updateClass: MetricFieldUpdateClass = .live,
        readAt: MetricReadStamp? = nil
    ) -> MetricRawField {
        MetricRawField(name: name, value: value.map { String($0) } ?? "—", unit: unit, explanation: explanation,
                       updateClass: updateClass, readAt: readAt)
    }

    /// On AC the gauge parks both runtime fields at 65535, so the row reads
    /// "不可用" for a structural reason rather than a stale read. Verified with
    /// `ioreg`: 5 minutes on AC produced zero changes and never a valid value.
    static func runtimeRawField(_ name: String, _ value: Int?, onAC: Bool = false) -> MetricRawField {
        var raw = field(name, runtimeRawFieldValue(value))
        if onAC { raw.availability = .notProvidedOnAC }
        return raw
    }

    /// The gauge reports whole minutes, which stops meaning anything past an hour
    /// or two. Append the same `h m` rendering the result above the field list
    /// uses, so the reader can tie the raw number to the headline without doing
    /// the division. Left off below an hour, where it would only add "0 h".
    private static func runtimeRawFieldValue(_ value: Int?) -> String {
        let raw = runtimeRawValue(value)
        guard let value, RuntimeSample.isValid(minutes: value), value >= 60 else { return raw }
        return "\(raw) (\(runtime(value)))"
    }

    /// The fuel gauge uses sentinel integers such as 65,535 to mean that no
    /// estimate is available. Product UI hides that implementation value and
    /// also rejects any runtime above the 24-hour display ceiling.
    static func runtimeRawValue(_ value: Int?) -> String {
        guard let value else { return "—" }
        guard RuntimeSample.isValid(minutes: value) else {
            return dashboardText("p.runtime_raw_unavailable", fallback: "不可用")
        }
        return "\(value) min"
    }

    /// Defaults to the bare clock so these cards read the same way as the field
    /// rows below them. The date is only worth the extra width when the value can
    /// legitimately be from another day — the persisted fallback sample.
    static func runtimeReadTimestamp(_ date: Date, includeDate: Bool = false) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: L10n.shared.effectiveCode)
        formatter.dateStyle = includeDate ? .short : .none
        formatter.timeStyle = .medium
        return formatter.string(from: date)
    }

    static func f(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "—" }
        return LNum("%.2f", value)
    }

    static func optional<T>(_ value: T?) -> String { value.map(String.init(describing:)) ?? "—" }

    static func runtime(_ minutes: Int?) -> String {
        guard let minutes, minutes > 0 else { return "—" }
        return "\(minutes / 60) h \(String(format: "%02d", minutes % 60)) m"
    }
}
