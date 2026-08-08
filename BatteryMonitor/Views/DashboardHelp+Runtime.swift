import Foundation
import SwiftUI

extension DashboardHelp {
    static func runtime(_ s: DashboardMetricSnapshot) -> MetricHelpContent {
        let detail = s.detail
        let systemMinutes = s.systemRuntimeMinutes
        let stableMinutes = s.stableRuntimeMinutes
        let currentMinutes = s.currentLoadRuntimeMinutes
        let referenceMinutes = currentMinutes ?? stableMinutes
        let hasLiveSystemReading = !s.data.isOnAC
            && s.data.timeRemainingMinutes.map(RuntimeSample.isValid(minutes:)) == true
        let systemNote: String
        if systemMinutes == nil, let referenceMinutes {
            let key = s.data.isOnAC
                ? "p.runtime_system_on_ac_estimate"
                : "p.runtime_system_unavailable_estimate"
            systemNote = dashboardText(
                key,
                replacements: ["time": runtime(referenceMinutes)]
            )
        } else if systemMinutes == nil {
            let key = s.data.isOnAC
                ? "p.runtime_system_on_ac_note"
                : "p.runtime_system_unavailable_note"
            systemNote = dashboardText(key)
        } else if hasLiveSystemReading {
            // Lead with what the number means, then how it is kept up to date:
            // the mechanism alone left readers unable to tell the three cards
            // apart, or to know when to distrust one.
            let meaning = dashboardText(
                "p.runtime_system_meaning"
            )
            systemNote = meaning + " · " + dashboardText(
                "p.runtime_system_read_live",
                replacements: [
                    "time": runtimeReadTimestamp(s.data.lastUpdated),
                    "interval": "\(MetricFieldFreshness.gaugeRefreshSeconds)",
                ]
            )
        } else {
            systemNote = dashboardText("p.chart_waiting")
        }

        let systemValue = systemMinutes.map(runtime)
            ?? dashboardText("p.runtime_unavailable")

        // The two derived rows are not live readings: state which sample they
        // were computed from and how often that sample is refreshed.
        var stableNote = dashboardText(
            "p.runtime_stable_note"
        )
        if let stableSampleTime = s.latestStablePowerSampleTime {
            stableNote += " · " + dashboardText(
                "p.runtime_stable_read",
                replacements: [
                    "time": runtimeReadTimestamp(stableSampleTime),
                    "samples": "\(s.recentStablePowerSamples.count)",
                ]
            )
        }

        let currentAge = s.currentPowerAgeSeconds
        var currentNote = dashboardText(
            "p.runtime_current_note"
        )
        let isCurrentSampleStale = currentAge > 120
        currentNote += " · " + dashboardText(
            isCurrentSampleStale ? "p.runtime_current_read_stale" : "p.runtime_current_read",
            replacements: [
                // Must be the same clock the age is measured from, otherwise the
                // timestamp and "N 秒前" in one sentence contradict each other.
                // A stale sample can predate a sleep, so that variant keeps the date.
                "time": runtimeReadTimestamp(s.rawFieldReadAt.at, includeDate: isCurrentSampleStale),
                "age": "\(currentAge)",
            ]
        )

        return content(
            id: "runtime.comparison",
            title: dashboardText("p.runtime_compare_title"),
            summary: dashboardText("p.runtime_compare_summary"),
            result: systemValue,
            fields: [
                runtimeRawField("TimeRemaining", detail.timeRemainingRaw, onAC: s.data.isOnAC),
                runtimeRawField("AvgTimeToEmpty", detail.avgTimeToEmpty, onAC: s.data.isOnAC),
                field("ModelDesignEnergy", f(s.designEnergyWh), "Wh", updateClass: .modelSpec),
                field("AppleRawCurrentCapacity", s.currentCapacity, "mAh"),
                field("DesignCapacity", s.designCapacity, "mAh"),
                // Stamped from the newest sample feeding the median, not from
                // this poll: the window is up to ten minutes wide. Named for the
                // window rather than "10m" because five samples are enough, so
                // the span can be much shorter than ten minutes.
                field("Derived.StableWindowMedianPower", f(s.stablePowerWatts), "W",
                      readAt: s.latestStablePowerSampleTime.map(MetricReadStamp.ourRead)),
                field("Derived.StableWindowSamples", s.recentStablePowerSamples.count, "",
                      readAt: s.latestStablePowerSampleTime.map(MetricReadStamp.ourRead)),
                field("BatteryData.SystemPower", f(s.currentPowerWatts), "W"),
                // This row's value already is the read age; a second age next to
                // it would only contradict itself as the clock ticks.
                field("Derived.CurrentPowerSampleAge", s.currentPowerAgeSeconds, "s",
                      updateClass: .untimed),
            ],
            formula: "systemMinutes = onBattery ? (valid(TimeRemaining) ?? valid(AvgTimeToEmpty)) : unavailable\nremainingWh = designWh × currentCapacity ÷ designCapacity\nstableMinutes = remainingWh ÷ median(last10mPower) × 60\ncurrentLoadMinutes = remainingWh ÷ currentSystemPower × 60",
            substitution: "system: \(runtimeRawValue(detail.timeRemainingRaw)) / \(runtimeRawValue(detail.avgTimeToEmpty)) → \(systemValue)\nremaining: \(f(s.designEnergyWh)) × \(s.currentCapacity) ÷ \(s.designCapacity) = \(f(s.remainingEnergyWh)) Wh\nstable: \(f(s.remainingEnergyWh)) ÷ \(f(s.stablePowerWatts)) × 60 = \(optional(stableMinutes)) min\ncurrent: \(f(s.remainingEnergyWh)) ÷ \(f(s.currentPowerWatts)) × 60 = \(optional(currentMinutes)) min",
            source: dashboardText("p.runtime_compare_source"),
            readAt: s.rawFieldReadAt,
            results: [
                MetricHelpResult(
                    id: "runtime.system",
                    title: dashboardText("p.runtime_system_label"),
                    value: systemValue,
                    note: systemNote,
                    style: .primary
                ),
                MetricHelpResult(
                    id: "runtime.stable",
                    title: dashboardText("p.runtime_stable_label"),
                    value: runtime(stableMinutes),
                    note: stableNote,
                    style: .stable
                ),
                MetricHelpResult(
                    id: "runtime.current-load",
                    title: dashboardText("p.runtime_current_label"),
                    value: runtime(currentMinutes),
                    note: currentNote,
                    style: .current
                ),
            ]
        )
    }

