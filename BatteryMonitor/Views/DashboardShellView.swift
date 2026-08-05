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

struct DashboardPageHeader<Trailing: View>: View {
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
