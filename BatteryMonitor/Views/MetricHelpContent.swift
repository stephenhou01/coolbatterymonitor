import SwiftUI

enum MetricHelpResultStyle: Equatable {
    case primary
    case stable
    case current

    var tint: Color {
        switch self {
        case .primary: return AppTheme.chargingCyan
        case .stable: return AppTheme.accentPurple
        case .current: return AppTheme.batteryYellow
        }
    }
}

/// A comparison value shown alongside the primary result. Runtime uses this to
/// keep the macOS value visually dominant while exposing two clearly-derived
/// estimates in the same question-mark drawer.
struct MetricHelpResult: Identifiable, Equatable {
    let id: String
    let title: String
    let value: String
    let note: String
    let style: MetricHelpResultStyle
}

struct MetricHelpTrendPoint: Identifiable, Equatable {
    enum Quality: Equatable { case measured, fitted }

    let timestamp: Date
    let value: Double
    var quality: Quality = .measured
    var segmentID: Int = 0
    var sampleCount: Int = 1

    var id: Date { timestamp }
}

enum MetricHelpTrendRange: String, CaseIterable, Identifiable {
    case tenMinutes
    case oneHour
    case twentyFourHours

    var id: String { rawValue }

    var duration: TimeInterval {
        switch self {
        case .tenMinutes: return 10 * 60
        case .oneHour: return 60 * 60
        case .twentyFourHours: return 24 * 60 * 60
        }
    }

    var title: String {
        switch self {
        case .tenMinutes:
            return dashboardText("p.trend_last_10min")
        case .oneHour:
            return dashboardText("p.trend_last_1h")
        case .twentyFourHours:
            return dashboardText("p.trend_last_24h")
        }
    }

    var targetPointCount: Int {
        switch self {
        case .tenMinutes: return 10
        case .oneHour: return 20
        case .twentyFourHours: return 40
        }
    }

    var bucketDuration: TimeInterval {
        duration / Double(targetPointCount)
    }

    var samplingSummary: String {
        switch self {
        case .tenMinutes: return "10 × 1 min"
        case .oneHour: return "20 × 3 min"
        case .twentyFourHours: return "40 × 36 min"
        }
    }

    /// All ranges use fixed, closed mean buckets: 10 min = 10 one-minute
    /// buckets, 1 h = 20 three-minute buckets, and 24 h = 40 thirty-six-minute
    /// buckets. The still-open bucket is deliberately omitted, so ten-second
    /// polling cannot make a chart promise a faster visible cadence.
    /// Only short bounded holes are fitted; longer offline periods remain
    /// separate line segments.
    func chartPoints(from points: [MetricHelpTrendPoint], maximumCount: Int = 240) -> [MetricHelpTrendPoint] {
        let sorted = points.filter { $0.value.isFinite }.sorted { $0.timestamp < $1.timestamp }
        guard let latest = sorted.last?.timestamp else { return [] }
        let interval = bucketDuration
        let end = Date(
            timeIntervalSince1970: floor(latest.timeIntervalSince1970 / interval) * interval
        )
        let start = end.addingTimeInterval(-duration)
        let visible = sorted.filter { $0.timestamp >= start && $0.timestamp < end }
        return bucketed(visible, start: start, count: targetPointCount)
    }

