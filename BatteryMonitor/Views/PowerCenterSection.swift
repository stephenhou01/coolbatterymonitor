import SwiftUI
import Charts

/// Power is shown separately from system remaining-time history. The line is a
/// real ten-second power series; processes are workload context, not fabricated
/// per-process watt allocations.
struct PowerCenterSection: View {
    let snapshot: DashboardMetricSnapshot
    let points: [RealtimeDataPoint]
    let processes: [ProcessPowerInfo]
    let hasProcessSample: Bool
    /// 全机 CPU 与「可见 / 系统」拆分。列表只覆盖当前用户可读的进程，
    /// 这一行负责把沙箱读不到的那部分标出来而不是让列表看起来像全量。
    let systemCPU: SystemCPUSnapshot
    let isLive: Bool
    let onToggleLive: () -> Void
    let onRefresh: () -> Void
    @Binding var selectedHelp: MetricHelpContent?

    @State private var selectedDate: Date?

    private var chartPoints: [RealtimeDataPoint] {
        Array(points.suffix(180)).filter { $0.power.isFinite && $0.power >= 0 }
    }

    private var selectedPoint: RealtimeDataPoint? {
        guard let selectedDate else { return chartPoints.last }
        return chartPoints.min { abs($0.timestamp.timeIntervalSince(selectedDate)) < abs($1.timestamp.timeIntervalSince(selectedDate)) }
    }

