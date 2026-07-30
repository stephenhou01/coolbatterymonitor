import SwiftUI

// MARK: - 赛博风格装饰
//
// 都做成可复用修饰器，避免在每张卡片里重复一堆 overlay。
// 所有动画都尊重「减弱动态效果」辅助功能设置。

extension AppTheme {

    /// 动态网格背景。放在最底层的 ZStack 里。
    struct GridBackground: View {
        var spacing: CGFloat = 34
        var lineWidth: CGFloat = 0.5
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @State private var drift: CGFloat = 0

        var body: some View {
            Canvas { ctx, size in
                var path = Path()
                var x: CGFloat = drift
                while x <= size.width { path.move(to: .init(x: x, y: 0)); path.addLine(to: .init(x: x, y: size.height)); x += spacing }
                var y: CGFloat = drift
                while y <= size.height { path.move(to: .init(x: 0, y: y)); path.addLine(to: .init(x: size.width, y: y)); y += spacing }
                ctx.stroke(path, with: .color(AppTheme.chargingCyan.opacity(0.055)), lineWidth: lineWidth)
            }
            .allowsHitTesting(false)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.linear(duration: 16).repeatForever(autoreverses: false)) { drift = spacing }
            }
        }
    }

    /// 呼吸光晕。用在背景做氛围。
    struct AmbientOrb: View {
        let color: Color
        var diameter: CGFloat = 420
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @State private var pulse = false

        var body: some View {
            Circle()
                .fill(RadialGradient(colors: [color.opacity(pulse ? 0.16 : 0.07), .clear],
                                     center: .center, startRadius: 0, endRadius: diameter / 2))
                .frame(width: diameter, height: diameter)
                .blur(radius: 30)
                .allowsHitTesting(false)
                .onAppear {
                    guard !reduceMotion else { return }
                    withAnimation(.easeInOut(duration: 5).repeatForever(autoreverses: true)) { pulse = true }
                }
        }
    }

    /// 卡片顶部的扫描线，缓慢横向扫过。
    struct Scanline: ViewModifier {
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @State private var phase: CGFloat = -0.4

        func body(content: Content) -> some View {
            content.overlay(alignment: .top) {
                GeometryReader { geo in
                    LinearGradient(colors: [.clear, AppTheme.chargingCyan.opacity(0.55), .clear],
                                   startPoint: .leading, endPoint: .trailing)
                        .frame(width: geo.size.width * 0.45, height: 1)
                        .offset(x: phase * geo.size.width)
                        .onAppear {
                            guard !reduceMotion else { return }
                            withAnimation(.linear(duration: 4.5).repeatForever(autoreverses: false)) { phase = 1.2 }
                        }
                }
                .frame(height: 1)
                .allowsHitTesting(false)
            }
        }
    }

    /// hover 时浮起 + 边框发光。
    struct HoverLift: ViewModifier {
        var radius: CGFloat = Radius.xl
        var accent: Color = AppTheme.chargingCyan
        @State private var hovering = false

        func body(content: Content) -> some View {
            content
                .overlay(
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .stroke(accent.opacity(hovering ? 0.45 : 0), lineWidth: 1)
                )
                .shadow(color: accent.opacity(hovering ? 0.18 : 0), radius: hovering ? 16 : 0, y: 4)
                .offset(y: hovering ? -2 : 0)
                .animation(.easeOut(duration: 0.18), value: hovering)
                .onHover { hovering = $0 }
        }
    }

    /// 入场：淡入 + 轻微上移。delay 用来做卡片依次出现。
    struct Reveal: ViewModifier {
        let delay: Double
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @State private var shown = false

        func body(content: Content) -> some View {
            content
                .opacity(shown ? 1 : 0)
                .offset(y: shown ? 0 : 14)
                .onAppear {
                    guard !reduceMotion else { shown = true; return }
                    withAnimation(.easeOut(duration: 0.5).delay(delay)) { shown = true }
                }
        }
    }

    static func hoverLift(radius: CGFloat = Radius.xl, accent: Color = chargingCyan) -> HoverLift {
        HoverLift(radius: radius, accent: accent)
    }
    static func reveal(_ delay: Double = 0) -> Reveal { Reveal(delay: delay) }

    // MARK: - 状态色

    static func statusColor(_ s: FactorStatus) -> Color {
        switch s {
        case .pass: return batteryGreen
        case .warn: return batteryYellow
        case .fail: return batteryRed
        }
    }

    static func healthColor(_ l: HealthLevel) -> Color {
        switch l {
        case .excellent: return batteryGreen
        case .good:      return chargingCyan
        case .fair:      return batteryYellow
        case .poor:      return batteryOrange
        case .critical:  return batteryRed
        }
    }

    static func powerLevelColor(_ l: PowerLevel) -> Color {
        switch l {
        case .idle:     return batteryGreen
        case .light:    return chargingCyan
        case .moderate: return batteryYellow
        case .heavy:    return batteryOrange
        case .full:     return batteryRed
        }
    }
}

// MARK: - 分区小标题
// 「Battery Health Diagnosis · 电池健康诊断」这种双语标签在原型里是写死的，
// 这里改成当前语言 + 英文并列（中文界面下才显示英文副标，避免英文界面重复）。

struct SectionLabel: View {
    let key: String
    let englishFallback: String

    var body: some View {
        let localized = L(key)
        let showsDual = localized != englishFallback
        return HStack(spacing: 6) {
            Rectangle()
                .fill(AppTheme.chargingCyan)
                .frame(width: 2, height: 10)
            Text(showsDual ? "\(englishFallback) · \(localized)" : localized)
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundStyle(AppTheme.textTertiary)
                .textCase(.uppercase)
                .tracking(0.8)
                .lineLimit(1)
        }
    }
}

/// 数字入场：从 0 滚到目标值。
struct CountUp: View {
    let value: Int
    let font: Font
    let color: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown: Double = 0

    var body: some View {
        Text("\(Int(shown))")
            .font(font)
            .foregroundStyle(color)
            .contentTransition(.numericText(value: shown))
            .onAppear {
                guard !reduceMotion else { shown = Double(value); return }
                withAnimation(.easeOut(duration: 0.9)) { shown = Double(value) }
            }
            .onChange(of: value) { _, v in
                withAnimation(.easeOut(duration: 0.5)) { shown = Double(v) }
            }
    }
}
