import SwiftUI
import AppKit

enum AppTheme {
    private static func adaptive(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        })
    }

    // MARK: - Colors
    static let background = adaptive(
        light: NSColor(srgbRed: 0.955, green: 0.968, blue: 0.989, alpha: 1),
        dark: NSColor(srgbRed: 0.040, green: 0.064, blue: 0.094, alpha: 1)
    )
    static let sidebarBackground = adaptive(
        light: NSColor(srgbRed: 0.925, green: 0.944, blue: 0.976, alpha: 0.96),
        dark: NSColor(srgbRed: 0.050, green: 0.078, blue: 0.112, alpha: 0.98)
    )
    static let cardBackground = adaptive(
        light: NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.82),
        dark: NSColor(srgbRed: 0.065, green: 0.096, blue: 0.132, alpha: 0.90)
    )
    static let surfaceRaised = adaptive(
        light: NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.96),
        dark: NSColor(srgbRed: 0.085, green: 0.120, blue: 0.160, alpha: 0.96)
    )
    static let surfaceSunken = adaptive(
        light: NSColor(srgbRed: 0.900, green: 0.922, blue: 0.955, alpha: 0.70),
        dark: NSColor(srgbRed: 0.015, green: 0.033, blue: 0.052, alpha: 0.70)
    )
    static let cardBorder = adaptive(
        light: NSColor(srgbRed: 0.18, green: 0.25, blue: 0.34, alpha: 0.14),
        dark: NSColor(srgbRed: 0.72, green: 0.82, blue: 0.92, alpha: 0.13)
    )
    static let divider = adaptive(
        light: NSColor(srgbRed: 0.12, green: 0.18, blue: 0.25, alpha: 0.12),
        dark: NSColor(srgbRed: 0.78, green: 0.86, blue: 0.94, alpha: 0.11)
    )
    static let textPrimary = Color(nsColor: .labelColor)
    static let textSecondary = Color(nsColor: .secondaryLabelColor)
    static let textTertiary = Color(nsColor: .tertiaryLabelColor)
    static let selectionText = Color.white

    /// A subtle surface/row tint that is white in dark mode and black in light
    /// mode. It replaces hard-coded white overlays without changing hierarchy.
    static func contrastOverlay(_ opacity: Double) -> Color {
        Color(nsColor: .labelColor).opacity(opacity)
    }

    // MARK: - Design Tokens (集中管理，提升迁移性)
    enum Spacing {
        static let xs: CGFloat = 6
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 20
        static let xxl: CGFloat = 24
    }
    enum Radius {
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let card: CGFloat = 14
        static let lg: CGFloat = 16
        static let xl: CGFloat = 20
    }
    enum Typography {
        static let sectionTitle = Font.system(size: 16, weight: .bold)
        static let cardValue = Font.system(size: 20, weight: .bold, design: .rounded)
        static let label = Font.system(size: 11)
        static let caption = Font.system(size: 10)
        static let micro = Font.system(size: 9)
    }

    static let batteryGreen = Color(red: 0.2, green: 0.85, blue: 0.4)
    static let batteryYellow = Color(red: 1.0, green: 0.78, blue: 0.2)
    static let batteryRed = Color(red: 1.0, green: 0.35, blue: 0.3)
    static let chargingBlue = Color(red: 0.3, green: 0.65, blue: 1.0)
    static let chargingCyan = Color(red: 0.2, green: 0.9, blue: 0.8)
    static let accentPurple = Color(red: 0.6, green: 0.4, blue: 1.0)
    static let batteryOrange = Color(red: 1.0, green: 0.58, blue: 0.2)

    // MARK: - Gradients
    static func batteryGradient(percent: Int) -> LinearGradient {
        let colors: [Color]
        if percent > 60 {
            colors = [batteryGreen.opacity(0.7), batteryGreen]
        } else if percent > 25 {
            colors = [batteryYellow.opacity(0.7), batteryYellow]
        } else {
            colors = [batteryRed.opacity(0.7), batteryRed]
        }
        return LinearGradient(colors: colors, startPoint: .bottom, endPoint: .top)
    }

    static let chargingGradient = LinearGradient(
        colors: [chargingBlue, chargingCyan],
        startPoint: .bottomLeading, endPoint: .topTrailing
    )

    static let gaugeBackgroundGradient = LinearGradient(
        colors: [surfaceSunken, cardBackground],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )

    // MARK: - Energy Colors
    static func energyColor(_ level: ProcessPowerInfo.EnergyLevel) -> Color {
        switch level {
        case .low: return batteryGreen
        case .moderate: return batteryYellow
        case .high: return batteryOrange
        case .veryHigh: return batteryRed
        }
    }

    static func rateColor(_ rate: Double) -> Color {
        if rate >= 55 { return batteryGreen }
        if rate >= 35 { return batteryYellow }
        return batteryRed
    }

    // MARK: - Card Modifier
    struct CardStyle: ViewModifier {
        var cornerRadius: CGFloat = Radius.xl
        func body(content: Content) -> some View {
            content
                .background(cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(cardBorder, lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.08), radius: 14, y: 5)
        }
    }

    static func card(radius: CGFloat = Radius.xl) -> CardStyle {
        CardStyle(cornerRadius: radius)
    }
}

// MARK: - Hover pointer (macOS 原生手感)
extension View {
    func pointerOnHover() -> some View {
        self.onHover { inside in
            if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
    }
}
