import SwiftUI
import Observation

@Observable
final class DashboardNavigation {
    static let shared = DashboardNavigation()

    var destination: DashboardDestination = .overview

    private init() {}
}

struct ContentView: View {
    @EnvironmentObject private var batteryService: BatteryService
    @EnvironmentObject private var processService: ProcessMonitorService
    @Environment(AppearanceSettings.self) private var appearance
    @State private var navigation = DashboardNavigation.shared
    @State private var selectedMetricHelp: MetricHelpContent?
    @State private var appeared = false

    var body: some View {
        ZStack(alignment: .trailing) {
            AppTheme.background.ignoresSafeArea()

            HStack(spacing: 0) {
                DashboardSidebar(selection: Binding(
                    get: { navigation.destination },
                    set: { navigation.destination = $0 }
                ))
                    .frame(width: 196)

                Rectangle()
                    .fill(AppTheme.divider)
                    .frame(width: 1)

                dashboardContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            if let selectedMetricHelp {
                MetricHelpDrawer(content: selectedMetricHelp) {
                    withAnimation(.easeOut(duration: 0.18)) { self.selectedMetricHelp = nil }
                }
                .zIndex(20)
            }
        }
        .onChange(of: processService.topProcesses) { _, processes in
            batteryService.updateProcesses(processes)
        }
        .background(AppearanceWindowBridge(mode: appearance.mode).frame(width: 0, height: 0))
        .opacity(appeared ? 1 : 0)
        .onAppear {
            withAnimation(.easeOut(duration: 0.32)) { appeared = true }
        }
        .animation(.easeOut(duration: 0.18), value: navigation.destination)
        .animation(.easeOut(duration: 0.18), value: selectedMetricHelp?.id)
    }

    @ViewBuilder
    private var dashboardContent: some View {
        switch navigation.destination {
        case .overview:
            DashboardOverviewPage(selectedHelp: $selectedMetricHelp)
        case .technical:
            DashboardTechnicalPage(selectedHelp: $selectedMetricHelp)
        case .trends:
            DashboardTrendsPage(selectedHelp: $selectedMetricHelp)
        case .diagnostics:
            DashboardDiagnosticsPage(selectedHelp: $selectedMetricHelp)
        case .settings:
            DashboardSettingsPage()
        }
    }
}