    private var peak: Double { max(chartPoints.map(\.power).max() ?? 0, snapshot.currentPowerWatts) }
    private var average: Double {
        guard !chartPoints.isEmpty else { return snapshot.currentPowerWatts }
        return chartPoints.map(\.power).reduce(0, +) / Double(chartPoints.count)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            DashboardSectionHeader(
                icon: BatteryMetricIcon.power.symbol,
                title: dashboardText("p.power_center_title", fallback: "当前功耗与程序活动"),
                color: AppTheme.chargingBlue,
                help: { DashboardHelp.power(snapshot) },
                selection: $selectedHelp,
                trailing: AnyView(liveControls)
            )

            Text(dashboardText(
                "p.power_center_subtitle",
                fallback: "蓝线是整台电脑的实时功率；右侧进程只解释当时谁更活跃，不把 CPU 占用伪装成精确瓦数。"
            ))
            .font(.system(size: 11.5))
            .foregroundStyle(AppTheme.textSecondary)
            .fixedSize(horizontal: false, vertical: true)

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 14) {
                    chartPanel.frame(minWidth: 560)
                    processPanel.frame(width: 350)
                }
                VStack(spacing: 14) {
                    chartPanel
                    processPanel
                }
            }
        }
        .padding(20)
        .finalDashboardCard(accent: AppTheme.chargingBlue)
    }

    private var liveControls: some View {
        HStack(spacing: 7) {
            HStack(spacing: 5) {
                Circle()
                    .fill(isLive ? AppTheme.batteryGreen : AppTheme.textTertiary)
                    .frame(width: 6, height: 6)
                Text(isLive
                     ? dashboardText("p.live_10s", fallback: "每 10 秒")
                     : dashboardText("p.live_paused", fallback: "已暂停"))
                    .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                    .foregroundStyle(isLive ? AppTheme.batteryGreen : AppTheme.textTertiary)
            }
            controlButton(icon: isLive ? "pause.fill" : "play.fill",
                          text: isLive
                            ? dashboardText("p.pause_refresh", fallback: "暂停")
                            : dashboardText("p.resume_refresh", fallback: "继续"),
                          action: onToggleLive)
            controlButton(icon: "arrow.clockwise",
                          text: dashboardText("p.refresh_now", fallback: "立即刷新"),
                          action: onRefresh)
        }
    }

    private func controlButton(icon: String, text: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(text, systemImage: icon)
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundStyle(AppTheme.chargingCyan)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Capsule().fill(AppTheme.chargingCyan.opacity(0.08)))
        }
        .buttonStyle(.plain)
        .pointerOnHover()
    }

    private var chartPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 14) {
                metric(LNum("%.1f W", snapshot.currentPowerWatts),
                       dashboardText("p.current_power_short", fallback: "当前"),
                       AppTheme.chargingBlue)
                metric(LNum("%.1f W", average),
                       dashboardText("p.window_average", fallback: "窗口均值"),
                       AppTheme.chargingCyan)
                metric(LNum("%.1f W", peak),
                       dashboardText("p.window_peak", fallback: "窗口峰值"),
                       AppTheme.batteryYellow)
                Spacer()
                Text(powerSourceLabel)
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundStyle(AppTheme.textTertiary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(AppTheme.contrastOverlay(0.035)))
            }

            if chartPoints.count >= 2 {
                Chart {
                    ForEach(chartPoints) { point in
                        AreaMark(
                            x: .value("Time", point.timestamp),
                            y: .value("Power", point.power)
                        )
                        .interpolationMethod(.linear)
                        .foregroundStyle(
                            LinearGradient(colors: [AppTheme.chargingBlue.opacity(0.28), .clear],
                                           startPoint: .top, endPoint: .bottom)
                        )

                        LineMark(
                            x: .value("Time", point.timestamp),
                            y: .value("Power", point.power)
                        )
                        .interpolationMethod(.linear)
                        .lineStyle(StrokeStyle(lineWidth: 2))
                        .foregroundStyle(AppTheme.chargingBlue)
                    }

                    if let selectedPoint {
                        RuleMark(x: .value("Selected", selectedPoint.timestamp))
                            .foregroundStyle(AppTheme.chargingCyan.opacity(0.5))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                            .annotation(position: .top, alignment: .leading) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(selectedPoint.timestamp.formatted(date: .omitted, time: .standard))
                                    Text(LNum("%.1f W", selectedPoint.power))
                                        .foregroundStyle(AppTheme.chargingBlue)
                                }
                                .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                                .padding(7)
                                .background(RoundedRectangle(cornerRadius: 7).fill(AppTheme.surfaceRaised.opacity(0.96)))
                            }
                    }
                }
                .chartXSelection(value: $selectedDate)
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 5)) { _ in
                        AxisGridLine().foregroundStyle(AppTheme.contrastOverlay(0.035))
                        AxisValueLabel(format: .dateTime.hour().minute())
                            .foregroundStyle(AppTheme.textTertiary)
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                        AxisGridLine().foregroundStyle(AppTheme.contrastOverlay(0.05))
                        AxisValueLabel {
                            if let watts = value.as(Double.self) {
                                Text(LNum("%.0f W", watts))
                            }
                        }
                        .foregroundStyle(AppTheme.textTertiary)
                    }
                }
                .frame(height: 250)
            } else {
                VStack(spacing: 8) {
                    ProgressView().scaleEffect(0.8)
                    Text(dashboardText("p.power_collecting", fallback: "正在收集实时功率；20 秒后会出现折线"))
                        .font(.system(size: 10.5))
                        .foregroundStyle(AppTheme.textTertiary)
                }
                .frame(maxWidth: .infinity, minHeight: 250)
            }

            HStack {
                Label(dashboardText("p.power_axis_time", fallback: "横轴：时间"), systemImage: "clock")
                Label(dashboardText("p.power_axis_watts", fallback: "纵轴：整机功率（W）"), systemImage: "bolt")
                Spacer()
                Text(dashboardText("p.power_hover_hint", fallback: "悬停查看每个时刻"))
            }
            .font(.system(size: 9.5))
            .foregroundStyle(AppTheme.textTertiary)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 13).fill(AppTheme.surfaceSunken))
        .overlay(RoundedRectangle(cornerRadius: 13).stroke(AppTheme.contrastOverlay(0.055), lineWidth: 1))
    }

    /// 全机 / 可见应用 / 系统进程 三列。
    ///
    /// 这三个数是**整机口径**（所有核加起来 100%），而下面每行的 CPU% 是
    /// **每核口径**（100% = 占满一个核，多核聚合行可以超过 100%）。两者单位不同，
    /// 所以刻意分成两个视觉区块、各自带单位说明，而不是混在一列里让人做减法。
    ///
    /// 排版是三列上下堆叠而不是一句长句：面板宽度硬编码 350pt，德语的
    /// 「Gesamtsystem / Sichtbare Apps / Systemprozesse」拼成一行会溢出。
    private var machineCPURow: some View {
        HStack(alignment: .top, spacing: 8) {
            machineCPUColumn(label: L("proc.cpu_machine"),
                             value: systemCPU.machineBusyPercent,
                             color: AppTheme.textSecondary)
            Divider().frame(height: 24)
            machineCPUColumn(label: L("proc.cpu_visible"),
                             value: systemCPU.machineBusyPercent == nil ? nil : systemCPU.visiblePercent,
                             color: AppTheme.chargingBlue)
            Divider().frame(height: 24)
            machineCPUColumn(label: L("proc.cpu_system"),
                             value: systemCPU.systemPercent,
                             color: AppTheme.textTertiary,
                             note: L("proc.cpu_system_note"))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 7)
        .padding(.horizontal, 10)
        .background(RoundedRectangle(cornerRadius: 9).fill(AppTheme.contrastOverlay(0.03)))
    }

    private func machineCPUColumn(label: String, value: Double?, color: Color,
                                  note: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(AppTheme.textTertiary)
            // 首次采样还没有前值可求差 —— 显示「—」而不是 0%，
            // 0% 会被读成「机器完全空闲」这个具体结论。
            Text(value.map { LNum("%.0f%%", $0) } ?? "—")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(color)
            if let note {
                Text(note)
                    .font(.system(size: 8))
                    .foregroundStyle(AppTheme.textTertiary.opacity(0.75))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var processPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(dashboardText("p.active_processes", fallback: "此刻活跃的程序与进程"), systemImage: "square.stack.3d.up.fill")
                    .font(.system(size: 11.5, weight: .bold))
                    .foregroundStyle(AppTheme.textPrimary)
                Spacer()
                Text(L("proc.col_cpu"))
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(AppTheme.textTertiary)
            }

            machineCPURow

            if processes.isEmpty {
                Text(hasProcessSample
                     ? dashboardText("p.no_active_processes", fallback: "当前没有达到展示门槛的活跃进程")
                     : dashboardText("p.process_collecting", fallback: "正在读取进程活动…"))
                    .font(.system(size: 10.5))
                    .foregroundStyle(AppTheme.textTertiary)
                    .frame(maxWidth: .infinity, minHeight: 190)
            } else {
                ForEach(Array(processes.prefix(6).enumerated()), id: \.element.id) { index, process in
                    ProcessRow(proc: process, index: index)
                }
            }

            Text(dashboardText(
                "p.process_context_note",
                fallback: "为什么不显示每个程序多少瓦？macOS 这里没有给出可靠的进程级瓦数；CPU% 只能帮助解释负载组合，不能直接分摊整机功耗。"
            ))
            .font(.system(size: 9.5))
            .foregroundStyle(AppTheme.textTertiary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 9).fill(AppTheme.batteryYellow.opacity(0.035)))
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 13).fill(AppTheme.surfaceSunken))
        .overlay(RoundedRectangle(cornerRadius: 13).stroke(AppTheme.contrastOverlay(0.055), lineWidth: 1))
    }

    private var powerSourceLabel: String {
        if snapshot.detail.systemPowerWatts > 0 { return "BatteryData.SystemPower" }
        if snapshot.detail.systemLoad != 0 { return "SystemLoad ÷ 1000" }
        return "Voltage × |Amperage|"
    }

    private func metric(_ value: String, _ title: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: 18, weight: .semibold, design: .monospaced))
                .foregroundStyle(color)
            Text(title).font(.system(size: 9.5)).foregroundStyle(AppTheme.textTertiary)
        }
    }
}
