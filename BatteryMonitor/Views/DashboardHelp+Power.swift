import Foundation
import SwiftUI

extension DashboardHelp {

    static func power(_ s: DashboardMetricSnapshot) -> MetricHelpContent {
        let directPower = s.detail.systemPowerWatts
        let telemetryPower = s.detail.systemLoad == 0
            ? nil
            : Double(abs(s.detail.systemLoad)) / 1000.0
        let currentVoltagePower = abs(Double(s.data.amperage)) / 1000.0 * s.data.voltage
        let selectedSource: String
        if directPower.isFinite, directPower > 0 {
            selectedSource = "BatteryData.SystemPower"
        } else if telemetryPower != nil {
            selectedSource = "PowerTelemetryData.SystemLoad ÷ 1000"
        } else {
            selectedSource = "|Amperage| ÷ 1000 × Voltage"
        }

        return content(
            id: "power.current",
            title: dashboardText("p.priority_power"),
            summary: dashboardText("p.help_summary_power"),
            result: LNum("%.2f W", s.currentPowerWatts),
            fields: [
                field("BatteryData.SystemPower", f(s.detail.systemPowerWatts), "W"),
                field("PowerTelemetryData.SystemLoad", s.detail.systemLoad, "mW"),
                field("Voltage", f(s.data.voltage), "V"),
                field("Amperage", s.data.amperage, "mA"),
                field("AccumulatedSystemLoad", s.detail.accumulatedSystemLoad, "raw"),
                field("SystemLoadAccumulatorCount", s.detail.systemLoadAccumulatorCount, "samples"),
            ],
            formula: "1. SystemPower, when valid\n2. |SystemLoad| ÷ 1000\n3. |Amperage| ÷ 1000 × Voltage\naveragePower = AccumulatedSystemLoad ÷ sampleCount ÷ 1000",
            substitution: "SystemPower = \(f(directPower)) W\n|SystemLoad| ÷ 1000 = \(f(telemetryPower)) W\n|\(s.data.amperage)| ÷ 1000 × \(f(s.data.voltage)) = \(f(currentVoltagePower)) W\nSelected: \(selectedSource) → \(f(s.currentPowerWatts)) W\n\(optional(s.detail.accumulatedSystemLoad)) ÷ \(optional(s.detail.systemLoadAccumulatorCount)) ÷ 1000 = \(f(s.detail.averageTelemetryPowerWatts)) W",
            source: "IOKit BatteryData.SystemPower and PowerTelemetryData. The UI labels fallbacks instead of pretending every source is identical.",
            readAt: s.rawFieldReadAt,
            trend: MetricHelpTrend(
                title: trendTitle(),
                latestText: LNum("%.2f W", s.currentPowerWatts),
                note: dashboardText(
                    "p.trend_note_power"
                ),
                unit: "W",
                tint: AppTheme.chargingCyan,
                points: trendPoints(s) { $0.power > 0 ? $0.power : nil },
                waitingText: trendWaiting()
            )
        )
    }

