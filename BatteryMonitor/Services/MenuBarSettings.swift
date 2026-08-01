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

    var id: String { rawValue }

    var title: String {
        switch self {
        case .runtime:
            return dashboardText("menu.metric.runtime", fallback: "剩余时间")
        case .power:
            return dashboardText("menu.metric.power", fallback: "当前功率")
        case .temperature:
            return dashboardText("menu.metric.temperature", fallback: "电池温度")
        case .cycles:
            return dashboardText("menu.metric.cycles", fallback: "循环次数")
        case .health:
            return dashboardText("menu.metric.health", fallback: "健康度")
        case .current:
            return dashboardText("menu.metric.current", fallback: "当前电流")
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
        }
    }

    var symbol: String { icon.symbol }
}

@Observable
final class MenuBarSettings {
    static let shared = MenuBarSettings()

    private static let secondaryMetricKey = "menuBar.secondaryMetric"
    private static let visibleMetricsKey = "menuBar.visibleMetrics"
    static let defaultVisibleMetrics: [MenuBarMetric] = [
        .runtime, .power, .temperature, .cycles, .health
    ]

    @ObservationIgnored private let defaults: UserDefaults
    private(set) var secondaryMetric: MenuBarMetric
    private(set) var visibleMetrics: [MenuBarMetric]

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

    func reset() {
        secondaryMetric = .runtime
        visibleMetrics = Self.defaultVisibleMetrics
        defaults.set(secondaryMetric.rawValue, forKey: Self.secondaryMetricKey)
        persistVisibleMetrics()
    }

    private func persistVisibleMetrics() {
        defaults.set(visibleMetrics.map(\.rawValue), forKey: Self.visibleMetricsKey)
    }

    private static func uniqued(_ metrics: [MenuBarMetric]) -> [MenuBarMetric] {
        var seen = Set<MenuBarMetric>()
        return metrics.filter { seen.insert($0).inserted }
    }
}
