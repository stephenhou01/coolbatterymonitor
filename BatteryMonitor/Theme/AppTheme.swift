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

// MARK: - Metric icon system

/// One semantic icon vocabulary shared by the overview, detail cards and the
/// menu-bar panel. Keeping the mapping here prevents the same metric from
/// becoming a bolt in one surface and an ECG waveform in another.
enum BatteryMetricIcon: String, CaseIterable {
    case stateOfCharge
    case runtime
    case power
    case adapter
    case adapterOutput
    case charging
    case temperature
    case cycles
    case health
    case current
    case capacity
    case designCapacity
    case usedCapacity
    case inaccessibleCapacity
    case permanentLoss
    case capacityGap
    case status
    case balance
    case resistance
    case voltage

    private var preferredSymbol: String {
        switch self {
        case .stateOfCharge: return "battery.75percent"
        case .runtime: return "clock"
        case .power: return "waveform.path.ecg"
        case .adapter: return "powerplug.fill"
        case .adapterOutput: return "arrow.down.circle.fill"
        case .charging: return "bolt.fill"
        case .temperature: return "thermometer.medium"
        case .cycles: return "arrow.triangle.2.circlepath"
        case .health: return "heart.fill"
        case .current: return "bolt.horizontal"
        case .capacity: return "battery.100percent"
        case .designCapacity: return "battery.100"
        case .usedCapacity: return "bolt.slash.fill"
        case .inaccessibleCapacity: return "lock.fill"
        case .permanentLoss: return "arrow.down.heart.fill"
        case .capacityGap: return "arrow.down.right.circle.fill"
        case .status: return "checkmark.shield.fill"
        case .balance: return "scale.3d"
        case .resistance: return "gauge.with.dots.needle.33percent"
        case .voltage: return "bolt.horizontal.circle"
        }
    }

    /// Conservative symbols kept for macOS 14 machines whose bundled SF
    /// Symbols catalogue may not contain a newer preferred glyph. A missing
    /// symbol must degrade to a simpler icon, never to an empty slot.
    var fallbackSymbol: String {
        switch self {
        case .stateOfCharge: return "battery.75"
        case .runtime: return "clock"
        case .power: return "waveform.path.ecg"
        case .adapter: return "powerplug"
        case .adapterOutput: return "arrow.down.circle"
        case .charging: return "bolt.fill"
        case .temperature: return "thermometer"
        case .cycles: return "arrow.2.circlepath"
        case .health: return "heart.fill"
        case .current: return "arrow.left.arrow.right"
        case .capacity: return "battery.100"
        case .designCapacity: return "ruler.fill"
        case .usedCapacity: return "bolt.slash"
        case .inaccessibleCapacity: return "lock.fill"
        case .permanentLoss: return "heart.slash.fill"
        case .capacityGap: return "arrow.down.right.circle"
        case .status: return "checkmark.shield"
        case .balance: return "scale.3d"
        case .resistance: return "gauge.medium"
        case .voltage: return "bolt.circle"
        }
    }

    private static let resolvedSymbols: [BatteryMetricIcon: String] = Dictionary(
        uniqueKeysWithValues: allCases.map { metric in
            let preferred = metric.preferredSymbol
            let resolved = NSImage(systemSymbolName: preferred, accessibilityDescription: nil) == nil
                ? metric.fallbackSymbol
                : preferred
            return (metric, resolved)
        }
    )

    /// Resolve once per process instead of asking AppKit for the same symbol on
    /// every ten-second refresh and SwiftUI body recomputation.
    var symbol: String { Self.resolvedSymbols[self] ?? fallbackSymbol }
}

enum MetricGlyphScale {
    case micro
    case compact
    case card
    case feature

    fileprivate var frame: CGFloat {
        switch self {
        case .micro: return 16
        case .compact: return 25
        case .card: return 38
        case .feature: return 48
        }
    }

    fileprivate var symbol: CGFloat {
        switch self {
        case .micro: return 9.5
        case .compact: return 13
        case .card: return 18
        case .feature: return 23
        }
    }
}

enum MetricGlyphStyle {
    case plain
    case tintedTile
}

/// Normalizes SF Symbols with very different native aspect ratios into one
/// visual weight. The tile uses semantic color at low opacity, so the icon
/// remains an accent and never competes with the metric value.
struct MetricGlyph: View {
    let systemName: String
    let tint: Color
    var scale: MetricGlyphScale = .compact
    var style: MetricGlyphStyle = .tintedTile

    @Environment(\.colorScheme) private var colorScheme
    @ScaledMetric(relativeTo: .body) private var accessibilityScale: CGFloat = 1

    init(
        _ metric: BatteryMetricIcon,
        tint: Color,
        scale: MetricGlyphScale = .compact,
        style: MetricGlyphStyle = .tintedTile
    ) {
        systemName = metric.symbol
        self.tint = tint
        self.scale = scale
        self.style = style
    }

    init(
        systemName: String,
        tint: Color,
        scale: MetricGlyphScale = .compact,
        style: MetricGlyphStyle = .tintedTile
    ) {
        self.systemName = systemName
        self.tint = tint
        self.scale = scale
        self.style = style
    }

    var body: some View {
        let multiplier = min(max(accessibilityScale, 1), 1.24)
        let dimension = scale.frame * multiplier
        let symbolSize = scale.symbol * multiplier

        ZStack {
            if style == .tintedTile {
                RoundedRectangle(cornerRadius: dimension * 0.29, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [tint.opacity(colorScheme == .dark ? 0.19 : 0.15),
                                     tint.opacity(colorScheme == .dark ? 0.065 : 0.045)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: dimension * 0.29, style: .continuous)
                            .stroke(tint.opacity(colorScheme == .dark ? 0.30 : 0.22), lineWidth: 0.8)
                    )
                    .shadow(color: tint.opacity(colorScheme == .dark ? 0.10 : 0.07), radius: 5, y: 2)
            }

            Image(systemName: systemName)
                .font(.system(size: symbolSize, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(tint)
                .frame(width: dimension, height: dimension)
        }
        .frame(width: dimension, height: dimension)
        .accessibilityHidden(true)
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