    static func adapterPower(_ s: DashboardMetricSnapshot) -> MetricHelpContent {
        let detail = s.detail
        let watts = detail.adapterWatts > 0 ? detail.adapterWatts : s.data.chargerWattage
        let rawWatts: Int? = watts > 0 ? watts : nil
        let rawVoltage: Int? = detail.adapterVoltage > 0 ? detail.adapterVoltage : nil
        let rawCurrent: Int? = detail.adapterCurrent > 0 ? detail.adapterCurrent : nil
        let rawSystemPowerIn: Int? = detail.systemPowerIn > 0 ? detail.systemPowerIn : nil
        let rawProfileCount: Int? = detail.usbHvcMenu.isEmpty ? nil : detail.usbHvcMenu.count
        let voltage = rawVoltage.map { Double($0) / 1000.0 }
        let current = rawCurrent.map { Double($0) / 1000.0 }
        let calculatedWatts = voltage.flatMap { voltage in current.map { voltage * $0 } }
        let displayedWatts = watts > 0 ? "\(watts) W" : calculatedWatts.map { LNum("%.1f W", $0) } ?? "—"
        let connected = s.data.isOnAC || detail.hasAdapterData
        let negotiated = voltage != nil && current != nil
        let adapterType = InsightEngine.localizedAdapterType(
            detail.adapterDescription,
            hasPD: !detail.usbHvcMenu.isEmpty || negotiated
        )
        let stateTitle: String
        let stateDetail: String
        if !connected {
            stateTitle = dashboardText("p.adapter_status_disconnected")
            stateDetail = dashboardText("p.adapter_status_disconnected_note")
        } else if negotiated {
            stateTitle = dashboardText("p.adapter_status_negotiated")
            stateDetail = "\(adapterType) · \(LNum("%.1f V", voltage ?? 0)) / \(LNum("%.2f A", current ?? 0))"
        } else {
            stateTitle = dashboardText("p.adapter_status_waiting")
            stateDetail = adapterType
        }

        let equation = if let voltage, let current, let calculatedWatts {
            "\(LNum("%.1f V", voltage)) × \(LNum("%.2f A", current)) = \(LNum("%.1f W", calculatedWatts))"
        } else {
            dashboardText("p.adapter_equation_waiting")
        }
        let equationNote: String
        if let calculatedWatts, watts > 0 {
            let tolerance = max(1.0, Double(watts) * 0.03)
            equationNote = abs(calculatedWatts - Double(watts)) <= tolerance
                ? dashboardText("p.adapter_contract_match")
                : dashboardText("p.adapter_contract_diff")
        } else {
            equationNote = dashboardText("p.adapter_contract_partial")
        }

        // Derived from Mac load + charge into the battery, not from
        // SystemPowerIn. The old series dropped every sample where SystemPowerIn
        // read 0 — and that field is measured going to 0 while plugged in and
        // drawing power, so the whole chart vanished for minutes at a time.
        let inputTrendPoints = trendPoints(s) { adapterOutputWatts($0) }
        let currentInput = connected
            ? (s.adapterOutputPowerWatts ?? inputTrendPoints.last?.value)
            : nil
        return content(
            id: "power.adapter",
            title: dashboardText("p.adapter_status_title"),
            summary: dashboardText(
                "p.help_summary_adapter_power"
            ),
            result: displayedWatts,
            // The adapter identity block appears and disappears with the cable,
            // not on the gauge's beat (measured: these fields cleared within 2 s
            // of an unplug), so they are stamped with our own read time.
            fields: [
                field("AdapterDetails.Watts", rawWatts, "W",
                      updateClass: .eventDriven, readAt: .ourRead(s.data.lastUpdated)),
                field("AdapterDetails.AdapterVoltage", rawVoltage, "mV",
                      updateClass: .eventDriven, readAt: .ourRead(s.data.lastUpdated)),
                field("AdapterDetails.Current", rawCurrent, "mA",
                      updateClass: .eventDriven, readAt: .ourRead(s.data.lastUpdated)),
                field("Derived.NegotiatedPower", f(calculatedWatts), "W",
                      updateClass: .eventDriven, readAt: .ourRead(s.data.lastUpdated)),
                field("PowerTelemetryData.SystemPowerIn", rawSystemPowerIn, "mW"),
                field("AdapterDetails.UsbHvcMenu", rawProfileCount, "profiles",
                      updateClass: .eventDriven, readAt: .ourRead(s.data.lastUpdated)),
                field("AdapterDetails.Description", detail.adapterDescription, "", "",
                      updateClass: .eventDriven, readAt: .ourRead(s.data.lastUpdated)),
            ],
            formula: "voltageV = AdapterVoltage ÷ 1000\ncurrentA = Current ÷ 1000\nnegotiatedPowerW = voltageV × currentA\nactualOutputW = macLoadW + max(batteryPowerW, 0)",
            substitution: "\(optional(rawVoltage)) ÷ 1000 = \(f(voltage)) V\n\(optional(rawCurrent)) ÷ 1000 = \(f(current)) A\n\(f(voltage)) × \(f(current)) = \(f(calculatedWatts)) W\n\(f(s.currentPowerWatts)) + \(f(max(0, s.batteryPowerWatts ?? 0))) = \(f(currentInput)) W\nSystemPowerIn (reference only): \(optional(rawSystemPowerIn)) mW",
            source: dashboardText(
                "p.help_source_adapter_power"
            ),
            readAt: s.rawFieldReadAt,
            powerContract: MetricPowerContract(
                stateTitle: stateTitle,
                stateDetail: stateDetail,
                isConnected: connected,
                isNegotiated: negotiated,
                voltageLabel: dashboardText("p.adapter_voltage"),
                voltageText: voltage.map { LNum("%.1f V", $0) } ?? "—",
                currentLabel: dashboardText("p.adapter_current"),
                currentText: current.map { LNum("%.2f A", $0) } ?? "—",
                powerLabel: dashboardText("p.adapter_rated_power"),
                powerText: displayedWatts,
                equationText: equation,
                equationNote: equationNote,
                trendTitle: dashboardText("p.adapter_input_trend"),
                trendValue: currentInput.map { LNum("%.1f W", $0) } ?? "—",
                trendNote: dashboardText("p.adapter_input_trend_note"),
                trendPoints: inputTrendPoints,
                ceilingWatts: watts > 0 ? Double(watts) : calculatedWatts
            )
        )
    }

