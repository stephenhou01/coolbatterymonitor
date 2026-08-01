import SwiftUI
import Charts

struct RealtimeMonitorView: View {
    let dataPoints: [RealtimeDataPoint]
    let batteryData: BatteryData
    @State private var selectedMetric: MetricType = .power
    @State private var selectedRange: TimeRange = .oneMinute
    @State private var appeared = false

    enum MetricType: String, CaseIterable {
        case voltage, amperage, power, temperature, percent

        var displayName: String {
            switch self {
            case .voltage: return L("rt.voltage")
            case .amperage: return L("rt.amperage")
            case .power: return L("rt.power")
            case .temperature: return L("rt.temperature")
            case .percent: return L("rt.percent")
            }
        }

        var tooltipKey: String {
            switch self {
            case .voltage: return "tip.voltage"
            case .amperage: return "tip.amperage"
            case .power: return "tip.power"
            case .temperature: return "tip.temperature"
            case .percent: return "tip.percent"
            }
        }
    }

    enum TimeRange: String, CaseIterable {
        case thirtySec, oneMinute, threeMinutes

        var displayName: String {
            switch self {
            case .thirtySec: return L("rt.30s")
            case .oneMinute: return L("rt.1m")
            case .threeMinutes: return L("rt.3m")
            }
        }

        var seconds: TimeInterval {
            switch self {
            case .thirtySec: return 30
            case .oneMinute: return 60
            case .threeMinutes: return 180
            }
        }
    }

    private var visiblePoints: [RealtimeDataPoint] {
        guard let last = dataPoints.last else { return dataPoints }
        let cutoff = last.timestamp.addingTimeInterval(-selectedRange.seconds)
        return dataPoints.filter { $0.timestamp >= cutoff }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
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
                        // 不加这两行，德语「Echtzeit-Monitor」会被右侧 segmented Picker
                        // （metric 名在西文里宽得多）挤成竖排 4 行
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                    // Tooltip follows the selected metric — the only surface for tip.percent,
                    // since "percent" has no mini card in currentStatsRow.
                    Image(systemName: "exclamationmark.circle")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(AppTheme.textTertiary.opacity(0.5))
                        .help(L(selectedMetric.tooltipKey))
                }
                Spacer()
            }

            // Metric selector 独占一行。
            //
            // 原来它和标题挤在同一行，两者都 fixedSize 不能压缩：实测法语头部需求
            // 542pt / 意大利语 558pt，而右栏只有 552pt —— 余量只有几个 pt，任何字体
            // 度量误差都会让整块内容超出窗口，ScrollView 居中后两侧被裁，左边留白
            // 直接消失。独占一行后最宽的语言（法语 346pt）也有充裕余量。
            Picker("", selection: $selectedMetric) {
                ForEach(MetricType.allCases, id: \.self) { metric in
                    Text(metric.displayName).tag(metric)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            // Time range selector
            HStack(spacing: 8) {
                ForEach(TimeRange.allCases, id: \.self) { range in
                    Button {
                        selectedRange = range
                    } label: {
                        Text(range.displayName)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(selectedRange == range ? AppTheme.chargingCyan : AppTheme.textTertiary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 5)
                            .background(
                                Capsule().fill(selectedRange == range
                                    ? AppTheme.chargingCyan.opacity(0.15)
                                    : AppTheme.contrastOverlay(0.03))
                            )
                    }
                    .buttonStyle(.plain)
                    .pointerOnHover()
                }
                Spacer()
                Text(L("rt.interval"))
                    .font(.system(size: 10))
                    .foregroundStyle(AppTheme.textTertiary)
            }

            // Main chart
            chartView
                .frame(height: 200)

            // Current stats row
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
                Text(L("rt.collecting_hint"))
                    .font(.system(size: 11))
                    .foregroundStyle(AppTheme.textTertiary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Chart(visiblePoints) { point in
                LineMark(
                    x: .value(L("rt.time"), point.timestamp),
                    y: .value(selectedMetric.displayName, metricValue(point))
                )
                .foregroundStyle(chartColor)
                .interpolationMethod(.catmullRom)
                .lineStyle(StrokeStyle(lineWidth: 2))

                AreaMark(
                    x: .value(L("rt.time"), point.timestamp),
                    y: .value(selectedMetric.displayName, metricValue(point))
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [chartColor.opacity(0.3), chartColor.opacity(0.02)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .interpolationMethod(.catmullRom)
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 5)) { value in
                    AxisGridLine()
                        .foregroundStyle(AppTheme.cardBorder)
                    AxisValueLabel {
                        if let date = value.as(Date.self) {
                            Text(date, format: .dateTime.hour().minute().second())
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
                tooltipKey: "tip.power"
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

    private func metricValue(_ point: RealtimeDataPoint) -> Double {
        switch selectedMetric {
        case .voltage: return point.voltage
        case .amperage: return point.amperage
        case .power: return point.power
        case .temperature: return point.temperature
        case .percent: return Double(point.percent)
        }
    }

    private var chartColor: Color {
        switch selectedMetric {
        case .voltage: return AppTheme.accentPurple
        case .amperage: return AppTheme.chargingCyan
        case .power: return AppTheme.chargingBlue
        case .temperature: return AppTheme.batteryYellow
        case .percent: return AppTheme.batteryGreen
        }
    }

    private var yAxisLabel: String {
        switch selectedMetric {
        case .voltage: return L("rt.y_voltage")
        case .amperage: return L("rt.y_amperage")
        case .power: return L("rt.y_power")
        case .temperature: return L("rt.y_temperature")
        case .percent: return L("rt.y_percent")
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
                    .lineLimit(1)               // 同 StatCard：长语言标签不得换行撑高卡片
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
