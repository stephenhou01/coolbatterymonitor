import SwiftUI
import Charts

// MARK: - 3. System runtime history / unplug forecast

struct RemainingTimeHistorySection: View {
    let snapshot: DashboardMetricSnapshot
    let samples: [RuntimeSample]
    @Binding var selectedHelp: MetricHelpContent?
    @State private var selectedDate: Date?
    @State private var showLearning = false

    private var directPoints: [RuntimeChartPoint] {
        samples
            .filter { RuntimeSample.isValid(minutes: $0.minutesRemaining) }
            .sorted { $0.timestamp < $1.timestamp }
            .map { .init(date: $0.timestamp, hours: Double($0.minutesRemaining) / 60, isForecast: false) }
    }

    private var forecastPoints: [RuntimeChartPoint] {
        guard directPoints.isEmpty, snapshot.data.isOnAC,
              let minutes = snapshot.unplugEstimateMinutes, minutes > 0 else { return [] }
        let start = snapshot.data.lastUpdated
        return [
            .init(date: start, hours: Double(minutes) / 60, isForecast: true),
            .init(date: start.addingTimeInterval(Double(minutes) * 60), hours: 0, isForecast: true),
        ]
    }

    private var points: [RuntimeChartPoint] { directPoints.isEmpty ? forecastPoints : directPoints }
    private var isForecast: Bool { directPoints.isEmpty && !forecastPoints.isEmpty }
    private var selectedPoint: RuntimeChartPoint? {
        guard let selectedDate, !points.isEmpty else { return nil }
        return points.min { abs($0.date.timeIntervalSince(selectedDate)) < abs($1.date.timeIntervalSince(selectedDate)) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            DashboardSectionHeader(
                icon: BatteryMetricIcon.runtime.symbol,
                title: isForecast
                    ? dashboardText("p.unplug_trend")
                    : dashboardText("p.remaining_trend"),
                color: isForecast ? AppTheme.batteryYellow : AppTheme.chargingCyan,
                help: { DashboardHelp.runtimeHistory(snapshot, isForecast: isForecast) },
                selection: $selectedHelp
            )

            Text(isForecast
                 ? dashboardText("p.unplug_head")
                 : dashboardText("p.dual_head"))
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(AppTheme.textPrimary)

            chart
                .frame(height: 270)

            HStack(spacing: 16) {
                legend(color: isForecast ? AppTheme.batteryYellow : AppTheme.chargingCyan,
                       text: isForecast
                        ? dashboardText("p.unplug_legend")
                        : dashboardText("p.chart_hours"))
                Spacer()
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 18) { historyMeta }
                VStack(alignment: .leading, spacing: 5) { historyMeta }
            }

            DisclosureGroup(isExpanded: $showLearning) {
                HStack(alignment: .top, spacing: 9) {
                    learningItem(title: dashboardText("p.ul_minutes"),
                                 body: dashboardText("p.learn_minutes"))
                    learningItem(title: dashboardText("p.ul_hours"),
                                 body: dashboardText("p.learn_hours"))
                    learningItem(title: dashboardText("p.ul_days"),
                                 body: dashboardText("p.learn_days"))
                }
                .padding(.top, 10)
            } label: {
                Text(dashboardText("p.learn_summary"))
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(AppTheme.textSecondary)
            }
            .tint(AppTheme.accentPurple)
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 10).fill(AppTheme.contrastOverlay(0.018)))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(AppTheme.contrastOverlay(0.055)))
        }
        .padding(22)
        .finalDashboardCard(accent: isForecast ? AppTheme.batteryYellow : AppTheme.chargingCyan)
    }

    @ViewBuilder
    private var chart: some View {
        if points.isEmpty {
            ZStack {
                RoundedRectangle(cornerRadius: 13).fill(AppTheme.surfaceSunken)
                VStack(spacing: 9) {
                    Image(systemName: "waveform.path.ecg")
                        .font(.system(size: 25, weight: .light))
                        .foregroundStyle(AppTheme.textTertiary)
                    Text(dashboardText("p.no_history"))
                        .font(.system(size: 11.5))
                        .foregroundStyle(AppTheme.textTertiary)
                }
            }
            .overlay(RoundedRectangle(cornerRadius: 13).stroke(AppTheme.contrastOverlay(0.055)))
        } else {
            Chart {
                ForEach(points) { point in
                    AreaMark(
                        x: .value(dashboardText("p.chart_time"), point.date),
                        y: .value(dashboardText("p.chart_hours"), point.hours)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [(isForecast ? AppTheme.batteryYellow : AppTheme.chargingCyan).opacity(0.22), .clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .interpolationMethod(isForecast ? .linear : .stepStart)

                    LineMark(
                        x: .value(dashboardText("p.chart_time"), point.date),
                        y: .value(dashboardText("p.chart_hours"), point.hours)
                    )
                    .foregroundStyle(isForecast ? AppTheme.batteryYellow : AppTheme.chargingCyan)
                    .lineStyle(StrokeStyle(lineWidth: 2.3, dash: isForecast ? [7, 6] : []))
                    .interpolationMethod(isForecast ? .linear : .stepStart)
                }

                if let selectedPoint {
                    RuleMark(x: .value("selected", selectedPoint.date))
                        .foregroundStyle(AppTheme.contrastOverlay(0.35))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    PointMark(
                        x: .value("selected-time", selectedPoint.date),
                        y: .value("selected-hours", selectedPoint.hours)
                    )
                    .foregroundStyle(isForecast ? AppTheme.batteryYellow : AppTheme.chargingCyan)
                    .symbolSize(42)
                    .annotation(position: .top, spacing: 9) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(selectedPoint.date.formatted(date: .omitted, time: .shortened))
                            Text(LNum("%.1f h · %d min", selectedPoint.hours, Int((selectedPoint.hours * 60).rounded())))
                                .foregroundStyle(isForecast ? AppTheme.batteryYellow : AppTheme.chargingCyan)
                        }
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .padding(9)
                        .background(RoundedRectangle(cornerRadius: 8).fill(AppTheme.surfaceRaised))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(AppTheme.chargingCyan.opacity(0.18)))
                    }
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) { value in
                    AxisGridLine().foregroundStyle(AppTheme.chargingCyan.opacity(0.055))
                    AxisValueLabel {
                        if let date = value.as(Date.self) {
                            Text(date, format: .dateTime.hour().minute())
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundStyle(AppTheme.textTertiary)
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                    AxisGridLine().foregroundStyle(AppTheme.chargingCyan.opacity(0.055))
                    AxisValueLabel {
                        if let h = value.as(Double.self) {
                            Text(LNum("%.1f h", h))
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundStyle(isForecast ? AppTheme.batteryYellow : AppTheme.chargingCyan)
                        }
                    }
                }
            }
            .chartXSelection(value: $selectedDate)
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 13).fill(AppTheme.surfaceSunken))
            .overlay(RoundedRectangle(cornerRadius: 13).stroke(AppTheme.contrastOverlay(0.055)))
        }
    }

    @ViewBuilder
    private var historyMeta: some View {
        metaPill(isForecast
                 ? dashboardText("p.unplug_note")
                 : dashboardText("p.direct_source"))
        metaPill(isForecast
                 ? dashboardText("p.forecast_only")
                 : dashboardText("p.sample_cadence_short"))
        metaPill(isForecast
                 ? dashboardText("p.unplug_method")
                 : dashboardText("p.no_recalc"))
    }

    private func metaPill(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 9.5))
            .foregroundStyle(AppTheme.textTertiary)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(Capsule().fill(AppTheme.contrastOverlay(0.025)))
    }

    private func legend(color: Color, text: String) -> some View {
        HStack(spacing: 6) {
            Capsule().fill(color).frame(width: 22, height: 2)
            Text(text).font(.system(size: 9.5)).foregroundStyle(AppTheme.textTertiary)
        }
    }

    private func learningItem(title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(AppTheme.chargingCyan)
            Text(body)
                .font(.system(size: 9))
                .foregroundStyle(AppTheme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

private struct RuntimeChartPoint: Identifiable {
    let date: Date
    let hours: Double
    let isForecast: Bool
    var id: String { "\(date.timeIntervalSince1970)-\(isForecast)" }
}
