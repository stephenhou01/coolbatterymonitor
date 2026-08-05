import SwiftUI

struct DashboardDiagnosticsPage: View {
    @EnvironmentObject private var batteryService: BatteryService
    @Binding var selectedHelp: MetricHelpContent?

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                DashboardPageHeader(
                    title: DashboardDestination.diagnostics.title,
                    subtitle: dashboardText("shell.diagnostics_subtitle", fallback: "先给结论，再展开证据")
                )
                if let insight = batteryService.insight {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                        HealthDiagnosisCard(diagnosis: insight.health)
                        ChargingHabitCard(habit: insight.habit)
                        AccessoryCard(accessory: insight.accessory)
                        PowerAnalysisCard(analysis: insight.power)
                    }
                    SystemAnomalySummaryCard(snapshot: batteryService.systemDataSnapshot,
                                             selectedHelp: $selectedHelp)
                } else {
                    VStack(spacing: 12) {
                        ProgressView().controlSize(.small)
                        Text(dashboardText("shell.diagnosing", fallback: "正在读取电池并生成诊断…"))
                            .font(.system(size: 12))
                            .foregroundStyle(AppTheme.textSecondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 260)
                    .modifier(AppTheme.card())
                }
            }
            .frame(maxWidth: 1060)
            .padding(28)
            .frame(maxWidth: .infinity)
        }
        .background(AppTheme.background)
    }
}

private struct SystemAnomalySummaryCard: View {
    @Environment(\.dashboardDataVersion) private var dataVersion
    let snapshot: SystemDataSnapshot
    @Binding var selectedHelp: MetricHelpContent?

    private var anomalies: [SystemFieldReading] {
        snapshot.fields.filter { $0.anomalyLevel > .none }.sorted { $0.anomalyLevel > $1.anomalyLevel }
    }

    var body: some View {
        // Filtered and sorted once: this was a computed property read four times
        // per redraw, so all 464 readings were scanned and sorted four times.
        let anomalies = self.anomalies
        return VStack(alignment: .leading, spacing: 13) {
            HStack {
                Image(systemName: anomalies.isEmpty ? "checkmark.shield.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(anomalies.isEmpty ? AppTheme.batteryGreen : AppTheme.batteryYellow)
                Text(dashboardText("shell.system_anomalies", fallback: "系统字段异常筛查"))
                    .font(AppTheme.Typography.sectionTitle)
                    .foregroundStyle(AppTheme.textPrimary)
                Spacer()
                Text("\(anomalies.count)")
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundStyle(anomalies.isEmpty ? AppTheme.batteryGreen : AppTheme.batteryYellow)
            }
            if anomalies.isEmpty {
                Text(dashboardText("p.system_no_anomaly", fallback: "本次快照没有命中已定义的异常规则"))
                    .font(.system(size: 11.5))
                    .foregroundStyle(AppTheme.textSecondary)
                    .padding(.vertical, 12)
            } else {
                ForEach(anomalies.prefix(8)) { field in
                    Button { selectedHelp = field.help } label: {
                        HStack(spacing: 10) {
                            Circle().fill(anomalyColor(field.anomalyLevel)).frame(width: 7, height: 7)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(field.metadata.path).font(.system(size: 11, weight: .medium, design: .monospaced))
                                Text(field.anomalyReason).font(.system(size: 9.5)).foregroundStyle(AppTheme.textTertiary).lineLimit(1)
                            }
                            Spacer()
                            Text(field.valueWithUnit).font(.system(size: 10.5, design: .monospaced))
                            Image(systemName: "questionmark.circle").foregroundStyle(AppTheme.textTertiary)
                        }
                        .foregroundStyle(AppTheme.textPrimary)
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 9).fill(AppTheme.contrastOverlay(0.025)))
                    }
                    .buttonStyle(.plain)
                    // Was `.onChange(of: field.help)`, which built a whole help
                    // sheet on every redraw just to use it as a comparison key.
                    // The row's identity is enough, and the sheet is now built
                    // only when this row's panel is the one on screen.
                    .onChange(of: dataVersion) { _, _ in
                        guard selectedHelp?.id == field.helpID else { return }
                        selectedHelp = field.help
                    }
                }
            }
        }
        .padding(AppTheme.Spacing.xl)
        .modifier(AppTheme.card())
    }

    private func anomalyColor(_ level: SystemFieldAnomalyLevel) -> Color {
        switch level {
        case .none: return AppTheme.textTertiary
        case .attention: return AppTheme.batteryYellow
        case .warning: return AppTheme.batteryOrange
        case .critical: return AppTheme.batteryRed
        }
    }
}
