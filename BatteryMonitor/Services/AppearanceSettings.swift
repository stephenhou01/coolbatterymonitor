import SwiftUI
import Observation
import AppKit

/// A single appearance preference shared by the main window and MenuBarExtra.
/// `system` is retained only so existing preferences can be migrated. New
/// selections are always one of the two concrete modes exposed by the UI.
enum AppearanceMode: String, Identifiable {
    case system
    case light
    case dark

    static let selectableCases: [AppearanceMode] = [.light, .dark]

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
        case .system: return dashboardText("appearance.system")
        case .light: return dashboardText("appearance.light")
        case .dark: return dashboardText("appearance.dark")
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

    init(defaults: UserDefaults = .standard,
         defaultMode: AppearanceMode? = nil) {
        self.defaults = defaults
        let storedMode = defaults.string(forKey: Self.preferenceKey)
            .flatMap(AppearanceMode.init(rawValue:))
        if let storedMode, AppearanceMode.selectableCases.contains(storedMode) {
            mode = storedMode
        } else if let defaultMode, AppearanceMode.selectableCases.contains(defaultMode) {
            mode = defaultMode
        } else {
            mode = Self.currentSystemMode()
        }

        // Older releases stored `system`, and a missing preference also meant
        // follow-system. Resolve that once to a visible choice so the selected
        // state can never point at the removed third option.
        if storedMode != mode {
            defaults.set(mode.rawValue, forKey: Self.preferenceKey)
        }
    }

    func select(_ newMode: AppearanceMode) {
        let selectedMode = AppearanceMode.selectableCases.contains(newMode)
            ? newMode
            : Self.currentSystemMode()
        if mode != selectedMode {
            mode = selectedMode
            defaults.set(selectedMode.rawValue, forKey: Self.preferenceKey)
        }
        applyToApplication()
    }

    private static func currentSystemMode() -> AppearanceMode {
        NSApplication.shared.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? .dark
            : .light
    }

    /// `preferredColorScheme` updates SwiftUI content, but MenuBarExtra is
    /// hosted by a separate AppKit window. Applying the same appearance to the
    /// application and all current windows makes the two buttons immediately
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
    var usesTransparentBackground = false

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
            guard let window = view.window else { return }
            window.appearance = selectedAppearance
            if usesTransparentBackground {
                window.isOpaque = false
                window.backgroundColor = .clear
                window.hasShadow = true
            }
        }
    }
}
