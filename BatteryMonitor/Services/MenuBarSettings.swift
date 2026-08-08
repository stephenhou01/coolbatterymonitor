import Foundation
import Observation

/// Metrics that can be surfaced in the menu-bar title and in the expanded panel.
/// Values remain grounded in the live BatteryData snapshot; this type only owns
/// presentation choices and never derives a new battery estimate.
enum MenuBarMetric: String, CaseIterable, Identifiable {
    case runtime
    case power
    case temperature
    case cycles
    case health
    case current
    case chargingPower
    case chargeSpeed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .runtime:
            return dashboardText("menu.metric.runtime")
        case .power:
            return dashboardText("menu.metric.power")
        case .temperature:
            return dashboardText("menu.metric.temperature")
        case .cycles:
            return dashboardText("menu.metric.cycles")
        case .health:
            return dashboardText("menu.metric.health")
        case .current:
            return dashboardText("menu.metric.current")
        case .chargingPower:
            // Deliberately not "充电功率" like the overview card: this list also
            // contains "当前功率", which is whole-Mac load. The two would be one
            // word apart in a picker whose whole job is telling them apart.
            return dashboardText("menu.metric.charge_power")
        case .chargeSpeed:
            return dashboardText("menu.metric.charge_speed")
        }
    }

    var icon: BatteryMetricIcon {
        switch self {
        case .runtime: return .runtime
        case .power: return .power
        case .temperature: return .temperature
        case .cycles: return .cycles
        case .health: return .health
        case .current: return .current
        case .chargingPower: return .charging
        case .chargeSpeed: return .chargeSpeed
        }
    }

    var symbol: String { icon.symbol }
}

/// Trend rows shown in the expanded menu-bar panel. Keeping this separate from
/// `MenuBarMetric` prevents non-chartable values from being persisted as live
/// trends while still giving the three supported series a stable saved order.
enum MenuBarTrendMetric: String, CaseIterable, Identifiable {
    case power
    case runtime
    case current

    var id: String { rawValue }

    var title: String {
        switch self {
        case .power:
            return dashboardText("shell.instant_power")
        case .runtime:
            return dashboardText("p.menu_time")
        case .current:
            return dashboardText("shell.current")
        }
    }

    var icon: BatteryMetricIcon {
        switch self {
        case .power: return .power
        case .runtime: return .runtime
        case .current: return .current
        }
    }
}

@Observable
final class MenuBarSettings {
    static let shared = MenuBarSettings()

    private static let secondaryMetricKey = "menuBar.secondaryMetric"
    private static let visibleMetricsKey = "menuBar.visibleMetrics"
    private static let visibleTrendMetricsKey = "menuBar.visibleTrendMetrics"
    static let defaultVisibleMetrics: [MenuBarMetric] = [
        .runtime, .power, .temperature, .cycles, .health
    ]
    static let defaultVisibleTrendMetrics: [MenuBarTrendMetric] = [
        .power, .runtime, .current
    ]

    @ObservationIgnored private let defaults: UserDefaults
    private(set) var secondaryMetric: MenuBarMetric
    private(set) var visibleMetrics: [MenuBarMetric]
    private(set) var visibleTrendMetrics: [MenuBarTrendMetric]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        secondaryMetric = defaults.string(forKey: Self.secondaryMetricKey)
            .flatMap(MenuBarMetric.init(rawValue:)) ?? .runtime

        let savedIDs = defaults.array(forKey: Self.visibleMetricsKey) as? [String]
        let savedMetrics = savedIDs?.compactMap(MenuBarMetric.init(rawValue:)) ?? []
        visibleMetrics = Self.uniqued(savedMetrics)
        if savedIDs == nil {
            visibleMetrics = Self.defaultVisibleMetrics
        }

