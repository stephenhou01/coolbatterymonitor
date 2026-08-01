import SwiftUI
import AppKit

/// Off-screen visual QA harness for the six overview metric help buttons and
/// the shared lowest-level field drawer.
@main
struct OverviewMetricSnapshotHarness {
    @MainActor
    static func main() throws {
        let arguments = CommandLine.arguments
        guard arguments.count >= 3 else {
            fputs("usage: OverviewMetricSnapshotHarness <light|dark> <output.png> [help-index]\n", stderr)
            exit(2)
        }

        let mode = AppearanceMode(rawValue: arguments[1]) ?? .dark
        let outputURL = URL(fileURLWithPath: arguments[2])
        let requestedHelp = arguments.count > 3 ? Int(arguments[3]) : nil

        _ = NSApplication.shared
        L10n.shared.select("zh-Hans")

        let suiteName = "com.stephen.BatteryMonitor.overview-snapshot"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let appearance = AppearanceSettings(defaults: defaults)
        appearance.select(mode)

        let batteryService = BatteryService()
        batteryService.refreshNow()
        let snapshot = DashboardMetricSnapshot(
            data: batteryService.batteryData,
            realtimeData: batteryService.realtimeData
        )
        let helps = [
            DashboardHelp.power(snapshot),
            DashboardHelp.adapterPower(snapshot),
            DashboardHelp.chargingPower(snapshot),
            DashboardHelp.temperature(snapshot),
            DashboardHelp.cycleCount(snapshot),
            DashboardHelp.health(snapshot),
        ]
        guard helps.count == 6, helps.allSatisfy({ !$0.rawFields.isEmpty }) else {
            throw SnapshotError.missingHelpContent
        }

        let page = DashboardOverviewPage(selectedHelp: .constant(nil))
            .environmentObject(batteryService)
            .environment(appearance)
            .environment(\.colorScheme, mode == .light ? .light : .dark)
            .frame(width: 1080, height: 800)

        let root = ZStack(alignment: .trailing) {
            page
            if let requestedHelp, helps.indices.contains(requestedHelp) {
                MetricHelpDrawer(content: helps[requestedHelp], onClose: {})
            }
        }
        .frame(width: 1080, height: 800)
        .environment(appearance)
        .environment(\.colorScheme, mode == .light ? .light : .dark)

        let hostingView = NSHostingView(rootView: root)
        hostingView.frame = NSRect(x: 0, y: 0, width: 1080, height: 800)
        let window = NSWindow(
            contentRect: hostingView.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        window.orderFrontRegardless()
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        hostingView.layoutSubtreeIfNeeded()

        guard let bitmap = hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds) else {
            throw SnapshotError.renderFailed
        }
        hostingView.cacheDisplay(in: hostingView.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else {
            throw SnapshotError.renderFailed
        }
        try png.write(to: outputURL, options: .atomic)
        window.orderOut(nil)
        defaults.removePersistentDomain(forName: suiteName)
    }

    private enum SnapshotError: Error {
        case missingHelpContent
        case renderFailed
    }
}
