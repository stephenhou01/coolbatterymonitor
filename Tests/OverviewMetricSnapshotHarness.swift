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
        var runtimeData = BatteryData()
        runtimeData.modelIdentifier = "Mac16,12"
        runtimeData.percent = 70
        runtimeData.timeRemainingMinutes = 135
        runtimeData.currentPowerWatts = 16.68
        runtimeData.hardwareDetail.designCapacity = 4629
        runtimeData.hardwareDetail.appleRawMaxCapacity = 4082
        runtimeData.hardwareDetail.appleRawCurrentCapacity = 3228
        runtimeData.hardwareDetail.presentRawFields.insert("AppleRawCurrentCapacity")
        runtimeData.hardwareDetail.timeRemainingRaw = 135
        runtimeData.hardwareDetail.avgTimeToEmpty = 142
        runtimeData.hardwareDetail.systemPowerWatts = 16.68
        let runtimeEnd = Date()
        let runtimePoints = [14.8, 15.4, 15.9, 16.2, 17.1].enumerated().map { offset, power in
            RealtimeDataPoint(
                timestamp: runtimeEnd.addingTimeInterval(Double(-30 * offset)),
                voltage: 12.4,
                amperage: -1_200,
                power: power,
                temperature: 30.8,
                percent: 70
            )
        }
        let runtimeSnapshot = DashboardMetricSnapshot(data: runtimeData, realtimeData: runtimePoints)
        let helps = [
            DashboardHelp.power(snapshot),
            DashboardHelp.adapterPower(snapshot),
            DashboardHelp.chargingPower(snapshot),
            DashboardHelp.temperature(snapshot),
            DashboardHelp.cycleCount(snapshot),
            DashboardHelp.health(snapshot),
            DashboardHelp.runtime(runtimeSnapshot),
        ]
        guard helps.count == 7, helps.allSatisfy({ !$0.rawFields.isEmpty }) else {
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
