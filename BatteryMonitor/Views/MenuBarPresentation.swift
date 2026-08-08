import SwiftUI

/// One definition shared by the menu-bar label and its expanded panel.
/// Battery mode always prefers the macOS time estimate; AC mode never reuses a
/// stale gauge value and may instead show the explicitly labelled unplug estimate.
struct MenuBarPresentation {
    let data: BatteryData
    /// Resolved once per gauge publish by `BatteryService`, not here — this type is
    /// rebuilt on every menu-bar redraw. nil means there is nothing honest to
    /// show (not charging, already full, or no usable reading).
    var chargeSpeed: ChargeSpeedEstimate? = nil

    var isLoaded: Bool {
        data.percent > 0 || data.designCapacity > 0 || !data.batteryModel.isEmpty
    }

    var isForecast: Bool {
        data.isOnAC && data.unplugEstimateMinutes != nil
    }

    var runtimeMinutes: Int? {
        data.isOnAC ? data.unplugEstimateMinutes : data.timeRemainingMinutes
    }

    var percentText: String {
        isLoaded ? "\(max(0, min(100, data.percent)))%" : "—%"
    }

    var runtimeText: String {
        Self.durationText(runtimeMinutes)
    }

    var timeTitle: String {
        dashboardText(isForecast ? "p.menu_unplug" : "p.menu_time")
    }

    var sourceText: String {
        if !data.isOnAC, runtimeMinutes != nil {
            return dashboardText("p.menu_direct")
        }
        if isForecast {
            return dashboardText("p.menu_forecast")
        }
        return dashboardText("p.menu_waiting")
    }

    var chargeFraction: Double {
        Double(max(0, min(100, data.percent))) / 100
    }

    var healthPercent: Double {
        max(0, min(100, data.systemHealthPercent ?? Double(data.maxCapacityPercent)))
    }

    var healthText: String { LNum("%.1f%%", healthPercent) }
    var powerText: String { LNum("%.1f W", max(0, data.currentPowerWatts)) }
    var temperatureText: String { LNum("%.1f °C", data.temperatureCelsius) }

    /// Charging power shares its formatter with the overview card so the two can
    /// never print the same watts differently. Building a snapshot here is cheap:
    /// it is a struct of stored references and derives nothing until asked.
    private var chargingSnapshot: DashboardMetricSnapshot {
        DashboardMetricSnapshot(data: data, realtimeData: [])
    }

    var chargingPowerText: String { chargingSnapshot.chargingPowerText }

    /// The two horizons the charge-speed metric is defined over.
    static let chargeSpeedHorizons: (short: Double, long: Double) = (5, 10)

    /// "+4%/5m · +9%/10m". nil when there is no estimate, so callers fall back to
    /// the bare percentage instead of printing "+0%".
    func chargeSpeedText(separator: String) -> String? {
        guard let chargeSpeed else { return nil }
        let short = chargeSpeed.gainPercent(overMinutes: Self.chargeSpeedHorizons.short)
        let long = chargeSpeed.gainPercent(overMinutes: Self.chargeSpeedHorizons.long)
        return LNum("+%.0f%%/%.0fm", short, Self.chargeSpeedHorizons.short)
            + separator
            + LNum("+%.0f%%/%.0fm", long, Self.chargeSpeedHorizons.long)
    }

    func title(for metric: MenuBarMetric) -> String {
        metric == .runtime ? timeTitle : metric.title
    }

    func value(for metric: MenuBarMetric) -> String {
        switch metric {
        case .runtime: return runtimeText
        case .power: return powerText
        case .temperature: return temperatureText
        case .cycles: return data.cycleCount.formatted()
        case .health: return healthText
        case .current: return LNum("%.2f A", Double(data.amperage) / 1000)
        case .chargingPower: return chargingPowerText
        case .chargeSpeed: return chargeSpeedText(separator: " · ") ?? "—"
        }
    }

    func statusValue(for metric: MenuBarMetric) -> String? {
        switch metric {
        case .runtime:
            guard runtimeMinutes != nil else { return nil }
            if isForecast {
                return "\(dashboardText("p.menu_unplug_short")) \(runtimeText)"
            }
            return runtimeText
        case .power:
            return isLoaded ? LNum("%.1fW", max(0, data.currentPowerWatts)) : nil
        case .temperature:
            return isLoaded ? LNum("%.1f°C", data.temperatureCelsius) : nil
        case .cycles:
            return isLoaded ? "\(data.cycleCount)×" : nil
        case .health:
            return isLoaded ? LNum("%.0f%%", healthPercent) : nil
        case .current:
            return isLoaded ? LNum("%.2fA", Double(data.amperage) / 1000) : nil
        case .chargingPower:
            // 0 W is the honest reading with nothing charging, and a fixed-width
            // one keeps the menu bar from shuffling on every plug event.
            return isLoaded ? chargingSnapshot.chargingPowerCompactText : nil
        case .chargeSpeed:
            return isLoaded ? chargeSpeedText(separator: "·") : nil
        }
    }

    func menuBarText(secondaryMetric: MenuBarMetric) -> String {
        guard let secondary = statusValue(for: secondaryMetric) else { return percentText }
        return "\(percentText) (\(secondary))"
    }

    /// A menu choice must explain both what is being selected and the exact
    /// text that will appear in the menu bar after selection.
    func choicePreviewText(for metric: MenuBarMetric) -> String {
        "\(metric.title)  ·  \(menuBarText(secondaryMetric: metric))"
    }

    static func durationText(_ minutes: Int?) -> String {
        guard let minutes, minutes > 0 else { return "—" }
        return String(format: "%dh %02dm", minutes / 60, minutes % 60)
    }
}
