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

            // Zero spacing here and the gap moved inside each label, so the
            // strip is contiguous: the space between two rows belongs to one of
            // them instead of being a dead 8pt band.
            VStack(spacing: 0) {
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
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(selection == destination
                                      ? LinearGradient(colors: [AppTheme.chargingBlue, Color(red: 0.12, green: 0.43, blue: 0.95)],
                                                       startPoint: .topLeading, endPoint: .bottomTrailing)
                                      : LinearGradient(colors: [.clear, .clear], startPoint: .leading, endPoint: .trailing))
                                .shadow(color: selection == destination ? AppTheme.chargingBlue.opacity(0.22) : .clear,
                                        radius: 10, y: 3)
                        }
                        // The inset and the row gap live inside the label, so they
                        // are part of the button rather than dead sidebar margin.
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                        // A plain button only accepts clicks on what it actually
                        // draws. The selected row has a real gradient behind it and
                        // was easy to hit; every other row was backed by a fully
                        // transparent fill, so only the icon and the label glyphs
                        // responded — and unselected rows are the ones being aimed
                        // at. Rectangle, not the rounded pill, so the corners and
                        // the full sidebar width count too.
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .pointerOnHover()
                }
            }

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

/// What the battery is actually doing right now. Four states rather than the
/// on-AC / on-battery pair the hero used to show: "plugged in" hid the case where
/// the adapter is attached, charging has stopped, and the battery is still
/// draining (measured at -694 mA with optimised charging holding 80%).
/// How often a rail card's number can change, which decides what its footer says.
/// Three genuinely different cadences share that row, and collapsing them into
/// one countdown would put a ticking clock under a factory constant.
enum MetricCardCadence {
    /// Republished with the rest of the gauge's fields, ~60 s apart.
    case gauge
    /// Only moves when the cable does — the adapter's rated wattage.
    case onPlug
    /// Never moves.
    case constant

    func text(_ stamp: MetricReadStamp, now: Date) -> String {
        switch self {
        case .gauge:
            return MetricFieldFreshness.countdownText(stamp, now: now)
        case .onPlug:
            // Short form: the rail column is ~240pt wide and the drawer's full
            // sentence wrapped to three lines, throwing this card's footer out of
            // line with the other six.
            return dashboardText(
                "p.field_cadence_on_plug",
                fallback: "插拔时变化 · 上次 {time}",
                replacements: ["time": MetricFieldFreshness.clockText(stamp.at)])
        case .constant:
            return dashboardText("p.field_constant", fallback: "出厂固定值，不随使用变化")
        }
    }
}

enum BatteryPowerState: Equatable {
    case charging
    case full
    /// On AC, the battery neither taking nor giving meaningful power — optimised
    /// charging holding, or a charger that cannot keep up. Deliberately not
    /// explained further: `ChargerData.NotChargingReason` is an undocumented
    /// bitmask and `InsightEngine` already decided not to guess at it.
    case pluggedIdle
    /// On AC and *still draining*. The old label for this was "plugged in, not
    /// charging", which is true but hides the direction — and left the flow
    /// diagram drawing an arrow the words denied.
    case pluggedDischarging
    case discharging

    /// A resting pack drifts by a few tens of milliamps. Below half a watt the
    /// direction is noise, not a state worth naming.
    static let restingWatts = 0.5

    /// Resolved from measured battery power, not from `IsCharging`. The flag
    /// comes from IOPowerSources while the current comes from the IORegistry, on
    /// a different refresh cadence, so the two disagree for a tick at a time —
    /// which is how the panel came to read "not charging · +3.95 A".
    static func resolve(_ s: DashboardMetricSnapshot) -> BatteryPowerState {
        guard s.data.isOnAC else { return .discharging }
        let watts = s.batteryPowerWatts ?? 0
        if watts >= restingWatts { return .charging }
        if watts <= -restingWatts { return .pluggedDischarging }
        // Inside the dead band the measurement cannot pick a side, so fall back
        // to the flags — including the top of a charge, where current has tapered
        // to nothing but `IsCharging` is still the honest answer.
        if s.data.isFullyCharged { return .full }
        return s.data.isCharging ? .charging : .pluggedIdle
    }
}

