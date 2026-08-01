import SwiftUI
import Charts

enum DashboardDestination: String, CaseIterable, Identifiable {
    case overview
    case technical
    case trends
    case diagnostics
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: return dashboardText("shell.overview", fallback: "总览")
        case .technical: return dashboardText("shell.technical", fallback: "技术参数")
        case .trends: return dashboardText("shell.trends", fallback: "趋势")
        case .diagnostics: return dashboardText("shell.diagnostics", fallback: "诊断")
        case .settings: return dashboardText("shell.settings", fallback: "设置")
        }
    }

    var symbol: String {
        switch self {
        case .overview: return "square.grid.2x2"
        case .technical: return "cpu"
        case .trends: return "chart.line.uptrend.xyaxis"
        case .diagnostics: return "stethoscope"
        case .settings: return "gearshape"
        }
    }
}

struct DashboardSidebar: View {
    @Binding var selection: DashboardDestination

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 9) {
                    Image(systemName: "battery.100percent.bolt")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(AppTheme.chargingBlue)
                    Text(L("app.title"))
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(AppTheme.textPrimary)
                        .lineLimit(1)
                }
                Text(dashboardText("shell.sidebar_subtitle", fallback: "你的 Mac 电池仪表盘"))
                    .font(.system(size: 10.5))
                    .foregroundStyle(AppTheme.textTertiary)
                    .lineLimit(1)
            }
            .padding(.top, 56)
            .padding(.horizontal, 20)
            .padding(.bottom, 25)

            VStack(spacing: 8) {
                ForEach(DashboardDestination.allCases) { destination in
                    Button {
                        selection = destination
                    } label: {
                        HStack(spacing: 13) {
                            Image(systemName: destination.symbol)
                                .font(.system(size: 16, weight: .medium))
                                .frame(width: 22)
                            Text(destination.title)
                                .font(.system(size: 13.5, weight: selection == destination ? .semibold : .regular))
                            Spacer()
                        }
                        .foregroundStyle(selection == destination ? AppTheme.selectionText : AppTheme.textSecondary)
                        .padding(.horizontal, 14)
                        .frame(height: 48)
                        .background {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(selection == destination
                                      ? LinearGradient(colors: [AppTheme.chargingBlue, Color(red: 0.12, green: 0.43, blue: 0.95)],
                                                       startPoint: .topLeading, endPoint: .bottomTrailing)
                                      : LinearGradient(colors: [.clear, .clear], startPoint: .leading, endPoint: .trailing))
                                .shadow(color: selection == destination ? AppTheme.chargingBlue.opacity(0.22) : .clear,
                                        radius: 10, y: 3)
                        }
                    }
                    .buttonStyle(.plain)
                    .pointerOnHover()
                }
            }
            .padding(.horizontal, 12)

            Spacer()

            HStack(spacing: 7) {
                Circle().fill(AppTheme.batteryGreen).frame(width: 7, height: 7)
                Text(dashboardText("shell.local_only", fallback: "数据仅保存在这台 Mac"))
                    .font(.system(size: 9.5))
                    .foregroundStyle(AppTheme.textTertiary)
                    .lineLimit(1)
            }
            .padding(20)
        }
        .background(AppTheme.sidebarBackground)
    }
}

private struct DashboardPageHeader<Trailing: View>: View {
    let title: String
    let subtitle: String
    let trailing: Trailing

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(AppTheme.textPrimary)
                Text(subtitle)
                    .font(.system(size: 10.5))
                    .foregroundStyle(AppTheme.textTertiary)
            }
            Spacer(minLength: 16)
            trailing
        }
    }
}

extension DashboardPageHeader where Trailing == EmptyView {
    init(title: String, subtitle: String) {
        self.init(title: title, subtitle: subtitle, trailing: EmptyView())
    }
}

struct AppearanceModePicker: View {
    @Environment(AppearanceSettings.self) private var appearance
    var showLabels = false

