import SwiftUI

struct BatteryGaugeView: View {
    let batteryData: BatteryData
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var animatedPercent: Double = 0
    @State private var glowPulse: Bool = false
    @State private var boltScale: CGFloat = 0.5

    var body: some View {
        ZStack {
            if batteryData.isCharging {
                Circle()
                    .fill(RadialGradient(
                        colors: [AppTheme.chargingBlue.opacity(glowPulse ? 0.3 : 0.08), .clear],
                        center: .center, startRadius: 50, endRadius: 170
                    ))
                    .frame(width: 340, height: 340)
                    .animation(reduceMotion ? nil : .easeInOut(duration: 2.0).repeatForever(autoreverses: true), value: glowPulse)
                    .onAppear { if !reduceMotion { glowPulse = true } }
            }

            Circle()
                .stroke(AppTheme.cardBorder, lineWidth: 20)
                .frame(width: 230, height: 230)

            Circle()
                .trim(from: 0, to: CGFloat(max(animatedPercent / 100.0, 0.001)))
                .stroke(
                    batteryData.isCharging ? AppTheme.chargingGradient : AppTheme.batteryGradient(percent: batteryData.percent),
                    style: StrokeStyle(lineWidth: 20, lineCap: .round)
                )
                .frame(width: 230, height: 230)
                .rotationEffect(.degrees(-90))
                .animation(.spring(response: 1.2, dampingFraction: 0.7), value: animatedPercent)

            Circle()
                .fill(AppTheme.gaugeBackgroundGradient)
                .frame(width: 186, height: 186)
                .shadow(color: .black.opacity(0.5), radius: 20)

            VStack(spacing: 2) {
                if batteryData.isCharging {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(AppTheme.chargingGradient)
                        .scaleEffect(boltScale)
                        .animation(reduceMotion ? nil : .spring(response: 0.6, dampingFraction: 0.7).repeatForever(autoreverses: true), value: boltScale)
                        .onAppear { boltScale = reduceMotion ? 1.0 : 1.12 }
                }

                Text("\(Int(animatedPercent))%")
                    .font(.system(size: 56, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .contentTransition(.numericText(value: animatedPercent))

                if batteryData.isCharging {
                    HStack(spacing: 4) {
                        Text(batteryData.timeRemaining)
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(AppTheme.chargingCyan)
                        Text(L("gauge.full"))
                            .font(.system(size: 11))
                            .foregroundStyle(AppTheme.textTertiary)
                    }
                } else if batteryData.isOnAC {
                    Text(L("gauge.ac"))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(AppTheme.textSecondary)
                } else {
                    Text(L("gauge.battery"))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(AppTheme.textSecondary)
                }

                HStack(spacing: 12) {
                    MiniMetric(icon: "bolt.fill", value: LNum("%.1fW", batteryData.currentPowerWatts), color: AppTheme.chargingBlue)
                    MiniMetric(icon: "thermometer.medium", value: LNum("%.0f°", batteryData.temperatureCelsius), color: tempColor)
                    // 数字与单位的拼接方式交给语言包决定（「210次」无空格，「210 Zyklen」有）
                    MiniMetric(icon: "arrow.triangle.2.circlepath", value: L("gauge.cycles_value", batteryData.cycleCount), color: AppTheme.textSecondary)
                }
                .padding(.top, 8)
            }

        }
        .onAppear { animatedPercent = Double(batteryData.percent) }
        .onChange(of: batteryData.percent) { _, newPercent in
            animatedPercent = Double(newPercent)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L("gauge.a11y_label"))
        .accessibilityValue("\(batteryData.percent)%, \(batteryData.isCharging ? L("gauge.a11y_charging") : L("gauge.a11y_battery"))")
    }

    private var tempColor: Color {
        if batteryData.temperatureCelsius > 40 { return AppTheme.batteryRed }
        if batteryData.temperatureCelsius > 35 { return AppTheme.batteryYellow }
        return AppTheme.batteryGreen
    }
}

struct MiniMetric: View {
    let icon: String
    let value: String
    let color: Color
    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(color)
            Text(value)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(AppTheme.textSecondary)
        }
    }
}

