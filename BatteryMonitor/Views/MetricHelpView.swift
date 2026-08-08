import SwiftUI
import Charts

struct MetricHelpButton: View {
    /// An autoclosure, which is the whole point: a heavy page holds ~50 of these
    /// buttons, and building every card's formula, substitution and raw-field
    /// list on every redraw — for panels nobody has opened — was the largest
    /// single cost of a page. Taking it unevaluated keeps every call site
    /// unchanged while deferring the work to the tap.
    let content: () -> MetricHelpContent
    @Binding var selection: MetricHelpContent?

    @Environment(\.dashboardDataVersion) private var dataVersion
    /// Set only while this button's own panel is the one on screen, so exactly
    /// one content object gets rebuilt per poll instead of fifty.
    @State private var presentedID: String?

    init(content: @autoclosure @escaping () -> MetricHelpContent,
         selection: Binding<MetricHelpContent?>) {
        self.content = content
        self._selection = selection
    }

    var body: some View {
        Button {
            let built = content()
            presentedID = built.id
            selection = built
        } label: {
            Text("?")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.textSecondary)
                .frame(width: 20, height: 20)
                .background(Circle().fill(AppTheme.contrastOverlay(0.055)))
                .overlay(Circle().stroke(AppTheme.contrastOverlay(0.10), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .pointerOnHover()
        .accessibilityLabel(dashboardText("p.help_open"))
        .help(dashboardText("p.help_open"))
        // The drawer holds a value copy, so it would otherwise freeze at the
        // moment of the tap. Rebuild on each poll, but only for the panel that is
        // actually open — `content()` here is the closure from the current body
        // pass, so it reads current data.
        .onChange(of: dataVersion) { _, _ in
            guard let presentedID, selection?.id == presentedID else { return }
            selection = content()
        }
        // Another button took over, or the drawer was dismissed: stop refreshing.
        .onChange(of: selection?.id) { _, newID in
            if newID != presentedID { presentedID = nil }
        }
    }
}

/// One chart shape for every help panel, so hovering behaves identically
/// wherever a trend appears. Selection state lives here rather than in the
/// drawer: each chart tracks its own pointer, and nothing has to be reset when
/// the drawer swaps to another metric.
struct MetricTrendChart: View {
    let trend: MetricHelpTrend
    var height: CGFloat = 132

    /// Where the pointer is on the x axis, driven by Charts' own
    /// `chartXSelection`. nil whenever the pointer is outside the plot.
    @State private var selectedDate: Date?

    var body: some View {
        Chart {
            ForEach(trend.points) { point in
                LineMark(
                    x: .value("Time", point.timestamp),
                    y: .value("Value", point.value),
                    series: .value("Segment", point.segmentID)
                )
                .foregroundStyle(trend.tint)
                .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))

                if point.quality == .fitted {
                    PointMark(
                        x: .value("Fitted time", point.timestamp),
                        y: .value("Fitted value", point.value)
                    )
                    .foregroundStyle(AppTheme.surfaceRaised)
                    .symbolSize(28)
                    .annotation(position: .overlay) {
                        Circle().stroke(trend.tint, lineWidth: 1).frame(width: 6, height: 6)
                    }
                }
            }

            if let ceiling = trend.ceiling, ceiling > 0 {
                RuleMark(y: .value("Ceiling", ceiling))
                    .foregroundStyle(AppTheme.batteryYellow.opacity(0.7))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
            }

            if let hovered = MetricHelpDrawer.nearestTrendPoint(trend.points, to: selectedDate) {
                RuleMark(x: .value("Hovered", hovered.timestamp))
                    .foregroundStyle(trend.tint.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .annotation(position: .top, alignment: .leading, spacing: 2, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        Text(MetricHelpDrawer.trendHoverText(hovered, unit: trend.unit))
                            .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                            .foregroundStyle(AppTheme.textPrimary)
                            .monospacedDigit()
                            .fixedSize()
                            .padding(.horizontal, 7)
                            .padding(.vertical, 4)
                            .background(RoundedRectangle(cornerRadius: 7)
                                .fill(AppTheme.surfaceRaised.opacity(0.96)))
                            .overlay(RoundedRectangle(cornerRadius: 7)
                                .stroke(AppTheme.cardBorder))
                    }
                PointMark(x: .value("Hovered", hovered.timestamp),
                          y: .value("Value", hovered.value))
                    .foregroundStyle(trend.tint)
                    .symbolSize(46)
            }
        }
        // Charts' own pointer tracking. The hand-rolled chartOverlay +
        // onContinuousHover this replaces never fired; the two charts elsewhere
        // in the app that do work use this API, and copying the proven one was
        // the right move from the start.
        .chartXSelection(value: $selectedDate)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 3)) { _ in
                AxisGridLine().foregroundStyle(AppTheme.contrastOverlay(0.04))
                AxisValueLabel(format: .dateTime.hour().minute())
                    .foregroundStyle(AppTheme.textTertiary)
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                AxisGridLine().foregroundStyle(AppTheme.contrastOverlay(0.05))
                AxisValueLabel {
                    if let number = value.as(Double.self) {
                        Text("\(Int(number.rounded()))\(trend.unit)")
                    }
                }
                .foregroundStyle(AppTheme.textTertiary)
            }
        }
        .chartYScale(domain: domain)
        .frame(height: height)
    }

    /// Power reads from zero so "half the wattage" looks like half. Temperature
    /// gets a padded window around its own range instead, because a 0℃ floor
    /// would render every real swing as a flat line.
    private var domain: ClosedRange<Double> {
        let values = trend.points.map(\.value)
        let peak = max(values.max() ?? 0, trend.ceiling ?? 0)
        guard !trend.baselineAtZero else {
            return 0...(max(peak, 1) * 1.08)
        }
        let low = values.min() ?? 0
        let pad = max((peak - low) * 0.18, 0.5)
        return (low - pad)...(peak + pad)
    }
}

