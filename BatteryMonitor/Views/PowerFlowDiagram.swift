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
/// Deliberately static: the arrows say direction with shape and colour rather
/// than motion. A battery monitor that runs a continuous animation to describe
/// power draw would be undercutting its own point.
struct PowerFlowDiagram: View {
    let flow: PowerFlow
    let batteryPercent: Int
    let batterySymbol: String

    private var hasAdapter: Bool { flow.adapterRatedWatts != nil }

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
                    title: dashboardText("shell.flow_battery", fallback: "电池"),
                    detail: "\(batteryPercent)%",
                    dimmed: flow.batteryToMac == nil && flow.adapterToBattery == nil
                )
                .frame(width: 104)
                .position(x: Self.columnX, y: 46)

                node(
                    symbol: "powerplug.fill",
                    tint: hasAdapter ? AppTheme.chargingBlue : AppTheme.textTertiary,
                    title: dashboardText("shell.flow_adapter", fallback: "充电器"),
                    detail: flow.adapterRatedWatts.map { "\($0) W" }
                        ?? dashboardText("shell.not_connected", fallback: "未连接"),
                    dimmed: !hasAdapter
                )
                .frame(width: 104)
                .position(x: Self.columnX, y: 158)

                node(
                    symbol: "laptopcomputer",
                    tint: AppTheme.textSecondary,
                    title: dashboardText("shell.flow_mac", fallback: "这台 Mac"),
                    detail: flow.macConsumption.map { LNum("%.1f W", $0) } ?? "—",
                    dimmed: false
                )
                .frame(width: 96)
                .position(x: Self.macX, y: 102)
            }
            .frame(width: Self.canvas.width, height: Self.canvas.height)

            if flow.origin == .partial {
                caption(dashboardText("shell.flow_derived",
                                      fallback: "本机没有返回电池电流，只能显示整机功率"))
            } else if flow.isIdle {
                caption(dashboardText("shell.flow_idle", fallback: "此刻没有可测到的功率流动"))
            }
        }
        .frame(maxWidth: .infinity)
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
            edge(path: Self.batteryToMacPath,
                 watts: flow.batteryToMac,
                 tint: AppTheme.chargingCyan,
                 labelAt: CGPoint(x: 120, y: 17))
            edge(path: Self.adapterToMacPath,
                 watts: flow.adapterToMac,
                 tint: AppTheme.chargingBlue,
                 labelAt: CGPoint(x: 130, y: 155))
            edge(path: Self.adapterToBatteryPath,
                 watts: flow.adapterToBattery,
                 tint: AppTheme.batteryGreen,
                 labelAt: CGPoint(x: 92, y: 107))
        }
    }

    private func edge(path: Path, watts: Double?, tint: Color, labelAt: CGPoint) -> some View {
        ZStack {
            path.stroke(
                watts == nil ? AppTheme.textTertiary.opacity(0.22) : tint,
                style: StrokeStyle(lineWidth: watts == nil ? 1 : 1.8, lineCap: .round, lineJoin: .round)
            )
            if let watts {
                Text(LNum("%.1f W", watts))
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .foregroundStyle(tint)
                    .monospacedDigit()
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(AppTheme.cardBackground))
                    .position(labelAt)
            }
        }
    }

    // Arrowheads are baked into the paths so an inactive edge keeps the same
    // geometry as an active one and only changes weight and colour.

    /// Out of the battery's right side, along the top, down and into the Mac.
    private static let batteryToMacPath: Path = {
        var p = Path()
        p.move(to: CGPoint(x: 82, y: 30))
        p.addLine(to: CGPoint(x: 162, y: 30))
        p.addLine(to: CGPoint(x: 162, y: 86))
        p.addLine(to: CGPoint(x: 206, y: 86))
        p.addLines(arrowRight(at: CGPoint(x: 206, y: 86)))
        return p
    }()

    /// Out of the adapter's right side, along the bottom, up and into the Mac on
    /// its own riser so the two inbound arrows never overlap.
    private static let adapterToMacPath: Path = {
        var p = Path()
        p.move(to: CGPoint(x: 82, y: 142))
        p.addLine(to: CGPoint(x: 184, y: 142))
        p.addLine(to: CGPoint(x: 184, y: 96))
        p.addLine(to: CGPoint(x: 206, y: 96))
        p.addLines(arrowRight(at: CGPoint(x: 206, y: 96)))
        return p
    }()

    /// Straight up the node column's centre line, adapter glyph to battery glyph.
    private static let adapterToBatteryPath: Path = {
        var p = Path()
        p.move(to: CGPoint(x: columnX, y: 124))
        p.addLine(to: CGPoint(x: columnX, y: 90))
        p.addLines(arrowUp(at: CGPoint(x: columnX, y: 90)))
        return p
    }()

    private static func arrowRight(at tip: CGPoint) -> [CGPoint] {
        [CGPoint(x: tip.x - 7, y: tip.y - 5), tip, CGPoint(x: tip.x - 7, y: tip.y + 5)]
    }

    private static func arrowUp(at tip: CGPoint) -> [CGPoint] {
        [CGPoint(x: tip.x - 5, y: tip.y + 7), tip, CGPoint(x: tip.x + 5, y: tip.y + 7)]
    }

    private var accessibilitySummary: String {
        var parts: [String] = []
        if let watts = flow.batteryToMac {
            parts.append(dashboardText("shell.flow_a11y_battery_to_mac",
                                       fallback: "电池向这台 Mac 供电 {watts} W",
                                       replacements: ["watts": LNum("%.1f", watts)]))
        }
        if let watts = flow.adapterToBattery {
            parts.append(dashboardText("shell.flow_a11y_adapter_to_battery",
                                       fallback: "充电器向电池充电 {watts} W",
                                       replacements: ["watts": LNum("%.1f", watts)]))
        }
        if let watts = flow.adapterToMac {
            parts.append(dashboardText("shell.flow_a11y_adapter_to_mac",
                                       fallback: "充电器向这台 Mac 供电 {watts} W",
                                       replacements: ["watts": LNum("%.1f", watts)]))
        }
        if parts.isEmpty {
            parts.append(dashboardText("shell.flow_idle", fallback: "此刻没有可测到的功率流动"))
        }
        return parts.joined(separator: "；")
    }
}
