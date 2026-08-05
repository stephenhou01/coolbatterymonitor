import SwiftUI

struct MenuBarStatusLabel: View {
    let data: BatteryData
    let secondaryMetric: MenuBarMetric
    var chargeSpeed: ChargeSpeedEstimate? = nil

    private var presentation: MenuBarPresentation { .init(data: data, chargeSpeed: chargeSpeed) }

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
    var chargeSpeed: ChargeSpeedEstimate? = nil

    @Environment(MenuBarSettings.self) private var menuSettings

    private var presentation: MenuBarPresentation { .init(data: data, chargeSpeed: chargeSpeed) }

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
            }

            menuBarPreview

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

    /// Show the choice in the context where it is actually used. A full-width
    /// strip reads as the macOS menu bar, while the status item's text remains
    /// the exact same view and formatting used by `MenuBarExtra`.
    private var menuBarPreview: some View {
        HStack(spacing: compact ? 7 : 9) {
            Image(systemName: "apple.logo")
                .font(.system(size: compact ? 9.5 : 11, weight: .semibold))

            Spacer(minLength: 12)

            MenuBarStatusLabel(data: data,
                               secondaryMetric: menuSettings.secondaryMetric,
                               chargeSpeed: chargeSpeed)
                .font(.system(size: compact ? 9.5 : 11, weight: .medium))

            Divider()
                .frame(height: compact ? 12 : 14)

            Image(systemName: "wifi")
            Image(systemName: "switch.2")
        }
        .foregroundStyle(AppTheme.textPrimary)
        .padding(.horizontal, compact ? 9 : 11)
        .frame(maxWidth: .infinity, minHeight: compact ? 28 : 34)
        .background(
            RoundedRectangle(cornerRadius: compact ? 7 : 8, style: .continuous)
                .fill(AppTheme.surfaceRaised)
                .shadow(color: Color.black.opacity(0.10), radius: 5, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: compact ? 7 : 8, style: .continuous)
                .stroke(AppTheme.cardBorder, lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
    }

    private var metricPicker: some View {
        Menu {
            ForEach(MenuBarMetric.allCases) { metric in
                Button {
                    menuSettings.selectSecondaryMetric(metric)
                } label: {
                    if menuSettings.secondaryMetric == metric {
                        Label(presentation.choicePreviewText(for: metric), systemImage: "checkmark")
                    } else {
                        Label(presentation.choicePreviewText(for: metric), systemImage: metric.symbol)
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                MetricGlyph(menuSettings.secondaryMetric.icon,
                            tint: AppTheme.chargingBlue,
                            scale: .micro,
                            style: .plain)
                Text(presentation.choicePreviewText(for: menuSettings.secondaryMetric))
                    .font(.system(size: compact ? 8.5 : 9, weight: .semibold, design: .rounded))
                    .monospacedDigit()
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
