import SwiftUI

struct ContentView: View {
    @EnvironmentObject var batteryService: BatteryService
    @EnvironmentObject var processService: ProcessMonitorService
    @State private var appeared = false

    var body: some View {
        ZStack {
            AppTheme.background.ignoresSafeArea()

            LinearGradient(
                colors: [AppTheme.accentPurple.opacity(0.04), .clear, AppTheme.chargingBlue.opacity(0.03)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            ).ignoresSafeArea()

            // 赛博氛围层：动态网格 + 呼吸光晕
            AppTheme.GridBackground().ignoresSafeArea()
            AppTheme.AmbientOrb(color: AppTheme.chargingCyan, diameter: 520)
                .offset(x: -260, y: -200).ignoresSafeArea()
            AppTheme.AmbientOrb(color: AppTheme.accentPurple, diameter: 460)
                .offset(x: 300, y: 160).ignoresSafeArea()

            ScrollView {
                VStack(spacing: AppTheme.Spacing.xl) {
                    headerView

                    HStack(alignment: .top, spacing: AppTheme.Spacing.xl) {
                        // Left column
                        VStack(spacing: AppTheme.Spacing.xl) {
                            VStack(spacing: AppTheme.Spacing.lg) {
                                BatteryGaugeView(batteryData: batteryService.batteryData)
                                    .frame(height: 280)

                                powerStatusTip
                                    .transition(.opacity.combined(with: .scale))
                            }
                            .padding(AppTheme.Spacing.xxl)
                            .modifier(AppTheme.card())

                            BatteryStatsGrid(batteryData: batteryService.batteryData)
                        }
                        .frame(maxWidth: 440)

                        // Right column
                        VStack(spacing: AppTheme.Spacing.xl) {
                            RealtimeMonitorView(
                                dataPoints: batteryService.realtimeData,
                                batteryData: batteryService.batteryData
                            )

                            HistoryChartView(
                                sessions: batteryService.chargingHistory,
                                isLoading: batteryService.isLoadingHistory,
                                onRefresh: { batteryService.refreshHistory() }
                            )

                            ProcessListView(
                                processes: processService.topProcesses,
                                hasSampled: processService.hasSampled,
                                onRefresh: { processService.fetchProcesses() }
                            )
                        }
                    }

                    // ── 消费者洞察层（追加在现有布局下方，上面部分不动）
                    if let insight = batteryService.insight {
                        HealthDiagnosisCard(diagnosis: insight.health)
                            .modifier(AppTheme.reveal(0.05))

                        HStack(alignment: .top, spacing: AppTheme.Spacing.xl) {
                            ChargingHabitCard(habit: insight.habit)
                            AccessoryCard(accessory: insight.accessory)
                        }
                        .fixedSize(horizontal: false, vertical: true)
                        .modifier(AppTheme.reveal(0.12))

                        PowerAnalysisCard(analysis: insight.power)
                            .modifier(AppTheme.reveal(0.19))

                        WeeklyReportCard(report: insight.weekly)
                            .modifier(AppTheme.reveal(0.26))

                        HardwareDetailView(detail: batteryService.batteryData.hardwareDetail)
                            .modifier(AppTheme.reveal(0.33))
                    }
                }
                .padding(AppTheme.Spacing.xxl)
            }
        }
        // 进程列表变化时刷新耗电分析（洞察平时 30s 一次，进程变化快需要单独触发）
        .onChange(of: processService.topProcesses) { _, procs in
            batteryService.updateProcesses(procs)
        }
        .opacity(appeared ? 1 : 0)
        .onAppear {
            withAnimation(.easeOut(duration: 0.6)) { appeared = true }
        }
    }

    @ViewBuilder
    private var powerStatusTip: some View {
        let d = batteryService.batteryData
        HStack(spacing: AppTheme.Spacing.sm) {
            if d.isCharging {
                Image(systemName: "bolt.fill").foregroundStyle(AppTheme.chargingCyan)
                Text(L("status.charging", d.currentPowerWatts, d.chargerWattage))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(AppTheme.textSecondary)
            } else if d.isOnAC {
                Image(systemName: "powerplug.fill").foregroundStyle(AppTheme.batteryGreen)
                Text(d.isFullyCharged ? L("status.ac_full") : L("status.ac_not_charging"))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(AppTheme.textSecondary)
            } else {
                Image(systemName: "battery.75").foregroundStyle(AppTheme.batteryYellow)
                Text(L("status.discharging", d.currentPowerWatts))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(AppTheme.textSecondary)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }

    /// 语言切换器。默认跟随系统，「跟随系统」始终留在首位，让默认状态可回退。
    /// 语言名用各自母语（endonym），由语言包的 _meta.name 提供。
    private var languagePicker: some View {
        let l10n = L10n.shared
        return Menu {
            Button {
                l10n.select(nil)
            } label: {
                if l10n.isFollowingSystem {
                    Label(L("lang.system"), systemImage: "checkmark")
                } else {
                    Text(L("lang.system"))
                }
            }
            Divider()
            ForEach(l10n.languages, id: \.code) { meta in
                Button {
                    l10n.select(meta.code)
                } label: {
                    if !l10n.isFollowingSystem && l10n.effectiveCode == meta.code {
                        Label(meta.name, systemImage: "checkmark")
                    } else {
                        Text(meta.name)
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "globe")
                    .font(.system(size: 11, weight: .semibold))
                Text(l10n.currentName)
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(AppTheme.chargingCyan)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(AppTheme.chargingCyan.opacity(0.1)))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .pointerOnHover()
    }

    private var headerView: some View {
        HStack {
            HStack(spacing: 10) {
                Image(systemName: "battery.100.bolt")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(AppTheme.chargingGradient)
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("app.title"))
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(AppTheme.textPrimary)
                    Text(batteryService.batteryData.batteryModel.isEmpty
                         ? L("app.subtitle")
                         : L("app.subtitle.model", batteryService.batteryData.batteryModel))
                        .font(.system(size: 12))
                        .foregroundStyle(AppTheme.textTertiary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }

            languagePicker

            Spacer()

            HStack(spacing: 6) {
                Circle()
                    .fill(AppTheme.batteryGreen)
                    .frame(width: 8, height: 8)
                    .opacity(0.9)
                Text(L("app.live"))
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(AppTheme.batteryGreen)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(AppTheme.batteryGreen.opacity(0.1))
                    .overlay(Capsule().stroke(AppTheme.batteryGreen.opacity(0.3), lineWidth: 1))
            )
        }
    }
}
