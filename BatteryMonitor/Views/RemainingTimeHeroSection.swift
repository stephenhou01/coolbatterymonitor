import SwiftUI

// MARK: - 1. Runtime hero

struct RemainingTimeHeroSection: View {
    let snapshot: DashboardMetricSnapshot
    @Binding var selectedHelp: MetricHelpContent?

    var body: some View {
        VStack(alignment: .leading, spacing: 17) {
            DashboardSectionHeader(
                icon: BatteryMetricIcon.runtime.symbol,
                title: dashboardText("p.remaining", fallback: "还能用多久"),
                color: AppTheme.chargingCyan,
                help: { DashboardHelp.runtime(snapshot) },
                selection: $selectedHelp
            )

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 18) {
                    runtimePrimary
                        .frame(minWidth: 335, idealWidth: 390, maxWidth: 430)
                    priorityGrid(columns: 3)
                }
                VStack(spacing: 14) {
                    runtimePrimary
                    priorityGrid(columns: 1)
                }
            }
        }
        .padding(22)
        .finalDashboardCard(accent: AppTheme.chargingCyan)
    }

    private var runtimePrimary: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(snapshot.data.isOnAC
                         ? dashboardText("p.unplug_kicker", fallback: "按当前电脑状态，拔掉电源后大约还能用")
                         : dashboardText("p.src_note", fallback: "macOS 直接给出的系统估算"))
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(AppTheme.textSecondary)
                    if snapshot.data.isOnAC {
                        Text(dashboardText("p.unplug_badge", fallback: "拔电预计"))
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundStyle(AppTheme.batteryYellow)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(RoundedRectangle(cornerRadius: 5).fill(AppTheme.batteryYellow.opacity(0.09)))
                            .overlay(RoundedRectangle(cornerRadius: 5).stroke(AppTheme.batteryYellow.opacity(0.35)))
                    }
                }
                Spacer()
                MetricHelpButton(content: DashboardHelp.runtime(snapshot), selection: $selectedHelp)
            }

            runtimeNumber

            Text(snapshot.data.isOnAC
                 ? dashboardText("p.unplug_note", fallback: "预计值 · 按当前功耗估算拔电后的可用时间")
                 : dashboardText("p.usage_basis", fallback: "由 macOS 报告，不按功率重新计算"))
                .font(.system(size: 10.5))
                .foregroundStyle(AppTheme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)

            Divider().overlay(AppTheme.contrastOverlay(0.06))

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text("\(snapshot.data.percent)%")
                        .font(.system(size: 24, weight: .semibold, design: .monospaced))
                        .foregroundStyle(AppTheme.textPrimary)
                    Text(dashboardText("p.system_charge", fallback: "macOS 电量"))
                        .font(.system(size: 10.5))
                        .foregroundStyle(AppTheme.textTertiary)
                    MetricHelpButton(content: DashboardHelp.stateOfCharge(snapshot), selection: $selectedHelp)
                    Spacer()
                    Text(snapshot.data.isOnAC ? L("gauge.ac") : L("gauge.battery"))
                        .font(.system(size: 10.5))
                        .foregroundStyle(AppTheme.textSecondary)
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(AppTheme.contrastOverlay(0.06))
                        Capsule()
                            .fill(AppTheme.chargingGradient)
                            .frame(width: geo.size.width * CGFloat(min(max(snapshot.data.percent, 0), 100)) / 100)
                    }
                }
                .frame(height: 8)
                .accessibilityHidden(true)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, minHeight: 218, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(AppTheme.chargingCyan.opacity(0.025))
        )
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(AppTheme.chargingCyan.opacity(0.15), lineWidth: 1))
    }

    @ViewBuilder
    private var runtimeNumber: some View {
        if let minutes = snapshot.displayedRuntimeMinutes, minutes > 0 {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(minutes / 60)")
                    .font(.system(size: 60, weight: .light, design: .monospaced))
                    .foregroundStyle(AppTheme.chargingCyan)
                    .contentTransition(.numericText())
                Text("h")
                    .font(.system(size: 15, weight: .medium, design: .monospaced))
                    .foregroundStyle(AppTheme.textTertiary)
                Text(String(format: "%02d", minutes % 60))
                    .font(.system(size: 60, weight: .light, design: .monospaced))
                    .foregroundStyle(AppTheme.chargingCyan)
                    .contentTransition(.numericText())
                Text("m")
                    .font(.system(size: 15, weight: .medium, design: .monospaced))
                    .foregroundStyle(AppTheme.textTertiary)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.68)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(dashboardText(
                "p.duration_accessibility",
                fallback: "{hours} 小时 {minutes} 分钟",
                replacements: ["hours": "\(minutes / 60)", "minutes": "\(minutes % 60)"]
            ))
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Text("—")
                    .font(.system(size: 60, weight: .light, design: .monospaced))
                    .foregroundStyle(AppTheme.chargingCyan)
                Text(L("calculating"))
                    .font(.system(size: 11))
                    .foregroundStyle(AppTheme.textTertiary)
            }
        }
    }

    private func priorityGrid(columns: Int) -> some View {
        let gridItems = Array(repeating: GridItem(.flexible(), spacing: 10), count: columns)
        return LazyVGrid(columns: gridItems, alignment: .leading, spacing: 10) {
            PriorityMetricCard(
                icon: .health,
                title: dashboardText("p.priority_health", fallback: "整块电池的健康状况"),
                value: LNum("%.0f", snapshot.healthPercent), unit: "%",
                status: snapshot.healthPercent >= 90 ? L("stat.health_excellent") : L("stat.health_good"),
                range: "80–100%",
                history: dashboardText("p.history_learning", fallback: "历史范围正在积累"),
                lowImpact: dashboardText("p.health_low_short", fallback: "低于 80% 可能提示检修，续航缩短"),
                highImpact: dashboardText("p.health_high_short", fallback: "续航更接近新机"),
                color: AppTheme.batteryYellow,
                help: { DashboardHelp.health(snapshot) },
                selection: $selectedHelp
            )
            PriorityMetricCard(
                icon: .power,
                title: dashboardText("p.priority_power", fallback: "当前电脑的使用功率"),
                value: LNum("%.1f", snapshot.currentPowerWatts), unit: "W",
                status: LNum("%.0f%% %@", snapshot.currentPowerWatts / max(snapshot.usualPowerWatts, 0.1) * 100,
                             dashboardText("p.p_ratio", fallback: "相对平时")),
                range: LNum("%.1f–%.1fW", snapshot.usualPowerWatts * 0.85, snapshot.usualPowerWatts * 1.3),
                history: LNum("%@ %.1fW", dashboardText("p.history_peak", fallback: "本次监控峰值"), snapshot.peakPowerWatts),
                lowImpact: dashboardText("p.power_low_short", fallback: "续航更长，发热更少"),
                highImpact: dashboardText("p.power_high_short", fallback: "续航更短，发热增加"),
                color: AppTheme.chargingBlue,
                help: { DashboardHelp.power(snapshot) },
                selection: $selectedHelp
            )
            PriorityMetricCard(
                icon: .temperature,
                title: dashboardText("p.priority_temp", fallback: "当前电池温度"),
                value: LNum("%.1f", snapshot.data.temperatureCelsius), unit: "°C",
                status: snapshot.data.temperatureCelsius < 35 ? L("stat.temp_normal") : L("stat.temp_high"),
                range: "15–35°C",
                history: snapshot.temperatureHistoryText,
                lowImpact: dashboardText("p.temp_low_short", fallback: "续航和功率会暂时下降"),
                highImpact: dashboardText("p.temp_high_short", fallback: "发热增加并加速老化"),
                color: snapshot.data.temperatureCelsius < 35 ? AppTheme.chargingCyan : AppTheme.batteryYellow,
                help: { DashboardHelp.temperature(snapshot) },
                selection: $selectedHelp
            )
        }
    }
}

