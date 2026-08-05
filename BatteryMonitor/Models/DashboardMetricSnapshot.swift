import Foundation

// MARK: - Dashboard data adapter

/// Keeps calculations in one place so every card uses the same definitions.
/// All source values remain the real model values; this adapter only chooses
/// fallbacks and formats the prototype's documented derived values.
struct DashboardMetricSnapshot {
    let data: BatteryData
    let realtimeData: [RealtimeDataPoint]
    /// The latest persisted Apple system estimate. Overview uses this while on
    /// AC because the live gauge returns 65535 there; derived power estimates
    /// are never written into this fallback.
    var systemRuntimeFallbackSample: RuntimeSample? = nil

    var detail: BatteryHardwareDetail { data.hardwareDetail }
    var modelIdentifier: String {
        data.modelIdentifier.isEmpty ? BatteryService.hardwareModel() : data.modelIdentifier
    }
    var specification: BatteryModelSpecification? {
        data.modelSpecification ?? BatteryModelSpecification.lookup(modelIdentifier: modelIdentifier)
    }

    var currentPowerWatts: Double {
        if detail.systemPowerWatts > 0.1 { return detail.systemPowerWatts }
        if detail.systemLoad > 0 { return Double(detail.systemLoad) / 1000.0 }
        return max(0, data.currentPowerWatts)
    }

    /// Real-time power crossing from the external adapter into the whole Mac.
    /// This is not battery charging power: part (or all) of it can be consumed
    /// directly by the running computer.
    ///
    /// Derived — deliberately — as `Mac load + charge into the battery`, the sum
    /// of the two adapter edges the overview's flow diagram already draws, so
    /// the diagram and this figure cannot disagree. It used to read
    /// `PowerTelemetryData.SystemPowerIn` directly; that field was measured
    /// reporting 0 mW on this Mac while plugged in and charging, which showed up
    /// as a missing card and a vanishing trend chart. SystemPowerIn is still
    /// listed as a raw field in the help panel, where a 0 reads as a 0 rather
    /// than as the machine's actual input.
    var adapterOutputPowerWatts: Double? {
        guard data.isOnAC else { return nil }
        let flow = PowerFlow.resolve(self)
        let watts = (flow.adapterToMac ?? 0) + (flow.adapterToBattery ?? 0)
        guard watts.isFinite, watts > 0 else { return nil }
        return watts
    }

    /// Positive battery-side current only. `InstantAmperage` is preferred for
    /// the live card; `Amperage` is the compatible smoothed fallback. A Mac can
    /// be on AC while this remains exactly zero because the adapter is powering
    /// the system without adding charge to the battery.
    var batteryChargingCurrentMilliamps: Int? {
        guard data.isCharging else { return 0 }
        if detail.presentRawFields.contains("InstantAmperage") {
            return max(0, detail.instantAmperage)
        }
        if detail.presentRawFields.contains("Amperage") {
            return max(0, detail.smoothedAmperage)
        }
        guard data.amperage != 0 else { return nil }
        return max(0, data.amperage)
    }

    /// Battery current with its sign intact: negative while discharging, positive
    /// while charging. Deliberately separate from
    /// `batteryChargingCurrentMilliamps`, which clamps the sign away and reports 0
    /// whenever the Mac is not charging — that hides the case this exists for: on
    /// AC, not charging, and the battery still draining (measured at -694 mA while
    /// optimised charging held at 80%). nil when no current field was returned;
    /// never 0 as a stand-in for a missing reading.
    var batteryCurrentMilliamps: Int? {
        guard let raw = rawBatteryCurrentMilliamps else { return nil }
        // Nothing can push charge into the pack with the cable out. A positive
        // reading here is the last pre-unplug sample: `ExternalConnected` is
        // event-driven and flips at once, while the gauge republishes current only
        // every ~60 s, so the two disagree for up to a minute (measured +2.88 A
        // with the charger out). Report nothing rather than a reading that the
        // state line directly contradicts; the next gauge tick fixes it.
        guard data.isOnAC || raw <= Self.staleChargeCurrentMilliamps else { return nil }
        return raw
    }

    /// Off AC, anything above this has to be stale — a resting pack drifts by a
    /// few tens of milliamps, it does not gain charge.
    static let staleChargeCurrentMilliamps = 50

    private var rawBatteryCurrentMilliamps: Int? {
        if detail.presentRawFields.contains("InstantAmperage") { return detail.instantAmperage }
        if detail.presentRawFields.contains("Amperage") { return detail.smoothedAmperage }
        guard data.amperage != 0 else { return nil }
        return data.amperage
    }

    /// Signed battery-side power, positive while charging. The one number the
    /// flow diagram and the power state both hang off, so that neither can
    /// contradict the current row — they are all the same measurement.
    ///
    /// Deliberately current × voltage rather than `PowerTelemetryData.BatteryPower`,
    /// which was measured reporting −3.38 W against a coulomb-counter reading of
    /// −10.16 W at the same gauge tick. See `PowerFlow` for the sample log.
    var batteryPowerWatts: Double? {
        guard let milliamps = batteryCurrentMilliamps else { return nil }
        let watts = Double(milliamps) / 1000 * voltageVolts
        return watts.isFinite ? watts : nil
    }

