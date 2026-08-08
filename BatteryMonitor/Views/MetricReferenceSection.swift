import SwiftUI

// MARK: - 5. Current values beside their ranges

struct MetricReferenceSection: View {
    let snapshot: DashboardMetricSnapshot
    @Binding var selectedHelp: MetricHelpContent?

    private var metrics: [ReferenceMetric] {
        let detail = snapshot.detail
        let delta = detail.cellVoltageDelta ?? 0
        let maxResistance = detail.weightedRa.max() ?? 0
        let cycleUsage = (detail.cycleUsage ?? 0) * 100
        let packVoltage = snapshot.voltageVolts

        return [
            ReferenceMetric(
                icon: .balance,
                title: dashboardText("insight.factor.balance"),
                current: "\(delta) mV",
                range: "0–20 mV",
                history: detail.cellVoltages.isEmpty
                    ? dashboardText("p.history_learning")
                    : detail.cellVoltages.map(String.init).joined(separator: " / ") + " mV",
                low: dashboardText("p.cb_ok"),
                high: dashboardText("p.cb_bad"),
                source: dashboardText("p.src_lit"),
                color: delta <= 20 ? AppTheme.chargingCyan : AppTheme.batteryYellow,
                help: { DashboardHelp.cellBalance(snapshot) }
            ),
            ReferenceMetric(
                icon: .resistance,
                title: dashboardText("insight.factor.resistance"),
                current: "\(maxResistance) mΩ",
                range: "0–130 mΩ",
                history: detail.weightedRa.isEmpty
                    ? dashboardText("p.history_learning")
                    : detail.weightedRa.map(String.init).joined(separator: " / ") + " mΩ",
                low: dashboardText("p.ra_ok"),
                high: dashboardText("p.ra_bad"),
                source: dashboardText("p.src_none_short"),
                color: maxResistance <= 130 ? AppTheme.chargingCyan : AppTheme.batteryYellow,
                help: { DashboardHelp.resistance(snapshot) }
            ),
            ReferenceMetric(
                icon: .cycles,
                title: dashboardText("insight.factor.cycles"),
                current: LNum("%.1f%%", cycleUsage),
                range: "0–50%",
                history: "\(detail.cycleCount) / \(max(detail.designCycleCount, 0))",
                low: dashboardText("p.cycle_low_short"),
                high: dashboardText("p.cycle_high_short"),
                source: dashboardText("p.src_apple"),
                color: cycleUsage <= 50 ? AppTheme.chargingCyan : AppTheme.batteryYellow,
                help: { DashboardHelp.cycles(snapshot) }
            ),
            ReferenceMetric(
                icon: .voltage,
                title: dashboardText("hw.m.pack_voltage"),
                current: LNum("%.2f V", packVoltage),
                range: detail.minimumPackVoltage > 0 && detail.maximumPackVoltage > 0
                    ? snapshot.voltageHistoryText : "—",
                history: snapshot.voltageHistoryText,
                low: dashboardText("p.pv_low"),
                high: dashboardText("p.pv_high"),
                source: dashboardText("p.src_personal"),
                color: AppTheme.accentPurple,
                help: { DashboardHelp.packVoltage(snapshot) }
            ),
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            DashboardSectionHeader(
                icon: "scale.3d",
                title: dashboardText("p.spec_other_title"),
                color: AppTheme.accentPurple,
                help: { DashboardHelp.specOverview(snapshot) },
                selection: $selectedHelp
            )

            Text(dashboardText("p.spec_other_sub"))
                .font(.system(size: 11))
                .foregroundStyle(AppTheme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)

            ViewThatFits(in: .horizontal) {
                referenceTable
                    .frame(minWidth: 890)
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    referenceCards
                }
                VStack(spacing: 10) { referenceCards }
            }

            Text(dashboardText("p.spec_source_note"))
                .font(.system(size: 9))
                .foregroundStyle(AppTheme.textTertiary)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 8).fill(AppTheme.contrastOverlay(0.018)))
        }
        .padding(22)
        .finalDashboardCard(accent: AppTheme.accentPurple)
    }

    private var referenceTable: some View {
        VStack(spacing: 0) {
            ReferenceTableRow(
                values: [
                    dashboardText("p.spec_metric"),
                    dashboardText("p.spec_current"),
                    dashboardText("p.good_range"),
                    dashboardText("p.history_extreme"),
                    dashboardText("p.low_effect"),
                    dashboardText("p.high_effect"),
                    dashboardText("p.spec_source"),
                ],
                weights: [1.25, 0.72, 0.8, 1.0, 1.75, 1.75, 0.9],
                isHeader: true
            )
            ForEach(metrics) { metric in
                ReferenceMetricRow(metric: metric, selection: $selectedHelp)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(AppTheme.contrastOverlay(0.06)))
    }

    @ViewBuilder
    private var referenceCards: some View {
        ForEach(metrics) { metric in
            ReferenceMetricCard(metric: metric, selection: $selectedHelp)
        }
    }
}

private struct ReferenceMetric: Identifiable {
    let icon: BatteryMetricIcon
    let title: String
    let current: String
    let range: String
    let history: String
    let low: String
    let high: String
    let source: String
    let color: Color
    /// Lazy: this metric is rendered in two ViewThatFits branches, so eagerly
    /// building the help sheet meant constructing it twice per redraw for a
    /// panel that is usually never opened.
    let help: () -> MetricHelpContent
    /// Was `help.id`, which forced the whole sheet to be built just to identify
    /// a row. The title is already unique within this table.
    var id: String { title }

