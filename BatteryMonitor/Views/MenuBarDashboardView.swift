import SwiftUI
import AppKit

/// A real AppKit backdrop blur for the menu-bar window. SwiftUI's material can
/// fall back to an in-window gray fill inside MenuBarExtra; `.behindWindow`
/// explicitly samples the desktop/app content under the popover instead.
private struct MenuBarGlassEffect: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let effect = NSVisualEffectView()
        effect.material = material
        effect.blendingMode = blendingMode
        effect.state = .active
        effect.isEmphasized = false
        return effect
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
        nsView.state = .active
        nsView.isEmphasized = false
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
    @State private var draggedMetric: MenuBarMetric?
    @State private var dragOriginIndex: Int?
    @State private var draggedTrendMetric: MenuBarTrendMetric?
    @State private var trendDragOriginIndex: Int?

    private let customizableMetricRowHeight: CGFloat = 44

    init(initiallyCustomizing: Bool = false) {
        _isCustomizing = State(initialValue: initiallyCustomizing)
    }

    private var data: BatteryData { batteryService.batteryData }
    private var presentation: MenuBarPresentation {
        .init(data: data, chargeSpeed: batteryService.chargeSpeed)
    }

    var body: some View {
        ZStack {
            MenuBarGlassEffect(
                // `popover` keeps the native blur visibly translucent in both
                // appearances. `hudWindow` becomes an almost opaque charcoal
                // slab in dark mode, which defeats the glass effect.
                material: .popover,
                blendingMode: .behindWindow
            )
                .ignoresSafeArea()
                .allowsHitTesting(false)

            LinearGradient(
                colors: glassTintColors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: [Color.white.opacity(colorScheme == .dark ? 0.035 : 0.10), .clear],
                center: .topLeading,
                startRadius: 12,
                endRadius: 360
            )

            VStack(spacing: 0) {
                header
                Divider().overlay(AppTheme.cardBorder)
                meters
                values
                if isCustomizing || !menuSettings.visibleTrendMetrics.isEmpty {
                    trendSection
                }
                if !isCustomizing {
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
                Color(red: 0.02, green: 0.17, blue: 0.27).opacity(0.105),
                Color(red: 0.02, green: 0.10, blue: 0.18).opacity(0.055),
                AppTheme.chargingCyan.opacity(0.025),
            ]
        }
        return [
            Color.white.opacity(0.055),
            Color(red: 0.43, green: 0.75, blue: 0.91).opacity(0.035),
            AppTheme.chargingCyan.opacity(0.018),
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
            MenuBarTopStatusConfigurationView(data: data,
                                              compact: true,
                                              chargeSpeed: batteryService.chargeSpeed)
                .padding(.vertical, 10)

            HStack {
                Text(dashboardText("menu.config.title", fallback: "已显示指标"))
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(AppTheme.textPrimary)
                Spacer()
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        isCustomizing.toggle()
                        if !isCustomizing {
                            resetAllMetricDrags()
                        }
                    }
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
                ForEach(menuSettings.visibleMetrics) { metric in
                    metricValueRow(metric)
                }
            }

            if isCustomizing {
                addMoreMetricsButton
            }
        }
        .overlay(alignment: .top) { Divider().overlay(AppTheme.cardBorder) }
    }

    private func metricValueRow(_ metric: MenuBarMetric) -> some View {
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
                    .foregroundStyle(draggedMetric == metric ? AppTheme.chargingCyan : AppTheme.textSecondary)
                    .frame(width: 26, height: 26)
                    .background(
                        Circle().fill(
                            draggedMetric == metric
                                ? AppTheme.chargingCyan.opacity(0.12)
                                : AppTheme.contrastOverlay(0.045)
                        )
                    )
                    .contentShape(Circle())
                    .highPriorityGesture(metricReorderGesture(for: metric))
                    .accessibilityLabel("\(dashboardText("menu.config.drag_to_reorder", fallback: "拖动调整顺序")) \(metric.title)")
                    .help(dashboardText("menu.config.drag_to_reorder", fallback: "拖动调整顺序"))
                    .pointerOnHover()
            }
        }
        .padding(.horizontal, isCustomizing ? 7 : 0)
        .frame(minHeight: isCustomizing ? 44 : 38)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(draggedMetric == metric ? AppTheme.chargingCyan.opacity(0.09) : .clear)
        )
        .overlay {
            if isCustomizing {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(draggedMetric == metric ? AppTheme.chargingCyan.opacity(0.52) : AppTheme.cardBorder,
                            lineWidth: 1)
            }
        }
        .overlay(alignment: .bottom) { Divider().overlay(AppTheme.cardBorder) }
        .zIndex(draggedMetric == metric ? 1 : 0)
    }

    /// Keep reordering inside the menu-bar window. System drag-and-drop sessions
    /// can leave a MenuBarExtra popover before SwiftUI delivers the matching
    /// drop, which makes the visible handle appear inert. A local mouse gesture
    /// follows the pointer and moves the persisted item as each row is crossed.
    private func metricReorderGesture(for metric: MenuBarMetric) -> some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .global)
            .onChanged { value in
                guard isCustomizing else { return }

                if draggedMetric == nil {
                    draggedMetric = metric
                    dragOriginIndex = menuSettings.visibleMetrics.firstIndex(of: metric)
                }

                guard draggedMetric == metric,
                      let originIndex = dragOriginIndex,
                      !menuSettings.visibleMetrics.isEmpty else { return }

                let crossedRows = Int((value.translation.height / customizableMetricRowHeight).rounded())
                let targetIndex = min(
                    max(0, originIndex + crossedRows),
                    menuSettings.visibleMetrics.count - 1
                )
                guard menuSettings.visibleMetrics.firstIndex(of: metric) != targetIndex else { return }

                withAnimation(.easeInOut(duration: 0.14)) {
                    menuSettings.move(metric, to: targetIndex)
                }
            }
            .onEnded { _ in
                resetMetricDrag()
            }
    }

    private func resetMetricDrag() {
        draggedMetric = nil
        dragOriginIndex = nil
    }

    private func resetAllMetricDrags() {
        resetMetricDrag()
        resetTrendMetricDrag()
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
        case .chargingPower: return AppTheme.batteryGreen
        case .chargeSpeed: return AppTheme.chargingCyan
        }
    }

    private var trendSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(dashboardText("shell.dynamic_trends", fallback: "动态趋势"))
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(AppTheme.textPrimary)
                Spacer()
                Text(dashboardText(
                    isCustomizing ? "menu.config.drag_to_reorder" : "shell.last_minutes",
                    fallback: isCustomizing ? "拖动调整顺序" : "最近采样"
                ))
                    .font(.system(size: 9))
                    .foregroundStyle(AppTheme.textTertiary)
            }

            if menuSettings.visibleTrendMetrics.isEmpty {
                Button {
                    withAnimation(.easeOut(duration: 0.15)) {
                        menuSettings.resetTrends()
                    }
                } label: {
                    Label(
                        dashboardText("menu.config.restore_defaults", fallback: "恢复默认"),
                        systemImage: "arrow.counterclockwise"
                    )
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(AppTheme.chargingBlue)
                    .frame(maxWidth: .infinity, minHeight: 38)
                }
                .buttonStyle(.plain)
                .pointerOnHover()
            } else {
                VStack(spacing: isCustomizing ? 0 : 8) {
                    ForEach(menuSettings.visibleTrendMetrics) { metric in
                        trendRow(metric)
                    }
                }
            }
        }
        .padding(.vertical, 13)
        .overlay(alignment: .top) { Divider().overlay(AppTheme.cardBorder) }
    }

    private func trendRow(_ metric: MenuBarTrendMetric) -> some View {
        let color = trendColor(metric)
        return HStack(spacing: 9) {
            MetricGlyph(metric.icon, tint: color, scale: .micro, style: .plain)
            Text(metric.title)
                .font(.system(size: 10.5))
                .foregroundStyle(AppTheme.textSecondary)
                .frame(width: 76, alignment: .leading)
            MenuSparkline(values: trendValues(metric), color: color)
                .frame(maxWidth: .infinity)
                .frame(height: 27)
            Text(trendValue(metric))
                .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                .foregroundStyle(AppTheme.textSecondary)
                .frame(width: 72, alignment: .trailing)

            if isCustomizing {
                Button {
                    withAnimation(.easeOut(duration: 0.15)) {
                        menuSettings.setTrendVisible(metric, visible: false)
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
                    .foregroundStyle(draggedTrendMetric == metric ? AppTheme.chargingCyan : AppTheme.textSecondary)
                    .frame(width: 26, height: 26)
                    .background(
                        Circle().fill(
                            draggedTrendMetric == metric
                                ? AppTheme.chargingCyan.opacity(0.12)
                                : AppTheme.contrastOverlay(0.045)
                        )
                    )
                    .contentShape(Circle())
                    .highPriorityGesture(trendMetricReorderGesture(for: metric))
                    .accessibilityLabel("\(dashboardText("menu.config.drag_to_reorder", fallback: "拖动调整顺序")) \(metric.title)")
                    .help(dashboardText("menu.config.drag_to_reorder", fallback: "拖动调整顺序"))
                    .pointerOnHover()
            }
        }
        .padding(.horizontal, isCustomizing ? 7 : 0)
        .frame(height: isCustomizing ? customizableMetricRowHeight : 32)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(draggedTrendMetric == metric ? AppTheme.chargingCyan.opacity(0.09) : .clear)
        )
        .overlay {
            if isCustomizing {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(
                        draggedTrendMetric == metric ? AppTheme.chargingCyan.opacity(0.52) : AppTheme.cardBorder,
                        lineWidth: 1
                    )
            }
        }
        .zIndex(draggedTrendMetric == metric ? 1 : 0)
    }

    private func trendMetricReorderGesture(for metric: MenuBarTrendMetric) -> some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .global)
            .onChanged { value in
                guard isCustomizing else { return }

                if draggedTrendMetric == nil {
                    draggedTrendMetric = metric
                    trendDragOriginIndex = menuSettings.visibleTrendMetrics.firstIndex(of: metric)
                }

                guard draggedTrendMetric == metric,
                      let originIndex = trendDragOriginIndex,
                      !menuSettings.visibleTrendMetrics.isEmpty else { return }

                let crossedRows = Int((value.translation.height / customizableMetricRowHeight).rounded())
                let targetIndex = min(
                    max(0, originIndex + crossedRows),
                    menuSettings.visibleTrendMetrics.count - 1
                )
                guard menuSettings.visibleTrendMetrics.firstIndex(of: metric) != targetIndex else { return }

                withAnimation(.easeInOut(duration: 0.14)) {
                    menuSettings.moveTrend(metric, to: targetIndex)
                }
            }
            .onEnded { _ in
                resetTrendMetricDrag()
            }
    }

    private func resetTrendMetricDrag() {
        draggedTrendMetric = nil
        trendDragOriginIndex = nil
    }

    private func trendValues(_ metric: MenuBarTrendMetric) -> [Double] {
        switch metric {
        case .power:
            return batteryService.realtimeData.suffix(32).map(\.power)
        case .runtime:
            return batteryService.runtimeSamples.suffix(32).map { Double($0.minutesRemaining) }
        case .current:
            return batteryService.realtimeData.suffix(32).map(\.amperage)
        }
    }

    private func trendValue(_ metric: MenuBarTrendMetric) -> String {
        switch metric {
        case .power:
            return presentation.powerText
        case .runtime:
            return presentation.runtimeText
        case .current:
            return LNum("%.2f A", Double(data.amperage) / 1000)
        }
    }

    private func trendColor(_ metric: MenuBarTrendMetric) -> Color {
        switch metric {
        case .power: return AppTheme.chargingCyan
        case .runtime: return AppTheme.chargingBlue
        case .current: return AppTheme.batteryGreen
        }
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

    /// 从可执行文件路径向上找到所属的 .app bundle，取它的真实图标。
    ///
    /// 两个守卫都是必需的，不是防御性冗余：
    /// - `hasPrefix("/")` —— 列表现在会出现没有 bundle 的进程（命令行工具、XPC helper），
    ///   它们的 name 可能是裸 comm 甚至空串。`URL(fileURLWithPath:)` 会把它当相对路径，
    ///   而 `deleteLastPathComponent()` 在没有 component 可删时会往上追加 `../`，
    ///   于是 `url.path != "/"` 永假 —— 主线程在 body 求值里死循环。
    /// - 深度上限 —— 即使是绝对路径，也不把终止条件全押在字符串比较上。
    private func applicationIcon(for executablePath: String) -> NSImage? {
        guard executablePath.hasPrefix("/") else { return nil }
        var url = URL(fileURLWithPath: executablePath)
        var depth = 0
        while url.path != "/", depth < 32 {
            if url.pathExtension.lowercased() == "app" {
                return NSWorkspace.shared.icon(forFile: url.path)
            }
            url.deleteLastPathComponent()
            depth += 1
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
