import SwiftUI
import AppKit

// MARK: - Geometry

/// One wire in the power-flow diagram: the polyline the current runs along, plus
/// the arrowhead drawn at its far end.
///
/// The two are deliberately separate. The arrowhead is a V that doubles back on
/// itself, so a pulse animated along the combined path appears to reverse for its
/// last few points. The static stroke wants both; the pulse wants the wire only.
struct PowerFlowEdgeGeometry {
    /// Source → destination, in the diagram's own 290×198 canvas coordinates.
    let points: [CGPoint]
    let arrowhead: [CGPoint]

    /// What the pulse rides.
    var wirePath: Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: first)
        for point in points.dropFirst() { path.addLine(to: point) }
        return path
    }

    /// What gets stroked. Same geometry whether the edge is live or idle, so an
    /// inactive edge only changes weight and colour.
    var fullPath: Path {
        var path = wirePath
        path.addLines(arrowhead)
        return path
    }

    /// Summed segment lengths, in points.
    ///
    /// Needed because the pulse's animation is expressed as a fraction of the
    /// path per second, while the thing that should track power is its speed *on
    /// screen*. Without dividing by length, the 34pt adapter→battery wire and the
    /// 180pt battery→Mac wire would take the same time to traverse and so appear
    /// to be flowing at wildly different rates at identical watts.
    var wireLength: CGFloat {
        zip(points, points.dropFirst())
            .reduce(0) { $0 + hypot($1.1.x - $1.0.x, $1.1.y - $1.0.y) }
    }

    static func arrowRight(at tip: CGPoint) -> [CGPoint] {
        [CGPoint(x: tip.x - 7, y: tip.y - 5), tip, CGPoint(x: tip.x - 7, y: tip.y + 5)]
    }

    static func arrowUp(at tip: CGPoint) -> [CGPoint] {
        [CGPoint(x: tip.x - 5, y: tip.y + 7), tip, CGPoint(x: tip.x + 5, y: tip.y + 7)]
    }
}

// MARK: - Speed

/// Turns watts into how fast the pulses travel.
enum PowerFlowSpeed {
    /// Points per second per watt. Straight proportionality, as specified — the
    /// clamps below are the only departure from it.
    static let pointsPerSecondPerWatt: Double = 3.6
    /// A trickle still has to look like it is moving; below this the pulse reads
    /// as a stationary dot.
    static let minimumPointsPerSecond: Double = 24
    /// Past this the eye cannot tell two speeds apart anyway, and a diagram that
    /// strobes at 100 W is just noise.
    static let maximumPointsPerSecond: Double = 150

    /// Watts are rounded to this before being used, so that the ±0.3 W jitter
    /// between gauge publishes does not restart the animation — a restart is
    /// visible as a small jump, and at a ten-second poll it would happen
    /// constantly for no visible change in speed.
    static let wattQuantum: Double = 0.5

    static func pointsPerSecond(forWatts watts: Double) -> Double {
        let quantised = (max(0, watts) / wattQuantum).rounded() * wattQuantum
        return min(max(quantised * pointsPerSecondPerWatt, minimumPointsPerSecond),
                   maximumPointsPerSecond)
    }

    /// Seconds for one pulse to travel the whole wire.
    static func traversalDuration(watts: Double, length: CGFloat) -> Double {
        guard length > 0 else { return 1 }
        return Double(length) / pointsPerSecond(forWatts: watts)
    }
}

// MARK: - Pulse shape

/// Evenly spaced bright segments sliding along the wire.
///
/// A custom `Shape` with `animatableData` rather than an animated `dashPhase`:
/// the phase route depends on SwiftUI interpolating inside `StrokeStyle`, while
/// this is the documented mechanism and produces the same marching effect from
/// geometry the view owns outright.
struct PowerFlowPulse: Shape {
    /// 0…1, where the leading pulse's head sits along the wire.
    var progress: CGFloat
    let wire: Path
    /// How many pulses are in flight at once.
    let count: Int
    /// Length of one pulse as a fraction of the whole wire.
    let segment: CGFloat

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        guard count > 0, segment > 0 else { return Path() }
        var combined = Path()
        for index in 0..<count {
            let head = (progress + CGFloat(index) / CGFloat(count))
                .truncatingRemainder(dividingBy: 1)
            let tail = head + segment
            if tail <= 1 {
                combined.addPath(wire.trimmedPath(from: head, to: tail))
            } else {
                // Wrapping keeps the stream continuous instead of every pulse
                // vanishing at the arrowhead and popping back in at the source.
                combined.addPath(wire.trimmedPath(from: head, to: 1))
                combined.addPath(wire.trimmedPath(from: 0, to: tail - 1))
            }
        }
        return combined
    }
}