struct BatteryStatsGrid: View {
    let batteryData: BatteryData

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            StatCard(title: batteryData.isCharging ? L("stat.charge_power") : L("stat.discharge_power"),
                     value: LNum("%.1fW", batteryData.currentPowerWatts),
                     icon: "bolt.fill", color: batteryData.isCharging ? AppTheme.chargingBlue : AppTheme.textSecondary,
                     subtitle: batteryData.isCharging ? L("stat.realtime_charging") : (batteryData.isOnAC ? L("stat.not_charging") : L("stat.on_battery")),
                     tooltipKey: "tip.charge_power")
            StatCard(title: L("stat.adapter"), value: batteryData.isOnAC && batteryData.chargerWattage > 0 ? "\(batteryData.chargerWattage)W" : L("stat.not_connected"),
                     icon: "powerplug.fill", color: batteryData.isOnAC ? AppTheme.accentPurple : AppTheme.textSecondary,
                     subtitle: batteryData.isOnAC ? L("stat.usbc") : L("stat.unplugged"),
                     tooltipKey: "tip.adapter")
            StatCard(title: L("stat.temperature"), value: LNum("%.1f°C", batteryData.temperatureCelsius),
                     icon: "thermometer.medium", color: tempColor,
                     subtitle: batteryData.temperatureCelsius > 38 ? L("stat.temp_high") : L("stat.temp_normal"),
                     tooltipKey: "tip.temperature")
            StatCard(title: L("stat.cycles"), value: "\(batteryData.cycleCount)",
                     icon: "arrow.triangle.2.circlepath", color: AppTheme.textSecondary,
                     subtitle: cycleHealth,
                     tooltipKey: "tip.cycles")
            StatCard(title: L("stat.health"), value: "\(batteryData.maxCapacityPercent)%",
                     icon: "heart.fill", color: healthColor,
                     subtitle: batteryData.maxCapacityPercent >= 90 ? L("stat.health_excellent") : L("stat.health_good"),
                     tooltipKey: "tip.health")
            StatCard(title: L("stat.condition"), value: batteryData.condition.localizedDescription,
                     icon: "checkmark.shield.fill", color: batteryData.condition == .normal ? AppTheme.batteryGreen : AppTheme.batteryYellow,
                     subtitle: L("stat.system_check"),
                     tooltipKey: "tip.condition")
        }
    }

    private var tempColor: Color {
        if batteryData.temperatureCelsius > 40 { return AppTheme.batteryRed }
        if batteryData.temperatureCelsius > 35 { return AppTheme.batteryYellow }
        return AppTheme.batteryGreen
    }
    private var healthColor: Color {
        if batteryData.maxCapacityPercent >= 90 { return AppTheme.batteryGreen }
        if batteryData.maxCapacityPercent >= 80 { return AppTheme.batteryYellow }
        return AppTheme.batteryRed
    }
    private var cycleHealth: String {
        if batteryData.cycleCount < 300 { return L("stat.cycle_good") }
        if batteryData.cycleCount < 500 { return L("stat.cycle_aging") }
        return L("stat.cycle_check")
    }
}

struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    let subtitle: String
    var tooltipKey: String? = nil
    @State private var appeared = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(color)
                Text(title)
                    .font(.system(size: 11))
                    .foregroundStyle(AppTheme.textTertiary)
                    // 长语言（如日语「バッテリーコンディション」、德语复合词）会换行撑破卡片，
                    // 导致同排卡片高度不齐。与下方 value/subtitle 保持同样的收缩策略。
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                if let key = tooltipKey {
                    Image(systemName: "exclamationmark.circle")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(AppTheme.textTertiary.opacity(0.5))
                        .help(L(key))
                }
            }
            Text(value)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(subtitle)
                .font(.system(size: 10))
                .foregroundStyle(color.opacity(0.7))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AppTheme.Spacing.md)
        .modifier(AppTheme.card(radius: AppTheme.Radius.card))
        .scaleEffect(appeared ? 1 : 0.9)
        .opacity(appeared ? 1 : 0)
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) { appeared = true }
        }
    }
}
