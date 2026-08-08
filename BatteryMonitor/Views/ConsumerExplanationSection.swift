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
            eyebrow: dashboardText("p.aging_judge_title"),
            title: dashboardText("p.aging_judge_lead"),
            message: dashboardText("p.aging_judge_body"),
            proof: dashboardText(
                "p.aging_proof",
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
            eyebrow: dashboardText("p.time_jump_title"),
            title: dashboardText("p.time_jump_lead"),
            message: dashboardText("p.time_jump_body"),
            proof: dashboardText("p.time_jump_proof")
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