    var body: some View {
        HStack(spacing: 3) {
            ForEach(AppearanceMode.allCases) { mode in
                Button {
                    withAnimation(.easeInOut(duration: 0.16)) {
                        appearance.select(mode)
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: mode.symbol)
                        if showLabels { Text(mode.title) }
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(appearance.mode == mode ? AppTheme.selectionText : AppTheme.textSecondary)
                    .padding(.horizontal, showLabels ? 10 : 9)
                    .frame(height: 30)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(appearance.mode == mode ? AppTheme.chargingBlue : .clear)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(mode.title)
                .accessibilityValue(appearance.mode == mode ? mode.title : "")
                .help(mode.title)
                .pointerOnHover()
            }
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(AppTheme.contrastOverlay(0.055))
                .overlay(RoundedRectangle(cornerRadius: 9).stroke(AppTheme.cardBorder))
        )
    }
}

struct LanguageSelectionMenu: View {
    var fullWidth = false
    var iconOnly = false

    var body: some View {
        let localization = L10n.shared
        Menu {
            Button { localization.select(nil) } label: {
                languageLabel(L("lang.system"), selected: localization.isFollowingSystem)
            }
            Divider()
            ForEach(localization.languages, id: \.code) { language in
                Button { localization.select(language.code) } label: {
                    languageLabel(language.name,
                                  selected: !localization.isFollowingSystem && localization.effectiveCode == language.code)
                }
            }
        } label: {
            Group {
                if iconOnly {
                    Image(systemName: "globe")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 30, height: 30)
                } else {
                    HStack(spacing: 8) {
                        Image(systemName: "globe")
                        Text(localization.currentName)
                            .lineLimit(1)
                        Spacer(minLength: fullWidth ? 10 : 0)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(AppTheme.textTertiary)
                    }
                    .padding(.horizontal, 11)
                    .frame(maxWidth: fullWidth ? .infinity : nil, minHeight: 32)
                }
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(AppTheme.textSecondary)
            .background(RoundedRectangle(cornerRadius: 8).fill(AppTheme.contrastOverlay(0.045)))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(AppTheme.cardBorder))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize(horizontal: !fullWidth, vertical: true)
        .accessibilityLabel(dashboardText("p.menu_language", fallback: "语言"))
        .accessibilityValue(localization.currentName)
        .help(localization.currentName)
        .pointerOnHover()
    }

    @ViewBuilder
    private func languageLabel(_ title: String, selected: Bool) -> some View {
        if selected { Label(title, systemImage: "checkmark") } else { Text(title) }
    }
}

struct DashboardOverviewPage: View {
    @EnvironmentObject private var batteryService: BatteryService
    @Binding var selectedHelp: MetricHelpContent?

    private var data: BatteryData { batteryService.batteryData }
    private var snapshot: DashboardMetricSnapshot {
        DashboardMetricSnapshot(data: data, realtimeData: batteryService.realtimeData)
    }
    private var presentation: MenuBarPresentation { .init(data: data) }

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                DashboardPageHeader(
                    title: L("app.title"),
                    subtitle: data.modelIdentifier.isEmpty ? L("app.subtitle") : data.modelIdentifier,
                    trailing: AppearanceModePicker()
                )

