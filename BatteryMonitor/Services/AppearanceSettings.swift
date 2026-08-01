import SwiftUI
import Observation
import AppKit

/// A single appearance preference shared by the main window and MenuBarExtra.
/// `system` intentionally resolves to nil so SwiftUI follows the current macOS
/// appearance and also reacts when the user changes it while the app is open.
enum AppearanceMode: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    var appKitAppearance: NSAppearance? {
        switch self {
        case .system: return nil
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        }
    }

    var title: String {
        switch self {
        case .system: return dashboardText("appearance.system", fallback: "跟随系统")
        case .light: return dashboardText("appearance.light", fallback: "浅色")
        case .dark: return dashboardText("appearance.dark", fallback: "深色")
        }
    }

    var symbol: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max.fill"
        case .dark: return "moon.fill"
        }
    }
}

@Observable
final class AppearanceSettings {
    static let shared = AppearanceSettings()

    private static let preferenceKey = "app.appearance.mode"
    @ObservationIgnored private let defaults: UserDefaults
    private(set) var mode: AppearanceMode

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        mode = defaults.string(forKey: Self.preferenceKey)
            .flatMap(AppearanceMode.init(rawValue:)) ?? .system
    }

    func select(_ newMode: AppearanceMode) {
        if mode != newMode {
            mode = newMode
            defaults.set(newMode.rawValue, forKey: Self.preferenceKey)
        }
        applyToApplication()
    }

    /// `preferredColorScheme` updates SwiftUI content, but MenuBarExtra is
    /// hosted by a separate AppKit window. Applying the same appearance to the
    /// application and all current windows makes the three buttons immediately
    /// affect both surfaces instead of only changing the selected icon.
    func applyToApplication() {
        let selectedAppearance = mode.appKitAppearance
        let apply = {
            NSApplication.shared.appearance = selectedAppearance
            NSApplication.shared.windows.forEach { $0.appearance = selectedAppearance }
            NSApplication.shared.mainMenu?.appearance = selectedAppearance
        }
        if Thread.isMainThread {
            apply()
        } else {
            DispatchQueue.main.async(execute: apply)
        }
    }
}

/// MenuBarExtra is hosted in its own private NSWindow and may be created after
/// the application-level appearance was applied. This zero-size bridge updates
/// that exact hosting window whenever the selected mode changes.
struct AppearanceWindowBridge: NSViewRepresentable {
    let mode: AppearanceMode

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        apply(to: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        apply(to: nsView)
    }

    private func apply(to view: NSView) {
        let selectedAppearance = mode.appKitAppearance
        DispatchQueue.main.async {
            view.window?.appearance = selectedAppearance
        }
    }
}
