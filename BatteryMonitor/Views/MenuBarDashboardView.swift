import SwiftUI
import AppKit

/// One definition shared by the menu-bar label and its expanded panel.
/// Battery mode always prefers the macOS time estimate; AC mode never reuses a
/// stale gauge value and may instead show the explicitly labelled unplug estimate.
struct MenuBarPresentation {
    let data: BatteryData

    var isLoaded: Bool {
        data.percent > 0 || data.designCapacity > 0 || !data.batteryModel.isEmpty
    }

    var isForecast: Bool {
        data.isOnAC && data.unplugEstimateMinutes != nil
    }

    var runtimeMinutes: Int? {
        data.isOnAC ? data.unplugEstimateMinutes : data.timeRemainingMinutes
    }

    var percentText: String {
        isLoaded ? "\(max(0, min(100, data.percent)))%" : "—%"
    }

    var runtimeText: String {
        Self.durationText(runtimeMinutes)
    }

    var timeTitle: String {
        dashboardText(isForecast ? "p.menu_unplug" : "p.menu_time",
                      fallback: isForecast ? "拔电后预计" : "还能用多久")
    }

    var sourceText: String {
        if !data.isOnAC, runtimeMinutes != nil {
            return dashboardText("p.menu_direct", fallback: "macOS 系统直接值")
        }
        if isForecast {
            return dashboardText("p.menu_forecast", fallback: "当前电脑状态下的拔电预计 · 不是系统历史")
        }
        return dashboardText("p.menu_waiting", fallback: "等待 macOS 给出剩余时间")
    }

    var chargeFraction: Double {
        Double(max(0, min(100, data.percent))) / 100
    }

    var healthPercent: Double {
        max(0, min(100, data.systemHealthPercent ?? Double(data.maxCapacityPercent)))
    }

    var healthText: String { LNum("%.1f%%", healthPercent) }
    var powerText: String { LNum("%.1f W", max(0, data.currentPowerWatts)) }
    var temperatureText: String { LNum("%.1f °C", data.temperatureCelsius) }

    func title(for metric: MenuBarMetric) -> String {
        metric == .runtime ? timeTitle : metric.title
    }

    func value(for metric: MenuBarMetric) -> String {
        switch metric {
        case .runtime: return runtimeText
        case .power: return powerText
        case .temperature: return temperatureText
        case .cycles: return data.cycleCount.formatted()
        case .health: return healthText
        case .current: return LNum("%.2f A", Double(data.amperage) / 1000)
        }
    }

    func statusValue(for metric: MenuBarMetric) -> String? {
        switch metric {
        case .runtime:
            guard runtimeMinutes != nil else { return nil }
            if isForecast {
                return "\(dashboardText("p.menu_unplug_short", fallback: "拔电约")) \(runtimeText)"
            }
            return runtimeText
        case .power:
            return isLoaded ? LNum("%.1fW", max(0, data.currentPowerWatts)) : nil
        case .temperature:
            return isLoaded ? LNum("%.1f°C", data.temperatureCelsius) : nil
        case .cycles:
            return isLoaded ? "\(data.cycleCount)×" : nil
        case .health:
            return isLoaded ? LNum("%.0f%%", healthPercent) : nil
        case .current:
            return isLoaded ? LNum("%.2fA", Double(data.amperage) / 1000) : nil
        }
    }

    func menuBarText(secondaryMetric: MenuBarMetric) -> String {
        guard let secondary = statusValue(for: secondaryMetric) else { return percentText }
        return "\(percentText) (\(secondary))"
    }

    static func durationText(_ minutes: Int?) -> String {
        guard let minutes, minutes > 0 else { return "—" }
        return String(format: "%dh %02dm", minutes / 60, minutes % 60)
    }
}

struct MenuBarStatusLabel: View {
    let data: BatteryData
    let secondaryMetric: MenuBarMetric

    private var presentation: MenuBarPresentation { .init(data: data) }

    var body: some View {
        Text(presentation.menuBarText(secondaryMetric: secondaryMetric))
            .monospacedDigit()
        .accessibilityLabel("\(presentation.percentText), \(presentation.title(for: secondaryMetric)) \(presentation.value(for: secondaryMetric))")
    }
}

/// Shared configuration for the text-only status item. The percentage remains
/// the stable anchor; users choose the live metric shown in parentheses.
struct MenuBarTopStatusConfigurationView: View {
    let data: BatteryData
    var compact = false

    @Environment(MenuBarSettings.self) private var menuSettings

