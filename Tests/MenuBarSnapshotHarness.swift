import SwiftUI
import AppKit

/// Off-screen visual QA harness. It renders the real MenuBarDashboardView even
/// when the interactive desktop is unavailable (for example while CI or a
/// remote build session has the display locked).
@main
struct MenuBarSnapshotHarness {
    @MainActor
    static func main() throws {
        let arguments = CommandLine.arguments
        guard arguments.count >= 3 else {
            fputs("usage: MenuBarSnapshotHarness <light|dark> <output.png> [customize] [--background=/path/image.png]\n", stderr)
            exit(2)
        }

        let mode = AppearanceMode(rawValue: arguments[1]) ?? .dark
        let outputURL = URL(fileURLWithPath: arguments[2])

        _ = NSApplication.shared
        L10n.shared.select("zh-Hans")

        let suiteName = "com.stephen.BatteryMonitor.snapshot"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let appearance = AppearanceSettings(defaults: defaults)
        appearance.select(mode)
        let menuSettings = MenuBarSettings(defaults: defaults)

        let batteryService = BatteryService()
        batteryService.refreshNow()

        let processService = ProcessMonitorService()
        processService.topProcesses = [
            ProcessPowerInfo(pid: 101,
                             name: "/Applications/Safari.app",
                             cpuPercent: 8.4,
                             memoryMB: 682,
                             cpuHistory: [4.1, 6.2, 8.4],
                             isForeground: true),
            ProcessPowerInfo(pid: 102,
                             name: "/Applications/Xcode.app",
                             cpuPercent: 4.7,
                             memoryMB: 1_480,
                             cpuHistory: [3.2, 4.3, 4.7]),
            ProcessPowerInfo(pid: 103,
                             name: "/System/Library/CoreServices/Finder.app",
                             cpuPercent: 1.8,
                             memoryMB: 244,
                             cpuHistory: [1.1, 2.0, 1.8]),
        ]
        processService.hasSampled = true

        let options = Array(arguments.dropFirst(3))
        let panel = MenuBarDashboardView(initiallyCustomizing: options.contains("customize"))
            .environmentObject(batteryService)
            .environmentObject(processService)
            .environment(appearance)
            .environment(menuSettings)
            .environment(\.colorScheme, mode == .light ? .light : .dark)

        let root: AnyView
        if let option = options.first(where: { $0.hasPrefix("--background=") }),
           let image = NSImage(contentsOfFile: String(option.dropFirst("--background=".count))) {
            root = AnyView(
                ZStack {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 440, height: 745)
                        .clipped()
                    panel
                }
                .frame(width: 440, height: 745)
            )
        } else {
            root = AnyView(panel)
        }

        let renderer = ImageRenderer(content: root)
        renderer.scale = 2
        renderer.proposedSize = ProposedViewSize(width: 440, height: nil)

        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else {
            throw SnapshotError.renderFailed
        }
        try png.write(to: outputURL, options: .atomic)
        defaults.removePersistentDomain(forName: suiteName)
    }

    private enum SnapshotError: Error {
        case renderFailed
    }
}