        let savedTrendIDs = defaults.array(forKey: Self.visibleTrendMetricsKey) as? [String]
        let savedTrendMetrics = savedTrendIDs?.compactMap(MenuBarTrendMetric.init(rawValue:)) ?? []
        visibleTrendMetrics = Self.uniqued(savedTrendMetrics)
        if savedTrendIDs == nil {
            visibleTrendMetrics = Self.defaultVisibleTrendMetrics
        }
    }

    func selectSecondaryMetric(_ metric: MenuBarMetric) {
        guard secondaryMetric != metric else { return }
        secondaryMetric = metric
        defaults.set(metric.rawValue, forKey: Self.secondaryMetricKey)
    }

    func setVisible(_ metric: MenuBarMetric, visible: Bool) {
        if visible {
            guard !visibleMetrics.contains(metric) else { return }
            visibleMetrics.append(metric)
        } else {
            guard let index = visibleMetrics.firstIndex(of: metric) else { return }
            visibleMetrics.remove(at: index)
        }
        persistVisibleMetrics()
    }

    func move(_ metric: MenuBarMetric, by offset: Int) {
        guard offset != 0,
              let source = visibleMetrics.firstIndex(of: metric) else { return }
        let destination = min(max(0, source + offset), visibleMetrics.count - 1)
        guard source != destination else { return }
        let moved = visibleMetrics.remove(at: source)
        visibleMetrics.insert(moved, at: destination)
        persistVisibleMetrics()
    }

    /// Reorders a visible metric by dropping it on the row currently occupying
    /// `destination`. This is the persistence boundary used by the inline drag
    /// handle in the menu-bar panel.
    func move(_ metric: MenuBarMetric, to destination: Int) {
        guard let source = visibleMetrics.firstIndex(of: metric) else { return }
        let boundedDestination = min(max(0, destination), visibleMetrics.count - 1)
        guard source != boundedDestination else { return }
        let moved = visibleMetrics.remove(at: source)
        visibleMetrics.insert(moved, at: min(boundedDestination, visibleMetrics.count))
        persistVisibleMetrics()
    }

    func setTrendVisible(_ metric: MenuBarTrendMetric, visible: Bool) {
        if visible {
            guard !visibleTrendMetrics.contains(metric) else { return }
            visibleTrendMetrics.append(metric)
        } else {
            guard let index = visibleTrendMetrics.firstIndex(of: metric) else { return }
            visibleTrendMetrics.remove(at: index)
        }
        persistVisibleTrendMetrics()
    }

    func moveTrend(_ metric: MenuBarTrendMetric, to destination: Int) {
        guard let source = visibleTrendMetrics.firstIndex(of: metric) else { return }
        let boundedDestination = min(max(0, destination), visibleTrendMetrics.count - 1)
        guard source != boundedDestination else { return }
        let moved = visibleTrendMetrics.remove(at: source)
        visibleTrendMetrics.insert(moved, at: min(boundedDestination, visibleTrendMetrics.count))
        persistVisibleTrendMetrics()
    }

    func resetTrends() {
        visibleTrendMetrics = Self.defaultVisibleTrendMetrics
        persistVisibleTrendMetrics()
    }

    func reset() {
        secondaryMetric = .runtime
        visibleMetrics = Self.defaultVisibleMetrics
        visibleTrendMetrics = Self.defaultVisibleTrendMetrics
        defaults.set(secondaryMetric.rawValue, forKey: Self.secondaryMetricKey)
        persistVisibleMetrics()
        persistVisibleTrendMetrics()
    }

    private func persistVisibleMetrics() {
        defaults.set(visibleMetrics.map(\.rawValue), forKey: Self.visibleMetricsKey)
    }

    private func persistVisibleTrendMetrics() {
        defaults.set(visibleTrendMetrics.map(\.rawValue), forKey: Self.visibleTrendMetricsKey)
    }

    private static func uniqued(_ metrics: [MenuBarMetric]) -> [MenuBarMetric] {
        var seen = Set<MenuBarMetric>()
        return metrics.filter { seen.insert($0).inserted }
    }

    private static func uniqued(_ metrics: [MenuBarTrendMetric]) -> [MenuBarTrendMetric] {
        var seen = Set<MenuBarTrendMetric>()
        return metrics.filter { seen.insert($0).inserted }
    }
}