    private var presentation: MenuBarPresentation { .init(data: data) }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 8 : 12) {
            HStack(alignment: .center, spacing: 12) {
                if !compact {
                    MetricGlyph(.stateOfCharge, tint: AppTheme.chargingCyan, scale: .card)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(dashboardText("menu.config.second_metric", fallback: "顶部状态栏"))
                        .font(.system(size: compact ? 10.5 : 13, weight: .semibold))
                        .foregroundStyle(AppTheme.textPrimary)
                    Text(dashboardText("menu.config.status_hint", fallback: "固定显示电量，再选择一个实时指标"))
                        .font(.system(size: compact ? 8.5 : 9.5))
                        .foregroundStyle(AppTheme.textSecondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 10)

                Text(presentation.menuBarText(secondaryMetric: menuSettings.secondaryMetric))
                    .font(.system(size: compact ? 10 : 11.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppTheme.textPrimary)
                    .monospacedDigit()
                    .padding(.horizontal, 10)
                    .frame(height: compact ? 27 : 30)
                    .background(Capsule().fill(AppTheme.chargingBlue.opacity(0.12)))
                    .overlay(Capsule().stroke(AppTheme.chargingBlue.opacity(0.28), lineWidth: 1))
                    .accessibilityLabel(presentation.menuBarText(secondaryMetric: menuSettings.secondaryMetric))
            }

            HStack(spacing: 8) {
                Text(dashboardText("menu.config.metric_choice", fallback: "第二项显示"))
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(AppTheme.textSecondary)
                Spacer()
                metricPicker
            }
        }
        .padding(compact ? 10 : 14)
        .background(
            RoundedRectangle(cornerRadius: compact ? 9 : 12, style: .continuous)
                .fill(AppTheme.contrastOverlay(0.028))
        )
        .overlay(
            RoundedRectangle(cornerRadius: compact ? 9 : 12, style: .continuous)
                .stroke(AppTheme.cardBorder, lineWidth: 1)
        )
    }

    private var metricPicker: some View {
        Menu {
            ForEach(MenuBarMetric.allCases) { metric in
                Button {
                    menuSettings.selectSecondaryMetric(metric)
                } label: {
                    if menuSettings.secondaryMetric == metric {
                        Label(metric.title, systemImage: "checkmark")
                    } else {
                        Label(metric.title, systemImage: metric.symbol)
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                MetricGlyph(menuSettings.secondaryMetric.icon,
                            tint: AppTheme.chargingBlue,
                            scale: .micro,
                            style: .plain)
                Text(menuSettings.secondaryMetric.title)
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 7, weight: .bold))
            }
            .font(.system(size: 9.5, weight: .medium))
            .foregroundStyle(AppTheme.chargingBlue)
            .padding(.horizontal, 9)
            .frame(height: 29)
            .background(RoundedRectangle(cornerRadius: 7).fill(AppTheme.contrastOverlay(0.05)))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(AppTheme.cardBorder))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }
}

struct MenuBarDashboardView: View {
    @EnvironmentObject private var batteryService: BatteryService
    @EnvironmentObject private var processService: ProcessMonitorService
    @Environment(AppearanceSettings.self) private var appearance
    @Environment(MenuBarSettings.self) private var menuSettings
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var isCustomizing = false
    @State private var dropTarget: MenuBarMetric?

    init(initiallyCustomizing: Bool = false) {
        _isCustomizing = State(initialValue: initiallyCustomizing)
    }

    private var data: BatteryData { batteryService.batteryData }
    private var presentation: MenuBarPresentation { .init(data: data) }

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()

            LinearGradient(
                colors: glassTintColors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: [Color.white.opacity(colorScheme == .dark ? 0.07 : 0.24), .clear],
                center: .topLeading,
                startRadius: 12,
                endRadius: 360
            )