struct DashboardOverviewPage: View {
    @EnvironmentObject private var batteryService: BatteryService
    @Binding var selectedHelp: MetricHelpContent?

    private var data: BatteryData { batteryService.batteryData }
    private var snapshot: DashboardMetricSnapshot {
        DashboardMetricSnapshot(
            data: data,
            realtimeData: batteryService.realtimeData,
            systemRuntimeFallbackSample: batteryService.runtimeSamples.last
        )
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
        // One snapshot for the whole card: it is a computed property that refilters
        // the realtime buffer on every read, and this card needs six values from it.
        let s = snapshot
        // Stacked rather than side by side: charge and the three runtime
        // estimates answer "how much is left", the diagram answers "where is it
        // going". Putting the second beside the first forced the card wide enough
        // that both halves ran cramped.
        return VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 22) {
                Text(presentation.percentText)
                    .font(.system(size: 68, weight: .light, design: .rounded))
                    .foregroundStyle(AppTheme.textPrimary)
                    .monospacedDigit()
                    .fixedSize()

                VStack(alignment: .leading, spacing: 9) {
                    HStack(spacing: 7) {
                        Text(dashboardText("shell.runtime_comparison", fallback: "续航时间对照"))
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(AppTheme.textSecondary)
                        MetricHelpButton(content: DashboardHelp.runtime(s),
                                         selection: $selectedHelp)
                    }

                    if s.designEnergyWh == nil {
                        // Both derived calibres depend on design energy, so an
                        // unrecognised model blanks them together. One honest line
                        // beats two cards showing "—".
                        VStack(spacing: 9) {
                            runtimeCard(
                                title: dashboardText("p.runtime_system_label", fallback: "macOS 系统时间"),
                                minutes: s.systemRuntimeMinutes,
                                basis: systemRuntimeBasis(s),
                                color: AppTheme.chargingCyan,
                                emphasised: true
                            )
                            derivedUnavailableCard
                        }
                    } else {
                        // All three share one vertical shape. The Apple estimate
                        // used to be a wide horizontal card, which stopped fitting
                        // the moment the row became three columns instead of one:
                        // its 32pt figure squeezed the title down to one character
                        // per line.
                        HStack(spacing: 10) {
                            runtimeCard(
                                title: dashboardText("p.runtime_system_label", fallback: "macOS 系统时间"),
                                minutes: s.systemRuntimeMinutes,
                                basis: systemRuntimeBasis(s),
                                color: AppTheme.chargingCyan,
                                emphasised: true
                            )
                            runtimeCard(
                                title: dashboardText("p.runtime_stable_label", fallback: "稳健估算"),
                                minutes: s.stableRuntimeMinutes,
                                basis: stableRuntimeBasis(s),
                                color: AppTheme.accentPurple
                            )
                            runtimeCard(
                                title: dashboardText("p.runtime_current_label", fallback: "当前负载估算"),
                                minutes: s.currentLoadRuntimeMinutes,
                                basis: currentRuntimeBasis(s),
                                color: AppTheme.batteryYellow
                            )
                        }
                    }
                }
            }

            Divider().overlay(AppTheme.cardBorder)