    /// Minutes until full, but only when charging and only when the value is a
    /// credible duration. `AvgTimeToFull` is passed through unfiltered by the
    /// parser, so the 65535 sentinel and absurd five-figure values both arrive
    /// here and must be rejected rather than displayed.
    var timeToFullMinutes: Int? {
        guard data.isCharging, let minutes = detail.avgTimeToFull,
              RuntimeSample.isValid(minutes: minutes) else { return nil }
        return minutes
    }

    /// Battery charging power = pack voltage × positive battery current.
    /// When IsCharging is false the physical flow into the battery is 0 W,
    /// regardless of the adapter's whole-Mac input power.
    var batteryChargingPowerWatts: Double? {
        guard data.isCharging else { return 0 }
        guard voltageVolts.isFinite, voltageVolts > 0,
              let milliamps = batteryChargingCurrentMilliamps else { return nil }
        return voltageVolts * Double(milliamps) / 1000.0
    }

    /// The one place charging power is turned into text. The overview card and the
    /// menu-bar status item both read it here rather than each formatting the same
    /// watts their own way — two formatters would eventually disagree about the
    /// zero case, which is precisely the case a user checks against the card.
    var chargingPowerText: String {
        guard let watts = batteryChargingPowerWatts else { return "—" }
        return watts < PowerFlow.minimumMeaningfulWatts ? "0 W" : LNum("%.1f W", watts)
    }

    /// Same value with the space closed up, for the menu-bar title where every
    /// point of width pushes the other status items along.
    var chargingPowerCompactText: String? {
        guard let watts = batteryChargingPowerWatts else { return nil }
        return watts < PowerFlow.minimumMeaningfulWatts ? "0W" : LNum("%.1fW", watts)
    }

    var usualPowerWatts: Double {
        detail.averageTelemetryPowerWatts ?? max(currentPowerWatts, 0.1)
    }

    var peakPowerWatts: Double {
        max(realtimeData.map(\.power).max() ?? 0, currentPowerWatts)
    }

    var healthPercent: Double {
        detail.systemHealthPercent ?? Double(data.maxCapacityPercent)
    }

    var rawHealthPercent: Double {
        detail.rawHealthPercent ?? Double(data.maxCapacityPercent)
    }

    var designCapacity: Int { max(detail.designCapacity, data.designCapacity) }
    var fullChargeCapacity: Int { max(detail.appleRawMaxCapacity, data.maxCapacity) }
    var currentCapacity: Int {
        guard detail.presentRawFields.contains("AppleRawCurrentCapacity") else { return 0 }
        let raw = detail.appleRawCurrentCapacity
        guard fullChargeCapacity > 0 else { return max(0, raw) }
        return min(max(0, raw), fullChargeCapacity)
    }
    var usedSinceFull: Int { max(0, fullChargeCapacity - currentCapacity) }
    /// The consumer-facing difference between the original design and today's FCC.
    /// When Qmax is trustworthy it is split below into charge that is still present
    /// but outside the usable voltage window, and true learned chemical loss.
    var longTermCapacityGap: Int { max(0, designCapacity - fullChargeCapacity) }

    /// Qmax is useful for the split only when it sits between FCC and design.
    /// Outside that interval it is stale/incompatible, so the UI keeps the total
    /// gap intact instead of presenting a confident but false decomposition.
    var qmaxCapacityForBreakdown: Int? {
        guard let qmax = detail.qmax.filter({ $0 > 0 }).min(),
              fullChargeCapacity > 0,
              designCapacity > 0,
              qmax >= fullChargeCapacity,
              qmax <= designCapacity else { return nil }
        return qmax
    }

    var inaccessibleCapacity: Int? {
        qmaxCapacityForBreakdown.map { max(0, $0 - fullChargeCapacity) }
    }

    var truePermanentLoss: Int? {
        qmaxCapacityForBreakdown.map { max(0, designCapacity - $0) }
    }

    var designEnergyWh: Double? { specification?.designEnergyWh }
    var currentFullEnergyWh: Double? {
        guard let designEnergyWh, designCapacity > 0, fullChargeCapacity > 0 else { return nil }
        return designEnergyWh * Double(fullChargeCapacity) / Double(designCapacity)
    }
    var remainingEnergyWh: Double? {
        guard detail.presentRawFields.contains("AppleRawCurrentCapacity"),
              let designEnergyWh, designCapacity > 0, currentCapacity > 0 else { return nil }
        return designEnergyWh * Double(currentCapacity) / Double(designCapacity)
    }
    var unplugEstimateMinutes: Int? {
        guard let remainingEnergyWh, currentPowerWatts > 0.1 else { return nil }
        let minutes = max(1, Int((remainingEnergyWh / currentPowerWatts * 60).rounded()))
        return RuntimeSample.isValid(minutes: minutes) ? minutes : nil
    }