/// Window-level trailing drawer. ContentView owns the selection so the panel is
/// not clipped by the dashboard's ScrollView.
struct MetricHelpDrawer: View {
    let content: MetricHelpContent
    let onClose: () -> Void
    @FocusState private var closeFocused: Bool
    @State private var selectedTrendRange: MetricHelpTrendRange = .tenMinutes
    var body: some View {
        HStack(spacing: 0) {
            Button(action: onClose) {
                Color.black.opacity(0.58)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHidden(true)

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    drawerHeader

                    VStack(alignment: .leading, spacing: 7) {
                        Text(content.title)
                            .font(.system(size: 23, weight: .bold, design: .rounded))
                            .foregroundStyle(AppTheme.textPrimary)
                        Text(content.summary)
                            .font(.system(size: 12.5))
                            .foregroundStyle(AppTheme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .lineSpacing(4)
                    }

                    resultBlock
                    adapterTrendBlock
                    trendBlock
                    rawFieldsBlock
                    formulaBlock
                    sourceBlock
                }
                .padding(.horizontal, 26)
                .padding(.vertical, 24)
            }
            .frame(width: 470)
            .background(
                LinearGradient(
                    colors: [AppTheme.surfaceRaised, AppTheme.cardBackground],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(AppTheme.chargingCyan.opacity(0.22))
                    .frame(width: 1)
            }
            .shadow(color: .black.opacity(0.55), radius: 30, x: -12)
        }
        .ignoresSafeArea()
        .transition(.opacity.combined(with: .move(edge: .trailing)))
        .onAppear { closeFocused = true }
        .onChange(of: content.id) { _, _ in selectedTrendRange = .tenMinutes }
        .onExitCommand(perform: onClose)
        .accessibilityElement(children: .contain)
    }

    private var drawerHeader: some View {
        HStack {
            Text(dashboardText("p.help_title"))
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .tracking(1.1)
                .foregroundStyle(AppTheme.chargingCyan)
            Spacer()
            Button(action: onClose) {
                Label(dashboardText("p.help_close"), systemImage: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AppTheme.textSecondary)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 7).fill(AppTheme.contrastOverlay(0.05)))
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
            .focused($closeFocused)
            .pointerOnHover()
        }
        .padding(.bottom, 14)
        .overlay(alignment: .bottom) {
            Rectangle().fill(AppTheme.contrastOverlay(0.07)).frame(height: 1)
        }
    }