                overviewHero
                metricRail
                statusBanner
            }
            .frame(maxWidth: 980)
            .padding(.horizontal, 34)
            .padding(.top, 28)
            .padding(.bottom, 34)
            .frame(maxWidth: .infinity)
        }
        .background(overviewBackground)
    }

    private var overviewBackground: some View {
        ZStack {
            AppTheme.background
            LinearGradient(colors: [AppTheme.chargingBlue.opacity(0.08), .clear, AppTheme.batteryGreen.opacity(0.035)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }

    private var overviewHero: some View {
        HStack(spacing: 24) {
            VStack(alignment: .leading, spacing: 12) {
                Text(presentation.percentText)
                    .font(.system(size: 68, weight: .light, design: .rounded))
                    .foregroundStyle(AppTheme.textPrimary)
                    .monospacedDigit()

                Text(data.isOnAC
                     ? dashboardText("p.menu_unplug", fallback: "拔电后预计")
                     : dashboardText("p.menu_time", fallback: "预计还能使用"))
                    .font(.system(size: 13))
                    .foregroundStyle(AppTheme.textSecondary)

                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(presentation.runtimeText)
                        .font(.system(size: 37, weight: .medium, design: .rounded))
                        .foregroundStyle(AppTheme.chargingBlue)
                        .monospacedDigit()
                    MetricHelpButton(content: DashboardHelp.runtime(snapshot),
                                     selection: $selectedHelp)
                }

                HStack(spacing: 8) {
                    MetricGlyph(data.isOnAC ? .charging : .power,
                                tint: data.isOnAC ? AppTheme.batteryYellow : AppTheme.chargingBlue,
                                scale: .micro,
                                style: .plain)
                    Text(presentation.sourceText)
                }
                .font(.system(size: 10.5))
                .foregroundStyle(data.isOnAC ? AppTheme.batteryYellow : AppTheme.chargingBlue)
            }

            Spacer(minLength: 24)

            VStack(spacing: 13) {
                Image(systemName: batterySymbol)
                    .font(.system(size: 116, weight: .ultraLight))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(AppTheme.batteryGreen, AppTheme.textTertiary)
                    .contentTransition(.symbolEffect(.replace))
                Text(data.isOnAC
                     ? dashboardText("shell.power_connected", fallback: "已连接电源")
                     : dashboardText("shell.on_battery", fallback: "正在使用电池"))
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(AppTheme.textTertiary)
            }
            .frame(width: 235)
        }
        .padding(28)
        .background(RoundedRectangle(cornerRadius: 16).fill(AppTheme.cardBackground))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppTheme.cardBorder))
        .shadow(color: Color.black.opacity(0.10), radius: 22, y: 8)
    }

    private var batterySymbol: String {
        switch data.percent {
        case 76...: return "battery.100percent"
        case 51...: return "battery.75percent"
        case 26...: return "battery.50percent"
        default: return "battery.25percent"
        }
    }

    private var metricRail: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 6), spacing: 0) {
            overviewMetric(.power, MenuBarMetric.power.title,
                           LNum("%.1f W", snapshot.currentPowerWatts), AppTheme.chargingBlue,
                           dashboardText("shell.power_hint", fallback: "整机实时功率"),
                           help: DashboardHelp.power(snapshot))
            overviewMetric(.adapter, dashboardText("shell.adapter", fallback: "适配器功率"),
                           "\(data.chargerWattage) W", AppTheme.textSecondary,
                           data.isOnAC ? dashboardText("shell.adapter_connected", fallback: "当前额定功率") : dashboardText("shell.not_connected", fallback: "未连接"),
                           help: DashboardHelp.adapterPower(snapshot))
            overviewMetric(.charging, dashboardText("shell.charge_power", fallback: "充电功率"),
                           LNum("%.1f W", max(0, Double(data.hardwareDetail.systemPowerIn) / 1000)), AppTheme.batteryGreen,
                           data.isCharging ? dashboardText("shell.charging", fallback: "正在充电") : dashboardText("shell.not_charging", fallback: "当前未充电"),
                           help: DashboardHelp.chargingPower(snapshot))
            overviewMetric(.temperature, MenuBarMetric.temperature.title,
                           LNum("%.1f ℃", data.temperatureCelsius), AppTheme.textSecondary,
                           dashboardText("shell.temp_range", fallback: "建议 20–35℃"),
                           help: DashboardHelp.temperature(snapshot))
            overviewMetric(.cycles, MenuBarMetric.cycles.title, "\(data.cycleCount)", AppTheme.accentPurple,
                           dashboardText("shell.cycle_reference", fallback: "参考额定 1000 次"),
                           help: DashboardHelp.cycleCount(snapshot))
            overviewMetric(.health, MenuBarMetric.health.title,
                           LNum("%.1f%%", snapshot.healthPercent), AppTheme.batteryGreen,
                           healthLabel,
                           help: DashboardHelp.health(snapshot))
        }
        .padding(.vertical, 18)
        .background(RoundedRectangle(cornerRadius: 15).fill(AppTheme.cardBackground))
        .overlay(RoundedRectangle(cornerRadius: 15).stroke(AppTheme.cardBorder))
    }

    private func overviewMetric(
        _ icon: BatteryMetricIcon,
        _ title: String,
        _ value: String,
        _ color: Color,
        _ hint: String,
        help: MetricHelpContent
    ) -> some View {
        VStack(spacing: 9) {
            MetricGlyph(icon, tint: color, scale: .card)
            Text(title)
                .font(.system(size: 10.5))
                .foregroundStyle(AppTheme.textSecondary)
                .lineLimit(2)
                .minimumScaleFactor(0.82)
                .multilineTextAlignment(.center)
            Text(value).font(.system(size: 20, weight: .medium, design: .rounded)).foregroundStyle(AppTheme.textPrimary).monospacedDigit().lineLimit(1)
            Text(hint).font(.system(size: 8.5)).foregroundStyle(AppTheme.textTertiary).lineLimit(2).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 146)
        .padding(.horizontal, 8)
        .overlay(alignment: .topTrailing) {
            MetricHelpButton(content: help, selection: $selectedHelp)
                .padding(9)
        }
        .overlay(alignment: .trailing) { Rectangle().fill(AppTheme.divider).frame(width: 1) }
    }

    private var healthLabel: String {
        if snapshot.healthPercent >= 90 { return dashboardText("shell.health_good", fallback: "状态良好") }
        if snapshot.healthPercent >= 80 { return dashboardText("shell.health_fair", fallback: "正常使用") }
        return dashboardText("shell.health_attention", fallback: "建议关注")
    }

    private var statusBanner: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle().fill(statusColor).frame(width: 48, height: 48)
                Image(systemName: statusSymbol).font(.system(size: 20, weight: .bold)).foregroundStyle(AppTheme.selectionText)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(statusHeadline)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppTheme.textPrimary)
                Text(statusSubtitle)
                    .font(.system(size: 10.5))
                    .foregroundStyle(AppTheme.textTertiary)
            }
            Spacer()
            Text(batteryService.isLiveRefreshEnabled
                 ? dashboardText("p.live_10s", fallback: "每 10 秒更新")
                 : dashboardText("p.live_paused", fallback: "已暂停"))
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(AppTheme.textTertiary)
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 15).fill(AppTheme.cardBackground))
        .overlay(RoundedRectangle(cornerRadius: 15).stroke(AppTheme.cardBorder))
    }

    private var needsAttention: Bool { snapshot.healthPercent < 80 || data.temperatureCelsius >= 45 }
    private var statusColor: Color { needsAttention ? AppTheme.batteryOrange : AppTheme.batteryGreen }
    private var statusSymbol: String { needsAttention ? "exclamationmark" : "checkmark" }
    private var statusHeadline: String {
        needsAttention
            ? dashboardText("shell.status_attention", fallback: "有一项指标需要关注")
            : dashboardText("shell.status_good", fallback: "状态良好 · 各项指标处于可接受范围")
    }
    private var statusSubtitle: String {
        dashboardText("shell.status_subtitle", fallback: "续航以系统读数为准；详细来源和公式可在技术参数中核验。")
    }
}