    init(icon: BatteryMetricIcon, title: String, current: String, range: String, history: String,
         low: String, high: String, source: String, color: Color,
         help: @escaping () -> MetricHelpContent) {
        self.icon = icon; self.title = title; self.current = current
        self.range = range; self.history = history; self.low = low; self.high = high
        self.source = source; self.color = color; self.help = help
    }
}

private struct ReferenceTableRow: View {
    let values: [String]
    let weights: [CGFloat]
    var isHeader = false

    var body: some View {
        GeometryReader { geometry in
            let total = max(weights.reduce(0, +), 0.1)
            HStack(alignment: .top, spacing: 0) {
                ForEach(values.indices, id: \.self) { index in
                    Text(values[index])
                        .font(.system(size: isHeader ? 8.5 : 9, weight: isHeader ? .medium : .regular))
                        .foregroundStyle(isHeader ? AppTheme.textTertiary : AppTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(width: geometry.size.width * weights[index] / total, alignment: .topLeading)
                        .padding(.horizontal, 8)
                }
            }
        }
        .frame(height: isHeader ? 34 : 76)
        .padding(.vertical, isHeader ? 8 : 10)
        .background(isHeader ? AppTheme.contrastOverlay(0.032) : AppTheme.contrastOverlay(0.012))
    }
}

private struct ReferenceMetricRow: View {
    let metric: ReferenceMetric
    @Binding var selection: MetricHelpContent?

    private let weights: [CGFloat] = [1.25, 0.72, 0.8, 1.0, 1.75, 1.75, 0.9]

    var body: some View {
        GeometryReader { geometry in
            let total = max(weights.reduce(0, +), 0.1)
            HStack(alignment: .top, spacing: 0) {
                metricLabel
                    .frame(width: geometry.size.width * weights[0] / total, alignment: .topLeading)
                tableText(metric.current, color: metric.color)
                    .frame(width: geometry.size.width * weights[1] / total, alignment: .topLeading)
                tableText(metric.range, color: AppTheme.chargingCyan)
                    .frame(width: geometry.size.width * weights[2] / total, alignment: .topLeading)
                tableText(metric.history)
                    .frame(width: geometry.size.width * weights[3] / total, alignment: .topLeading)
                tableText(metric.low)
                    .frame(width: geometry.size.width * weights[4] / total, alignment: .topLeading)
                tableText(metric.high)
                    .frame(width: geometry.size.width * weights[5] / total, alignment: .topLeading)
                tableText(metric.source, color: AppTheme.accentPurple)
                    .frame(width: geometry.size.width * weights[6] / total, alignment: .topLeading)
            }
        }
        .frame(height: 94)
        .padding(.horizontal, 8)
        .padding(.vertical, 12)
        .background(AppTheme.contrastOverlay(0.012))
        .overlay(alignment: .top) { Rectangle().fill(AppTheme.contrastOverlay(0.05)).frame(height: 1) }
    }

    private var metricLabel: some View {
        HStack(spacing: 4) {
            MetricGlyph(metric.icon, tint: metric.color, scale: .micro, style: .plain)
            Text(metric.title)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(AppTheme.textPrimary)
            MetricHelpButton(content: metric.help(), selection: $selection)
        }
        .padding(.horizontal, 8)
    }

    private func tableText(_ text: String, color: Color = AppTheme.textSecondary) -> some View {
        Text(text)
            .font(.system(size: 8.5))
            .foregroundStyle(color)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 8)
    }
}

private struct ReferenceMetricCard: View {
    let metric: ReferenceMetric
    @Binding var selection: MetricHelpContent?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                MetricGlyph(metric.icon, tint: metric.color, scale: .compact)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 4) {
                        Text(metric.title)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(AppTheme.textPrimary)
                        MetricHelpButton(content: metric.help(), selection: $selection)
                    }
                    Text(metric.current)
                        .font(.system(size: 20, weight: .medium, design: .monospaced))
                        .foregroundStyle(metric.color)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(dashboardText("p.good_range"))
                    Text(metric.range).foregroundStyle(AppTheme.chargingCyan)
                }
                .font(.system(size: 8.5, design: .monospaced))
                .foregroundStyle(AppTheme.textTertiary)
            }

            labeledText(dashboardText("p.history_extreme"), metric.history)
            HStack(alignment: .top, spacing: 8) {
                effectBox(title: dashboardText("p.low_effect"), text: metric.low, color: AppTheme.chargingBlue)
                effectBox(title: dashboardText("p.high_effect"), text: metric.high, color: AppTheme.batteryYellow)
            }
            labeledText(dashboardText("p.spec_source"), metric.source)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 235, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 12).fill(AppTheme.contrastOverlay(0.018)))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(AppTheme.contrastOverlay(0.06)))
    }

    private func labeledText(_ label: String, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            Text(label).foregroundStyle(AppTheme.textTertiary)
            Text(text).foregroundStyle(AppTheme.textSecondary)
            Spacer()
        }
        .font(.system(size: 8.5))
    }

    private func effectBox(title: String, text: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.system(size: 8, weight: .semibold)).foregroundStyle(color)
            Text(text).font(.system(size: 8.5)).foregroundStyle(AppTheme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 8).fill(color.opacity(0.035)))
    }
}
