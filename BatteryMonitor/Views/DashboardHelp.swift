import Foundation
import SwiftUI

// MARK: - Question-mark definitions and lowest-level formulas

enum DashboardHelp {
    static func runtime(_ s: DashboardMetricSnapshot) -> MetricHelpContent {
        let detail = s.detail
        let systemMinutes = s.systemRuntimeMinutes
        let stableMinutes = s.stableRuntimeMinutes
        let currentMinutes = s.currentLoadRuntimeMinutes
        let referenceMinutes = currentMinutes ?? stableMinutes
        let hasLiveSystemReading = !s.data.isOnAC
            && s.data.timeRemainingMinutes.map(RuntimeSample.isValid(minutes:)) == true
        let validFallbackSample = s.systemRuntimeFallbackSample.flatMap { sample in
            RuntimeSample.isValid(minutes: sample.minutesRemaining) ? sample : nil
        }
        let systemReadTime = hasLiveSystemReading
            ? s.data.lastUpdated
            : validFallbackSample?.timestamp
        let systemNote: String
        if systemMinutes == nil, let referenceMinutes {
            systemNote = dashboardText(
                "p.runtime_system_unavailable_estimate",
                fallback: "按实测功耗预计可用 {time} · 拔掉电源后约等 10 分钟再查看系统时间",
                replacements: ["time": runtime(referenceMinutes)]
            )
        } else if systemMinutes == nil {
            systemNote = dashboardText(
                "p.runtime_system_unavailable_note",
                fallback: "暂无可靠的系统时间 · 拔掉电源后约等 10 分钟再查看"
            )
        } else if let systemReadTime {
            // Lead with what the number means, then how it is kept up to date:
            // the mechanism alone left readers unable to tell the three cards
            // apart, or to know when to distrust one.
            let meaning = dashboardText(
                "p.runtime_system_meaning",
                fallback: "和菜单栏同一个数字。电量计按平均电流估算，负载突然变重后要过一两分钟才跟上"
            )
            let key = hasLiveSystemReading
                ? "p.runtime_system_read_live"
                : "p.runtime_system_read_last"
            let fallback = hasLiveSystemReading
                ? "TimeRemaining / AvgTimeToEmpty · 上次刷新 {time} · 电量计约 {interval} 秒刷新一次，每次有效读数存一条历史"
                : "TimeRemaining / AvgTimeToEmpty · 最近一次有效读数在 {time}，之后系统一直没给出有效值"
            systemNote = meaning + " · " + dashboardText(
                key,
                fallback: fallback,
                replacements: [
                    // A stale fallback sample can be hours or days old, so that
                    // variant keeps the date; live reads are always same-day and
                    // match the bare clock used by the field rows below.
                    "time": runtimeReadTimestamp(systemReadTime, includeDate: !hasLiveSystemReading),
                    "interval": "\(MetricFieldFreshness.gaugeRefreshSeconds)",
                ]
            )
        } else {
            systemNote = dashboardText("p.chart_waiting", fallback: "等待电量计给出续航预测")
        }

        let systemValue = systemMinutes.map(runtime)
            ?? dashboardText("p.runtime_unavailable", fallback: "不可用")

        // The two derived rows are not live readings: state which sample they
        // were computed from and how often that sample is refreshed.
        var stableNote = dashboardText(
            "p.runtime_stable_note",
            fallback: "回答「按最近这段时间的用法还能撑多久」：取最近 10 分钟功耗的中位数，一闪而过的高负载不会带偏它；至少要 5 个有效样本"
        )
        if let stableSampleTime = s.latestStablePowerSampleTime {
            stableNote += " · " + dashboardText(
                "p.runtime_stable_read",
                fallback: "最新样本读取于 {time}（窗口内 {samples} 个有效样本）· 每 10 秒采样一次",
                replacements: [
                    "time": runtimeReadTimestamp(stableSampleTime),
                    "samples": "\(s.recentStablePowerSamples.count)",
                ]
            )
        }

        let currentAge = s.currentPowerAgeSeconds
        var currentNote = dashboardText(
            "p.runtime_current_note",
            fallback: "回答「如果一直像现在这样用」：直接按此刻功耗换算，所以对负载变化最敏感，也最容易偏高或偏低；样本超过 120 秒就等新数据"
        )
        let isCurrentSampleStale = currentAge > 120
        currentNote += " · " + dashboardText(
            isCurrentSampleStale ? "p.runtime_current_read_stale" : "p.runtime_current_read",
            fallback: isCurrentSampleStale
                ? "上次读取于 {time}，已过 {age} 秒 · 每 10 秒刷新一次"
                : "读取于 {time}（{age} 秒前）· 每 10 秒刷新一次",
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
            title: dashboardText("p.runtime_compare_title", fallback: "三种续航口径"),
            summary: dashboardText("p.runtime_compare_summary", fallback: "主结果以 macOS 系统时间为准；下面两项是同一份剩余电量分别按稳健功耗和当前功耗换算的参考值。"),
            result: systemValue,
            fields: [
                runtimeRawField("TimeRemaining", detail.timeRemainingRaw, onAC: s.data.isOnAC),
                runtimeRawField("AvgTimeToEmpty", detail.avgTimeToEmpty, onAC: s.data.isOnAC),
                field("ModelDesignEnergy", f(s.designEnergyWh), "Wh", updateClass: .modelSpec),
                field("AppleRawCurrentCapacity", s.currentCapacity, "mAh"),
                field("DesignCapacity", s.designCapacity, "mAh"),
                // Stamped from the newest sample feeding the median, not from
                // this poll: the window is up to ten minutes wide.
                field("Derived.Recent10mMedianPower", f(s.stablePowerWatts), "W",
                      readAt: s.latestStablePowerSampleTime.map(MetricReadStamp.ourRead)),
                field("Derived.Recent10mValidSamples", s.recentStablePowerSamples.count, "",
                      readAt: s.latestStablePowerSampleTime.map(MetricReadStamp.ourRead)),
                field("BatteryData.SystemPower", f(s.currentPowerWatts), "W"),
                // This row's value already is the read age; a second age next to
                // it would only contradict itself as the clock ticks.
                field("Derived.CurrentPowerSampleAge", s.currentPowerAgeSeconds, "s",
                      updateClass: .untimed),
            ],
            formula: "systemMinutes = valid(TimeRemaining) ?? valid(AvgTimeToEmpty) ?? latestPersistedSystemSample\nremainingWh = designWh × currentCapacity ÷ designCapacity\nstableMinutes = remainingWh ÷ median(last10mPower) × 60\ncurrentLoadMinutes = remainingWh ÷ currentSystemPower × 60",
            substitution: "system: \(runtimeRawValue(detail.timeRemainingRaw)) / \(runtimeRawValue(detail.avgTimeToEmpty)); latest persisted \(runtimeRawValue(s.systemRuntimeFallbackSample?.minutesRemaining)) → \(systemValue)\nremaining: \(f(s.designEnergyWh)) × \(s.currentCapacity) ÷ \(s.designCapacity) = \(f(s.remainingEnergyWh)) Wh\nstable: \(f(s.remainingEnergyWh)) ÷ \(f(s.stablePowerWatts)) × 60 = \(optional(stableMinutes)) min\ncurrent: \(f(s.remainingEnergyWh)) ÷ \(f(s.currentPowerWatts)) × 60 = \(optional(currentMinutes)) min",
            source: dashboardText("p.runtime_compare_source", fallback: "macOS 系统时间来自 AppleSmartBattery；两项计算值由本机剩余能量和实测功耗推导，只作对照，不写入系统续航历史。"),
            readAt: s.rawFieldReadAt,
            results: [
                MetricHelpResult(
                    id: "runtime.system",
                    title: dashboardText("p.runtime_system_label", fallback: "macOS 系统时间"),
                    value: systemValue,
                    note: systemNote,
                    style: .primary
                ),
                MetricHelpResult(
                    id: "runtime.stable",
                    title: dashboardText("p.runtime_stable_label", fallback: "稳健估算"),
                    value: runtime(stableMinutes),
                    note: stableNote,
                    style: .stable
                ),
                MetricHelpResult(
                    id: "runtime.current-load",
                    title: dashboardText("p.runtime_current_label", fallback: "当前负载估算"),
                    value: runtime(currentMinutes),
                    note: currentNote,
                    style: .current
                ),
            ]
        )
    }

