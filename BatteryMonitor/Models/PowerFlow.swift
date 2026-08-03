import Foundation

/// Who is powering whom, right now.
///
/// ## Why this is not built on `PowerTelemetryData`
///
/// The first version of this type read `SystemPowerIn` / `BatteryPower` /
/// `SystemLoad`, because those three satisfy
/// `systemPowerIn − batteryPower = systemLoad` exactly and so the arrows were
/// guaranteed to add up. That guarantee turned out to be worthless: the relation
/// is an identity Apple computes, so it holds just as exactly when the numbers
/// are wrong. A 40-sample run on AC (`QATests/BuildValidation/telemetry-plugged-*.log`)
/// caught all three fields misreporting:
///
///     t=81  SystemLoad = 1499 mW          BatteryData.SystemPower = 9.20 W
///     t=42  SystemPowerIn = 15 mW         ExternalConnected = true, machine running
///     t=0   BatteryPower = −3380 mW       Amperage × Voltage = −10160 mW
///
/// A Mac with its display on does not run at 1.5 W. The group is internally
/// consistent and externally false, which is the worst combination available:
/// it drew a battery-powered Mac while the adapter was charging, and an adapter
/// charging the battery while the pack was draining.
///
/// ## What it is built on instead
///
/// The signed battery current from the gauge's coulomb counter, times pack
/// voltage. That is the same field the dashboard's "current" row displays, so
/// the diagram and that row cannot contradict each other — the failure the
/// telemetry version shipped. The adapter's two edges are then reconstructed
/// from conservation against total system power rather than read from
/// `SystemPowerIn`, which is unreliable on AC.
struct PowerFlow: Equatable {
    /// Where the numbers came from, so the UI can say so rather than implying
    /// every Mac reports the same fields.
    enum Origin: Equatable {
        /// A signed battery current was available: every edge is grounded.
        case measured
        /// No current field at all. Total draw is still known, but which side is
        /// supplying it is not, so the battery edge is omitted rather than guessed.
        case partial
    }

    /// Adapter power feeding the machine — total draw minus whatever the battery
    /// is contributing. nil when nothing is plugged in.
    let adapterToMac: Double?
    /// Charge flowing into the battery. nil unless the battery is actually taking
    /// charge.
    let adapterToBattery: Double?
    /// Battery discharge feeding the machine. nil unless the battery is actually
    /// giving power back — which happens while plugged in more often than the
    /// `IsCharging` flag suggests.
    let batteryToMac: Double?
    /// What the whole machine is drawing.
    let macConsumption: Double?
    /// The adapter's rated wattage, for the node label. nil when unplugged.
    let adapterRatedWatts: Int?
    let origin: Origin

    /// Below this, a reading is noise rather than a flow: the gauge reports tiny
    /// non-zero values while idle, and drawing a 0.0 W arrow is worse than
    /// drawing none.
    static let minimumMeaningfulWatts = 0.05

    static func resolve(_ s: DashboardMetricSnapshot) -> PowerFlow {
        let ratedWatts = s.data.chargerWattage > 0 ? s.data.chargerWattage : nil
        let load = max(0, s.currentPowerWatts)

        // Off the adapter there is exactly one thing that can be powering the
        // machine, and it is not a measurement question. Deriving this edge from
        // the pack current instead was wrong twice over: the reading lags a plug
        // event by up to a gauge tick and can still be *positive* seconds after
        // the cable is out (measured +2.88 A while unplugged), which blanked the
        // whole diagram; and even when the sign is right the pack rail and the
        // system rail disagree by a couple of watts, so the one inbound arrow did
        // not match the number on the Mac node (8.6 W in, 11.1 W consumed).
        guard s.data.isOnAC else {
            return PowerFlow(
                adapterToMac: nil,
                adapterToBattery: nil,
                batteryToMac: positive(load),
                macConsumption: positive(load),
                adapterRatedWatts: nil,
                origin: s.batteryPowerWatts == nil ? .partial : .measured
            )
        }

        guard let batteryWatts = s.batteryPowerWatts else {
            // Total draw is still real; the adapter must be covering it if one is
            // attached. The battery edge stays absent rather than assumed zero.
            return PowerFlow(
                adapterToMac: positive(load),
                adapterToBattery: nil,
                batteryToMac: nil,
                macConsumption: positive(load),
                adapterRatedWatts: ratedWatts,
                origin: .partial
            )
        }

        // Discharge is clamped to total draw. The pack reading and the system
        // power reading come off different rails and disagree by a watt or two
        // (measured 11.70 vs 9.20 at t=81); without the clamp the battery would
        // be drawn supplying more than the machine consumes, and the two inbound
        // arrows would visibly fail to sum to the Mac's number.
        let charge = max(0, batteryWatts)
        let discharge = min(max(0, -batteryWatts), load)

        return PowerFlow(
            adapterToMac: positive(load - discharge),
            adapterToBattery: positive(charge),
            batteryToMac: positive(discharge),
            macConsumption: positive(load),
            adapterRatedWatts: ratedWatts,
            origin: .measured
        )
    }

    private static func positive(_ watts: Double) -> Double? {
        guard watts.isFinite, watts >= minimumMeaningfulWatts else { return nil }
        return watts
    }

    /// True when nothing is moving in either direction — a freshly woken Mac
    /// before the gauge has published, for instance.
    var isIdle: Bool {
        adapterToMac == nil && adapterToBattery == nil && batteryToMac == nil
    }
}