    private func bucketed(_ points: [MetricHelpTrendPoint], start: Date, count: Int) -> [MetricHelpTrendPoint] {
        guard count > 0 else { return [] }
        let interval = duration / Double(count)
        var buckets = Array(repeating: [MetricHelpTrendPoint](), count: count)
        for point in points {
            let index = Int(floor(point.timestamp.timeIntervalSince(start) / interval))
            guard buckets.indices.contains(index) else { continue }
            buckets[index].append(point)
        }

        var slots: [MetricHelpTrendPoint?] = buckets.enumerated().map { index, bucket in
            guard !bucket.isEmpty else { return nil }
            let weight = bucket.reduce(0) { $0 + max(1, $1.sampleCount) }
            let value = bucket.reduce(0.0) { $0 + $1.value * Double(max(1, $1.sampleCount)) } / Double(weight)
            return MetricHelpTrendPoint(
                timestamp: start.addingTimeInterval((Double(index) + 0.5) * interval),
                value: value,
                quality: .measured,
                sampleCount: weight
            )
        }

        let maximumFittedRun = self == .oneHour ? 2 : 1
        var index = 0
        while index < slots.count {
            guard slots[index] == nil else { index += 1; continue }
            let gapStart = index
            while index < slots.count, slots[index] == nil { index += 1 }
            let gapEnd = index
            let gapLength = gapEnd - gapStart
            guard gapLength <= maximumFittedRun,
                  gapStart > 0, gapEnd < slots.count,
                  let left = slots[gapStart - 1], let right = slots[gapEnd] else { continue }
            for offset in 0..<gapLength {
                let fraction = Double(offset + 1) / Double(gapLength + 1)
                slots[gapStart + offset] = MetricHelpTrendPoint(
                    timestamp: start.addingTimeInterval((Double(gapStart + offset) + 0.5) * interval),
                    value: left.value + (right.value - left.value) * fraction,
                    quality: .fitted,
                    sampleCount: 0
                )
            }
        }

        var segment = 0
        var foundGap = false
        return slots.compactMap { slot in
            guard var point = slot else { foundGap = true; return nil }
            if foundGap { segment += 1; foundGap = false }
            point.segmentID = segment
            return point
        }
    }
}

/// A trend chart carried by a help panel. Kept as data rather than a view so
/// every metric can offer one without the drawer knowing which metric it is.
struct MetricHelpTrend: Equatable {
    let title: String
    /// The headline figure shown beside the title — normally the latest sample.
    let latestText: String
    let note: String
    /// Suffix for the hover readout and the y-axis labels, e.g. `W` or `℃`.
    let unit: String
    let tint: Color
    let points: [MetricHelpTrendPoint]
    /// Dashed reference line, e.g. an adapter's negotiated ceiling.
    var ceiling: Double? = nil
    /// Power starts the y axis at zero, because "half the wattage" should look
    /// like half. Temperature does not: a 0℃ floor would flatten every real
    /// swing a battery actually makes.
    var baselineAtZero: Bool = true
    /// Shown instead of the chart when there are not yet two samples.
    var waitingText: String = dashboardText("p.adapter_trend_waiting")

    var isPlottable: Bool { points.count >= 2 }
}

/// Consumer-facing explanation of an adapter's negotiated PD contract. The
/// rated contract and the Mac's live input are deliberately kept separate:
/// 20V × 3.25A describes what the adapter can provide, not what the Mac is
/// necessarily drawing at this instant.
struct MetricPowerContract: Equatable {
    let stateTitle: String
    let stateDetail: String
    let isConnected: Bool
    let isNegotiated: Bool
    let voltageLabel: String
    let voltageText: String
    let currentLabel: String
    let currentText: String
    let powerLabel: String
    let powerText: String
    let equationText: String
    let equationNote: String
    let trendTitle: String
    let trendValue: String
    let trendNote: String
    let trendPoints: [MetricHelpTrendPoint]
    let ceilingWatts: Double?
}

/// Content shared by every question-mark affordance on the final dashboard.
/// Keeping the explanation as data lets the same drawer serve top-level answers,
/// formulas, reference rows, and the hardware table.
struct MetricHelpContent: Identifiable, Equatable {
    let id: String
    let title: String
    let summary: String
    let result: String
    let rawFields: [MetricRawField]
    let formula: String
    let substitution: String
    let source: String
    /// The read time shared by every `.live` field in this card. One IOKit
    /// property snapshot backs the whole card, so one read time is honest.
    var readAt: MetricReadStamp? = nil
    var comparisonResults: [MetricHelpResult] = []
    var powerContract: MetricPowerContract? = nil
    /// Optional history for metrics that move within the rolling 24-hour
    /// buffer. Cycle count and health are deliberately left without one because
    /// the ten-second sampler does not add meaningful resolution for them.
    var trend: MetricHelpTrend? = nil
}

/// Carries the poll timestamp down to every help button so an open drawer can
/// refresh without any card having to build its help content speculatively.
/// Defaults to `.distantPast`, so a button outside the dashboard simply never
/// auto-refreshes instead of crashing.
private struct DashboardDataVersionKey: EnvironmentKey {
    static let defaultValue = Date.distantPast
}

extension EnvironmentValues {
    var dashboardDataVersion: Date {
        get { self[DashboardDataVersionKey.self] }
        set { self[DashboardDataVersionKey.self] = newValue }
    }
}
