import SwiftUI
import AppKit

enum AppTheme {
    // MARK: - Colors
    static let background = Color(red: 0.07, green: 0.07, blue: 0.10)
    static let cardBackground = Color(red: 0.12, green: 0.12, blue: 0.16)
    static let cardBorder = Color.white.opacity(0.08)
    static let textPrimary = Color.white
    static let textSecondary = Color.white.opacity(0.7)
    static let textTertiary = Color.white.opacity(0.6)  // WCAG-friendlier on dark cards

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
        colors: [Color(red: 0.08, green: 0.08, blue: 0.12), Color(red: 0.14, green: 0.14, blue: 0.20)],
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
