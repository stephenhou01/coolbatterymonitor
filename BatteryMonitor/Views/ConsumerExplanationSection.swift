import SwiftUI

// MARK: - 6. Consumer explanations

struct ConsumerExplanationSection: View {
    let snapshot: DashboardMetricSnapshot

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 14) { explanationCards }
            VStack(spacing: 14) { explanationCards }
        }
    }

    @ViewBuilder
    private var explanationCards: some View {
        ExplanationCard(
            icon: "gauge.with.dots.needle.33percent",
            color: AppTheme.batteryRed,
            eyebrow: dashboardText("p.aging_judge_title", fallback: "判断电池是不是老化"),
            title: dashboardText("p.aging_judge_lead", fallback: "循环次数像里程表：说明用过多少，不单独决定健康"),
            message: dashboardText("p.aging_judge_body", fallback: "真正要一起看的是：充满容量是否持续下降、内阻是否上升、电芯是否开始不同步，以及高温是否变得常见。"),
            proof: dashboardText(
                "p.aging_proof",
                fallback: "这台电脑已完成 {cyc} 次循环；目前最大容量比设计少 {loss} mAh。平均每循环 {per} mAh 只用于回顾，不能线性预测寿命。",
                replacements: [
                    "cyc": snapshot.detail.cycleCount.formatted(),
                    "loss": snapshot.longTermCapacityGap.formatted(),
                    "per": LNum("%.1f mAh", snapshot.detail.chargeDeficitPerCycle ?? 0),
                ]
            )
        )

        ExplanationCard(
            icon: "arrow.up.arrow.down.circle",
            color: AppTheme.batteryYellow,
            eyebrow: dashboardText("p.time_jump_title", fallback: "剩余时间为什么会跳"),
            title: dashboardText("p.time_jump_lead", fallback: "开始编译时下降，停下来阅读时又上升，并不代表电量回来了"),
            message: dashboardText("p.time_jump_body", fallback: "macOS 会不断用最近的使用状态重估还能维持多久。功耗会影响估算，但本页在电池供电时只记录系统给出的答案，不另算一套。"),
            proof: dashboardText("p.time_jump_proof", fallback: "电池供电：记录 macOS 剩余时间。连接电源：显示“当前储能 ÷ 当前功率”，并明确标成拔电预计。")
        )
    }
}

private struct ExplanationCard: View {
    let icon: String
    let color: Color
    let eyebrow: String
    let title: String
    let message: String
    let proof: String

    var body: some View {
        HStack(alignment: .top, spacing: 17) {
            Image(systemName: icon)
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(color)
                .frame(width: 58, height: 58)
                .background(
                    RadialGradient(colors: [color.opacity(0.18), color.opacity(0.035)],
                                   center: .center, startRadius: 0, endRadius: 42)
                )
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(color.opacity(0.22)))

            VStack(alignment: .leading, spacing: 9) {
                Text(eyebrow.uppercased())
                    .font(.system(size: 8.5, weight: .semibold, design: .monospaced))
                    .tracking(0.9)
                    .foregroundStyle(color)
                Text(title)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(message)
                    .font(.system(size: 10.5))
                    .foregroundStyle(AppTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(3)
                Text(proof)
                    .font(.system(size: 9.5, design: .monospaced))
                    .foregroundStyle(AppTheme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(2)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 8).fill(color.opacity(0.035)))
                    .overlay(alignment: .leading) { Rectangle().fill(color).frame(width: 2) }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, minHeight: 235, alignment: .topLeading)
        .finalDashboardCard(accent: color)
    }
}
