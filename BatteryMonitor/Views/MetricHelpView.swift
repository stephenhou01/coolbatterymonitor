import SwiftUI
import Charts

/// A lowest-level field that participates in a displayed metric.
struct MetricRawField: Identifiable, Equatable {
    let name: String
    let value: String
    var unit: String = ""

    var id: String { "\(name)|\(value)|\(unit)" }
}

enum MetricHelpResultStyle: Equatable {
    case primary
    case stable
    case current

    var tint: Color {
        switch self {
        case .primary: return AppTheme.chargingCyan
        case .stable: return AppTheme.accentPurple
        case .current: return AppTheme.batteryYellow
        }
    }
}

/// A comparison value shown alongside the primary result. Runtime uses this to
/// keep the macOS value visually dominant while exposing two clearly-derived
/// estimates in the same question-mark drawer.
struct MetricHelpResult: Identifiable, Equatable {
    let id: String
    let title: String
    let value: String
    let note: String
    let style: MetricHelpResultStyle
}

struct MetricHelpTrendPoint: Identifiable, Equatable {
    let timestamp: Date
    let watts: Double

    var id: Date { timestamp }
}

/// Consumer-facing explanation of an adapter's negotiated PD contract. The
/// rated contract and the Mac's live input are deliberately kept separate:
/// 20V × 3.25A describes what the adapter can provide, not what the Mac is
/// necessarily drawing at this instant.
struct MetricPowerContract: Equatable {
    let stateTitle: String
    let stateDetail: String
    let isConnected: Bool
    let isNegotiated: Bool
    let voltageLabel: String
    let voltageText: String
    let currentLabel: String
    let currentText: String
    let powerLabel: String
    let powerText: String
    let equationText: String
    let equationNote: String
    let trendTitle: String
    let trendValue: String
    let trendNote: String
    let trendPoints: [MetricHelpTrendPoint]
    let ceilingWatts: Double?
}

/// Content shared by every question-mark affordance on the final dashboard.
/// Keeping the explanation as data lets the same drawer serve top-level answers,
/// formulas, reference rows, and the hardware table.
struct MetricHelpContent: Identifiable, Equatable {
    let id: String
    let title: String
    let summary: String
    let result: String
    let rawFields: [MetricRawField]
    let formula: String
    let substitution: String
    let source: String
    var comparisonResults: [MetricHelpResult] = []
    var powerContract: MetricPowerContract? = nil
}

struct MetricHelpButton: View {
    let content: MetricHelpContent
    @Binding var selection: MetricHelpContent?

    var body: some View {
        Button {
            selection = content
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
        .accessibilityLabel(dashboardText("p.help_open", fallback: "查看定义和计算方法"))
        .help(dashboardText("p.help_open", fallback: "查看定义和计算方法"))
    }
}

/// Window-level trailing drawer. ContentView owns the selection so the panel is
/// not clipped by the dashboard's ScrollView.
struct MetricHelpDrawer: View {
    let content: MetricHelpContent
    let onClose: () -> Void
    @FocusState private var closeFocused: Bool

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
        .onExitCommand(perform: onClose)
        .accessibilityElement(children: .contain)
    }