// MARK: - Animated edge

/// The static wire plus, when it is both carrying power and actually being
/// looked at, a stream of pulses running along it at a speed set by the watts.
struct PowerFlowAnimatedEdge: View {
    let geometry: PowerFlowEdgeGeometry
    let watts: Double?
    let tint: Color
    /// False when the user has paused live refresh, when the hosting window is
    /// hidden, or when Reduce Motion is on.
    let isAnimating: Bool

    @State private var progress: CGFloat = 0

    /// One pulse roughly every this many points, so a long wire carries more of
    /// them and the spacing looks the same everywhere.
    private static let pointsPerPulse: CGFloat = 34
    private static let pulseLengthPoints: CGFloat = 11

    private var pulseCount: Int {
        max(1, Int((geometry.wireLength / Self.pointsPerPulse).rounded()))
    }

    private var pulseFraction: CGFloat {
        guard geometry.wireLength > 0 else { return 0 }
        return min(0.5, Self.pulseLengthPoints / geometry.wireLength)
    }

    private var duration: Double {
        PowerFlowSpeed.traversalDuration(watts: watts ?? 0, length: geometry.wireLength)
    }

    private var isFlowing: Bool { isAnimating && watts != nil }

    var body: some View {
        ZStack {
            geometry.fullPath.stroke(
                watts == nil ? AppTheme.textTertiary.opacity(0.22) : tint,
                style: StrokeStyle(lineWidth: watts == nil ? 1 : 1.8,
                                   lineCap: .round, lineJoin: .round)
            )

            if isFlowing {
                PowerFlowPulse(progress: progress,
                               wire: geometry.wirePath,
                               count: pulseCount,
                               segment: pulseFraction)
                    .stroke(tint, style: StrokeStyle(lineWidth: 3.4, lineCap: .round))
                    .blur(radius: 1.7)
                    .opacity(0.8)
                    .allowsHitTesting(false)
            }
        }
        .onAppear { restart() }
        .onDisappear { halt() }
        .onChange(of: isFlowing) { _, _ in restart() }
        .onChange(of: duration) { _, _ in restart() }
    }

    private func restart() {
        halt()
        guard isFlowing, duration > 0 else { return }
        withAnimation(.linear(duration: duration).repeatForever(autoreverses: false)) {
            progress = 1
        }
    }

    /// Clearing the animation before re-arming it matters: `repeatForever` keeps
    /// running against the old duration otherwise, so a change in watts would
    /// layer a second animation on top of the first instead of replacing it.
    private func halt() {
        withTransaction(Transaction(animation: nil)) { progress = 0 }
    }
}

// MARK: - Visibility

/// Reports whether the window hosting this view can actually be seen.
///
/// This exists to answer the objection that kept the diagram static: a battery
/// monitor should not spend cycles animating a picture nobody is looking at.
/// `onDisappear` covers a closed window and a switched tab; this covers the
/// window being minimised or completely buried behind another app's.
struct WindowVisibilityReader: NSViewRepresentable {
    @Binding var isVisible: Bool

    func makeNSView(context: Context) -> ProbeView {
        ProbeView { report($0) }
    }

    func updateNSView(_ nsView: ProbeView, context: Context) {
        nsView.onChange = { report($0) }
        nsView.report()
    }

    /// Never assign straight through: the probe reports from inside
    /// `viewDidMoveToWindow` and from notification delivery, both of which can
    /// land during a SwiftUI update pass.
    private func report(_ visible: Bool) {
        guard visible != isVisible else { return }
        DispatchQueue.main.async { isVisible = visible }
    }

    final class ProbeView: NSView {
        var onChange: (Bool) -> Void
        private var observers: [NSObjectProtocol] = []

        init(onChange: @escaping (Bool) -> Void) {
            self.onChange = onChange
            super.init(frame: .zero)
            let names: [Notification.Name] = [
                NSWindow.didChangeOcclusionStateNotification,
                NSWindow.didMiniaturizeNotification,
                NSWindow.didDeminiaturizeNotification,
            ]
            observers = names.map { name in
                NotificationCenter.default.addObserver(
                    forName: name, object: nil, queue: .main
                ) { [weak self] _ in self?.report() }
            }
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("not used from a nib") }

        deinit {
            observers.forEach(NotificationCenter.default.removeObserver)
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            report()
        }

        /// No window yet means the view is mid-attachment, not hidden — reporting
        /// false there would stop the animation before it ever started.
        func report() {
            guard let window else { return onChange(true) }
            onChange(window.isVisible
                     && !window.isMiniaturized
                     && window.occlusionState.contains(.visible))
        }
    }
}