            batteryStatusPanel(s)
        }
        .padding(28)
        .background(RoundedRectangle(cornerRadius: 16).fill(AppTheme.cardBackground))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppTheme.cardBorder))
        .shadow(color: Color.black.opacity(0.10), radius: 22, y: 8)
    }

    /// One shape for all three estimates. `emphasised` is the Apple calibre: it
    /// gets the tinted background and a larger figure, but the same geometry, so
    /// the row cannot break the way a mixed horizontal/vertical row did.
    ///
    /// Fixed height on purpose. With `Spacer` doing the vertical work, one card
    /// growing dragged the other two with it and left them mostly empty.
    private func runtimeCard(
        title: String,
        minutes: Int?,
        basis: String,
        color: Color,
        emphasised: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                if emphasised {
                    Image(systemName: "apple.logo")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(color)
                }
                Text(title)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(emphasised ? AppTheme.textPrimary : AppTheme.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            Text(basis)
                .font(.system(size: 9))
                .foregroundStyle(AppTheme.textTertiary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                // Reserve both lines whether or not the basis needs them, so the
                // three figures always sit on the same baseline.
                .frame(maxWidth: .infinity, minHeight: 24, alignment: .topLeading)
            Text(MenuBarPresentation.durationText(minutes))
                .font(.system(size: emphasised ? 26 : 22, weight: .medium, design: .rounded))
                .foregroundStyle(color)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.55)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: 92, maxHeight: 92, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 11)
            .fill(emphasised ? color.opacity(0.06) : AppTheme.contrastOverlay(0.025)))
        .overlay(RoundedRectangle(cornerRadius: 11)
            .stroke(emphasised ? color.opacity(0.20) : AppTheme.cardBorder))
        .accessibilityElement(children: .combine)
    }

    private var derivedUnavailableCard: some View {
        Text(dashboardText("shell.derived_runtime_unavailable",
                           fallback: "本机型号缺少额定电量数据，无法换算稳健估算与当前负载估算"))
            .font(.system(size: 10))
            .foregroundStyle(AppTheme.textTertiary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 11).fill(AppTheme.contrastOverlay(0.025)))
            .overlay(RoundedRectangle(cornerRadius: 11).stroke(AppTheme.cardBorder))
    }

    /// Concise basis lines. Each says where the number comes from in one breath;
    /// the question mark next to the section title carries the long version.
    private func systemRuntimeBasis(_ s: DashboardMetricSnapshot) -> String {
        guard s.systemRuntimeMinutes != nil else {
            return dashboardText("shell.apple_runtime_unavailable", fallback: "Apple 官方系统预估 · 拔电使用后生成")
        }
        // On AC the gauge parks its estimate, so what is on screen is the last
        // valid reading rather than a live one — say so instead of implying live.
        guard data.timeRemainingMinutes != nil else {
            return dashboardText("shell.apple_runtime_last_note",
                                 fallback: "接电状态下保留最近一次有效的 Apple 官方系统预估")
        }
        return dashboardText("shell.system_runtime_basis", fallback: "Apple 官方算法 · 与菜单栏一致")
    }

    private func stableRuntimeBasis(_ s: DashboardMetricSnapshot) -> String {
        guard s.stableRuntimeMinutes != nil else {
            return dashboardText("shell.stable_runtime_collecting",
                                 fallback: "正在积累样本 {samples}/5",
                                 replacements: ["samples": "\(s.recentStablePowerSamples.count)"])
        }
        return dashboardText("shell.stable_runtime_basis", fallback: "近 10 分钟功耗中位数")
    }

    private func currentRuntimeBasis(_ s: DashboardMetricSnapshot) -> String {
        guard s.currentLoadRuntimeMinutes != nil else {
            return dashboardText("shell.instant_runtime_waiting", fallback: "等待有效的瞬时功率数据")
        }
        return dashboardText("shell.current_runtime_basis",
                             fallback: "按此刻 {power} W 计算",
                             replacements: ["power": LNum("%.1f", s.currentPowerWatts)])
    }


    private var batterySymbol: String {
        switch data.percent {
        case 76...: return "battery.100percent"
        case 51...: return "battery.75percent"
        case 26...: return "battery.50percent"
        default: return "battery.25percent"
        }
    }

    /// State plus the two numbers that are not already in the metric rail one row
    /// below: signed battery current, and time to full while charging.
    private func batteryStatusPanel(_ s: DashboardMetricSnapshot) -> some View {
        let state = BatteryPowerState.resolve(s)
        // Diagram left, readings right. Stacking these vertically left the 290pt
        // drawing marooned in the middle of a very wide card with a full-width
        // capsule under it. Pairing them keeps the row compact and reads as one
        // thing: the picture and the numbers behind it.
        return HStack(alignment: .center, spacing: 26) {
            Spacer(minLength: 0)

            PowerFlowDiagram(
                flow: PowerFlow.resolve(s),
                batteryPercent: data.percent,
                batterySymbol: batterySymbol
            )
            .fixedSize()

            VStack(alignment: .leading, spacing: 8) {
                Text(stateTitle(state))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(stateTint(state))
                    .fixedSize(horizontal: false, vertical: true)

                if state != .full {
                    statusDetailRow(
                        label: dashboardText("shell.battery_current", fallback: "电流"),
                        value: batteryCurrentText(s),
                        tint: stateTint(state)
                    )
                }
                if state == .charging {
                    statusDetailRow(
                        label: dashboardText("shell.time_to_full", fallback: "充满还需"),
                        value: MenuBarPresentation.durationText(s.timeToFullMinutes),
                        tint: AppTheme.batteryGreen
                    )
                }

                // Every number in this row comes from one gauge publish, so one
                // stamp covers it. Same wording as the help drawer's field lines.
                TimelineView(.periodic(from: Date(), by: 1)) { timeline in
                    Text(MetricFieldFreshness.countdownText(s.rawFieldReadAt, now: timeline.date))
                        .font(.system(size: 9))
                        .foregroundStyle(AppTheme.textTertiary)
                        .monospacedDigit()
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(width: 230, alignment: .leading)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
    }

    private func statusDetailRow(label: String, value: String, tint: Color) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(AppTheme.textTertiary)
            Spacer(minLength: 6)
            Text(value)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(tint)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 8).fill(AppTheme.contrastOverlay(0.03)))
        .accessibilityElement(children: .combine)
    }

    /// Signed on purpose: the sign is the direction, and a negative current while
    /// plugged in is exactly the state the old single status line hid.
    private func batteryCurrentText(_ s: DashboardMetricSnapshot) -> String {
        guard let milliamps = s.batteryCurrentMilliamps else { return "—" }
        return LNum("%+.2f A", Double(milliamps) / 1000)
    }

    private func stateTitle(_ state: BatteryPowerState) -> String {
        switch state {
        case .charging: return dashboardText("shell.charging", fallback: "正在充电")
        case .full: return dashboardText("shell.state_full", fallback: "已充满 · 电源供电")
        case .pluggedIdle: return dashboardText("shell.state_plugged_idle", fallback: "已接电源 · 未充电")
        case .pluggedDischarging:
            return dashboardText("shell.state_plugged_discharging", fallback: "已接电源 · 电池放电中")
        case .discharging: return dashboardText("shell.on_battery", fallback: "正在使用电池")
        }
    }

    private func stateTint(_ state: BatteryPowerState) -> Color {
        switch state {
        case .charging, .full: return AppTheme.batteryGreen
        case .pluggedIdle: return AppTheme.batteryYellow
        case .pluggedDischarging: return AppTheme.chargingCyan
        case .discharging: return AppTheme.chargingCyan
        }
    }

    private var metricRail: some View {
        // ViewThatFits builds both candidates, so the grid is constructed twice.
        // Building the snapshot once here means 2 rebuilds instead of ~26: each
        // of the seven cards used to re-read `snapshot` for its value and again
        // for its help sheet.
        let s = snapshot
        return ViewThatFits(in: .horizontal) {
            metricGrid(s, columnCount: 7)
                .frame(minWidth: 760)
            metricGrid(s, columnCount: 4)
        }
        .padding(.vertical, 18)
        .background(RoundedRectangle(cornerRadius: 15).fill(AppTheme.cardBackground))
        .overlay(RoundedRectangle(cornerRadius: 15).stroke(AppTheme.cardBorder))
    }

    private func metricGrid(_ s: DashboardMetricSnapshot, columnCount: Int) -> some View {
        // Last ten minutes at our 10 s poll. Sliced once for all four trend lines
        // rather than per card, which ViewThatFits would have doubled.
        let recent = Array(s.realtimeData.suffix(60))
        let stamp = s.rawFieldReadAt
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: columnCount), spacing: 0) {
            overviewMetric(.power, MenuBarMetric.power.title,
                           LNum("%.1f W", s.currentPowerWatts), AppTheme.chargingBlue,
                           dashboardText("shell.power_hint", fallback: "整机实时功率"),
                           field: "BatteryData.SystemPower", cadence: .gauge, stamp: stamp,
                           series: recent.map(\.power),
                           help: { DashboardHelp.power(s) })
            overviewMetric(.adapter, dashboardText("shell.adapter", fallback: "适配器功率"),
                           "\(data.chargerWattage) W", AppTheme.textSecondary,
                           data.isOnAC ? dashboardText("shell.adapter_connected", fallback: "当前额定功率") : dashboardText("shell.not_connected", fallback: "未连接"),
                           // A rating negotiated once at plug-in, not a measurement.
                           field: "AdapterDetails.Watts", cadence: .onPlug, stamp: stamp,
                           help: { DashboardHelp.adapterPower(s) })
            overviewMetric(.adapterOutput, dashboardText("shell.adapter_output_power", fallback: "适配器输出功率"),
                           s.adapterOutputPowerWatts.map { LNum("%.1f W", $0) } ?? "—",
                           AppTheme.chargingCyan,
                           data.isOnAC ? dashboardText("shell.whole_mac_input", fallback: "整机实时输入") : dashboardText("shell.not_connected", fallback: "未连接"),
                           // Derived, and labelled as such: SystemPowerIn was
                           // measured reading 0 mW while plugged in and charging.
                           field: "SystemPower + Voltage × Amperage", cadence: .gauge, stamp: stamp,
                           series: recent.compactMap { point -> Double? in
                               guard point.isOnAC else { return nil }
                               return max(0, point.power) + max(0, point.amperage / 1000 * point.voltage)
                           },
                           help: { DashboardHelp.adapterOutputPower(s) })
            overviewMetric(.charging, dashboardText("shell.charge_power", fallback: "充电功率"),
                           chargingPowerText(s), AppTheme.batteryGreen,
                           data.isCharging ? dashboardText("shell.charging", fallback: "正在充电") : dashboardText("shell.not_charging", fallback: "当前未充电"),
                           field: "Voltage × Amperage", cadence: .gauge, stamp: stamp,
                           series: recent.map { max(0, $0.amperage) / 1000 * $0.voltage },
                           help: { DashboardHelp.chargingPower(s) })
            overviewMetric(.temperature, MenuBarMetric.temperature.title,
                           LNum("%.1f ℃", data.temperatureCelsius), AppTheme.textSecondary,
                           dashboardText("shell.temp_range", fallback: "建议 20–35℃"),
                           field: "Temperature", cadence: .gauge, stamp: stamp,
                           series: recent.map(\.temperature),
                           help: { DashboardHelp.temperature(s) })
            overviewMetric(.cycles, MenuBarMetric.cycles.title, "\(data.cycleCount)", AppTheme.accentPurple,
                           dashboardText("shell.cycle_reference", fallback: "参考额定 1000 次"),
                           // Re-read on the gauge's beat like everything else; it
                           // just rarely moves. Saying "constant" here would be a lie.
                           field: "CycleCount", cadence: .gauge, stamp: stamp,
                           help: { DashboardHelp.cycleCount(s) })
            overviewMetric(.health, MenuBarMetric.health.title,
                           LNum("%.1f%%", s.healthPercent), AppTheme.batteryGreen,
                           healthLabel,
                           field: "AppleRawMaxCapacity ÷ DesignCapacity",
                           cadence: .gauge, stamp: stamp,
                           help: { DashboardHelp.health(s) })
        }
    }

    private func chargingPowerText(_ s: DashboardMetricSnapshot) -> String {
        guard let watts = s.batteryChargingPowerWatts else { return "—" }
        return watts < 0.05 ? "0 W" : LNum("%.1f W", watts)
    }

    private func overviewMetric(
        _ icon: BatteryMetricIcon,
        _ title: String,
        _ value: String,
        _ color: Color,
        _ hint: String,
        /// The lowest-level key this number comes from. Shown verbatim so the
        /// card can be checked against `ioreg` without opening the drawer.
        field: String,
        cadence: MetricCardCadence,
        stamp: MetricReadStamp,
        /// Recent samples for the trend line. Empty means no series exists for
        /// this metric — a rated wattage has nothing to plot.
        series: [Double] = [],
        /// Built on tap: the rail holds seven of these and ViewThatFits renders
        /// it twice, so eager construction meant fourteen unused help sheets per
        /// redraw.
        help: @escaping () -> MetricHelpContent
    ) -> some View {
        VStack(spacing: 7) {
            MetricGlyph(icon, tint: color, scale: .card)
            Text(title)
                .font(.system(size: 10.5))
                .foregroundStyle(AppTheme.textSecondary)
                .lineLimit(2)
                .minimumScaleFactor(0.82)
                .multilineTextAlignment(.center)
            // The trend sits behind the value instead of under it: a chart row of
            // its own would add its height to all seven columns.
            Text(value)
                .font(.system(size: 20, weight: .medium, design: .rounded))
                .foregroundStyle(AppTheme.textPrimary)
                .monospacedDigit()
                .lineLimit(1)
                .frame(maxWidth: .infinity, minHeight: 30)
                .background(alignment: .bottom) {
                    MetricSparkline(values: series, tint: color)
                        .frame(height: 26)
                        .padding(.horizontal, 2)
                }
            Text(hint)
                .font(.system(size: 8.5))
                .foregroundStyle(AppTheme.textTertiary)
                .lineLimit(2)
                .multilineTextAlignment(.center)

            Spacer(minLength: 0)

            // Fixed height so all seven footers share a baseline regardless of
            // how many lines each cadence sentence needs.
            VStack(spacing: 2) {
                Text(field)
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundStyle(AppTheme.textTertiary.opacity(0.75))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                TimelineView(.periodic(from: Date(), by: 1)) { timeline in
                    Text(cadence.text(stamp, now: timeline.date))
                        .font(.system(size: 8))
                        .foregroundStyle(AppTheme.textTertiary.opacity(0.75))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
            .frame(height: 24)
        }
        // Sized to the content. It was 186 while the stack only needed ~145, and
        // the Spacer turned that slack into a gap under the hint line.
        .frame(maxWidth: .infinity, minHeight: 148)
        .padding(.horizontal, 8)
        .padding(.bottom, 6)
        .overlay(alignment: .topTrailing) {
            MetricHelpButton(content: help(), selection: $selectedHelp)
                .padding(9)
        }
        .overlay(alignment: .trailing) { Rectangle().fill(AppTheme.divider).frame(width: 1) }
    }

    private var healthLabel: String {
        let health = snapshot.healthPercent
        if health >= 90 { return dashboardText("shell.health_good", fallback: "状态良好") }
        if health >= 80 { return dashboardText("shell.health_fair", fallback: "正常使用") }
        return dashboardText("shell.health_attention", fallback: "建议关注")
    }

    private var statusBanner: some View {
        // One snapshot for the banner. needsAttention reads healthPercent, and it
        // used to be re-evaluated by statusColor, statusSymbol and statusHeadline
        // separately — three snapshot rebuilds for one boolean.
        let attention = needsAttention
        return HStack(spacing: 16) {
            ZStack {
                Circle().fill(attention ? AppTheme.batteryOrange : AppTheme.batteryGreen)
                    .frame(width: 48, height: 48)
                Image(systemName: attention ? "exclamationmark" : "checkmark")
                    .font(.system(size: 20, weight: .bold)).foregroundStyle(AppTheme.selectionText)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(attention
                     ? dashboardText("shell.status_attention", fallback: "有一项指标需要关注")
                     : dashboardText("shell.status_good", fallback: "状态良好 · 各项指标处于可接受范围"))
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
    private var statusSubtitle: String {
        dashboardText("shell.status_subtitle", fallback: "续航以系统读数为准；详细来源和公式可在技术参数中核验。")
    }
}

struct DashboardTechnicalPage: View {
    @EnvironmentObject private var batteryService: BatteryService
    @Binding var selectedHelp: MetricHelpContent?

    var body: some View {
        ScrollView {
            // Lazy on purpose: this page stacks nine heavy sections, and a plain
            // VStack builds every one of them — both charts, the 464-row
            // workbench, all the ViewThatFits candidates — before the first
            // screenful can be shown. The direct child of the ScrollView has to
            // be the lazy one for the sections below to inherit the viewport.
            LazyVStack(spacing: 20) {
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
    @Environment(\.dashboardDataVersion) private var dataVersion
    let snapshot: SystemDataSnapshot
    @Binding var selectedHelp: MetricHelpContent?

    private var anomalies: [SystemFieldReading] {
        snapshot.fields.filter { $0.anomalyLevel > .none }.sorted { $0.anomalyLevel > $1.anomalyLevel }
    }

    var body: some View {
        // Filtered and sorted once: this was a computed property read four times
        // per redraw, so all 464 readings were scanned and sorted four times.
        let anomalies = self.anomalies
        return VStack(alignment: .leading, spacing: 13) {
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
                    // Was `.onChange(of: field.help)`, which built a whole help
                    // sheet on every redraw just to use it as a comparison key.
                    // The row's identity is enough, and the sheet is now built
                    // only when this row's panel is the one on screen.
                    .onChange(of: dataVersion) { _, _ in
                        guard selectedHelp?.id == field.helpID else { return }
                        selectedHelp = field.help
                    }
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
            MenuBarTopStatusConfigurationView(data: batteryService.batteryData)

            Divider().overlay(AppTheme.cardBorder)

            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 11).fill(AppTheme.batteryGreen.opacity(0.10))
                    Image(systemName: "menubar.rectangle").foregroundStyle(AppTheme.batteryGreen)
                }
                .frame(width: 42, height: 42)
                VStack(alignment: .leading, spacing: 3) {
                    Text(dashboardText("menu.config.title", fallback: "弹出面板指标"))
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

            Divider().overlay(AppTheme.cardBorder)

            HStack(spacing: 8) {
                Image(systemName: "chart.xyaxis.line")
                    .foregroundStyle(AppTheme.chargingCyan)
                Text(dashboardText("shell.dynamic_trends", fallback: "动态趋势"))
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(AppTheme.textPrimary)
                Spacer()
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 9) {
                ForEach(MenuBarTrendMetric.allCases) { metric in
                    Toggle(isOn: Binding(
                        get: { menuSettings.visibleTrendMetrics.contains(metric) },
                        set: { menuSettings.setTrendVisible(metric, visible: $0) }
                    )) {
                        HStack(spacing: 8) {
                            Image(systemName: metric.icon.symbol)
                                .foregroundStyle(menuTrendMetricColor(metric))
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

    private func menuTrendMetricColor(_ metric: MenuBarTrendMetric) -> Color {
        switch metric {
        case .power: return AppTheme.chargingCyan
        case .runtime: return AppTheme.chargingBlue
        case .current: return AppTheme.batteryGreen
        }
    }
}