struct DashboardTechnicalPage: View {
    @EnvironmentObject private var batteryService: BatteryService
    @Binding var selectedHelp: MetricHelpContent?

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                DashboardPageHeader(
                    title: DashboardDestination.technical.title,
                    subtitle: dashboardText("shell.technical_subtitle", fallback: "完整保留所有指标、公式、来源和系统原始字段")
                )
                FinalDashboardView(
                    batteryData: batteryService.batteryData,
                    realtimeData: batteryService.realtimeData,
                    persistedRuntimeSamples: batteryService.runtimeSamples,
                    selectedHelp: $selectedHelp
                )
            }
            .frame(maxWidth: 1240)
            .padding(28)
            .frame(maxWidth: .infinity)
        }
        .background(AppTheme.background)
    }
}

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
                Chart(points) { point in
                    AreaMark(x: .value("time", point.timestamp), y: .value("hours", Double(point.minutesRemaining) / 60))
                        .foregroundStyle(LinearGradient(colors: [AppTheme.chargingBlue.opacity(0.22), .clear], startPoint: .top, endPoint: .bottom))
                        .interpolationMethod(.stepStart)
                    LineMark(x: .value("time", point.timestamp), y: .value("hours", Double(point.minutesRemaining) / 60))
                        .foregroundStyle(AppTheme.chargingBlue)
                        .lineStyle(StrokeStyle(lineWidth: 2))
                        .interpolationMethod(.stepStart)
                }
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