    static func chargingPower(_ s: DashboardMetricSnapshot) -> MetricHelpContent {
        let voltage = s.voltageVolts
        let currentMilliamps = s.batteryChargingCurrentMilliamps
        let currentAmps = currentMilliamps.map { Double($0) / 1000.0 }
        let watts = s.batteryChargingPowerWatts
        let displayedWatts = watts.map { $0 < 0.05 ? "0 W" : LNum("%.1f W", $0) } ?? "—"
        let rawVoltage = s.detail.packVoltage > 0 ? s.detail.packVoltage : nil
        let rawSmoothedCurrent: Int? = if s.detail.presentRawFields.contains("Amperage") {
            s.detail.smoothedAmperage
        } else if s.data.amperage != 0 {
            s.data.amperage
        } else {
            nil
        }
        return content(
            id: "power.charging",
            title: dashboardText("shell.charge_power"),
            summary: dashboardText(
                "p.help_summary_charging_power"
            ),
            result: displayedWatts,
            fields: [
                field("AppleRawBatteryVoltage", s.detail.appleRawBatteryVoltage, "mV"),
                field("Voltage", s.detail.voltageRaw, "mV"),
                field("Derived.BatteryPackVoltage", rawVoltage, "mV"),
                field("InstantAmperage", s.detail.presentRawFields.contains("InstantAmperage") ? s.detail.instantAmperage : nil, "mA"),
                field("Amperage", rawSmoothedCurrent, "mA"),
                field("IsCharging", s.data.isCharging ? "true" : "false"),
            ],
            formula: "batteryVoltageV = batteryVoltageMillivolts ÷ 1000\nbatteryChargingCurrentA = IsCharging ? max(batteryCurrentMilliamps, 0) ÷ 1000 : 0\nbatteryChargingPowerW = batteryVoltageV × batteryChargingCurrentA",
            substitution: "\(optional(rawVoltage)) ÷ 1000 = \(LNum("%.3f V", voltage))\nIsCharging = \(s.data.isCharging) → \(optional(currentMilliamps)) ÷ 1000 = \(f(currentAmps)) A\n\(LNum("%.3f", voltage)) × \(f(currentAmps)) = \(displayedWatts)",
            source: dashboardText(
                "p.help_source_charging_power"
            ),
            readAt: s.rawFieldReadAt,
            trend: MetricHelpTrend(
                title: trendTitle(),
                latestText: displayedWatts,
                note: dashboardText(
                    "p.trend_note_charge"
                ),
                unit: "W",
                tint: AppTheme.batteryGreen,
                points: trendPoints(s) { chargeWatts($0) },
                waitingText: trendWaiting()
            )
        )
    }

    static func adapterOutputPower(_ s: DashboardMetricSnapshot) -> MetricHelpContent {
        let detail = s.detail
        let watts = s.adapterOutputPowerWatts
        let displayedWatts = watts.map { LNum("%.1f W", $0) } ?? "—"
        return content(
            id: "power.adapter-output",
            title: dashboardText("shell.adapter_output_power"),
            summary: dashboardText(
                "p.help_summary_adapter_output_power"
            ),
            result: displayedWatts,
            fields: [
                field(
                    "PowerTelemetryData.SystemPowerIn",
                    detail.presentRawFields.contains("PowerTelemetryData.SystemPowerIn") ? detail.systemPowerIn : nil,
                    "mW",
                    dashboardText("p.raw_power_in_explain")
                ),
                field(
                    "PowerTelemetryData.VoltageIn",
                    detail.presentRawFields.contains("PowerTelemetryData.VoltageIn") ? detail.systemVoltageIn : nil,
                    "mV",
                    dashboardText("p.raw_voltage_in_explain")
                ),
                field(
                    "PowerTelemetryData.CurrentIn",
                    detail.presentRawFields.contains("PowerTelemetryData.CurrentIn") ? detail.systemCurrentIn : nil,
                    "mA",
                    dashboardText("p.raw_current_in_explain")
                ),
                field(
                    "PowerTelemetryData.AdapterEfficiencyLoss",
                    detail.presentRawFields.contains("PowerTelemetryData.AdapterEfficiencyLoss") ? detail.adapterEfficiencyLoss : nil,
                    "mW",
                    dashboardText("p.raw_adapter_loss_explain")
                ),
            ],
            formula: "adapterOutputPowerW = macLoadW + max(batteryPowerW, 0)",
            substitution: "\(f(s.currentPowerWatts)) + \(f(max(0, s.batteryPowerWatts ?? 0))) = \(displayedWatts)\nSystemPowerIn (reference only): \(optional(detail.presentRawFields.contains("PowerTelemetryData.SystemPowerIn") ? detail.systemPowerIn : nil)) mW",
            source: dashboardText(
                "p.help_source_adapter_output_power"
            ),
            readAt: s.rawFieldReadAt,
            trend: MetricHelpTrend(
                title: trendTitle(),
                latestText: displayedWatts,
                note: dashboardText(
                    "p.trend_note_adapter_output"
                ),
                unit: "W",
                tint: AppTheme.chargingCyan,
                points: trendPoints(s) { adapterOutputWatts($0) },
                waitingText: trendWaiting()
            )
        )
    }

}
