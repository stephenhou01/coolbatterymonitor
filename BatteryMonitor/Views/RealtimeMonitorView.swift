import SwiftUI
import Charts

struct RealtimeMonitorView: View {
    let dataPoints: [RealtimeDataPoint]
    let archivedDataPoints: [RealtimeDataPoint]
    let batteryData: BatteryData
    @State private var selectedMetric: MetricType = .power
    @State private var selectedRange: MetricHelpTrendRange = .tenMinutes
    @State private var selectedDate: Date?

    enum MetricType: String, CaseIterable, Identifiable {
        case voltage, amperage, power, temperature, percent
        case adapterRatedPower, adapterOutputPower, chargingPower, cycleCount, health

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .voltage: return L("rt.voltage")
            case .amperage: return L("rt.amperage")
            case .power: return L("rt.power")
            case .temperature: return L("rt.temperature")
            case .percent: return L("rt.percent")
            case .adapterRatedPower: return L("shell.adapter")
            case .adapterOutputPower: return L("shell.adapter_output_power")
            case .chargingPower: return L("menu.metric.charge_power")
            case .cycleCount: return L("menu.metric.cycles")
            case .health: return L("menu.metric.health")
            }
        }

        var tooltipKey: String {
            switch self {
            case .voltage: return "tip.voltage"
            case .amperage: return "tip.amperage"
            case .power: return "p.help_summary_power"
            case .temperature: return "tip.temperature"
            case .percent: return "tip.percent"
            case .adapterRatedPower: return "p.help_summary_adapter_power"
            case .adapterOutputPower: return "p.help_summary_adapter_output_power"
            case .chargingPower: return "p.help_summary_charging_power"
            case .cycleCount: return "p.help_summary_cycle_count"
            case .health: return "p.help_summary_health"
            }
        }

        var unit: String {
            switch self {
            case .voltage: return "V"
            case .amperage: return "mA"
            case .power, .adapterRatedPower, .adapterOutputPower, .chargingPower: return "W"
            case .temperature: return "℃"
            case .percent, .health: return "%"
            case .cycleCount: return ""
            }
        }
    }

    private var historySource: [RealtimeDataPoint] {
        TelemetryHistoryArchive.mergedHistory(archive: archivedDataPoints, raw: dataPoints)
    }

    private var visiblePoints: [MetricHelpTrendPoint] {
        selectedRange.chartPoints(from: historySource.compactMap { point in
            guard let value = metricValue(point), value.isFinite else { return nil }
            return MetricHelpTrendPoint(timestamp: point.timestamp,
                                        value: value,
                                        sampleCount: point.sampleCount)
        })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                MetricGlyph(
                    .power,
                    tint: AppTheme.chargingCyan,
                    scale: .compact
                )
                HStack(spacing: 4) {
                    Text(L("rt.title"))
                        .font(AppTheme.Typography.sectionTitle)
                        .foregroundStyle(AppTheme.textPrimary)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                    Image(systemName: "exclamationmark.circle")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(AppTheme.textTertiary.opacity(0.5))
                        .help(L(selectedMetric.tooltipKey))
                }
                Spacer()
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 5), spacing: 6) {
                ForEach(MetricType.allCases) { metric in
                    Button {
                        selectedMetric = metric
                        selectedDate = nil
                    } label: {
                        Text(metric.displayName)
                            .font(.system(size: 10.5, weight: .semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                            .frame(maxWidth: .infinity, minHeight: 30)
                            .foregroundStyle(selectedMetric == metric ? AppTheme.selectionText : AppTheme.textSecondary)
                            .background(RoundedRectangle(cornerRadius: 7)
                                .fill(selectedMetric == metric ? chartColor(for: metric) : AppTheme.contrastOverlay(0.035)))
                    }
                    .buttonStyle(.plain)
                    .pointerOnHover()
                }
            }

            HStack(spacing: 10) {
                Picker("", selection: $selectedRange) {
                    ForEach(MetricHelpTrendRange.allCases) { range in
                        Text(range.title).tag(range)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 430)
                Spacer()
                Text(selectedRange.samplingSummary)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(AppTheme.textTertiary)
            }

            chartView
                .frame(height: 200)

            currentStatsRow
        }
        .padding(AppTheme.Spacing.xl)
        .modifier(AppTheme.card())
    }

    // MARK: - Chart View

    @ViewBuilder
    private var chartView: some View {
        if visiblePoints.count < 2 {
            VStack(spacing: 12) {
                ProgressView()
                    .progressViewStyle(.circular)
                    .scaleEffect(0.8)
                Text(L("rt.collecting"))
                    .font(.system(size: 13))
                    .foregroundStyle(AppTheme.textSecondary)
                Text(selectedRange.samplingSummary)
                    .font(.system(size: 11))
                    .foregroundStyle(AppTheme.textTertiary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Chart {
                if Set(visiblePoints.map(\.segmentID)).count == 1 {
                    ForEach(visiblePoints) { point in
                        AreaMark(
                            x: .value(L("rt.time"), point.timestamp),
                            y: .value(selectedMetric.displayName, point.value)
                        )
                        .foregroundStyle(LinearGradient(
                            colors: [chartColor.opacity(0.24), chartColor.opacity(0.02)],
                            startPoint: .top, endPoint: .bottom
                        ))
                        .interpolationMethod(selectedRange == .tenMinutes ? .stepEnd : .linear)
                    }
                }

                ForEach(visiblePoints) { point in
                    LineMark(
                        x: .value(L("rt.time"), point.timestamp),
                        y: .value(selectedMetric.displayName, point.value),
                        series: .value("Segment", point.segmentID)
                    )
                    .foregroundStyle(chartColor)
                    .interpolationMethod(selectedRange == .tenMinutes ? .stepEnd : .linear)
                    .lineStyle(StrokeStyle(lineWidth: 2))

                    if point.quality == .fitted {
                        PointMark(x: .value("Fitted time", point.timestamp),
                                  y: .value("Fitted value", point.value))
                            .foregroundStyle(AppTheme.surfaceRaised)
                            .symbolSize(28)
                            .annotation(position: .overlay) {
                                Circle().stroke(chartColor, lineWidth: 1).frame(width: 6, height: 6)
                            }
                    }
                }

                if let hovered = hoveredPoint {
                    RuleMark(x: .value(L("rt.time"), hovered.timestamp))
                        .foregroundStyle(chartColor.opacity(0.5))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                        .annotation(position: .top, alignment: .leading, spacing: 2,
                                    overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                            Text(hoverReadout(hovered))
                                .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                                .foregroundStyle(AppTheme.textPrimary)
                                .monospacedDigit()
                                .fixedSize()
                                .padding(.horizontal, 7)
                                .padding(.vertical, 4)
                                .background(RoundedRectangle(cornerRadius: 7)
                                    .fill(AppTheme.surfaceRaised.opacity(0.96)))
                                .overlay(RoundedRectangle(cornerRadius: 7)
                                    .stroke(AppTheme.cardBorder))
                        }
                    PointMark(
                        x: .value(L("rt.time"), hovered.timestamp),
                        y: .value(selectedMetric.displayName, hovered.value)
                    )
                    .foregroundStyle(chartColor)
                    .symbolSize(46)
                }
            }
            .chartXSelection(value: $selectedDate)
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 5)) { value in
                    AxisGridLine()
                        .foregroundStyle(AppTheme.cardBorder)
                    AxisValueLabel {
                        if let date = value.as(Date.self) {
                            Text(date, format: selectedRange == .tenMinutes
                                 ? .dateTime.hour().minute().second()
                                 : .dateTime.hour().minute())
                                .font(.system(size: 9))
                                .foregroundStyle(AppTheme.textTertiary)
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine()
                        .foregroundStyle(AppTheme.cardBorder)
                    AxisValueLabel {
                        if let doubleVal = value.as(Double.self) {
                            Text(LNum("%.1f", doubleVal))
                                .font(.system(size: 9))
                                .foregroundStyle(AppTheme.textTertiary)
                        }
                    }
                }
            }
            .chartYAxisLabel(yAxisLabel, position: .leading)
            .animation(.easeInOut(duration: 0.3), value: visiblePoints.count)
            .animation(.easeInOut(duration: 0.3), value: selectedRange)
        }
    }

    // MARK: - Current Stats Row

    private var currentStatsRow: some View {
        HStack(spacing: 12) {
            StatMiniCard(
                icon: .power,
                label: L("rt.power"),
                value: LNum("%.1fW", batteryData.currentPowerWatts),
                color: AppTheme.chargingBlue,
                tooltipKey: "p.help_summary_power"
            )
            StatMiniCard(
                icon: .voltage,
                label: L("rt.voltage"),
                value: LNum("%.2fV", batteryData.voltage),
                color: AppTheme.accentPurple,
                tooltipKey: "tip.voltage"
            )
            StatMiniCard(
                icon: .current,
                label: L("rt.amperage"),
                value: "\(batteryData.amperage)mA",
                color: AppTheme.chargingCyan,
                tooltipKey: "tip.amperage"
            )
            StatMiniCard(
                icon: .temperature,
                label: L("rt.temperature"),
                value: LNum("%.1f°C", batteryData.temperatureCelsius),
                color: tempColor,
                tooltipKey: "tip.temperature"
            )
        }
    }

    // MARK: - Helpers

    private var hoveredPoint: MetricHelpTrendPoint? {
        guard let selectedDate else { return nil }
        return visiblePoints.min {
            abs($0.timestamp.timeIntervalSince(selectedDate)) < abs($1.timestamp.timeIntervalSince(selectedDate))
        }
    }

    private func hoverReadout(_ point: MetricHelpTrendPoint) -> String {
        let time = point.timestamp.formatted(selectedRange == .tenMinutes
            ? .dateTime.hour().minute().second()
            : .dateTime.hour().minute())
        let fitted = point.quality == .fitted ? " · \(dashboardText("p.trend_fitted", fallback: "拟合"))" : ""
        return "\(time) · \(formatted(point.value))\(fitted)"
    }

    private func metricValue(_ point: RealtimeDataPoint) -> Double? {
        switch selectedMetric {
        case .voltage: return point.voltage
        case .amperage: return point.amperage
        case .power: return point.power
        case .temperature: return point.temperature
        case .percent: return Double(point.percent)
        case .adapterRatedPower:
            return point.adapterRatedPower ?? {
                guard let volts = point.adapterVoltage, let amps = point.adapterCurrent else { return nil }
                return volts * amps
            }()
        case .adapterOutputPower: return point.adapterOutputPower
        case .chargingPower: return point.chargingPower
        case .cycleCount: return point.cycleCount.map(Double.init)
        case .health: return point.healthPercent
        }
    }

    private func formatted(_ value: Double) -> String {
        switch selectedMetric {
        case .cycleCount: return LNum("%.0f", value)
        case .percent, .health: return LNum("%.1f%%", value)
        case .voltage: return LNum("%.2f V", value)
        case .amperage: return LNum("%.0f mA", value)
        case .temperature: return LNum("%.1f ℃", value)
        case .power, .adapterRatedPower, .adapterOutputPower, .chargingPower:
            return LNum("%.1f W", value)
        }
    }

    private var chartColor: Color {
        chartColor(for: selectedMetric)
    }

    private func chartColor(for metric: MetricType) -> Color {
        switch metric {
        case .voltage: return AppTheme.accentPurple
        case .amperage: return AppTheme.chargingCyan
        case .power: return AppTheme.chargingBlue
        case .temperature: return AppTheme.batteryYellow
        case .percent: return AppTheme.batteryGreen
        case .adapterRatedPower: return AppTheme.batteryYellow
        case .adapterOutputPower: return AppTheme.chargingCyan
        case .chargingPower: return AppTheme.batteryGreen
        case .cycleCount: return AppTheme.accentPurple
        case .health: return AppTheme.batteryGreen
        }
    }

    private var yAxisLabel: String {
        switch selectedMetric {
        case .voltage: return L("rt.y_voltage")
        case .amperage: return L("rt.y_amperage")
        case .power: return L("rt.y_power")
        case .temperature: return L("rt.y_temperature")
        case .percent: return L("rt.y_percent")
        case .adapterRatedPower, .adapterOutputPower, .chargingPower:
            return "\(selectedMetric.displayName) (W)"
        case .cycleCount: return selectedMetric.displayName
        case .health: return "\(selectedMetric.displayName) (%)"
        }
    }

    private var tempColor: Color {
        if batteryData.temperatureCelsius > 40 { return AppTheme.batteryRed }
        if batteryData.temperatureCelsius > 35 { return AppTheme.batteryYellow }
        return AppTheme.batteryGreen
    }
}

// MARK: - Mini Stat Card

struct StatMiniCard: View {
    let icon: BatteryMetricIcon
    let label: String
    let value: String
    let color: Color
    var tooltipKey: String? = nil

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                MetricGlyph(icon, tint: color, scale: .micro, style: .plain)
                Text(label)
                    .font(.system(size: 10))
                    .foregroundStyle(AppTheme.textTertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                if let key = tooltipKey {
                    Image(systemName: "exclamationmark.circle")
                        .font(.system(size: 8, weight: .medium))
                        .foregroundStyle(AppTheme.textTertiary.opacity(0.5))
                        .help(L(key))
                }
            }
            Text(value)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(color.opacity(0.08))
        )
    }
}
