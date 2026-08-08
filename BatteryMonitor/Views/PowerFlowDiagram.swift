import SwiftUI

/// Battery above, adapter below it, machine to the right — with an arrow on each
/// edge that carries power, labelled with its watts.
///
/// Laid out on one absolute canvas rather than nested stacks. The stack version
/// put all three edges in a column of their own beside the nodes, which left the
/// adapter→battery arrow floating in the gap instead of visibly joining the two
/// icons it describes. Here that edge is a plain vertical segment on the node
/// column's own centre line, between the adapter glyph and the battery glyph.
///
/// Each live edge carries a stream of pulses whose speed is proportional to its
/// watts, so the picture says how *hard* power is flowing and not only which way.
///
/// This was static for a long time on the grounds that a battery monitor running
/// a continuous animation undercuts its own point. That objection is answered by
/// gating rather than by refusing: the pulses stop under Reduce Motion, stop when
/// the user pauses live refresh, and stop whenever the hosting window is closed,
/// minimised or buried. What is left runs only while someone is actually looking
/// at it — see `PowerFlowAnimatedEdge` and `WindowVisibilityReader`.
struct PowerFlowDiagram: View {
    let flow: PowerFlow
    let batteryPercent: Int
    let batterySymbol: String
    /// Turns the adapter→battery arrow's watts into "and that means this much
    /// charge in five minutes". Only that one edge carries it: watts into the Mac
    /// are consumed, not stored, so there is no percentage to convert them into.
    var chargeSpeed: ChargeSpeedEstimate? = nil
    /// Mirrors the dashboard's own live-refresh switch. Pausing the readings and
    /// leaving the picture animating would be claiming motion the numbers behind
    /// it are no longer being updated to support.
    var isLive: Bool = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isWindowVisible = true

    private var hasAdapter: Bool { flow.adapterRatedWatts != nil }

    private var isAnimating: Bool { isLive && isWindowVisible && !reduceMotion }

    // One canvas, one coordinate system. Everything below is in these points.
    private static let canvas = CGSize(width: 290, height: 198)
    private static let columnX: CGFloat = 58
    private static let macX: CGFloat = 232

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                edges
                node(
                    symbol: batterySymbol,
                    tint: batteryTint,
                    title: dashboardText("shell.flow_battery"),
                    detail: "\(batteryPercent)%",
                    dimmed: flow.batteryToMac == nil && flow.adapterToBattery == nil
                )
                .frame(width: 104)
                .position(x: Self.columnX, y: 46)

                node(
                    symbol: "powerplug.fill",
                    tint: hasAdapter ? AppTheme.chargingBlue : AppTheme.textTertiary,
                    title: dashboardText("shell.flow_adapter"),
                    detail: flow.adapterRatedWatts.map { "\($0) W" }
                        ?? dashboardText("shell.not_connected"),
                    dimmed: !hasAdapter
                )
                .frame(width: 104)
                .position(x: Self.columnX, y: 158)