    static func stateOfCharge(_ s: DashboardMetricSnapshot) -> MetricHelpContent {
        content(
            id: "state-of-charge",
            title: dashboardText("p.system_charge", fallback: "macOS 电量"),
            summary: dashboardText("p.help_summary_soc", fallback: "这里与系统菜单栏采用同一用户口径。原始 mAh 只用于容量拆解，不拿来覆盖 macOS 的 0–100%。"),
            result: "\(s.data.percent)%",
            fields: [
                field("CurrentCapacity", s.detail.currentCapacityRaw, "%"),
                field("AppleRawCurrentCapacity", s.detail.appleRawCurrentCapacity, "mAh"),
                field("AppleRawMaxCapacity", s.detail.appleRawMaxCapacity, "mAh"),
            ],
            formula: dashboardText("p.help_direct", fallback: "无公式：直接读取系统用户可见百分比。"),
            substitution: "CurrentCapacity → \(s.data.percent)%",
            source: "AppleSmartBattery CurrentCapacity / macOS visible state of charge.",
            readAt: s.rawFieldReadAt,
        )
    }

    static func health(_ s: DashboardMetricSnapshot) -> MetricHelpContent {
        content(
            id: "health.system",
            title: dashboardText("p.priority_health", fallback: "整块电池的健康状况"),
            summary: dashboardText("p.help_summary_health", fallback: "主界面采用与系统设置更接近的口径；容量条另给出不含安全预留的直接容量比例，两者分母不同。"),
            result: LNum("%.1f%%", s.healthPercent),
            fields: [
                field("AppleRawMaxCapacity", s.fullChargeCapacity, "mAh"),
                field("PackReserve", s.detail.packReserve, "mAh"),
                field("DesignCapacity", s.designCapacity, "mAh"),
            ],
            formula: "health = (FullChargeCapacity + PackReserve) ÷ (DesignCapacity − PackReserve) × 100",
            substitution: "(\(s.fullChargeCapacity) + \(s.detail.packReserve)) ÷ (\(s.designCapacity) − \(s.detail.packReserve)) × 100 = \(LNum("%.1f%%", s.healthPercent))",
            source: "Derived from IOKit fields and aligned to this Mac's system reading. This inferred formula is labelled rather than presented as an Apple-published formula.",
            readAt: s.rawFieldReadAt,
        )
    }

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
            title: dashboardText("p.priority_power", fallback: "当前电脑的使用功率"),
            summary: dashboardText("p.help_summary_power", fallback: "优先读取 BatteryData.SystemPower；不可用时才依次退回 SystemLoad 或电压×电流。长期基线来自电量计累计遥测。"),
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
                    "p.trend_note_power",
                    fallback: "整机功率每 10 秒采样一次。把鼠标移到线上可以看到该分钟的读数。"
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
            stateTitle = dashboardText("p.adapter_status_disconnected", fallback: "未连接充电器")
            stateDetail = dashboardText("p.adapter_status_disconnected_note", fallback: "插入电源后会读取协商电压、电流和额定功率")
        } else if negotiated {
            stateTitle = dashboardText("p.adapter_status_negotiated", fallback: "已连接 · 协商成功")
            stateDetail = "\(adapterType) · \(LNum("%.1f V", voltage ?? 0)) / \(LNum("%.2f A", current ?? 0))"
        } else {
            stateTitle = dashboardText("p.adapter_status_waiting", fallback: "已连接 · 等待协商字段")
            stateDetail = adapterType
        }

        let equation = if let voltage, let current, let calculatedWatts {
            "\(LNum("%.1f V", voltage)) × \(LNum("%.2f A", current)) = \(LNum("%.1f W", calculatedWatts))"
        } else {
            dashboardText("p.adapter_equation_waiting", fallback: "等待电压和电流字段")
        }
        let equationNote: String
        if let calculatedWatts, watts > 0 {
            let tolerance = max(1.0, Double(watts) * 0.03)
            equationNote = abs(calculatedWatts - Double(watts)) <= tolerance
                ? dashboardText("p.adapter_contract_match", fallback: "三个字段相互吻合；这是充电器能力上限，不是实时耗电。")
                : dashboardText("p.adapter_contract_diff", fallback: "系统报告的额定功率与电压×电流略有差异；分别保留原始值，避免强行改写。")
        } else {
            equationNote = dashboardText("p.adapter_contract_partial", fallback: "字段不完整时不反推缺失值。")
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
            title: dashboardText("p.adapter_status_title", fallback: "充电器状态"),
            summary: dashboardText(
                "p.help_summary_adapter_power",
                fallback: "这是充电器与电脑协商出的额定功率，不是电脑此刻一定正在消耗这么多。拔掉电源后，这组字段通常会消失。"
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
                "p.help_source_adapter_power",
                fallback: "IOKit AppleSmartBattery.AdapterDetails。它表示当前电源协商档位；实际输入功率请看 SystemPowerIn。"
            ),
            readAt: s.rawFieldReadAt,
            powerContract: MetricPowerContract(
                stateTitle: stateTitle,
                stateDetail: stateDetail,
                isConnected: connected,
                isNegotiated: negotiated,
                voltageLabel: dashboardText("p.adapter_voltage", fallback: "协商电压"),
                voltageText: voltage.map { LNum("%.1f V", $0) } ?? "—",
                currentLabel: dashboardText("p.adapter_current", fallback: "协商电流"),
                currentText: current.map { LNum("%.2f A", $0) } ?? "—",
                powerLabel: dashboardText("p.adapter_rated_power", fallback: "额定功率"),
                powerText: displayedWatts,
                equationText: equation,
                equationNote: equationNote,
                trendTitle: dashboardText("p.adapter_input_trend", fallback: "整机实际输入功率"),
                trendValue: currentInput.map { LNum("%.1f W", $0) } ?? "—",
                trendNote: dashboardText("p.adapter_input_trend_note", fallback: "青线是推导值：电脑当前功率 + 充入电池的功率，和上方流向图的两条出边同源。黄色虚线是协商上限，两者不同很正常。鼠标移到线上可看该分钟读数。"),
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
            title: dashboardText("shell.charge_power", fallback: "充电功率"),
            summary: dashboardText(
                "p.help_summary_charging_power",
                fallback: "这是实际流进电池的功率：电池电压 × 正向充电电流。电脑插着电但电池没有充电时，这里就是 0 W。"
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
                "p.help_source_charging_power",
                fallback: "由 AppleSmartBattery 的电池组电压与带符号电池电流推导；放电方向的负电流不会被算作充电。"
            ),
            readAt: s.rawFieldReadAt,
            trend: MetricHelpTrend(
                title: trendTitle(),
                latestText: displayedWatts,
                note: dashboardText(
                    "p.trend_note_charge",
                    fallback: "每个点是当时的电池电压 × 正向电流。放电时记为 0，所以充电停止会看到线落到底，而不是断开。"
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
            title: dashboardText("shell.adapter_output_power", fallback: "适配器输出功率"),
            summary: dashboardText(
                "p.help_summary_adapter_output_power",
                fallback: "这是适配器送进整台电脑的实时功率，既包含电脑当前使用的部分，也可能包含给电池充电的部分；它不是电池充电功率。"
            ),
            result: displayedWatts,
            fields: [
                field(
                    "PowerTelemetryData.SystemPowerIn",
                    detail.presentRawFields.contains("PowerTelemetryData.SystemPowerIn") ? detail.systemPowerIn : nil,
                    "mW",
                    dashboardText("p.raw_power_in_explain", fallback: "充电器实际送入 Mac 的功率")
                ),
                field(
                    "PowerTelemetryData.VoltageIn",
                    detail.presentRawFields.contains("PowerTelemetryData.VoltageIn") ? detail.systemVoltageIn : nil,
                    "mV",
                    dashboardText("p.raw_voltage_in_explain", fallback: "进入 Mac 的实时电压")
                ),
                field(
                    "PowerTelemetryData.CurrentIn",
                    detail.presentRawFields.contains("PowerTelemetryData.CurrentIn") ? detail.systemCurrentIn : nil,
                    "mA",
                    dashboardText("p.raw_current_in_explain", fallback: "进入 Mac 的实时电流")
                ),
                field(
                    "PowerTelemetryData.AdapterEfficiencyLoss",
                    detail.presentRawFields.contains("PowerTelemetryData.AdapterEfficiencyLoss") ? detail.adapterEfficiencyLoss : nil,
                    "mW",
                    dashboardText("p.raw_adapter_loss_explain", fallback: "适配器效率损耗原始值")
                ),
            ],
            formula: "adapterOutputPowerW = macLoadW + max(batteryPowerW, 0)",
            substitution: "\(f(s.currentPowerWatts)) + \(f(max(0, s.batteryPowerWatts ?? 0))) = \(displayedWatts)\nSystemPowerIn (reference only): \(optional(detail.presentRawFields.contains("PowerTelemetryData.SystemPowerIn") ? detail.systemPowerIn : nil)) mW",
            source: dashboardText(
                "p.help_source_adapter_output_power",
                fallback: "推导值：电脑当前功率 + 充入电池的功率，和概览流向图的两条适配器出边同源。原先直读 PowerTelemetryData.SystemPowerIn，但实测这台 Mac 插着电充着电时该字段会归零，所以只把它保留在下方原始字段里作参考。"
            ),
            readAt: s.rawFieldReadAt,
            trend: MetricHelpTrend(
                title: trendTitle(),
                latestText: displayedWatts,
                note: dashboardText(
                    "p.trend_note_adapter_output",
                    fallback: "拔掉电源的时间段不画线——那时适配器没有输出，画一条 0 和画一段空白意思不同。鼠标移到线上可看该分钟读数。"
                ),
                unit: "W",
                tint: AppTheme.chargingCyan,
                points: trendPoints(s) { adapterOutputWatts($0) },
                waitingText: trendWaiting()
            )
        )
    }

    static func cycleCount(_ s: DashboardMetricSnapshot) -> MetricHelpContent {
        let count = s.detail.cycleCount > 0 ? s.detail.cycleCount : s.data.cycleCount
        let rated = s.detail.designCycleCount
        let usage = rated > 0 ? Double(count) / Double(rated) * 100 : nil
        let substitution: String
        if let usage {
            substitution = "\(count) ÷ \(rated) × 100 = \(LNum("%.1f%%", usage))"
        } else {
            substitution = "CycleCount → \(count)"
        }
        return content(
            id: "cycles.count",
            title: MenuBarMetric.cycles.title,
            summary: dashboardText(
                "p.help_summary_cycle_count",
                fallback: "一次循环等于累计用掉 100% 的设计电量，可以由多次浅充浅放累加。它像里程表，不能单独代表电池健康。"
            ),
            result: "\(count)",
            fields: [
                field("CycleCount", count, "cycles"),
                field("DesignCycleCount9C", rated, "cycles"),
            ],
            formula: rated > 0
                ? "cycleUse = CycleCount ÷ DesignCycleCount × 100"
                : dashboardText("p.help_direct", fallback: "无公式：直接读取系统字段。"),
            substitution: substitution,
            source: dashboardText(
                "p.help_source_cycle_count",
                fallback: "IOKit CycleCount；额定参考来自 DesignCycleCount9C。达到额定循环数不等于电池会立即失效。"
            ),
            readAt: s.rawFieldReadAt,
        )
    }

    static func temperature(_ s: DashboardMetricSnapshot) -> MetricHelpContent {
        let raw = s.detail.temperatureRaw
        let divisor: Double
        let rawUnit: String
        if (raw ?? 0) > 1_000 {
            divisor = 100
            rawUnit = "0.01°C"
        } else if (raw ?? 0) > 100 {
            divisor = 10
            rawUnit = "0.1°C"
        } else {
            divisor = 1
            rawUnit = "°C"
        }
        return content(
            id: "temperature.current",
            title: dashboardText("p.priority_temp", fallback: "当前电池温度"),
            summary: dashboardText("p.help_summary_temperature", fallback: "电量计字段在不同平台可能使用不同标度；服务层按原始量级解码，并保留原始值供核验。"),
            result: LNum("%.1f °C", s.data.temperatureCelsius),
            fields: [field("Temperature", raw, rawUnit)],
            formula: "if raw > 1000: °C = raw ÷ 100; else if raw > 100: °C = raw ÷ 10; else °C = raw",
            substitution: divisor == 1
                ? "\(optional(raw)) → \(LNum("%.2f °C", s.data.temperatureCelsius))"
                : "\(optional(raw)) ÷ \(Int(divisor)) = \(LNum("%.2f °C", s.data.temperatureCelsius))",
            source: "IOKit Temperature with platform-aware scale decoding; lifetime minimum and maximum are shown separately.",
            readAt: s.rawFieldReadAt,
            trend: MetricHelpTrend(
                title: trendTitle(),
                latestText: LNum("%.1f ℃", s.data.temperatureCelsius),
                note: dashboardText(
                    "p.trend_note_temperature",
                    fallback: "纵轴贴着实际区间画，不从 0 ℃ 起——否则电池真实的几度波动会被压成一条直线。鼠标移到线上可看该分钟读数。"
                ),
                unit: "℃",
                tint: AppTheme.batteryYellow,
                points: trendPoints(s) { $0.temperature > 0 ? $0.temperature : nil },
                baselineAtZero: false,
                waitingText: trendWaiting()
            )
        )
    }

    static func officialBenchmark(_ s: DashboardMetricSnapshot, specification spec: BatteryModelSpecification) -> MetricHelpContent {
        let impliedPower = spec.designEnergyWh / max(spec.officialWebHours, 0.1)
        let sameLoad = (s.currentFullEnergyWh ?? 0) / impliedPower
        return content(
            id: "runtime.official-benchmark",
            title: dashboardText("p.runtime_audit_tag", fallback: "公开基准 × 这台电脑"),
            summary: dashboardText("p.audit_conditions", fallback: "官方网页续航来自固定亮度、Wi‑Fi 和轻负载条件，不等于任何满电电脑都能跑同样久。"),
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
                title: dashboardText("p.unplug_trend", fallback: "拔电后的预计续航"),
                summary: dashboardText("p.forecast_only", fallback: "虚线只是当前拔电预计，不会冒充系统历史。"),
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
            title: dashboardText("p.remaining_trend", fallback: "系统剩余时间记录"),
            summary: dashboardText("p.help_summary_time_history", fallback: "纵轴逐点记录 macOS 当时报告的剩余小时，横轴是采样时刻；相邻系统读数用阶梯连接，不按功率重算。"),
            result: runtime(s.data.timeRemainingMinutes ?? 0),
            fields: [runtimeRawField("TimeRemaining", s.detail.timeRemainingRaw, onAC: s.data.isOnAC),
                     runtimeRawField("AvgTimeToEmpty", s.detail.avgTimeToEmpty, onAC: s.data.isOnAC)],
            formula: dashboardText("p.help_direct", fallback: "无公式：每次保存有效系统读数。"),
            substitution: "validMinutes(TimeRemaining) → history point; minimum interval = 56 s",
            source: "AppleSmartBattery runtime fields; sentinel values and duplicate sub-56-second samples are rejected.",
            readAt: s.rawFieldReadAt,
        )
    }

    static func capacityOverview(_ s: DashboardMetricSnapshot) -> MetricHelpContent {
        var fields = [
            field("DesignCapacity", s.designCapacity, "mAh"),
            field("AppleRawMaxCapacity (FCC)", s.fullChargeCapacity, "mAh"),
            field("AppleRawCurrentCapacity", s.currentCapacity, "mAh"),
        ]
        if let qmax = s.qmaxCapacityForBreakdown {
            fields.append(field("min(Qmax)", qmax, "mAh"))
        }
        let formula: String
        let substitution: String
        if let inaccessible = s.inaccessibleCapacity,
           let permanent = s.truePermanentLoss {
            formula = "DesignCapacity = CurrentRemaining + UsedSinceFull + (minQmax − FCC) + (DesignCapacity − minQmax)"
            substitution = "\(s.designCapacity) = \(s.currentCapacity) + \(s.usedSinceFull) + \(inaccessible) + \(permanent) mAh; FCC = \(s.currentCapacity) + \(s.usedSinceFull) = \(s.fullChargeCapacity) mAh"
        } else {
            formula = "DesignCapacity = CurrentRemaining + UsedSinceFull + LongTermCapacityGap"
            substitution = "\(s.designCapacity) = \(s.currentCapacity) + \(s.usedSinceFull) + \(s.longTermCapacityGap) mAh; Qmax unavailable, so the long-term gap is not split"
        }
        return content(
            id: "capacity.overview",
            title: dashboardText("p.where_title", fallback: "你买的容量去哪了"),
            summary: dashboardText("p.help_summary_capacity", fallback: "同一把尺下，先用 FCC 把容量分成可用与长期差额；Qmax 可信时，再把长期差额拆成暂时够不到和真正老化。"),
            result: "\(s.designCapacity.formatted()) mAh",
            fields: fields,
            formula: formula,
            substitution: substitution,
            source: "IOKit capacity fields. Qmax decomposition is shown only when min(Qmax) lies between FCC and DesignCapacity.",
            readAt: s.rawFieldReadAt,
        )
    }

    static func designCapacity(_ s: DashboardMetricSnapshot) -> MetricHelpContent {
        directCapacity(id: "capacity.design", title: dashboardText("p.design_capacity", fallback: "设计容量"),
                       summary: dashboardText("p.help_summary_design_capacity", fallback: "这台电池出厂时的标称容量，是容量拆解的总尺。"),
                       fieldName: "DesignCapacity", value: s.designCapacity, readAt: s.rawFieldReadAt)
    }

    static func currentMax(_ s: DashboardMetricSnapshot) -> MetricHelpContent {
        directCapacity(id: "capacity.current-max", title: dashboardText("p.current_max", fallback: "目前最大容量"),
                       summary: dashboardText("p.help_summary_full_capacity", fallback: "这块电池现在充满后，系统允许实际使用的总容量。"),
                       fieldName: "AppleRawMaxCapacity", value: s.fullChargeCapacity, readAt: s.rawFieldReadAt)
    }

    static func currentActual(_ s: DashboardMetricSnapshot) -> MetricHelpContent {
        content(
            id: "capacity.current",
            title: dashboardText("p.current_actual", fallback: "此刻还剩"),
            summary: dashboardText("p.current_actual_desc", fallback: "本次剩余电量；会随使用减少，充电后可以回来。"),
            result: "\(s.currentCapacity.formatted()) mAh",
            fields: [field("AppleRawCurrentCapacity", s.detail.appleRawCurrentCapacity, "mAh"), field("AppleRawMaxCapacity", s.fullChargeCapacity, "mAh")],
            formula: "currentActual = min(AppleRawCurrentCapacity, AppleRawMaxCapacity)",
            substitution: "min(\(s.detail.appleRawCurrentCapacity), \(s.fullChargeCapacity)) = \(s.currentCapacity) mAh",
            source: "IOKit live capacity, capped at full-charge capacity to reject transient over-range readings.",
            readAt: s.rawFieldReadAt,
        )
    }

    static func usedSinceFull(_ s: DashboardMetricSnapshot) -> MetricHelpContent {
        content(
            id: "capacity.used",
            title: dashboardText("p.used_since_full", fallback: "本次已经用掉"),
            summary: dashboardText("p.help_summary_used", fallback: "这是从本次满充到现在流出的电，会在下一次充电时补回来；它和永久老化不能相加。"),
            result: "\(s.usedSinceFull.formatted()) mAh",
            fields: [field("AppleRawMaxCapacity", s.fullChargeCapacity, "mAh"), field("AppleRawCurrentCapacity", s.currentCapacity, "mAh")],
            formula: "usedSinceFull = FullChargeCapacity − CurrentCapacity",
            substitution: "\(s.fullChargeCapacity) − \(s.currentCapacity) = \(s.usedSinceFull) mAh",
            source: "Derived from two IOKit capacity readings on the same scale.",
            readAt: s.rawFieldReadAt,
        )
    }

    static func capacityGap(_ s: DashboardMetricSnapshot) -> MetricHelpContent {
        content(
            id: "capacity.long-term-gap",
            title: dashboardText("p.capacity_gap", fallback: "长期容量总差额"),
            summary: dashboardText("p.capacity_gap_summary", fallback: "这是设计容量与当前满充 FCC 的总差额。它可能同时包含真正化学老化、截止电压与标定影响，不能全部直接叫作永久损失。"),
            result: "\(s.longTermCapacityGap.formatted()) mAh",
            fields: [field("DesignCapacity", s.designCapacity, "mAh"), field("AppleRawMaxCapacity (FCC)", s.fullChargeCapacity, "mAh")],
            formula: "longTermCapacityGap = DesignCapacity − FCC",
            substitution: "\(s.designCapacity) − \(s.fullChargeCapacity) = \(s.longTermCapacityGap) mAh",
            source: "Derived from IOKit design and FCC readings. Qmax is required before this total can be split responsibly.",
            readAt: s.rawFieldReadAt,
        )
    }

    static func inaccessibleCapacity(_ s: DashboardMetricSnapshot) -> MetricHelpContent {
        let qmax = s.qmaxCapacityForBreakdown ?? 0
        let inaccessible = s.inaccessibleCapacity ?? 0
        return content(
            id: "capacity.inaccessible",
            title: dashboardText("p.seg_un", fallback: "暂时够不到"),
            summary: dashboardText("p.unusable_ex", fallback: "化学容量仍在，但没有进入当前可用满充 FCC；像吸管够不到的杯底水。"),
            result: "\(inaccessible.formatted()) mAh",
            fields: [field("min(Qmax)", qmax, "mAh"), field("AppleRawMaxCapacity (FCC)", s.fullChargeCapacity, "mAh")],
            formula: "inaccessibleCapacity = min(Qmax) − FCC",
            substitution: "\(qmax) − \(s.fullChargeCapacity) = \(inaccessible) mAh",
            source: "Battery gauge learned Qmax and FCC. Shown only when FCC ≤ min(Qmax) ≤ DesignCapacity.",
            readAt: s.rawFieldReadAt,
        )
    }

    static func permanentLoss(_ s: DashboardMetricSnapshot) -> MetricHelpContent {
        let qmax = s.qmaxCapacityForBreakdown ?? s.fullChargeCapacity
        let permanent = s.truePermanentLoss ?? s.longTermCapacityGap
        return content(
            id: "capacity.true-permanent-loss",
            title: dashboardText("p.seg_age", fallback: "真正老化"),
            summary: dashboardText("p.seg_age_d", fallback: "设计容量与电量计学习到的化学容量之差，像水箱本身缩小了。"),
            result: "\(permanent.formatted()) mAh",
            fields: [field("DesignCapacity", s.designCapacity, "mAh"), field("min(Qmax)", qmax, "mAh")],
            formula: "truePermanentLoss = DesignCapacity − min(Qmax)",
            substitution: "\(s.designCapacity) − \(qmax) = \(permanent) mAh",
            source: "Derived from design capacity and the weakest cell's learned Qmax. The UI uses this label only when Qmax passes the FCC/design consistency gate.",
            readAt: s.rawFieldReadAt,
        )
    }

    static func specOverview(_ s: DashboardMetricSnapshot) -> MetricHelpContent {
        content(
            id: "references.overview",
            title: dashboardText("p.spec_other_title", fallback: "其余 4 项关键指标"),
            summary: dashboardText("p.spec_source_note", fallback: "每个合理范围都会说明依据，不把 Apple 规格、个人历史和通用资料混成一个标准答案。"),
            result: "4 × REFERENCE",
            // Label-only rows: these three name groups of fields, they are not
            // readings, so they carry neither a read time nor a cadence.
            fields: [field("IOKit live fields", "current values", "", "", updateClass: .untimed),
                     field("LifetimeData", "personal extremes", "", "", updateClass: .untimed),
                     field("Apple/general references", "labelled ranges", "", "", updateClass: .untimed)],
            formula: dashboardText("p.help_direct", fallback: "每一行分别使用自己的字段或明确标注的推导。"),
            substitution: "current value + range + history + low/high impact + source",
            source: "Mixed sources, labelled per metric.",
            readAt: s.rawFieldReadAt,
        )
    }

    static func cellBalance(_ s: DashboardMetricSnapshot) -> MetricHelpContent {
        let cells = s.detail.cellVoltages
        let delta = s.detail.cellVoltageDelta ?? 0
        return content(
            id: "reference.cell-balance",
            title: dashboardText("insight.factor.balance", fallback: "各单元均衡度"),
            summary: dashboardText("p.help_summary_balance", fallback: "串联电芯中最弱的一节会先触及截止线，因此压差越小，整包越同步。"),
            result: "\(delta) mV",
            fields: [field("BatteryData.CellVoltage", cells.map(String.init).joined(separator: " / "), "mV")],
            formula: "cellBalance = max(CellVoltage) − min(CellVoltage)",
            substitution: cells.isEmpty ? "no valid cell-voltage array" : "\(cells.max() ?? 0) − \(cells.min() ?? 0) = \(delta) mV",
            source: "IOKit cell voltages; 0–20 mV is a general lithium-pack reference, not an Apple service specification.",
            readAt: s.rawFieldReadAt,
        )
    }

    static func resistance(_ s: DashboardMetricSnapshot) -> MetricHelpContent {
        let values = s.detail.weightedRa
        let maximum = values.max() ?? 0
        return content(
            id: "reference.resistance",
            title: dashboardText("insight.factor.resistance", fallback: "电池内部阻力"),
            summary: dashboardText("p.help_summary_resistance", fallback: "显示最差一节的加权内阻，因为串联电池组会被阻力最高的一节限制；更重要的是观察同一台电脑的变化趋势。"),
            result: "\(maximum) mΩ",
            fields: [field("BatteryData.WeightedRa", values.map(String.init).joined(separator: " / "), "mΩ")],
            formula: "displayedResistance = max(WeightedRa)",
            substitution: "max(\(values.map(String.init).joined(separator: ", "))) = \(maximum) mΩ",
            source: "IOKit gauge value. 0–130 mΩ is a presentation reference; Apple publishes no fixed service range for this field.",
            readAt: s.rawFieldReadAt,
        )
    }

    static func cycles(_ s: DashboardMetricSnapshot) -> MetricHelpContent {
        let rated = s.detail.designCycleCount
        let usage = (s.detail.cycleUsage ?? 0) * 100
        return content(
            id: "reference.cycles",
            title: dashboardText("insight.factor.cycles", fallback: "循环使用率"),
            summary: dashboardText("p.help_summary_cycles", fallback: "循环次数像里程表，只说明累计使用；是否需要检修仍需结合容量、内阻、电芯差和温度。"),
            result: LNum("%.1f%%", usage),
            fields: [field("CycleCount", s.detail.cycleCount), field("DesignCycleCount9C", rated)],
            formula: "cycleUse = CycleCount ÷ DesignCycleCount × 100",
            substitution: rated > 0 ? "\(s.detail.cycleCount) ÷ \(rated) × 100 = \(LNum("%.1f%%", usage))" : "DesignCycleCount unavailable",
            source: "IOKit CycleCount and rated design-cycle field; Apple's 80% capacity threshold is not the same thing as reaching the cycle rating.",
            readAt: s.rawFieldReadAt,
        )
    }

    static func packVoltage(_ s: DashboardMetricSnapshot) -> MetricHelpContent {
        content(
            id: "reference.pack-voltage",
            title: dashboardText("hw.m.pack_voltage", fallback: "电池组电压"),
            summary: dashboardText("p.help_summary_voltage", fallback: "电压会随电量和负载变化；单次高低不等于健康好坏，所以与这块电池自己的历史极限一起展示。"),
            result: LNum("%.2f V", s.voltageVolts),
            fields: [
                field("Voltage", s.detail.voltageRaw ?? s.detail.packVoltage, "mV"),
                field("AppleRawBatteryVoltage", s.detail.appleRawBatteryVoltage, "mV"),
                field("LifetimeData.MinimumPackVoltage", s.detail.minimumPackVoltage, "mV"),
                field("LifetimeData.MaximumPackVoltage", s.detail.maximumPackVoltage, "mV"),
            ],
            formula: "packVoltageV = packVoltageMillivolts ÷ 1000",
            substitution: "\(s.detail.packVoltage) ÷ 1000 = \(LNum("%.3f V", s.voltageVolts))",
            source: "IOKit live pack voltage and lifetime extremes from this battery.",
            readAt: s.rawFieldReadAt,
        )
    }

    private static func directCapacity(id: String, title: String, summary: String, fieldName: String, value: Int,
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
    private static func trendPoints(
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
    private static func adapterOutputWatts(_ point: RealtimeDataPoint) -> Double? {
        guard point.isOnAC else { return nil }
        return max(0, point.power) + max(0, batteryWatts(point))
    }

    /// Power flowing into the pack. Discharge is recorded as 0 rather than
    /// dropped, so a charge that stops shows as a line falling to the floor
    /// instead of a gap.
    private static func chargeWatts(_ point: RealtimeDataPoint) -> Double {
        max(0, batteryWatts(point))
    }

    private static func trendTitle() -> String {
        dashboardText("p.trend_last_10min", fallback: "最近 10 分钟")
    }

    private static func trendWaiting() -> String {
        dashboardText("p.trend_waiting", fallback: "正在积累历史数据")
    }

    private static func content(
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

    private static func field(
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

    private static func field<T: BinaryInteger>(
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
    private static func runtimeRawField(_ name: String, _ value: Int?, onAC: Bool = false) -> MetricRawField {
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
    private static func runtimeRawValue(_ value: Int?) -> String {
        guard let value else { return "—" }
        guard RuntimeSample.isValid(minutes: value) else {
            return dashboardText("p.runtime_raw_unavailable", fallback: "不可用")
        }
        return "\(value) min"
    }

    /// Defaults to the bare clock so these cards read the same way as the field
    /// rows below them. The date is only worth the extra width when the value can
    /// legitimately be from another day — the persisted fallback sample.
    private static func runtimeReadTimestamp(_ date: Date, includeDate: Bool = false) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: L10n.shared.effectiveCode)
        formatter.dateStyle = includeDate ? .short : .none
        formatter.timeStyle = .medium
        return formatter.string(from: date)
    }

    private static func f(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "—" }
        return LNum("%.2f", value)
    }

    private static func optional<T>(_ value: T?) -> String { value.map(String.init(describing:)) ?? "—" }

    private static func runtime(_ minutes: Int?) -> String {
        guard let minutes, minutes > 0 else { return "—" }
        return "\(minutes / 60) h \(String(format: "%02d", minutes % 60)) m"
    }
}
