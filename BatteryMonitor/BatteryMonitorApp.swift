import AppKit
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
                .frame(minWidth: DashboardWindowSizing.minimum.width,
                       minHeight: DashboardWindowSizing.minimum.height)
                .background(DashboardWindowSizingBridge().frame(width: 0, height: 0))
                .onAppear(perform: startMonitoringIfNeeded)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: DashboardWindowSizing.preferred.width,
                     height: DashboardWindowSizing.preferred.height)

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
                               secondaryMetric: menuBarSettings.secondaryMetric,
                               chargeSpeed: batteryService.chargeSpeed)
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

/// Keeps the full dashboard useful on a laptop display without turning it into
/// a nearly full-screen window. The migration runs once so later user resizing
/// is still respected by normal macOS window restoration.
private enum DashboardWindowSizing {
    static let preferred = CGSize(width: 1040, height: 680)
    static let minimum = CGSize(width: 800, height: 560)
    static let migrationKey = "dashboard.window.compactDefault.v1"
    static let screenMargin: CGFloat = 56
}

private struct DashboardWindowSizingBridge: NSViewRepresentable {
    func makeNSView(context: Context) -> DashboardWindowReaderView {
        let view = DashboardWindowReaderView()
        view.onWindowChange = configure
        return view
    }

    func updateNSView(_ nsView: DashboardWindowReaderView, context: Context) {
        nsView.onWindowChange = configure
        if let window = nsView.window { configure(window) }
    }

    private func configure(_ window: NSWindow) {
        window.contentMinSize = NSSize(width: DashboardWindowSizing.minimum.width,
                                       height: DashboardWindowSizing.minimum.height)

        // Window restoration completes during the same run-loop turn. Defer
        // the one-time migration so an older restored frame cannot overwrite
        // the compact size immediately after we apply it.
        DispatchQueue.main.async { migrateRestoredWindowIfNeeded(window) }
    }

    private func migrateRestoredWindowIfNeeded(_ window: NSWindow) {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: DashboardWindowSizing.migrationKey) else { return }

        let visibleSize = (window.screen ?? NSScreen.main)?.visibleFrame.size
        let targetWidth = min(
            DashboardWindowSizing.preferred.width,
            max(DashboardWindowSizing.minimum.width,
                (visibleSize?.width ?? DashboardWindowSizing.preferred.width) - DashboardWindowSizing.screenMargin)
        )
        let targetHeight = min(
            DashboardWindowSizing.preferred.height,
            max(DashboardWindowSizing.minimum.height,
                (visibleSize?.height ?? DashboardWindowSizing.preferred.height) - DashboardWindowSizing.screenMargin)
        )
        let currentSize = window.contentLayoutRect.size

        // Do not enlarge a window the user already made smaller. Only migrate
        // the former 1240x860 default (or another oversized restored frame).
        if currentSize.width > targetWidth + 1 || currentSize.height > targetHeight + 1 {
            window.setContentSize(NSSize(width: min(currentSize.width, targetWidth),
                                         height: min(currentSize.height, targetHeight)))
            window.center()
        }
        defaults.set(true, forKey: DashboardWindowSizing.migrationKey)
    }
}

private final class DashboardWindowReaderView: NSView {
    var onWindowChange: ((NSWindow) -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let window { onWindowChange?(window) }
    }
}
