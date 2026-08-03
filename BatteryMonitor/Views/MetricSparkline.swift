import SwiftUI

/// A trend line drawn *behind* a metric's value rather than beside it.
///
/// The rail is seven columns wide; a separate chart row per card would have cost
/// every card the same height again. Sitting the line under the number costs
/// nothing vertically and puts the shape where the eye already is.
///
/// Deliberately unlabelled and unaxed: it answers "rising, falling, or steady"
/// and nothing more. The exact history lives behind the question mark, and the
/// trends page draws it properly.
struct MetricSparkline: View {
    let values: [Double]
    let tint: Color

    /// Two points make a line; one makes a dot that reads as noise.
    static let minimumPoints = 2
    /// A range narrower than this is a flat reading with sensor jitter on top.
    /// Scaling it to full height would turn ±0.05 W into a mountain range.
    static let minimumRange = 0.5

    var body: some View {
        GeometryReader { geo in
            let shaped = Self.normalised(values)
            if shaped.count >= Self.minimumPoints {
                let line = Self.path(shaped, in: geo.size)
                ZStack {
                    Self.fill(shaped, in: geo.size)
                        .fill(LinearGradient(colors: [tint.opacity(0.16), tint.opacity(0.01)],
                                             startPoint: .top, endPoint: .bottom))
                    line.stroke(tint.opacity(0.45), style: StrokeStyle(lineWidth: 1.2,
                                                                       lineCap: .round,
                                                                       lineJoin: .round))
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// Maps the samples into 0...1 with 0 at the bottom. A flat series lands at
    /// mid-height rather than pinned to an edge.
    static func normalised(_ values: [Double]) -> [Double] {
        let usable = values.filter { $0.isFinite }
        guard usable.count >= minimumPoints,
              let low = usable.min(), let high = usable.max() else { return [] }
        let span = high - low
        guard span >= minimumRange else { return usable.map { _ in 0.5 } }
        return usable.map { ($0 - low) / span }
    }

    static func path(_ shaped: [Double], in size: CGSize) -> Path {
        Path { p in
            for (index, value) in shaped.enumerated() {
                let point = position(index, value, count: shaped.count, in: size)
                index == 0 ? p.move(to: point) : p.addLine(to: point)
            }
        }
    }

    static func fill(_ shaped: [Double], in size: CGSize) -> Path {
        var p = path(shaped, in: size)
        p.addLine(to: CGPoint(x: size.width, y: size.height))
        p.addLine(to: CGPoint(x: 0, y: size.height))
        p.closeSubpath()
        return p
    }

    private static func position(_ index: Int, _ value: Double, count: Int, in size: CGSize) -> CGPoint {
        let x = count == 1 ? size.width / 2 : size.width * CGFloat(index) / CGFloat(count - 1)
        return CGPoint(x: x, y: size.height * (1 - CGFloat(value)))
    }
}
