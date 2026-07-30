import SwiftUI

@main
struct BatteryMonitorApp: App {
    @StateObject private var batteryService = BatteryService()
    @StateObject private var processService = ProcessMonitorService()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(batteryService)
                .environmentObject(processService)
                .preferredColorScheme(.dark)
                .frame(minWidth: 960, minHeight: 640)
                .onAppear {
                    batteryService.startMonitoring()
                    processService.startMonitoring()
                }
                .onDisappear {
                    batteryService.stopMonitoring()
                    processService.stopMonitoring()
                }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1060, height: 720)
    }
}