                node(
                    symbol: "laptopcomputer",
                    tint: AppTheme.textSecondary,
                    title: dashboardText("shell.flow_mac"),
                    detail: flow.macConsumption.map { LNum("%.1f W", $0) } ?? "—",
                    dimmed: false
                )
                .frame(width: 96)
                .position(x: Self.macX, y: 102)
            }
            .frame(width: Self.canvas.width, height: Self.canvas.height)

            if flow.origin == .partial {
                caption(dashboardText("shell.flow_derived"))
            } else if flow.isIdle {
                caption(dashboardText("shell.flow_idle"))
            } else if let source = chargeSpeed?.source, flow.adapterToBattery != nil {
                // The ≈ figure is the only predicted number in this drawing. Say so
                // right under it, and say which of the two bases produced it —
                // "not modelled" is the caveat a user needs before trusting it.
                caption(source == .measured
                        ? dashboardText("shell.flow_forecast_measured")
                        : dashboardText("shell.flow_forecast_derived"))
            }
        }
        .frame(maxWidth: .infinity)
        .background(WindowVisibilityReader(isVisible: $isWindowVisible).frame(width: 0, height: 0))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilitySummary)
    }

    private var batteryTint: Color {
        if flow.batteryToMac != nil { return AppTheme.chargingCyan }
        if flow.adapterToBattery != nil { return AppTheme.batteryGreen }
        return AppTheme.textTertiary
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 8.5))
            .foregroundStyle(AppTheme.textTertiary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Nodes

    private func node(symbol: String, tint: Color, title: String, detail: String, dimmed: Bool) -> some View {
        VStack(spacing: 4) {
            Image(systemName: symbol)
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(tint)
                .opacity(dimmed ? 0.4 : 1)
                .frame(height: 30)
            Text(title)
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundStyle(dimmed ? AppTheme.textTertiary : AppTheme.textSecondary)
            Text(detail)
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(dimmed ? AppTheme.textTertiary : tint)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
    }

    // MARK: - Edges

    private var edges: some View {
        ZStack {
            edge(geometry: Self.batteryToMac,
                 watts: flow.batteryToMac,
                 tint: AppTheme.chargingCyan,
                 labelAt: CGPoint(x: 120, y: 17))
            edge(geometry: Self.adapterToMac,
                 watts: flow.adapterToMac,
                 tint: AppTheme.chargingBlue,
                 labelAt: CGPoint(x: 130, y: 155))
            edge(geometry: Self.adapterToBattery,
                 watts: flow.adapterToBattery,
                 tint: AppTheme.batteryGreen,
                 labelAt: CGPoint(x: 92, y: 107),
                 secondLine: chargeGainText)
        }
    }

    /// "≈+4%/5m" — what the watts on this edge amount to over five minutes.
    /// Prefixed with ≈ because it is a prediction, not a reading.
    private var chargeGainText: String? {
        guard let chargeSpeed else { return nil }
        let minutes = MenuBarPresentation.chargeSpeedHorizons.short
        return LNum("≈+%.0f%%/%.0fm", chargeSpeed.gainPercent(overMinutes: minutes), minutes)
    }

    private func edge(
        geometry: PowerFlowEdgeGeometry,
        watts: Double?,
        tint: Color,
        labelAt: CGPoint,
        secondLine: String? = nil
    ) -> some View {
        ZStack {
            PowerFlowAnimatedEdge(geometry: geometry,
                                  watts: watts,
                                  tint: tint,
                                  isAnimating: isAnimating)
            if let watts {
                // Stacked, not appended: a single line of "11.9 W · ≈+4%/5m" grows
                // to about 80pt and runs into the Mac node, which starts at x=184.
                // The gap this label sits in is ~35pt tall, so two lines fit.
                VStack(spacing: 0) {
                    Text(LNum("%.1f W", watts))
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .foregroundStyle(tint)
                    if let secondLine {
                        Text(secondLine)
                            .font(.system(size: 8, weight: .medium, design: .rounded))
                            .foregroundStyle(tint.opacity(0.75))
                    }
                }
                .monospacedDigit()
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(Capsule().fill(AppTheme.cardBackground))
                .position(labelAt)
            }
        }
    }

    // Wire and arrowhead are described separately — see PowerFlowEdgeGeometry for
    // why. An inactive edge keeps the same geometry as an active one and changes
    // only weight and colour.

    /// Out of the battery's right side, along the top, down and into the Mac.
    private static let batteryToMac = PowerFlowEdgeGeometry(
        points: [CGPoint(x: 82, y: 30), CGPoint(x: 162, y: 30),
                 CGPoint(x: 162, y: 86), CGPoint(x: 206, y: 86)],
        arrowhead: PowerFlowEdgeGeometry.arrowRight(at: CGPoint(x: 206, y: 86))
    )

    /// Out of the adapter's right side, along the bottom, up and into the Mac on
    /// its own riser so the two inbound arrows never overlap.
    private static let adapterToMac = PowerFlowEdgeGeometry(
        points: [CGPoint(x: 82, y: 142), CGPoint(x: 184, y: 142),
                 CGPoint(x: 184, y: 96), CGPoint(x: 206, y: 96)],
        arrowhead: PowerFlowEdgeGeometry.arrowRight(at: CGPoint(x: 206, y: 96))
    )

    /// Straight up the node column's centre line, adapter glyph to battery glyph.
    private static let adapterToBattery = PowerFlowEdgeGeometry(
        points: [CGPoint(x: columnX, y: 124), CGPoint(x: columnX, y: 90)],
        arrowhead: PowerFlowEdgeGeometry.arrowUp(at: CGPoint(x: columnX, y: 90))
    )

    private var accessibilitySummary: String {
        var parts: [String] = []
        if let watts = flow.batteryToMac {
            parts.append(dashboardText("shell.flow_a11y_battery_to_mac",
                                       replacements: ["watts": LNum("%.1f", watts)]))
        }
        if let watts = flow.adapterToBattery {
            var line = dashboardText("shell.flow_a11y_adapter_to_battery",
                                     replacements: ["watts": LNum("%.1f", watts)])
            if let chargeGainText {
                line += "，\(chargeGainText)"
            }
            parts.append(line)
        }
        if let watts = flow.adapterToMac {
            parts.append(dashboardText("shell.flow_a11y_adapter_to_mac",
                                       replacements: ["watts": LNum("%.1f", watts)]))
        }
        if parts.isEmpty {
            parts.append(dashboardText("shell.flow_idle"))
        }
        return parts.joined(separator: "；")
    }
}