            VStack(spacing: 0) {
                header
                Divider().overlay(AppTheme.cardBorder)
                meters
                values
                if !isCustomizing {
                    trendSection
                    processSection
                }
                footer
            }
            .padding(17)
        }
        .frame(width: 440)
        .fixedSize(horizontal: true, vertical: true)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(glassBorder, lineWidth: 0.8)
        }
        .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.34 : 0.18), radius: 24, y: 10)
        .background(
            AppearanceWindowBridge(mode: appearance.mode, usesTransparentBackground: true)
                .frame(width: 0, height: 0)
        )
    }

    private var glassTintColors: [Color] {
        if colorScheme == .dark {
            return [
                Color(red: 0.02, green: 0.17, blue: 0.27).opacity(0.36),
                Color(red: 0.02, green: 0.10, blue: 0.18).opacity(0.28),
                AppTheme.chargingCyan.opacity(0.10),
            ]
        }
        return [
            Color.white.opacity(0.30),
            Color(red: 0.43, green: 0.75, blue: 0.91).opacity(0.18),
            AppTheme.chargingCyan.opacity(0.08),
        ]
    }

    private var glassBorder: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.26)
            : Color.white.opacity(0.72)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                MetricGlyph(.stateOfCharge, tint: AppTheme.chargingCyan, scale: .card)

                Text(L("app.title"))
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)

                Spacer(minLength: 4)

                compactAppearanceToggle
                settingsMenu
                LanguageSelectionMenu(iconOnly: true)
                headerIconButton(
                    symbol: "minus",
                    help: dashboardText("p.menu_close", fallback: "收起菜单栏面板"),
                    action: dismiss.callAsFunction
                )
                headerIconButton(
                    symbol: "power",
                    help: dashboardText("p.menu_quit", fallback: "完全退出 BatteryMonitor"),
                    tint: AppTheme.batteryRed
                ) {
                    NSApplication.shared.terminate(nil)
                }
            }

            Text(presentation.sourceText)
                .font(.system(size: 9.5))
                .foregroundStyle(AppTheme.textTertiary)
                .lineLimit(1)
                .padding(.leading, 43)
        }
        .padding(.bottom, 13)
    }

    private var compactAppearanceToggle: some View {
        HStack(spacing: 2) {
            ForEach([AppearanceMode.light, AppearanceMode.dark]) { mode in
                Button {
                    withAnimation(.easeInOut(duration: 0.16)) { appearance.select(mode) }
                } label: {
                    Image(systemName: mode.symbol)
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(resolvedAppearanceMode == mode ? AppTheme.selectionText : AppTheme.textSecondary)
                        .frame(width: 27, height: 27)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(resolvedAppearanceMode == mode ? AppTheme.chargingBlue : .clear)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(mode.title)
                .accessibilityValue(resolvedAppearanceMode == mode ? mode.title : "")
                .accessibilityAddTraits(resolvedAppearanceMode == mode ? .isSelected : [])
                .help(mode.title)
                .pointerOnHover()
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 8).fill(AppTheme.contrastOverlay(0.045)))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(AppTheme.cardBorder))
    }

    private var resolvedAppearanceMode: AppearanceMode {
        guard appearance.mode == .system else { return appearance.mode }
        let match = NSApplication.shared.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua])
        return match == .darkAqua ? .dark : .light
    }

    private func headerIconButton(
        symbol: String,
        help: String,
        tint: Color = AppTheme.textSecondary,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10.5, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 30, height: 30)
                .background(RoundedRectangle(cornerRadius: 8).fill(AppTheme.contrastOverlay(0.045)))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(AppTheme.cardBorder))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(help)
        .help(help)
        .pointerOnHover()
    }

    private var meters: some View {
        meter(
            title: dashboardText("p.system_charge", fallback: "macOS 电量"),
            value: presentation.percentText,
            fraction: presentation.chargeFraction,
            colors: [AppTheme.batteryGreen, AppTheme.chargingCyan]
        )
        .padding(.vertical, 15)
    }

    private func meter(title: String, value: String, fraction: Double, colors: [Color]) -> some View {
        VStack(spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.system(size: 11))
                    .foregroundStyle(AppTheme.textSecondary)
                Spacer()
                Text(value)
                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                    .foregroundStyle(AppTheme.textPrimary)
            }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(AppTheme.contrastOverlay(0.07))
                    Capsule()
                        .fill(LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(0, geometry.size.width * min(1, max(0, fraction))))
                }
            }
            .frame(height: 7)
        }
    }

    private var values: some View {
        VStack(spacing: 0) {
            MenuBarTopStatusConfigurationView(data: data, compact: true)
                .padding(.vertical, 10)

            HStack {
                Text(dashboardText("menu.config.title", fallback: "已显示指标"))
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(AppTheme.textPrimary)
                Spacer()
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) { isCustomizing.toggle() }
                } label: {
                    Label(
                        dashboardText("menu.config.customize", fallback: "自定义"),
                        systemImage: isCustomizing ? "checkmark" : "slider.horizontal.3"
                    )
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(isCustomizing ? AppTheme.batteryGreen : AppTheme.chargingBlue)
                }
                .buttonStyle(.plain)
                .pointerOnHover()
            }
            .frame(height: 34)

            if menuSettings.visibleMetrics.isEmpty {
                Text(dashboardText("menu.config.empty", fallback: "没有显示指标，可点“自定义”添加"))
                    .font(.system(size: 10))
                    .foregroundStyle(AppTheme.textTertiary)
                    .frame(maxWidth: .infinity, minHeight: 42)
            } else {
                ForEach(Array(menuSettings.visibleMetrics.enumerated()), id: \.element.id) { index, metric in
                    metricValueRow(metric, index: index)
                }
            }

            if isCustomizing {
                addMoreMetricsButton
            }
        }
        .overlay(alignment: .top) { Divider().overlay(AppTheme.cardBorder) }
    }

    private func metricValueRow(_ metric: MenuBarMetric, index: Int) -> some View {
        HStack(spacing: 9) {
            MetricGlyph(metric.icon, tint: metricColor(metric), scale: .compact)
            Text(presentation.title(for: metric))
                .font(.system(size: 11))
                .foregroundStyle(AppTheme.textSecondary)
            Spacer(minLength: 20)
            Text(presentation.value(for: metric))
                .font(.system(size: metric == .runtime ? 15 : 12,
                              weight: metric == .runtime ? .semibold : .medium,
                              design: .monospaced))
                .foregroundStyle(metric == .runtime ? AppTheme.chargingCyan : AppTheme.textPrimary)
                .monospacedDigit()

            if isCustomizing {
                Button {
                    withAnimation(.easeOut(duration: 0.15)) {
                        menuSettings.setVisible(metric, visible: false)
                    }
                } label: {
                    Image(systemName: "minus.circle")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AppTheme.batteryRed)
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(AppTheme.batteryRed.opacity(0.08)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(dashboardText("menu.config.hide", fallback: "隐藏")) \(metric.title)")
                .help(dashboardText("menu.config.hide", fallback: "隐藏"))
                .pointerOnHover()

                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppTheme.textSecondary)
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(AppTheme.contrastOverlay(0.045)))
                    .contentShape(Circle())
                    .draggable(metric.rawValue) {
                        Label(metric.title, systemImage: metric.symbol)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(AppTheme.textPrimary)
                            .padding(.horizontal, 11)
                            .padding(.vertical, 8)
                            .background(RoundedRectangle(cornerRadius: 8).fill(AppTheme.surfaceRaised))
                    }
                    .accessibilityLabel("\(dashboardText("menu.config.drag_to_reorder", fallback: "拖动调整顺序")) \(metric.title)")
                    .help(dashboardText("menu.config.drag_to_reorder", fallback: "拖动调整顺序"))
                    .pointerOnHover()
            }
        }
        .padding(.horizontal, isCustomizing ? 7 : 0)
        .frame(minHeight: isCustomizing ? 44 : 38)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(dropTarget == metric ? AppTheme.chargingCyan.opacity(0.09) : .clear)
        )
        .overlay {
            if isCustomizing {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(dropTarget == metric ? AppTheme.chargingCyan.opacity(0.52) : AppTheme.cardBorder,
                            lineWidth: 1)
            }
        }
        .overlay(alignment: .bottom) { Divider().overlay(AppTheme.cardBorder) }
        .dropDestination(for: String.self) { items, _ in
            guard isCustomizing,
                  let rawValue = items.first,
                  let draggedMetric = MenuBarMetric(rawValue: rawValue) else { return false }
            withAnimation(.easeInOut(duration: 0.18)) {
                menuSettings.move(draggedMetric, to: index)
            }
            dropTarget = nil
            return true
        } isTargeted: { targeted in
            if targeted {
                dropTarget = metric
            } else if dropTarget == metric {
                dropTarget = nil
            }
        }
    }

    private var addMoreMetricsButton: some View {
        Button(action: showMetricSettings) {
            HStack(spacing: 10) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(AppTheme.batteryGreen)
                VStack(alignment: .leading, spacing: 2) {
                    Text(dashboardText("menu.config.add_more", fallback: "添加更多指标"))
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(AppTheme.textPrimary)
                    Text(dashboardText("menu.config.manage_in_dashboard", fallback: "前往完整看板选择其他指标"))
                        .font(.system(size: 8.5))
                        .foregroundStyle(AppTheme.textTertiary)
                }
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(AppTheme.chargingBlue)
            }
            .padding(.horizontal, 10)
            .frame(height: 47)
            .background(RoundedRectangle(cornerRadius: 9).fill(AppTheme.batteryGreen.opacity(0.055)))
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(AppTheme.batteryGreen.opacity(0.18)))
        }
        .buttonStyle(.plain)
        .pointerOnHover()
        .padding(.top, 8)
    }

    private func metricColor(_ metric: MenuBarMetric) -> Color {
        switch metric {
        case .runtime: return AppTheme.chargingCyan
        case .power: return AppTheme.chargingBlue
        case .temperature: return AppTheme.batteryGreen
        case .cycles: return AppTheme.accentPurple
        case .health: return AppTheme.batteryGreen
        case .current: return AppTheme.batteryYellow
        }
    }

    private var trendSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(dashboardText("shell.dynamic_trends", fallback: "动态趋势"))
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(AppTheme.textPrimary)
                Spacer()
                Text(dashboardText("shell.last_minutes", fallback: "最近采样"))
                    .font(.system(size: 9))
                    .foregroundStyle(AppTheme.textTertiary)
            }

            trendRow(
                icon: .power,
                title: dashboardText("shell.instant_power", fallback: "瞬时功率"),
                values: batteryService.realtimeData.suffix(32).map(\.power),
                value: presentation.powerText,
                color: AppTheme.chargingCyan
            )
            trendRow(
                icon: .runtime,
                title: dashboardText("p.menu_time", fallback: "预计续航"),
                values: batteryService.runtimeSamples.suffix(32).map { Double($0.minutesRemaining) },
                value: presentation.runtimeText,
                color: AppTheme.chargingBlue
            )
            trendRow(
                icon: .current,
                title: dashboardText("shell.current", fallback: "电流"),
                values: batteryService.realtimeData.suffix(32).map(\.amperage),
                value: LNum("%.2f A", Double(data.amperage) / 1000),
                color: AppTheme.batteryGreen
            )
        }
        .padding(.vertical, 13)
        .overlay(alignment: .top) { Divider().overlay(AppTheme.cardBorder) }
    }

    private func trendRow(icon: BatteryMetricIcon, title: String, values: [Double], value: String, color: Color) -> some View {
        HStack(spacing: 9) {
            MetricGlyph(icon, tint: color, scale: .micro, style: .plain)
            Text(title)
                .font(.system(size: 10.5))
                .foregroundStyle(AppTheme.textSecondary)
                .frame(width: 76, alignment: .leading)
            MenuSparkline(values: values, color: color)
                .frame(maxWidth: .infinity)
                .frame(height: 27)
            Text(value)
                .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                .foregroundStyle(AppTheme.textSecondary)
                .frame(width: 72, alignment: .trailing)
        }
        .frame(height: 32)
    }

    private var processSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(dashboardText("shell.top_processes", fallback: "活跃耗电应用 Top 3"))
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(AppTheme.textPrimary)
                Spacer()
                Text(dashboardText("shell.cpu_context", fallback: "CPU 活动参考"))
                    .font(.system(size: 8.5))
                    .foregroundStyle(AppTheme.textTertiary)
            }

            if processService.topProcesses.isEmpty {
                HStack {
                    Text(processService.hasSampled
                         ? dashboardText("menu.process.none", fallback: "暂未读到活跃应用，点此重新采样")
                         : dashboardText("p.process_collecting", fallback: "正在读取进程活动…"))
                        .font(.system(size: 10))
                        .foregroundStyle(AppTheme.textTertiary)
                    Spacer()
                    Button(action: processService.fetchProcesses) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(AppTheme.chargingBlue)
                    .pointerOnHover()
                }
                .frame(maxWidth: .infinity, minHeight: 48)
            } else {
                ForEach(Array(processService.topProcesses.prefix(3).enumerated()), id: \.element.id) { index, process in
                    HStack(spacing: 9) {
                        menuProcessIconView(process)
                        Text(process.displayName)
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(AppTheme.textPrimary)
                            .lineLimit(1)
                        Spacer()
                        Text(LNum("%.1f%% CPU", process.cpuPercent))
                            .font(.system(size: 9.5, weight: index == 0 ? .semibold : .regular, design: .monospaced))
                            .foregroundStyle(AppTheme.energyColor(process.energyImpact))
                    }
                    .frame(height: 28)
                }
            }
        }
        .padding(.vertical, 13)
        .overlay(alignment: .top) { Divider().overlay(AppTheme.cardBorder) }
    }

    private var footer: some View {
        Button(action: showDashboard) {
            HStack(spacing: 7) {
                Image(systemName: BatteryMetricIcon.power.symbol)
                Text(dashboardText("p.menu_open", fallback: "打开完整看板"))
            }
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(AppTheme.textPrimary)
            .frame(maxWidth: .infinity, minHeight: 34)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(AppTheme.chargingCyan.opacity(0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .stroke(AppTheme.chargingCyan.opacity(0.24), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .pointerOnHover()
        .padding(.top, 14)
    }

    private var settingsMenu: some View {
        Menu {
            Button(action: refreshNow) {
                Label(dashboardText("p.refresh_now", fallback: "立即刷新"), systemImage: "arrow.clockwise")
            }
            Button(action: toggleLiveRefresh) {
                Label(
                    batteryService.isLiveRefreshEnabled
                        ? dashboardText("p.pause_refresh", fallback: "暂停")
                        : dashboardText("p.resume_refresh", fallback: "继续"),
                    systemImage: batteryService.isLiveRefreshEnabled ? "pause.fill" : "play.fill"
                )
            }

        } label: {
            Image(systemName: "gearshape.fill")
                .font(.system(size: 11))
                .foregroundStyle(AppTheme.textSecondary)
                .frame(width: 30, height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(AppTheme.contrastOverlay(0.035))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(AppTheme.cardBorder, lineWidth: 1)
                        )
                )
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .tint(AppTheme.textSecondary)
        .fixedSize()
        .accessibilityLabel(dashboardText("p.menu_settings", fallback: "设置"))
        .help(dashboardText("p.menu_settings", fallback: "设置"))
        .pointerOnHover()
    }

    private func refreshNow() {
        batteryService.refreshNow()
        processService.fetchProcesses()
    }

    private func toggleLiveRefresh() {
        let enabled = !batteryService.isLiveRefreshEnabled
        batteryService.setLiveRefreshEnabled(enabled)
        processService.setLiveRefreshEnabled(enabled)
    }

    private func showDashboard() {
        openWindow(id: "dashboard")
        NSApplication.shared.activate(ignoringOtherApps: true)
        dismiss()
    }

    private func showMetricSettings() {
        DashboardNavigation.shared.destination = .settings
        openWindow(id: "dashboard")
        NSApplication.shared.activate(ignoringOtherApps: true)
        dismiss()
    }

    private func menuProcessIcon(_ name: String) -> String {
        let lower = name.lowercased()
        if lower.contains("terminal") || lower.contains("iterm") { return "terminal" }
        if lower.contains("xcode") || lower.contains("code") { return "hammer" }
        if lower.contains("safari") || lower.contains("chrome") { return "globe" }
        if lower.contains("window") || lower.contains("system") { return "macwindow" }
        return "app"
    }

    @ViewBuilder
    private func menuProcessIconView(_ process: ProcessPowerInfo) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(AppTheme.energyColor(process.energyImpact).opacity(0.13))
            if let image = applicationIcon(for: process.name) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .padding(2)
            } else {
                Image(systemName: menuProcessIcon(process.displayName))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(AppTheme.energyColor(process.energyImpact))
            }
        }
        .frame(width: 24, height: 24)
    }

    private func applicationIcon(for executablePath: String) -> NSImage? {
        var url = URL(fileURLWithPath: executablePath)
        while url.path != "/" {
            if url.pathExtension.lowercased() == "app" {
                return NSWorkspace.shared.icon(forFile: url.path)
            }
            url.deleteLastPathComponent()
        }
        return nil
    }
}

private struct MenuSparkline: View {
    let values: [Double]
    let color: Color

    var body: some View {
        GeometryReader { geometry in
            if values.count >= 2 {
                let minValue = values.min() ?? 0
                let maxValue = values.max() ?? 1
                let span = max(maxValue - minValue, 0.0001)
                let step = geometry.size.width / CGFloat(values.count - 1)
                Path { path in
                    for (index, value) in values.enumerated() {
                        let point = CGPoint(
                            x: CGFloat(index) * step,
                            y: geometry.size.height - CGFloat((value - minValue) / span) * geometry.size.height
                        )
                        if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
                    }
                }
                .stroke(color, style: StrokeStyle(lineWidth: 1.35, lineCap: .round, lineJoin: .round))
            } else {
                Capsule().fill(color.opacity(0.22)).frame(height: 1).frame(maxHeight: .infinity)
            }
        }
        .accessibilityHidden(true)
    }
}