    /// Valid power readings from the most recent ten minutes. Requiring at
    /// least five readings prevents a few instantaneous values from being
    /// presented as a stable estimate. Timestamps are kept here so the help
    /// sheet can state when the window was last refreshed instead of implying
    /// the median is a live reading.
    var recentStablePowerPoints: [RealtimeDataPoint] {
        guard let end = realtimeData.map(\.timestamp).max() else { return [] }
        let start = end.addingTimeInterval(-10 * 60)
        return realtimeData.filter {
            $0.timestamp >= start && $0.timestamp <= end && $0.power.isFinite && $0.power > 0.1
        }
    }

    var recentStablePowerSamples: [Double] {
        recentStablePowerPoints.map(\.power)
    }

    /// Read time of the newest sample that actually feeds the median.
    var latestStablePowerSampleTime: Date? {
        recentStablePowerPoints.map(\.timestamp).max()
    }

    var stablePowerWatts: Double? {
        let values = recentStablePowerSamples.sorted()
        guard values.count >= 5 else { return nil }
        let middle = values.count / 2
        if values.count.isMultiple(of: 2) {
            return (values[middle - 1] + values[middle]) / 2
        }
        return values[middle]
    }

    /// Wall-clock span the median actually covers. The window is capped at ten
    /// minutes but the floor is only five samples, so a fresh launch can produce
    /// a median from ~40 s of data. The basis line quotes this rather than always
    /// claiming ten minutes. Same `>= 5` floor as `stablePowerWatts` on purpose:
    /// a span shown next to a figure computed from a different threshold would
    /// describe samples that never fed it.
    var stablePowerSpanSeconds: Int? {
        let times = recentStablePowerPoints.map(\.timestamp)
        guard times.count >= 5, let first = times.min(), let last = times.max() else { return nil }
        return max(0, Int(last.timeIntervalSince(first).rounded()))
    }

    var stableRuntimeMinutes: Int? {
        guard let remainingEnergyWh,
              let stablePowerWatts,
              stablePowerWatts > 0.1 else { return nil }
        let minutes = max(1, Int((remainingEnergyWh / stablePowerWatts * 60).rounded()))
        return RuntimeSample.isValid(minutes: minutes) ? minutes : nil
    }

    /// Read time to quote for raw IOKit fields. The gauge's own publish time is
    /// preferred because that is when the numbers were actually produced —
    /// measured with `ioreg`, it advances once a minute, so our poll time can
    /// understate a reading's age by nearly a minute. Falls back to the poll time
    /// when the gauge does not publish `UpdateTime`.
    var rawFieldReadAt: MetricReadStamp {
        if let published = detail.gaugeUpdateTime {
            return .gauge(published, polledAt: data.lastUpdated,
                          interval: detail.gaugePublishInterval)
        }
        return .ourRead(data.lastUpdated)
    }

    /// Age of the power reading itself, not of our last poll. Bounded by the
    /// gauge's ~60 s beat plus our poll lag, which stays well inside the 120 s
    /// staleness gate below.
    var currentPowerAgeSeconds: Int {
        max(0, Int(Date().timeIntervalSince(rawFieldReadAt.at).rounded()))
    }

    var currentLoadRuntimeMinutes: Int? {
        guard currentPowerAgeSeconds <= 120 else { return nil }
        return unplugEstimateMinutes
    }

    var systemRuntimeMinutes: Int? {
        if !data.isOnAC,
           let minutes = data.timeRemainingMinutes,
           RuntimeSample.isValid(minutes: minutes) {
            return minutes
        }
        guard let fallback = systemRuntimeFallbackSample,
              RuntimeSample.isValid(minutes: fallback.minutesRemaining) else { return nil }
        return fallback.minutesRemaining
    }

    var displayedRuntimeMinutes: Int? {
        data.isOnAC ? unplugEstimateMinutes : data.timeRemainingMinutes
    }

    var temperatureHistoryText: String {
        guard detail.minimumTemperature != 0 || detail.maximumTemperature != 0 else {
            return dashboardText("p.history_learning", fallback: "历史范围正在积累")
        }
        return "\(detail.minimumTemperature)–\(detail.maximumTemperature)°C"
    }

    var voltageVolts: Double {
        if detail.packVoltage > 0 { return Double(detail.packVoltage) / 1000.0 }
        return data.voltage
    }

    var voltageHistoryText: String {
        guard detail.minimumPackVoltage > 0, detail.maximumPackVoltage > 0 else {
            return dashboardText("p.history_learning", fallback: "历史范围正在积累")
        }
        return LNum("%.2f–%.2f V", Double(detail.minimumPackVoltage) / 1000,
                    Double(detail.maximumPackVoltage) / 1000)
    }
}