    private var resultBlock: some View {
        return VStack(alignment: .leading, spacing: 9) {
            drawerEyebrow(dashboardText("p.help_current"))

            if let contract = content.powerContract {
                adapterContractBlock(contract)
            } else if content.comparisonResults.isEmpty {
                Text(content.result)
                    .font(.system(size: 27, weight: .medium, design: .monospaced))
                    .foregroundStyle(AppTheme.chargingCyan)
                    .minimumScaleFactor(0.75)
                    .lineLimit(2)
            } else {
                if let primary = content.comparisonResults.first {
                    comparisonResultCard(primary, primary: true)
                }
                HStack(alignment: .top, spacing: 9) {
                    ForEach(content.comparisonResults.dropFirst()) { item in
                        comparisonResultCard(item, primary: false)
                    }
                }
            }
        }
    }

    private func adapterContractBlock(_ contract: MetricPowerContract) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 11) {
                Image(systemName: contract.isConnected ? "powerplug.fill" : "powerplug")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(contract.isConnected ? AppTheme.chargingCyan : AppTheme.textTertiary)
                    .frame(width: 40, height: 40)
                    .background(
                        RoundedRectangle(cornerRadius: 11)
                            .fill((contract.isConnected ? AppTheme.chargingCyan : AppTheme.textTertiary).opacity(0.08))
                    )
                VStack(alignment: .leading, spacing: 3) {
                    Text(contract.stateTitle)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(AppTheme.textPrimary)
                    Text(contract.stateDetail)
                        .font(.system(size: 9.5))
                        .foregroundStyle(AppTheme.textTertiary)
                        .lineLimit(2)
                }
                Spacer(minLength: 8)
                Text(contract.isNegotiated
                     ? dashboardText("p.adapter_status_ready_badge")
                     : dashboardText("p.adapter_status_waiting_badge"))
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .tracking(0.8)
                    .foregroundStyle(contract.isNegotiated ? AppTheme.batteryGreen : AppTheme.textTertiary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Capsule().fill((contract.isNegotiated ? AppTheme.batteryGreen : AppTheme.textTertiary).opacity(0.08)))
            }

            HStack(spacing: 7) {
                contractMetric(icon: "bolt.circle.fill", label: contract.voltageLabel,
                               value: contract.voltageText, tint: AppTheme.chargingBlue)
                equationOperator("×")
                contractMetric(icon: "waveform.path.ecg", label: contract.currentLabel,
                               value: contract.currentText, tint: AppTheme.batteryGreen)
                equationOperator("=")
                contractMetric(icon: "bolt.fill", label: contract.powerLabel,
                               value: contract.powerText, tint: AppTheme.batteryYellow)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(contract.equationText)
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(AppTheme.textPrimary)
                    .textSelection(.enabled)
                Text(contract.equationNote)
                    .font(.system(size: 9.5))
                    .foregroundStyle(AppTheme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(2)
            }
            .padding(11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 9).fill(AppTheme.chargingCyan.opacity(0.045)))
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(AppTheme.chargingCyan.opacity(0.13), lineWidth: 1))
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12).fill(AppTheme.contrastOverlay(0.025)))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(AppTheme.contrastOverlay(0.08), lineWidth: 1))
    }

    private func contractMetric(icon: String, label: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tint)
            Text(label)
                .font(.system(size: 8.5, weight: .medium))
                .foregroundStyle(AppTheme.textTertiary)
                .lineLimit(1)
            Text(value)
                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                .foregroundStyle(AppTheme.textPrimary)
                .minimumScaleFactor(0.72)
                .lineLimit(1)
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 78, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 9).fill(tint.opacity(0.045)))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(tint.opacity(0.13), lineWidth: 1))
    }

    private func equationOperator(_ value: String) -> some View {
        Text(value)
            .font(.system(size: 13, weight: .bold, design: .rounded))
            .foregroundStyle(AppTheme.textTertiary)
            .frame(width: 10)
    }

    /// The adapter panel keeps its own trend so the negotiated-ceiling rule line
    /// stays attached to the contract it belongs to; everything else goes
    /// through `content.trend`. Both render the same chart.
    @ViewBuilder
    private var adapterTrendBlock: some View {
        if let contract = content.powerContract {
            trendCard(MetricHelpTrend(
                title: contract.trendTitle,
                latestText: contract.trendValue,
                note: contract.trendNote,
                unit: "W",
                tint: AppTheme.chargingCyan,
                points: contract.trendPoints,
                ceiling: contract.ceilingWatts,
                waitingText: dashboardText("p.adapter_trend_waiting")
            ))
        }
    }

    @ViewBuilder
    private var trendBlock: some View {
        if let trend = content.trend {
            trendCard(trend)
        }
    }

    private func trendCard(_ trend: MetricHelpTrend) -> some View {
        let visibleTrend = MetricHelpTrend(
            title: trend.title,
            latestText: trend.latestText,
            note: trend.note,
            unit: trend.unit,
            tint: trend.tint,
            points: selectedTrendRange.chartPoints(from: trend.points),
            ceiling: trend.ceiling,
            baselineAtZero: trend.baselineAtZero,
            waitingText: trend.waitingText
        )
        return VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline) {
                drawerEyebrow(visibleTrend.title)
                Spacer()
                Text(visibleTrend.latestText)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(visibleTrend.tint)
            }

            Picker("", selection: $selectedTrendRange) {
                ForEach(MetricHelpTrendRange.allCases) { range in
                    Text(range.title).tag(range)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .accessibilityLabel(dashboardText("p.trend_range"))

            Text(selectedTrendRange.samplingSummary)
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundStyle(AppTheme.textTertiary)

            if visibleTrend.isPlottable {
                MetricTrendChart(trend: visibleTrend)
            } else {
                HStack(spacing: 9) {
                    Image(systemName: "chart.xyaxis.line")
                        .foregroundStyle(AppTheme.textTertiary)
                    Text(visibleTrend.waitingText)
                        .font(.system(size: 10.5))
                        .foregroundStyle(AppTheme.textTertiary)
                }
                .frame(maxWidth: .infinity, minHeight: 72, alignment: .center)
            }

            Text(visibleTrend.note)
                .font(.system(size: 9.5))
                .foregroundStyle(AppTheme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(2)
        }
        .padding(13)
        .background(RoundedRectangle(cornerRadius: 11).fill(AppTheme.contrastOverlay(0.02)))
        .overlay(RoundedRectangle(cornerRadius: 11).stroke(AppTheme.contrastOverlay(0.07), lineWidth: 1))
    }

    /// Snaps the pointer's x position to a recorded sample. Snapping rather than
    /// interpolating keeps the readout honest: every figure it shows was
    /// measured, not drawn between two measurements.
    ///
    /// nil in, nil out — no selection means no readout, rather than defaulting to
    /// the latest point and looking like a permanent marker.
    static func nearestTrendPoint(_ points: [MetricHelpTrendPoint], to date: Date?) -> MetricHelpTrendPoint? {
        guard let date else { return nil }
        return points.min { lhs, rhs in
            abs(lhs.timestamp.timeIntervalSince(date)) < abs(rhs.timestamp.timeIntervalSince(date))
        }
    }

    /// Minute granularity, as asked: these are 10-second samples of values that
    /// mostly republish once a minute, so seconds would imply a precision the
    /// series does not have.
    static func trendHoverText(_ point: MetricHelpTrendPoint, unit: String = "W") -> String {
        let fitted = point.quality == .fitted
            ? " · \(dashboardText("p.trend_fitted"))"
            : ""
        return "\(MetricFieldFreshness.minuteText(point.timestamp)) · \(LNum("%.1f", point.value)) \(unit)\(fitted)"
    }

    private func comparisonResultCard(_ item: MetricHelpResult, primary: Bool) -> some View {
        let tint = item.style.tint
        return VStack(alignment: .leading, spacing: primary ? 7 : 5) {
            Text(item.title)
                .font(.system(size: primary ? 10.5 : 9.5, weight: .semibold))
                .foregroundStyle(primary ? tint : AppTheme.textSecondary)
                .lineLimit(1)
            Text(item.value)
                .font(.system(size: primary ? 27 : 18, weight: .medium, design: .monospaced))
                .foregroundStyle(tint)
                .minimumScaleFactor(0.72)
                .lineLimit(1)
            Text(item.note)
                .font(.system(size: primary ? 10 : 9))
                .foregroundStyle(AppTheme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(2)
        }
        .padding(primary ? 14 : 11)
        .frame(maxWidth: .infinity, minHeight: primary ? 94 : 106, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 11).fill(tint.opacity(0.045)))
        .overlay(RoundedRectangle(cornerRadius: 11).stroke(tint.opacity(0.16), lineWidth: 1))
    }

    @ViewBuilder
    private var rawFieldsBlock: some View {
        if !content.rawFields.isEmpty {
            VStack(alignment: .leading, spacing: 9) {
                drawerEyebrow(dashboardText("p.help_raw"))
                // One ticking clock for the whole list so the "N s ago" part
                // keeps counting between the ten-second polls. It only drives
                // the freshness lines, and stops when the drawer closes.
                TimelineView(.periodic(from: Date(), by: 1)) { timeline in
                    VStack(alignment: .leading, spacing: 9) {
                        ForEach(content.rawFields) { field in
                            rawFieldRow(field, now: timeline.date)
                        }
                    }
                }
            }
        }
    }

    private func rawFieldRow(_ field: MetricRawField, now: Date) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(field.localizedExplanation)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AppTheme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(field.name)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(AppTheme.textTertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.68)
                    .allowsTightening(true)
                    .textSelection(.enabled)
                if let freshness = MetricFieldFreshness.text(for: field, cardReadAt: content.readAt, now: now) {
                    Text(freshness)
                        .font(.system(size: 9))
                        .foregroundStyle(AppTheme.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text([field.value, field.unit].filter { !$0.isEmpty }.joined(separator: " "))
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(AppTheme.chargingCyan)
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
                .minimumScaleFactor(0.72)
                .textSelection(.enabled)
                .frame(maxWidth: 145, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 8).fill(AppTheme.contrastOverlay(0.025)))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(AppTheme.contrastOverlay(0.065), lineWidth: 1))
    }

    private var formulaBlock: some View {
        VStack(alignment: .leading, spacing: 9) {
            drawerEyebrow(dashboardText("p.help_formula"))
            formulaText(content.formula, tint: AppTheme.accentPurple)
            drawerEyebrow(dashboardText("p.help_substitution"))
                .padding(.top, 3)
            formulaText(content.substitution, tint: AppTheme.chargingCyan)
        }
    }

    private var sourceBlock: some View {
        VStack(alignment: .leading, spacing: 9) {
            drawerEyebrow(dashboardText("p.help_source"))
            Text(content.source)
                .font(.system(size: 11.5))
                .foregroundStyle(AppTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(3)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 9).fill(AppTheme.batteryYellow.opacity(0.04)))
                .overlay(RoundedRectangle(cornerRadius: 9).stroke(AppTheme.batteryYellow.opacity(0.14), lineWidth: 1))
        }
    }

    private func drawerEyebrow(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 9, weight: .medium, design: .monospaced))
            .tracking(1)
            .foregroundStyle(AppTheme.textTertiary)
    }

    private func formulaText(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(AppTheme.textPrimary)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
            .lineSpacing(4)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 8).fill(tint.opacity(0.055)))
            .overlay(alignment: .leading) { Rectangle().fill(tint).frame(width: 2) }
    }
}

