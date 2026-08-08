import SwiftUI

struct DashboardSettingsPage: View {
    @EnvironmentObject private var batteryService: BatteryService
    @EnvironmentObject private var processService: ProcessMonitorService
    @Environment(MenuBarSettings.self) private var menuSettings

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                DashboardPageHeader(
                    title: DashboardDestination.settings.title,
                    subtitle: dashboardText("shell.settings_subtitle")
                )
                settingsCard(icon: "circle.lefthalf.filled", title: dashboardText("shell.appearance")) {
                    AppearanceModePicker(showLabels: true)
                }
                settingsCard(icon: "globe", title: dashboardText("p.menu_language")) {
                    LanguageSelectionMenu(fullWidth: true)
                        .frame(width: 230)
                }
                menuBarMetricSettingsCard
                settingsCard(icon: "arrow.triangle.2.circlepath", title: dashboardText("shell.live_refresh")) {
                    Toggle(isOn: Binding(
                        get: { batteryService.isLiveRefreshEnabled },
                        set: { setLiveRefresh($0) }
                    )) {
                        Text(batteryService.isLiveRefreshEnabled
                             ? dashboardText("p.live_10s")
                             : dashboardText("p.live_paused"))
                    }
                    .toggleStyle(.switch)
                    .font(.system(size: 11))
                }
                HStack(spacing: 8) {
                    Image(systemName: "lock.shield")
                    Text(dashboardText("shell.privacy_note"))
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
            MenuBarTopStatusConfigurationView(data: batteryService.batteryData,
                                              chargeSpeed: batteryService.chargeSpeed)

            Divider().overlay(AppTheme.cardBorder)

            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 11).fill(AppTheme.batteryGreen.opacity(0.10))
                    Image(systemName: "menubar.rectangle").foregroundStyle(AppTheme.batteryGreen)
                }
                .frame(width: 42, height: 42)
                VStack(alignment: .leading, spacing: 3) {
                    Text(dashboardText("menu.config.title"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(AppTheme.textPrimary)
                    Text(dashboardText("menu.config.manage_in_dashboard"))
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
                Text(dashboardText("shell.dynamic_trends"))
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
        case .chargingPower: return AppTheme.batteryGreen
        case .chargeSpeed: return AppTheme.chargingCyan
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
