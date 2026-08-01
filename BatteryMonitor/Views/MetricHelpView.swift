import SwiftUI

/// A lowest-level field that participates in a displayed metric.
struct MetricRawField: Identifiable, Equatable {
    let name: String
    let value: String
    var unit: String = ""

    var id: String { "\(name)|\(value)|\(unit)" }
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
        VStack(alignment: .leading, spacing: 6) {
            drawerEyebrow(dashboardText("p.help_current", fallback: "当前结果"))
            Text(content.result)
                .font(.system(size: 27, weight: .medium, design: .monospaced))
                .foregroundStyle(AppTheme.chargingCyan)
                .minimumScaleFactor(0.75)
                .lineLimit(2)
        }
        .padding(15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(AppTheme.chargingCyan.opacity(0.045)))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(AppTheme.chargingCyan.opacity(0.15), lineWidth: 1))
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
