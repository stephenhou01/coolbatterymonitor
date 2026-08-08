import SwiftUI

enum DashboardDestination: String, CaseIterable, Identifiable {
    case overview
    case technical
    case trends
    case diagnostics
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: return dashboardText("shell.overview")
        case .technical: return dashboardText("shell.technical")
        case .trends: return dashboardText("shell.trends")
        case .diagnostics: return dashboardText("shell.diagnostics")
        case .settings: return dashboardText("shell.settings")
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
                        .minimumScaleFactor(0.88)
                }
                Text(dashboardText("shell.sidebar_subtitle"))
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
                Text(dashboardText("shell.local_only"))
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
            ForEach(AppearanceMode.selectableCases) { mode in
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
        .accessibilityLabel(dashboardText("p.menu_language"))
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
                replacements: ["time": MetricFieldFreshness.clockText(stamp.at)])
        case .constant:
            return dashboardText("p.field_constant")
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

    /// Resolved from measured battery power, not from `IsCharging` alone.
    ///
    /// The reason is not a sampling race between two APIs, which is what an
    /// earlier version of this comment claimed: `BatteryService.fetchData` reads
    /// `IsCharging` and the battery current out of the *same* IORegistry
    /// snapshot (`fetchFromIOPowerSources` only runs when that read fails
    /// outright). AppleSmartBattery genuinely reports `IsCharging = false` with
    /// `InstantAmperage` positive, which is how the panel came to read
    /// "not charging · +3.95 A". Do not "fix the synchronisation" — there is
    /// nothing out of sync.
    ///
    /// The charging half of the decision lives in
    /// `DashboardMetricSnapshot.isEffectivelyCharging` so the state line, the
    /// charging-power card, the time-to-full row and the charge-speed forecast
    /// are all the same verdict. Post-condition worth keeping true:
    /// `state == .charging` ⟺ `isEffectivelyCharging`.
    static func resolve(_ s: DashboardMetricSnapshot) -> BatteryPowerState {
        guard s.data.isOnAC else { return .discharging }
        let watts = s.batteryPowerWatts ?? 0
        if watts <= -DashboardMetricSnapshot.chargeDirectionDeadBandWatts { return .pluggedDischarging }
        if s.isEffectivelyCharging { return .charging }
        // Left over: inside the dead band with neither flag set, or holding full.
        return s.data.isFullyCharged ? .full : .pluggedIdle
    }
}
