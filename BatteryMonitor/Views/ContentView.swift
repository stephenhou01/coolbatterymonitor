import SwiftUI

struct ContentView: View {
    @EnvironmentObject var batteryService: BatteryService
    @EnvironmentObject var processService: ProcessMonitorService
    @State private var appeared = false
    @State private var selectedMetricHelp: MetricHelpContent?

    var body: some View {
        ZStack(alignment: .trailing) {
            AppTheme.background.ignoresSafeArea()

            LinearGradient(
                colors: [AppTheme.accentPurple.opacity(0.04), .clear, AppTheme.chargingBlue.opacity(0.03)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            ).ignoresSafeArea()

            // 赛博氛围层：静态网格 + 柔光；常驻工具不为装饰维持持续动画。
            AppTheme.GridBackground().ignoresSafeArea()
            AppTheme.AmbientOrb(color: AppTheme.chargingCyan, diameter: 520)
                .offset(x: -260, y: -200).ignoresSafeArea()
            AppTheme.AmbientOrb(color: AppTheme.accentPurple, diameter: 460)
                .offset(x: 300, y: 160).ignoresSafeArea()

            ScrollView {
                VStack(spacing: AppTheme.Spacing.xl) {
                    headerView

                    FinalDashboardView(
                        batteryData: batteryService.batteryData,
                        realtimeData: batteryService.realtimeData,
                        persistedRuntimeSamples: batteryService.runtimeSamples,
                        selectedHelp: $selectedMetricHelp
                    )

                }
                .frame(maxWidth: 1240)
                .padding(AppTheme.Spacing.xxl)
                .frame(maxWidth: .infinity)
            }

            if let selectedMetricHelp {
                MetricHelpDrawer(content: selectedMetricHelp) {
                    withAnimation(.easeOut(duration: 0.18)) { self.selectedMetricHelp = nil }
                }
                .zIndex(20)
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
        .animation(.easeOut(duration: 0.2), value: selectedMetricHelp?.id)
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
                    .fill(batteryService.isLiveRefreshEnabled ? AppTheme.batteryGreen : AppTheme.textTertiary)
                    .frame(width: 8, height: 8)
                    .opacity(0.9)
                Text(batteryService.isLiveRefreshEnabled
                     ? L("app.live")
                     : dashboardText("p.live_paused", fallback: "已暂停"))
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(batteryService.isLiveRefreshEnabled ? AppTheme.batteryGreen : AppTheme.textTertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill((batteryService.isLiveRefreshEnabled ? AppTheme.batteryGreen : AppTheme.textTertiary).opacity(0.1))
                    .overlay(Capsule().stroke((batteryService.isLiveRefreshEnabled ? AppTheme.batteryGreen : AppTheme.textTertiary).opacity(0.3), lineWidth: 1))
            )
        }
    }
}
