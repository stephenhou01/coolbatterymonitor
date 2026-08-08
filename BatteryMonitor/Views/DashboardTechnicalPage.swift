import SwiftUI

struct DashboardTechnicalPage: View {
    @EnvironmentObject private var batteryService: BatteryService
    @Binding var selectedHelp: MetricHelpContent?

    var body: some View {
        ScrollView {
            // Lazy on purpose: this page stacks nine heavy sections, and a plain
            // VStack builds every one of them — both charts, the 464-row
            // workbench, all the ViewThatFits candidates — before the first
            // screenful can be shown. The direct child of the ScrollView has to
            // be the lazy one for the sections below to inherit the viewport.
            LazyVStack(spacing: 20) {
                DashboardPageHeader(
                    title: DashboardDestination.technical.title,
                    subtitle: dashboardText("shell.technical_subtitle")
                )
                FinalDashboardView(
                    batteryData: batteryService.batteryData,
                    realtimeData: batteryService.realtimeData,
                    persistedRuntimeSamples: batteryService.runtimeSamples,
                    selectedHelp: $selectedHelp
                )
            }
            .frame(maxWidth: 1240)
            .padding(28)
            .frame(maxWidth: .infinity)
        }
        .background(AppTheme.background)
    }
}