private struct PriorityMetricCard: View {
    let icon: BatteryMetricIcon
    let title: String
    let value: String
    let unit: String
    let status: String
    let range: String
    let history: String
    let lowImpact: String
    let highImpact: String
    let color: Color
    /// Lazy so the sheet is built on tap, not on every redraw of the card.
    let help: () -> MetricHelpContent
    @Binding var selection: MetricHelpContent?

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 6) {
                MetricGlyph(icon, tint: color, scale: .compact)
                Text(title)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(AppTheme.textTertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                Spacer(minLength: 2)
                MetricHelpButton(content: help(), selection: $selection)
            }

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(.system(size: 23, weight: .semibold, design: .monospaced))
                    .foregroundStyle(AppTheme.textPrimary)
                    .contentTransition(.numericText())
                Text(unit)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(AppTheme.textTertiary)
            }
            Text(status)
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.72)

            Divider().overlay(AppTheme.contrastOverlay(0.055))

            HStack(alignment: .firstTextBaseline) {
                Text(dashboardText("p.good_range", fallback: "合理范围"))
                    .font(.system(size: 8.5))
                    .foregroundStyle(AppTheme.textTertiary)
                Spacer()
                Text(range)
                    .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(AppTheme.chargingCyan)
            }
            Text(history)
                .font(.system(size: 8.5))
                .foregroundStyle(AppTheme.textTertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            HStack(alignment: .top, spacing: 5) {
                impact(text: lowImpact, arrow: "arrow.down", tint: AppTheme.chargingBlue)
                impact(text: highImpact, arrow: "arrow.up", tint: AppTheme.batteryYellow)
            }
        }
        .padding(13)
        .frame(maxWidth: .infinity, minHeight: 205, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 12).fill(AppTheme.contrastOverlay(0.022)))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(AppTheme.contrastOverlay(0.06), lineWidth: 1))
    }

    private func impact(text: String, arrow: String, tint: Color) -> some View {
        HStack(alignment: .top, spacing: 3) {
            Image(systemName: arrow)
                .font(.system(size: 7, weight: .bold))
                .foregroundStyle(tint)
                .padding(.top, 2)
            Text(text)
                .font(.system(size: 8))
                .foregroundStyle(AppTheme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(6)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 7).fill(AppTheme.contrastOverlay(0.018)))
    }
}
