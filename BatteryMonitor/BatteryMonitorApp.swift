import SwiftUI

@main
struct BatteryMonitorApp: App {
    @StateObject private var batteryService = BatteryService()
    @StateObject private var processService = ProcessMonitorService()
    @State private var appearance = AppearanceSettings.shared
    @State private var menuBarSettings = MenuBarSettings.shared
    @State private var didStartMonitoring = false

    var body: some Scene {
        Window("Battery Monitor", id: "dashboard") {
            ContentView()
                .environmentObject(batteryService)
                .environmentObject(processService)
                .environment(appearance)
                .environment(menuBarSettings)
                .preferredColorScheme(appearance.mode.colorScheme)
                .frame(minWidth: 900, minHeight: 680)
                .onAppear(perform: startMonitoringIfNeeded)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1240, height: 860)

        MenuBarExtra {
            MenuBarDashboardView()
                .environmentObject(batteryService)
                .environmentObject(processService)
                .environment(appearance)
                .environment(menuBarSettings)
                .preferredColorScheme(appearance.mode.colorScheme)
                .onAppear(perform: startMonitoringIfNeeded)
        } label: {
            MenuBarStatusLabel(data: batteryService.batteryData,
                               secondaryMetric: menuBarSettings.secondaryMetric)
                .onAppear(perform: startMonitoringIfNeeded)
        }
        .menuBarExtraStyle(.window)
    }

    /// The service belongs to the app, not the dashboard window. Closing the
    /// window must leave the menu-bar estimate and its ten-second refresh alive.
    private func startMonitoringIfNeeded() {
        appearance.applyToApplication()
        guard !didStartMonitoring else { return }
        didStartMonitoring = true
        batteryService.startMonitoring()
        processService.startMonitoring()
    }
}
