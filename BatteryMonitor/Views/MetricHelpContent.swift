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
    let timestamp: Date
    let value: Double

    var id: Date { timestamp }
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
    var waitingText: String = dashboardText("p.adapter_trend_waiting", fallback: "正在积累历史数据")

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
    /// Optional history for metrics that actually move within the ten-minute
    /// buffer. Cycle count and health are deliberately left without one: over
    /// ten minutes they are a flat line, and drawing one would imply the app
    /// has resolution it does not.
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