    private var drawerHeader: some View {
        HStack {
            Text(dashboardText("p.help_title", fallback: "这个指标从哪里来？"))
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .tracking(1.1)
                .foregroundStyle(AppTheme.chargingCyan)
            Spacer()
            Button(action: onClose) {
                Label(dashboardText("p.help_close", fallback: "关闭"), systemImage: "xmark")
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
        VStack(alignment: .leading, spacing: 9) {
            drawerEyebrow(dashboardText("p.help_current", fallback: "当前结果"))

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
                     ? dashboardText("p.adapter_status_ready_badge", fallback: "PD READY")
                     : dashboardText("p.adapter_status_waiting_badge", fallback: "WAITING"))
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

    @ViewBuilder
    private var adapterTrendBlock: some View {
        if let contract = content.powerContract {
            VStack(alignment: .leading, spacing: 9) {
                HStack(alignment: .firstTextBaseline) {
                    drawerEyebrow(contract.trendTitle)
                    Spacer()
                    Text(contract.trendValue)
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(AppTheme.chargingCyan)
                }

                if contract.trendPoints.count >= 2 {
                    Chart {
                        ForEach(contract.trendPoints) { point in
                            AreaMark(
                                x: .value("Time", point.timestamp),
                                yStart: .value("Zero", 0),
                                yEnd: .value("Input power", point.watts)
                            )
                            .foregroundStyle(AppTheme.chargingCyan.opacity(0.08))

                            LineMark(
                                x: .value("Time", point.timestamp),
                                y: .value("Input power", point.watts)
                            )
                            .foregroundStyle(AppTheme.chargingCyan)
                            .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                        }

                        if let ceiling = contract.ceilingWatts, ceiling > 0 {
                            RuleMark(y: .value("Contract ceiling", ceiling))
                                .foregroundStyle(AppTheme.batteryYellow.opacity(0.7))
                                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        }
                    }
                    .chartXAxis {
                        AxisMarks(values: .automatic(desiredCount: 3)) { value in
                            AxisGridLine().foregroundStyle(AppTheme.contrastOverlay(0.04))
                            AxisValueLabel(format: .dateTime.hour().minute())
                                .foregroundStyle(AppTheme.textTertiary)
                        }
                    }
                    .chartYAxis {
                        AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                            AxisGridLine().foregroundStyle(AppTheme.contrastOverlay(0.05))
                            AxisValueLabel {
                                if let watts = value.as(Double.self) {
                                    Text("\(Int(watts.rounded()))W")
                                }
                            }
                            .foregroundStyle(AppTheme.textTertiary)
                        }
                    }
                    .chartYScale(domain: adapterChartDomain(contract))
                    .frame(height: 132)
                } else {
                    HStack(spacing: 9) {
                        Image(systemName: "chart.xyaxis.line")
                            .foregroundStyle(AppTheme.textTertiary)
                        Text(dashboardText("p.adapter_trend_waiting", fallback: "正在积累输入功率历史"))
                            .font(.system(size: 10.5))
                            .foregroundStyle(AppTheme.textTertiary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 72, alignment: .center)
                }

                Text(contract.trendNote)
                    .font(.system(size: 9.5))
                    .foregroundStyle(AppTheme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(2)
            }
            .padding(13)
            .background(RoundedRectangle(cornerRadius: 11).fill(AppTheme.contrastOverlay(0.02)))
            .overlay(RoundedRectangle(cornerRadius: 11).stroke(AppTheme.contrastOverlay(0.07), lineWidth: 1))
        }
    }

    private func adapterChartDomain(_ contract: MetricPowerContract) -> ClosedRange<Double> {
        let peak = contract.trendPoints.map(\.watts).max() ?? 0
        let upper = max(max(contract.ceilingWatts ?? 0, peak), 1) * 1.08
        return 0...upper
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
                drawerEyebrow(dashboardText("p.help_raw", fallback: "最底层输入字段"))
                ForEach(content.rawFields) { field in
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(field.name)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(AppTheme.textSecondary)
                            .textSelection(.enabled)
                        Spacer(minLength: 8)
                        Text([field.value, field.unit].filter { !$0.isEmpty }.joined(separator: " "))
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundStyle(AppTheme.textPrimary)
                            .multilineTextAlignment(.trailing)
                            .textSelection(.enabled)
                    }
                    .padding(11)
                    .background(RoundedRectangle(cornerRadius: 8).fill(AppTheme.contrastOverlay(0.025)))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(AppTheme.contrastOverlay(0.065), lineWidth: 1))
                }
            }
        }
    }

    private var formulaBlock: some View {
        VStack(alignment: .leading, spacing: 9) {
            drawerEyebrow(dashboardText("p.help_formula", fallback: "公式"))
            formulaText(content.formula, tint: AppTheme.accentPurple)
            drawerEyebrow(dashboardText("p.help_substitution", fallback: "代入这台电脑的数值"))
                .padding(.top, 3)
            formulaText(content.substitution, tint: AppTheme.chargingCyan)
        }
    }

    private var sourceBlock: some View {
        VStack(alignment: .leading, spacing: 9) {
            drawerEyebrow(dashboardText("p.help_source", fallback: "来源与可靠性"))
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

/// The prototype adds many new keys while the native language packs are being
/// migrated in parallel. Falling back here keeps the UI readable during that
/// migration and automatically yields to the selected language once a key lands.
func dashboardText(
    _ key: String,
    fallback: String,
    replacements: [String: String] = [:]
) -> String {
    let localized = L(key)
    let source = localized == key ? fallback : localized
    return dashboardNativeText(source, replacements: replacements)
}

/// Prototype copy occasionally contains small HTML fragments and named
/// placeholders. Native SwiftUI text must never expose those implementation
/// details, so normalize them at the localization boundary.
private func dashboardNativeText(_ source: String, replacements: [String: String]) -> String {
    var result = source
        .replacingOccurrences(of: "<br>", with: "\n", options: .caseInsensitive)
        .replacingOccurrences(of: "<br/>", with: "\n", options: .caseInsensitive)
        .replacingOccurrences(of: "<br />", with: "\n", options: .caseInsensitive)
        .replacingOccurrences(of: "<strong>", with: "", options: .caseInsensitive)
        .replacingOccurrences(of: "</strong>", with: "", options: .caseInsensitive)
        .replacingOccurrences(of: "&nbsp;", with: " ", options: .caseInsensitive)
        .replacingOccurrences(of: "&amp;", with: "&", options: .caseInsensitive)

    for (name, value) in replacements {
        result = result.replacingOccurrences(of: "{\(name)}", with: value)
    }
    return result
}
