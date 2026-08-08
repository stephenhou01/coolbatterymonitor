import SwiftUI

// MARK: - 2. Published benchmark x this Mac

struct RuntimeBenchmarkSection: View {
    let snapshot: DashboardMetricSnapshot
    let specification: BatteryModelSpecification
    @Binding var selectedHelp: MetricHelpContent?

    private var officialPower: Double { specification.designEnergyWh / specification.officialWebHours }
    private var sameLoadHours: Double {
        (snapshot.currentFullEnergyWh ?? specification.designEnergyWh) / officialPower
    }
    private var actualHours: Double {
        if !snapshot.data.isOnAC, let minutes = snapshot.data.timeRemainingMinutes { return Double(minutes) / 60 }
        return Double(snapshot.unplugEstimateMinutes ?? 0) / 60
    }
    private var powerRatio: Double { snapshot.currentPowerWatts / max(officialPower, 0.1) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            DashboardSectionHeader(
                icon: "scale.3d",
                title: dashboardText("p.runtime_audit_tag"),
                color: AppTheme.accentPurple,
                help: { DashboardHelp.officialBenchmark(snapshot, specification: specification) },
                selection: $selectedHelp,
                trailing: AnyView(
                    Link(destination: specification.sourceURL) {
                        Text("APPLE TECH SPECS ↗")
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundStyle(AppTheme.textTertiary)
                    }
                )
            )

            Text(dashboardText("p.runtime_audit_title"))
                .font(.system(size: 19, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.textPrimary)

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 16) {
                    benchmarkBody
                    verdict
                        .frame(width: 255)
                }
                VStack(spacing: 14) {
                    benchmarkBody
                    verdict
                }
            }

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 16) { methodNote; conditionNote }
                VStack(alignment: .leading, spacing: 9) { methodNote; conditionNote }
            }
        }
        .padding(22)
        .finalDashboardCard(accent: AppTheme.accentPurple)
    }

    private var benchmarkBody: some View {
        VStack(spacing: 12) {
            VStack(spacing: 10) {
                RuntimeAuditRow(
                    title: dashboardText("p.audit_official"),
                    note: LNum("%.1fWh · %.2fW · VIDEO %.0fh", specification.designEnergyWh, officialPower,
                               specification.officialVideoHours),
                    hours: specification.officialWebHours,
                    maximum: specification.officialWebHours,
                    color: AppTheme.accentPurple
                )
                RuntimeAuditRow(
                    title: dashboardText("p.audit_same_load"),
                    note: LNum("%.1fWh", snapshot.currentFullEnergyWh ?? 0),
                    hours: sameLoadHours,
                    maximum: specification.officialWebHours,
                    color: AppTheme.chargingCyan
                )
                deltaText(
                    dashboardText("p.audit_capacity_note"),
                    value: max(0, specification.officialWebHours - sameLoadHours),
                    color: AppTheme.chargingCyan
                )
                RuntimeAuditRow(
                    title: dashboardText("p.audit_actual"),
                    note: snapshot.data.isOnAC
                        ? LNum("%.1fWh ÷ %.1fW", snapshot.remainingEnergyWh ?? 0, snapshot.currentPowerWatts)
                        : dashboardText("p.direct_source"),
                    hours: actualHours,
                    maximum: specification.officialWebHours,
                    color: AppTheme.batteryYellow
                )
            }
            .padding(15)
            .background(RoundedRectangle(cornerRadius: 12).fill(AppTheme.surfaceSunken))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(AppTheme.contrastOverlay(0.055), lineWidth: 1))

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 9) { officialConfiguration; currentConfiguration }
                VStack(spacing: 9) { officialConfiguration; currentConfiguration }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var verdict: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(LNum("%.1f×", powerRatio))
                .font(.system(size: 40, weight: .light, design: .monospaced))
                .foregroundStyle(AppTheme.batteryYellow)
            Text(dashboardText("p.audit_cause"))
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(AppTheme.textPrimary)
            Text(
                dashboardText(
                    "p.audit_cause_body",
                    replacements: ["ratio": LNum("%.1f", powerRatio)]
                )
            )
                .font(.system(size: 10.5))
                .foregroundStyle(AppTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(3)
        }
        .padding(17)
        .frame(maxWidth: .infinity, minHeight: 175, alignment: .topLeading)
        .background(
            RadialGradient(colors: [AppTheme.batteryYellow.opacity(0.13), AppTheme.batteryYellow.opacity(0.025)],
                           center: .topTrailing, startRadius: 0, endRadius: 230)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(AppTheme.batteryYellow.opacity(0.18), lineWidth: 1))
    }

    private var officialConfiguration: some View {
        configurationTile(
            label: dashboardText("p.audit_test_config"),
            value: "M4 · \(specification.testCPUCoreCount)C CPU / \(specification.testGPUCoreCount)C GPU · \(specification.testMemoryGB)GB / \(specification.testStorageGB)GB"
        )
    }

    private var currentConfiguration: some View {
        let memoryGB = Int(ProcessInfo.processInfo.physicalMemory / 1_073_741_824)
        return configurationTile(
            label: dashboardText("p.audit_your_config"),
            value: "\(snapshot.detail.chipModel.isEmpty ? snapshot.modelIdentifier : snapshot.detail.chipModel) · \(ProcessInfo.processInfo.processorCount)C CPU · \(memoryGB)GB"
        )
    }

    private func configurationTile(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 8.5))
                .foregroundStyle(AppTheme.textTertiary)
            Text(value)
                .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                .foregroundStyle(AppTheme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 55, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 8).fill(AppTheme.contrastOverlay(0.018)))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(AppTheme.contrastOverlay(0.05)))
    }

    private func deltaText(_ format: String, value: Double, color: Color) -> some View {
        let number = LNum("%.1f", value)
        let rendered = format.contains("{hours}")
            ? format.replacingOccurrences(of: "{hours}", with: number)
            : String(format: format, locale: Locale(identifier: L10n.shared.effectiveCode), value)
        return Text("↳ " + rendered)
            .font(.system(size: 9))
            .foregroundStyle(color)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 178)
    }

    private var methodNote: some View {
        Text(dashboardText("p.audit_method"))
            .font(.system(size: 9))
            .foregroundStyle(AppTheme.textTertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
    private var conditionNote: some View {
        Text(dashboardText("p.audit_conditions"))
            .font(.system(size: 9))
            .foregroundStyle(AppTheme.textTertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct RuntimeAuditRow: View {
    let title: String
    let note: String
    let hours: Double
    let maximum: Double
    let color: Color

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 11) { label; bar; hoursLabel }
            VStack(alignment: .leading, spacing: 7) { label; HStack { bar; hoursLabel } }
        }
    }

    private var label: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(AppTheme.textPrimary)
            Text(note)
                .font(.system(size: 8, design: .monospaced))
                .foregroundStyle(AppTheme.textTertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(minWidth: 160, idealWidth: 190, alignment: .leading)
    }
    private var bar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 5).fill(AppTheme.contrastOverlay(0.04))
                RoundedRectangle(cornerRadius: 5)
                    .fill(LinearGradient(colors: [color.opacity(0.35), color], startPoint: .leading, endPoint: .trailing))
                    .frame(width: geo.size.width * CGFloat(min(1, max(0.03, hours / max(maximum, 0.1)))))
            }
        }
        .frame(minWidth: 120, maxWidth: .infinity, minHeight: 18, maxHeight: 18)
    }
    private var hoursLabel: some View {
        Text(LNum("%.1f h", hours))
            .font(.system(size: 14, weight: .medium, design: .monospaced))
            .foregroundStyle(AppTheme.textPrimary)
            .frame(width: 62, alignment: .trailing)
    }
}
