import SwiftUI
import Charts

struct DashboardTrendsPage: View {
    @EnvironmentObject private var batteryService: BatteryService
    @EnvironmentObject private var processService: ProcessMonitorService
    @Binding var selectedHelp: MetricHelpContent?

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                DashboardPageHeader(
                    title: DashboardDestination.trends.title,
                    subtitle: dashboardText("shell.trends_subtitle", fallback: "把实时波动与长期记录分开看")
                )
                RealtimeMonitorView(dataPoints: batteryService.realtimeData,
                                    batteryData: batteryService.batteryData)
                RuntimeHistorySummaryCard(samples: batteryService.runtimeSamples,
                                          fallbackMinutes: batteryService.batteryData.timeRemainingMinutes)
                ProcessListView(processes: processService.topProcesses,
                                hasSampled: processService.hasSampled,
                                onRefresh: processService.fetchProcesses)
                HistoryChartView(sessions: batteryService.chargingHistory,
                                 isLoading: batteryService.isLoadingHistory,
                                 onRefresh: batteryService.refreshHistory)
            }
            .frame(maxWidth: 1060)
            .padding(28)
            .frame(maxWidth: .infinity)
        }
        .background(AppTheme.background)
    }
}

private struct RuntimeHistorySummaryCard: View {
    let samples: [RuntimeSample]
    let fallbackMinutes: Int?

    private var points: [RuntimeSample] { Array(samples.suffix(120)) }
    /// Pointer position on the x axis, from Charts' own `chartXSelection`.
    @State private var selectedDate: Date?

    /// Snapped to a recorded sample rather than interpolated — every figure the
    /// readout shows is one macOS actually reported.
    private var hovered: RuntimeSample? {
        guard let selectedDate else { return nil }
        return points.min {
            abs($0.timestamp.timeIntervalSince(selectedDate)) < abs($1.timestamp.timeIntervalSince(selectedDate))
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: "clock.arrow.2.circlepath").foregroundStyle(AppTheme.chargingBlue)
                Text(dashboardText("p.remaining_trend", fallback: "系统剩余时间记录"))
                    .font(AppTheme.Typography.sectionTitle)
                    .foregroundStyle(AppTheme.textPrimary)
                Spacer()
                if let minutes = points.last?.minutesRemaining ?? fallbackMinutes {
                    Text(MenuBarPresentation.durationText(minutes))
                        .font(.system(size: 16, weight: .semibold, design: .monospaced))
                        .foregroundStyle(AppTheme.chargingBlue)
                }
            }
            if points.count >= 2 {
                Chart {
                    ForEach(points) { point in
                        AreaMark(x: .value("time", point.timestamp), y: .value("hours", Double(point.minutesRemaining) / 60))
                            .foregroundStyle(LinearGradient(colors: [AppTheme.chargingBlue.opacity(0.22), .clear], startPoint: .top, endPoint: .bottom))
                            .interpolationMethod(.stepStart)
                        LineMark(x: .value("time", point.timestamp), y: .value("hours", Double(point.minutesRemaining) / 60))
                            .foregroundStyle(AppTheme.chargingBlue)
                            .lineStyle(StrokeStyle(lineWidth: 2))
                            .interpolationMethod(.stepStart)
                    }

                    if let hovered {
                        RuleMark(x: .value("time", hovered.timestamp))
                            .foregroundStyle(AppTheme.chargingBlue.opacity(0.5))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                            .annotation(position: .top, alignment: .leading, spacing: 2,
                                        overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                                Text("\(MetricFieldFreshness.minuteText(hovered.timestamp)) · \(MenuBarPresentation.durationText(hovered.minutesRemaining))")
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
                        PointMark(x: .value("time", hovered.timestamp),
                                  y: .value("hours", Double(hovered.minutesRemaining) / 60))
                            .foregroundStyle(AppTheme.chargingBlue)
                            .symbolSize(46)
                    }
                }
                .chartXSelection(value: $selectedDate)
                .chartYAxis { AxisMarks(position: .leading) }
                .frame(height: 210)
            } else {
                Text(dashboardText("p.no_history", fallback: "继续使用后，这里会记录 macOS 给出的剩余时间变化"))
                    .font(.system(size: 12))
                    .foregroundStyle(AppTheme.textTertiary)
                    .frame(maxWidth: .infinity, minHeight: 130)
            }
        }
        .padding(AppTheme.Spacing.xl)
        .modifier(AppTheme.card())
    }
}