struct DashboardDiagnosticsPage: View {
    @EnvironmentObject private var batteryService: BatteryService
    @Binding var selectedHelp: MetricHelpContent?

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                DashboardPageHeader(
                    title: DashboardDestination.diagnostics.title,
                    subtitle: dashboardText("shell.diagnostics_subtitle", fallback: "先给结论，再展开证据")
                )
                if let insight = batteryService.insight {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                        HealthDiagnosisCard(diagnosis: insight.health)
                        ChargingHabitCard(habit: insight.habit)
                        AccessoryCard(accessory: insight.accessory)
                        PowerAnalysisCard(analysis: insight.power)
                    }
                    SystemAnomalySummaryCard(snapshot: batteryService.systemDataSnapshot,
                                             selectedHelp: $selectedHelp)
                } else {
                    VStack(spacing: 12) {
                        ProgressView().controlSize(.small)
                        Text(dashboardText("shell.diagnosing", fallback: "正在读取电池并生成诊断…"))
                            .font(.system(size: 12))
                            .foregroundStyle(AppTheme.textSecondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 260)
                    .modifier(AppTheme.card())
                }
            }
            .frame(maxWidth: 1060)
            .padding(28)
            .frame(maxWidth: .infinity)
        }
        .background(AppTheme.background)
    }
}

private struct SystemAnomalySummaryCard: View {
    let snapshot: SystemDataSnapshot
    @Binding var selectedHelp: MetricHelpContent?

    private var anomalies: [SystemFieldReading] {
        snapshot.fields.filter { $0.anomalyLevel > .none }.sorted { $0.anomalyLevel > $1.anomalyLevel }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                Image(systemName: anomalies.isEmpty ? "checkmark.shield.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(anomalies.isEmpty ? AppTheme.batteryGreen : AppTheme.batteryYellow)
                Text(dashboardText("shell.system_anomalies", fallback: "系统字段异常筛查"))
                    .font(AppTheme.Typography.sectionTitle)
                    .foregroundStyle(AppTheme.textPrimary)
                Spacer()
                Text("\(anomalies.count)")
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundStyle(anomalies.isEmpty ? AppTheme.batteryGreen : AppTheme.batteryYellow)
            }
            if anomalies.isEmpty {
                Text(dashboardText("p.system_no_anomaly", fallback: "本次快照没有命中已定义的异常规则"))
                    .font(.system(size: 11.5))
                    .foregroundStyle(AppTheme.textSecondary)
                    .padding(.vertical, 12)
            } else {
                ForEach(anomalies.prefix(8)) { field in
                    Button { selectedHelp = field.help } label: {
                        HStack(spacing: 10) {
                            Circle().fill(anomalyColor(field.anomalyLevel)).frame(width: 7, height: 7)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(field.metadata.path).font(.system(size: 11, weight: .medium, design: .monospaced))
                                Text(field.anomalyReason).font(.system(size: 9.5)).foregroundStyle(AppTheme.textTertiary).lineLimit(1)
                            }
                            Spacer()
                            Text(field.valueWithUnit).font(.system(size: 10.5, design: .monospaced))
                            Image(systemName: "questionmark.circle").foregroundStyle(AppTheme.textTertiary)
                        }
                        .foregroundStyle(AppTheme.textPrimary)
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 9).fill(AppTheme.contrastOverlay(0.025)))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(AppTheme.Spacing.xl)
        .modifier(AppTheme.card())
    }

    private func anomalyColor(_ level: SystemFieldAnomalyLevel) -> Color {
        switch level {
        case .none: return AppTheme.textTertiary
        case .attention: return AppTheme.batteryYellow
        case .warning: return AppTheme.batteryOrange
        case .critical: return AppTheme.batteryRed
        }
    }
}

