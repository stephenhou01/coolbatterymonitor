import Foundation

/// How fast the pack is actually filling, expressed as percent-per-minute so the
/// UI can turn it into "how much will land in the next 5 / 10 minutes".
///
/// ## Why the measured window is the primary source, not the power calculation
///
/// The obvious formula is `charge power ÷ full-charge energy`. On a real machine
/// at 96% that produced 11.9 W ÷ ~70 Wh ≈ 1.4 %/min — a predicted +7% over five
/// minutes — while macOS itself reported 29 minutes to fill the remaining 4%, an
/// actual 0.14 %/min. A factor of ten. Above roughly 80% the charger leaves
/// constant-current and tapers under constant voltage, so instantaneous power
/// extrapolated forward overshoots badly and keeps overshooting for the entire
/// rest of the charge.
///
/// Measuring the pack's own charge counter over a two-minute window has no such
/// blind spot: the taper is already in the measurement. The power calculation is
/// kept only as the cold-start fallback for the first two minutes after plugging
/// in, before a window exists.
///
/// ## Why the counter and not the percentage
///
/// The displayed state of charge is an integer. Over two minutes a normal charge
/// moves it 2–3 points, so ±1 of quantisation is a ±35% error on the rate.
/// `AppleRawCurrentCapacity` is milliamp-hours out of a ~5000 mAh pack, two
/// orders of magnitude finer, and it is the field the gauge actually integrates.
struct ChargeSpeedEstimate: Equatable {
    /// Where `percentPerMinute` came from, so the help drawer can say so rather
    /// than presenting a cold-start extrapolation as if it were observed.
    enum Source: Equatable {
        /// Differenced from the pack's own charge counter over a real window.
        case measured
        /// Charge current ÷ full-charge capacity. Instantaneous, and optimistic
        /// once the charge starts to taper.
        case derived
    }

    /// Always > 0 — a non-positive rate is reported as no estimate at all.
    let percentPerMinute: Double
    /// Percentage points still to fill. The hard ceiling on any prediction: the
    /// pack cannot take more than this no matter how fast it is going.
    let headroomPercent: Double
    /// The system's own `AvgTimeToFull`. Second ceiling: if macOS says the pack
    /// fills within the horizon being predicted, the answer is all the headroom.
    let timeToFullMinutes: Int?
    let source: Source

    /// Below this a rate is gauge noise rather than charging.
    static let minimumMeaningfulRate = 0.001
    /// Target measurement window. Two minutes, per the product decision.
    static let measurementWindowSeconds: TimeInterval = 120
    /// The gauge republishes roughly every 56 s while the UI polls every 10 s, so
    /// the two endpoints of a two-minute window land wherever the publish clock
    /// happens to be. Accept one poll tick of slack rather than throwing away a
    /// window that is 118 seconds wide.
    static let minimumWindowSeconds: TimeInterval = 110
    /// Stop looking back past this. Older samples describe an earlier phase of
    /// the charge curve, which is exactly what this metric must not average over.
    static let maximumWindowSeconds: TimeInterval = 480

    /// Percentage points expected to land over `minutes`, linearly extrapolated
    /// and then clamped by both physical ceilings.
    ///
    /// Deliberately linear: modelling the constant-voltage taper would need a
    /// decay coefficient, and any coefficient available here would be invented
    /// rather than measured. Because of this, ten minutes is exactly twice five
    /// minutes until one of the clamps bites — which is the honest shape of a
    /// linear model, not a bug.
    func gainPercent(overMinutes minutes: Double) -> Double {
        guard minutes > 0 else { return 0 }
        // macOS says the pack is full before this horizon ends, so the answer is
        // everything that is left rather than the linear projection.
        if let timeToFullMinutes, Double(timeToFullMinutes) <= minutes {
            return headroomPercent
        }
        return min(percentPerMinute * minutes, headroomPercent)
    }