    static func officialBenchmark(_ s: DashboardMetricSnapshot, specification spec: BatteryModelSpecification) -> MetricHelpContent {
        let impliedPower = spec.designEnergyWh / max(spec.officialWebHours, 0.1)
        let sameLoad = (s.currentFullEnergyWh ?? 0) / impliedPower
        return content(
            id: "runtime.official-benchmark",
            title: dashboardText("p.runtime_audit_tag"),
            summary: dashboardText("p.audit_conditions"),
            result: LNum("%.0f h WEB · %.0f h VIDEO", spec.officialWebHours, spec.officialVideoHours),
            fields: [
                field("hw.model", s.modelIdentifier, "", updateClass: .modelSpec),
                field("Apple design energy", f(spec.designEnergyWh), "Wh", updateClass: .modelSpec),
                field("Apple wireless web", f(spec.officialWebHours), "h", updateClass: .modelSpec),
                field("Apple streaming video", f(spec.officialVideoHours), "h", updateClass: .modelSpec),
                field("AppleRawMaxCapacity", s.fullChargeCapacity, "mAh"),
                field("DesignCapacity", s.designCapacity, "mAh"),
            ],
            formula: "officialImpliedPower = designEnergy ÷ officialRuntime\ncurrentFullWh = designWh × FCC ÷ DesignCapacity\nsameLoadRuntime = currentFullWh ÷ officialImpliedPower",
            substitution: "\(f(spec.designEnergyWh)) ÷ \(f(spec.officialWebHours)) = \(f(impliedPower)) W\n\(f(s.currentFullEnergyWh)) ÷ \(f(impliedPower)) = \(f(sameLoad)) h",
            source: "\(spec.sourceName) · \(spec.sourceURL.absoluteString) · controlled Apple test. Current capacity and power come from this Mac's IOKit fields.",
            readAt: s.rawFieldReadAt,
        )
    }

    static func runtimeHistory(_ s: DashboardMetricSnapshot, isForecast: Bool) -> MetricHelpContent {
        if isForecast {
            return content(
                id: "runtime.history.forecast",
                title: dashboardText("p.unplug_trend"),
                summary: dashboardText("p.forecast_only"),
                result: runtime(s.unplugEstimateMinutes ?? 0),
                fields: [field("remainingEnergy", f(s.remainingEnergyWh), "Wh"), field("SystemPower", f(s.currentPowerWatts), "W")],
                formula: "unplugRuntime = remainingEnergy ÷ currentPower",
                substitution: "\(f(s.remainingEnergyWh)) Wh ÷ \(f(s.currentPowerWatts)) W = \(f(Double(s.unplugEstimateMinutes ?? 0) / 60)) h",
                source: "Derived forecast while connected to power; dashed and excluded from system history.",
                readAt: s.rawFieldReadAt
            )
        }
        return content(
            id: "runtime.history.system",
            title: dashboardText("p.remaining_trend"),
            summary: dashboardText("p.help_summary_time_history"),
            result: runtime(s.data.timeRemainingMinutes ?? 0),
            fields: [runtimeRawField("TimeRemaining", s.detail.timeRemainingRaw, onAC: s.data.isOnAC),
                     runtimeRawField("AvgTimeToEmpty", s.detail.avgTimeToEmpty, onAC: s.data.isOnAC)],
            formula: dashboardText("p.help_direct"),
            substitution: "validMinutes(TimeRemaining) → history point; minimum interval = 56 s",
            source: "AppleSmartBattery runtime fields; sentinel values and duplicate sub-56-second samples are rejected.",
            readAt: s.rawFieldReadAt,
        )
    }

}
