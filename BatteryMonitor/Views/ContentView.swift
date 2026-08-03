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
                    // Scoped to the content area on purpose. On the whole ZStack
                    // this animated the sidebar, the divider and the drawer too,
                    // which meant both page trees stayed alive and were laid out
                    // every frame for 0.18 s — the single biggest cost of a tab
                    // switch on the heavier pages.
                    .animation(.easeOut(duration: 0.18), value: navigation.destination)
            }

            if let selectedMetricHelp {
                MetricHelpDrawer(content: selectedMetricHelp) {
                    withAnimation(.easeOut(duration: 0.18)) { self.selectedMetricHelp = nil }
                }
                .zIndex(20)
                .animation(.easeOut(duration: 0.18), value: selectedMetricHelp.id)
            }
        }
        // One cheap signal every help button can watch, so only the open panel
        // rebuilds itself on a poll.
        .environment(\.dashboardDataVersion, batteryService.batteryData.lastUpdated)
        .onChange(of: processService.topProcesses) { _, processes in
            batteryService.updateProcesses(processes)
        }
        .background(AppearanceWindowBridge(mode: appearance.mode).frame(width: 0, height: 0))
        .opacity(appeared ? 1 : 0)
        .onAppear {
            withAnimation(.easeOut(duration: 0.32)) { appeared = true }
        }
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
