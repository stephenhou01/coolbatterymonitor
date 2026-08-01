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

    var menuBarText: String {
        guard runtimeMinutes != nil else { return percentText }
        if isForecast {
            let prefix = dashboardText("p.menu_unplug_short", fallback: "拔电约")
            return "\(percentText) (\(prefix) \(runtimeText))"
        }
        return "\(percentText) (\(runtimeText))"
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

    static func durationText(_ minutes: Int?) -> String {
        guard let minutes, minutes > 0 else { return "—" }
        return String(format: "%dh %02dm", minutes / 60, minutes % 60)
    }
}

struct MenuBarStatusLabel: View {
    let data: BatteryData

    private var presentation: MenuBarPresentation { .init(data: data) }

    var body: some View {
        HStack(spacing: 5) {
            MenuBarBatteryGlyph(percent: data.percent, isCharging: data.isCharging || data.isOnAC)
            Text(presentation.menuBarText)
                .monospacedDigit()
        }
        .accessibilityLabel("\(presentation.percentText), \(presentation.timeTitle) \(presentation.runtimeText)")
    }
}

private struct MenuBarBatteryGlyph: View {
    let percent: Int
    let isCharging: Bool

    private var fraction: CGFloat {
        CGFloat(max(0, min(100, percent))) / 100
    }

    var body: some View {
        HStack(spacing: 1) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2.2, style: .continuous)
                    .stroke(.primary, lineWidth: 1.25)
                GeometryReader { geometry in
                    RoundedRectangle(cornerRadius: 1.2, style: .continuous)
                        .fill(.primary)
                        .frame(width: max(1, (geometry.size.width - 3) * fraction))
                        .padding(1.5)
                }
                if isCharging {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 5.5, weight: .black))
                        .foregroundStyle(.background)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(width: 19, height: 10)

            Capsule().fill(.primary).frame(width: 1.8, height: 4.5)
        }
        .frame(width: 22, height: 12)
        .accessibilityHidden(true)
    }
}

struct MenuBarDashboardView: View {
    @EnvironmentObject private var batteryService: BatteryService
    @EnvironmentObject private var processService: ProcessMonitorService
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismiss) private var dismiss

    private var data: BatteryData { batteryService.batteryData }
    private var presentation: MenuBarPresentation { .init(data: data) }

    var body: some View {
        ZStack {
            AppTheme.background
            LinearGradient(
                colors: [AppTheme.chargingCyan.opacity(0.07), .clear],
                startPoint: .topLeading,
                endPoint: .center
            )

            VStack(spacing: 0) {
                header
                Divider().overlay(AppTheme.cardBorder)
                meters
                values
                footer
            }
            .padding(16)
        }
        .frame(width: 380)
        .fixedSize(horizontal: true, vertical: true)
    }

    private var header: some View {
        HStack(spacing: 11) {
            ZStack {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(AppTheme.chargingCyan.opacity(0.09))
                    .overlay(
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .stroke(AppTheme.chargingCyan.opacity(0.28), lineWidth: 1)
                    )
                Image(systemName: "battery.100")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(AppTheme.chargingCyan)
            }
            .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 3) {
                Text("BatteryMonitor")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.textPrimary)
                Text(presentation.sourceText)
                    .font(.system(size: 9.5))
                    .foregroundStyle(AppTheme.textTertiary)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            Button(action: dismiss.callAsFunction) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(Color.white.opacity(0.05)))
            }
            .buttonStyle(.plain)
            .foregroundStyle(AppTheme.textTertiary)
            .help(dashboardText("p.menu_close", fallback: "关闭菜单栏面板"))
            .pointerOnHover()
        }
        .padding(.bottom, 14)
    }

    private var meters: some View {
        VStack(spacing: 14) {
            meter(
                title: dashboardText("p.system_charge", fallback: "macOS 电量"),
                value: presentation.percentText,
                fraction: presentation.chargeFraction,
                colors: [AppTheme.batteryGreen, AppTheme.chargingCyan]
            )
            meter(
                title: dashboardText("p.priority_health", fallback: "整块电池的健康状况"),
                value: presentation.healthText,
                fraction: presentation.healthPercent / 100,
                colors: [AppTheme.chargingBlue, AppTheme.chargingCyan]
            )
        }
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
                    Capsule().fill(Color.white.opacity(0.07))
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
            valueRow(presentation.timeTitle, presentation.runtimeText,
                     valueColor: AppTheme.chargingCyan, prominent: true)
            valueRow(dashboardText("p.priority_power", fallback: "目前电脑的使用功率"),
                     presentation.powerText)
            valueRow(L("stat.cycles"), data.cycleCount.formatted())
            valueRow(dashboardText("p.priority_temp", fallback: "目前电池温度"),
                     presentation.temperatureText)
        }
        .overlay(alignment: .top) { Divider().overlay(AppTheme.cardBorder) }
    }

    private func valueRow(
        _ title: String,
        _ value: String,
        valueColor: Color = AppTheme.textPrimary,
        prominent: Bool = false
    ) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 11))
                .foregroundStyle(AppTheme.textSecondary)
            Spacer(minLength: 20)
            Text(value)
                .font(.system(size: prominent ? 16 : 12,
                              weight: prominent ? .semibold : .medium,
                              design: .monospaced))
                .foregroundStyle(valueColor)
                .monospacedDigit()
        }
        .frame(minHeight: 40)
        .overlay(alignment: .bottom) { Divider().overlay(AppTheme.cardBorder) }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            settingsMenu

            Button(action: showDashboard) {
                HStack(spacing: 7) {
                    Image(systemName: "waveform.path.ecg")
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
        }
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

            Divider()
            languageMenu
            Divider()

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Label(dashboardText("p.menu_quit", fallback: "退出 BatteryMonitor"),
                      systemImage: "power")
            }
        } label: {
            Image(systemName: "gearshape.fill")
                .font(.system(size: 13))
                .foregroundStyle(AppTheme.textSecondary)
                .frame(width: 36, height: 34)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Color.white.opacity(0.035))
                        .overlay(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .stroke(AppTheme.cardBorder, lineWidth: 1)
                        )
                )
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .tint(AppTheme.textSecondary)
        .fixedSize()
        .help(dashboardText("p.menu_settings", fallback: "设置"))
        .pointerOnHover()
    }

    private var languageMenu: some View {
        let localization = L10n.shared
        return Menu {
            Button {
                localization.select(nil)
            } label: {
                if localization.isFollowingSystem {
                    Label(L("lang.system"), systemImage: "checkmark")
                } else {
                    Text(L("lang.system"))
                }
            }
            Divider()
            ForEach(localization.languages, id: \.code) { language in
                Button {
                    localization.select(language.code)
                } label: {
                    if !localization.isFollowingSystem,
                       localization.effectiveCode == language.code {
                        Label(language.name, systemImage: "checkmark")
                    } else {
                        Text(language.name)
                    }
                }
            }
        } label: {
            Label(dashboardText("p.menu_language", fallback: "语言"), systemImage: "globe")
        }
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
}