/// Resolve dashboard copy exclusively from generated language packs. The built-in
/// English pack is the runtime fallback when the selected language lacks a key.
func dashboardText(
    _ key: String,
    replacements: [String: String] = [:]
) -> String {
    dashboardNativeText(L(key), replacements: replacements)
}

/// Prototype copy occasionally contains small HTML fragments and named
/// placeholders. Native SwiftUI text must never expose those implementation
/// details, so normalize them at the localization boundary.
private func dashboardNativeText(_ source: String, replacements: [String: String]) -> String {
    var result = source
    // A dashboard redraw makes hundreds of these calls, and almost none of the
    // shipped copy contains markup — the seven scans below (six of them
    // case-insensitive, so ICU case folding) were pure waste on every one of
    // them. One cheap probe for the only two characters that can start a
    // fragment cuts the string cost of a full page redraw roughly in half.
    if source.contains("<") || source.contains("&") {
        result = result
            .replacingOccurrences(of: "<br>", with: "\n", options: .caseInsensitive)
            .replacingOccurrences(of: "<br/>", with: "\n", options: .caseInsensitive)
            .replacingOccurrences(of: "<br />", with: "\n", options: .caseInsensitive)
            .replacingOccurrences(of: "<strong>", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "</strong>", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "&nbsp;", with: " ", options: .caseInsensitive)
            .replacingOccurrences(of: "&amp;", with: "&", options: .caseInsensitive)
    }

    guard !replacements.isEmpty else { return result }
    for (name, value) in replacements {
        result = result.replacingOccurrences(of: "{\(name)}", with: value)
    }
    return result
}