struct DashboardSettingsPage: View {
    @EnvironmentObject private var batteryService: BatteryService
    @EnvironmentObject private var processService: ProcessMonitorService
    @Environment(MenuBarSettings.self) private var menuSettings

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                DashboardPageHeader(
                    title: DashboardDestination.settings.title,
                    subtitle: dashboardText("shell.settings_subtitle", fallback: "语言、外观和实时采样")
                )
                settingsCard(icon: "circle.lefthalf.filled", title: dashboardText("shell.appearance", fallback: "外观")) {
                    AppearanceModePicker(showLabels: true)
                }
                settingsCard(icon: "globe", title: dashboardText("p.menu_language", fallback: "语言")) {
                    LanguageSelectionMenu(fullWidth: true)
                        .frame(width: 230)
                }
                menuBarMetricSettingsCard
                settingsCard(icon: "arrow.triangle.2.circlepath", title: dashboardText("shell.live_refresh", fallback: "实时更新")) {
                    Toggle(isOn: Binding(
                        get: { batteryService.isLiveRefreshEnabled },
                        set: { setLiveRefresh($0) }
                    )) {
                        Text(batteryService.isLiveRefreshEnabled
                             ? dashboardText("p.live_10s", fallback: "每 10 秒更新")
                             : dashboardText("p.live_paused", fallback: "已暂停"))
                    }
                    .toggleStyle(.switch)
                    .font(.system(size: 11))
                }
                HStack(spacing: 8) {
                    Image(systemName: "lock.shield")
                    Text(dashboardText("shell.privacy_note", fallback: "所有采样和历史数据都只保存在这台 Mac，不上传服务器。"))
                }
                .font(.system(size: 10.5))
                .foregroundStyle(AppTheme.textTertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(RoundedRectangle(cornerRadius: 12).fill(AppTheme.contrastOverlay(0.025)))
            }
            .frame(maxWidth: 760)
            .padding(28)
            .frame(maxWidth: .infinity)
        }
        .background(AppTheme.background)
    }

    private var menuBarMetricSettingsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 11).fill(AppTheme.batteryGreen.opacity(0.10))
                    Image(systemName: "menubar.rectangle").foregroundStyle(AppTheme.batteryGreen)
                }
                .frame(width: 42, height: 42)
                VStack(alignment: .leading, spacing: 3) {
                    Text(dashboardText("menu.config.title", fallback: "显示指标"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(AppTheme.textPrimary)
                    Text(dashboardText("menu.config.manage_in_dashboard", fallback: "选择菜单栏面板要显示的指标；顺序和删除可在面板编辑状态调整。"))
                        .font(.system(size: 9.5))
                        .foregroundStyle(AppTheme.textTertiary)
                }
                Spacer()
            }

            Divider().overlay(AppTheme.cardBorder)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 9) {
                ForEach(MenuBarMetric.allCases) { metric in
                    Toggle(isOn: Binding(
                        get: { menuSettings.visibleMetrics.contains(metric) },
                        set: { menuSettings.setVisible(metric, visible: $0) }
                    )) {
                        HStack(spacing: 8) {
                            Image(systemName: metric.symbol)
                                .foregroundStyle(menuMetricColor(metric))
                                .frame(width: 18)
                            Text(metric.title)
                                .font(.system(size: 10.5, weight: .medium))
                                .foregroundStyle(AppTheme.textPrimary)
                        }
                    }
                    .toggleStyle(.switch)
                    .padding(.horizontal, 11)
                    .frame(height: 40)
                    .background(RoundedRectangle(cornerRadius: 9).fill(AppTheme.contrastOverlay(0.025)))
                    .overlay(RoundedRectangle(cornerRadius: 9).stroke(AppTheme.cardBorder))
                }
            }
        }
        .padding(18)
        .modifier(AppTheme.card(radius: 14))
    }

    private func settingsCard<Content: View>(icon: String, title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 11).fill(AppTheme.chargingBlue.opacity(0.10))
                Image(systemName: icon).foregroundStyle(AppTheme.chargingBlue)
            }
            .frame(width: 42, height: 42)
            Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(AppTheme.textPrimary)
            Spacer()
            content()
        }
        .padding(18)
        .modifier(AppTheme.card(radius: 14))
    }

    private func setLiveRefresh(_ enabled: Bool) {
        batteryService.setLiveRefreshEnabled(enabled)
        processService.setLiveRefreshEnabled(enabled)
    }

    private func menuMetricColor(_ metric: MenuBarMetric) -> Color {
        switch metric {
        case .runtime: return AppTheme.chargingCyan
        case .power: return AppTheme.chargingBlue
        case .temperature, .health: return AppTheme.batteryGreen
        case .cycles: return AppTheme.accentPurple
        case .current: return AppTheme.batteryYellow
        }
    }
}