    /// nil whenever there is nothing honest to show: not charging, already full,
    /// or no usable current/counter reading. Callers fall back to the plain
    /// percentage rather than printing a zero.
    static func resolve(
        data: BatteryData,
        samples: [RealtimeDataPoint],
        now: Date = Date()
    ) -> ChargeSpeedEstimate? {
        // Same charging verdict as the state line and the charging-power card.
        // Reading `data.isCharging` directly here would put the flow diagram's
        // `≈+x%/5m` badge (PowerFlowDiagram, shown only when an estimate exists)
        // on a different rule from the green adapter→battery edge beside it,
        // which is lit from `batteryPowerWatts` — a lit edge with no number next
        // to it. The snapshot has to be built before the guard that uses it.
        let snapshot = DashboardMetricSnapshot(data: data, realtimeData: samples)
        guard snapshot.isEffectivelyCharging else { return nil }

        // No separate `!isFullyCharged` guard: the flag can be set while current
        // is still going in, and rejecting that case would leave the state line
        // saying "charging" and the time-to-full row populated while the speed
        // silently vanished. A pack with no headroom is caught right below, which
        // is the condition that actually matters.
        let headroom = 100 - Double(max(0, min(100, data.percent)))
        guard headroom > 0 else { return nil }

        let capacity = fullChargeCapacity(data)
        guard capacity > 0 else { return nil }

        let rate = measuredRate(samples: samples, capacity: capacity, now: now)
            ?? derivedRate(snapshot: snapshot, capacity: capacity)
        guard let rate, rate.value > minimumMeaningfulRate, rate.value.isFinite else { return nil }

        return ChargeSpeedEstimate(
            percentPerMinute: rate.value,
            headroomPercent: headroom,
            timeToFullMinutes: snapshot.timeToFullMinutes,
            source: rate.source
        )
    }

    // MARK: - Sources

    private struct Rate {
        let value: Double
        let source: Source
    }

    /// The pack's full-charge capacity in mAh. `appleRawMaxCapacity` is the field
    /// the counter is measured against; `maxCapacity` is the compatible fallback.
    private static func fullChargeCapacity(_ data: BatteryData) -> Int {
        max(data.hardwareDetail.appleRawMaxCapacity, data.maxCapacity)
    }

    /// Difference the charge counter between two gauge publishes.
    ///
    /// The endpoints are chosen by *counter change*, not by window edge. Picking
    /// the oldest sample inside the window instead would divide by the full two
    /// minutes while the counter had only advanced during part of it — and when
    /// the gauge had not republished at all it would difference a value against
    /// itself and report a rate of zero on a machine that is visibly charging.
    private static func measuredRate(
        samples: [RealtimeDataPoint],
        capacity: Int,
        now: Date
    ) -> Rate? {
        guard let latest = samples.last,
              let latestCapacity = latest.rawCurrentCapacity,
              latest.isOnAC,
              now.timeIntervalSince(latest.timestamp) <= maximumWindowSeconds else { return nil }

        for sample in samples.dropLast().reversed() {
            // The cable coming out ends the charge session; samples from before
            // it describe a different one.
            guard sample.isOnAC, let capacityThen = sample.rawCurrentCapacity else { return nil }

            let span = latest.timestamp.timeIntervalSince(sample.timestamp)
            guard span <= maximumWindowSeconds else { return nil }

            // Both conditions have to hold at the same endpoint, and either one
            // failing means keep walking back rather than give up:
            //   - too close in time: a 20-second span is gauge jitter, not a rate
            //   - same counter value: the gauge had not republished yet
            // Bailing out on the first *differing* sample was wrong — with a
            // 10-second poll the nearest change is usually only 60 s back, which
            // would reject every window that a longer look-back would satisfy.
            guard span >= minimumWindowSeconds, capacityThen != latestCapacity else { continue }

            // Counter went down while nominally charging: not a charge rate.
            guard latestCapacity > capacityThen else { return nil }

            let gainedPercent = Double(latestCapacity - capacityThen) / Double(capacity) * 100
            let rate = gainedPercent / (span / 60)
            guard rate.isFinite, rate > minimumMeaningfulRate else { return nil }
            return Rate(value: rate, source: .measured)
        }
        return nil
    }

    /// Cold-start estimate: charge current ÷ capacity.
    ///
    /// Current over capacity rather than watts over watt-hours. The two are the
    /// same quantity at one pack voltage, but this form needs no entry in
    /// `BatteryModelSpecification`, so it still works on a Mac the model table
    /// has never heard of. The current itself comes from
    /// `batteryChargingCurrentMilliamps` so this cannot disagree with the
    /// charging-power card about which raw field to trust.
    private static func derivedRate(snapshot: DashboardMetricSnapshot, capacity: Int) -> Rate? {
        guard let milliamps = snapshot.batteryChargingCurrentMilliamps, milliamps > 0 else { return nil }
        let rate = Double(milliamps) / Double(capacity) * 100 / 60
        guard rate.isFinite, rate > minimumMeaningfulRate else { return nil }
        return Rate(value: rate, source: .derived)
    }
}
