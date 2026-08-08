import SwiftUI

// MARK: - Complete hardware evidence table

/// One row in the 74-metric evidence table.  The compact table keeps the most
/// useful comparison visible, while every row's question mark opens the exact
/// raw fields, formula, substitution and reliability evidence.
struct CompleteHardwareMetric: Identifiable {
    let id: String
    let field: String
    let value: String
    let unit: String
    let meaning: String
    let referenceRange: String
    let reliability: FieldReliability
    let usage: String
    let valueStars: Int
    let note: String
    let rawFields: [MetricRawField]
    let formula: String
    let substitution: String
    /// Read time of the snapshot this row was built from, carrying whether it is
    /// the gauge's own publish moment or merely our poll.
    var readAt: MetricReadStamp? = nil

    var searchableText: String {
        [field, value, unit, meaning, referenceRange, usage, note]
            .joined(separator: " ")
            .localizedLowercase
    }

    var help: MetricHelpContent {
        let starText = valueStars > 0 ? String(repeating: "★", count: valueStars) : "—"
        let origin: String
        if field == "ModelDesignEnergy" {
            origin = hardwareText("p.help_origin_model")
        } else if reliability == .derived || field.hasPrefix("→") {
            origin = hardwareText("p.help_origin_derived")
        } else {
            origin = hardwareText("p.help_origin_iokit")
        }
        return MetricHelpContent(
            id: "hardware.\(id)",
            title: meaning,
            summary: note.isEmpty ? meaning : note,
            result: [value, unit].filter { !$0.isEmpty }.joined(separator: " "),
            rawFields: rawFields,
            formula: formula,
            substitution: substitution,
            source: "\(origin) · \(L(reliability.labelKey)) · \(usage) · \(hardwareText("hw.column.product_value")) \(starText) · \(referenceRange)",
            readAt: readAt
        )
    }
}

struct CompleteHardwareGroup: Identifiable {
    let id: String
    let title: String
    let summary: String
    let metrics: [CompleteHardwareMetric]
}

/// The finalized prototype's last section, migrated to native SwiftUI.
/// The dense evidence starts collapsed to keep the main consumer story fast and
/// readable, but the user's attached dictionary is never pruned: one disclosure
/// reveals every raw and derived metric in the same bottom section.
struct CompleteHardwareDetailView: View {
    let data: BatteryData
    @Binding var selectedHelp: MetricHelpContent?

    @State private var expanded = false
    @State private var searchText = ""
    @State private var collapsedGroups: Set<String> = []

    private var groups: [CompleteHardwareGroup] {
        CompleteHardwareMetricCatalog.build(data)
    }

    /// Keep the collapsed first paint cheap. Building the complete catalog also
    /// builds 74 help sheets and localized explanations, so do that only after
    /// the user expands the bottom section.
    private let totalCount = 74

    private var filteredGroups: [CompleteHardwareGroup] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).localizedLowercase
        guard !query.isEmpty else { return groups }
        return groups.compactMap { group in
            let metrics = group.metrics.filter {
                $0.searchableText.contains(query)
                    || group.title.localizedLowercase.contains(query)
                    || group.summary.localizedLowercase.contains(query)
            }
            return metrics.isEmpty ? nil : CompleteHardwareGroup(
                id: group.id, title: group.title, summary: group.summary, metrics: metrics
            )
        }
    }

    private var visibleCount: Int {
        filteredGroups.reduce(0) { $0 + $1.metrics.count }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: expanded ? 16 : 0) {
            titleBar

            if expanded {
                intro
                searchBar

                if filteredGroups.isEmpty {
                    emptyState
                } else {
                    ScrollView(.horizontal, showsIndicators: true) {
                        VStack(alignment: .leading, spacing: 5) {
                            wideHeader
                            ForEach(filteredGroups) { group in
                                groupView(group)
                            }
                        }
                        .frame(minWidth: 1080)
                    }
                }
            }
        }
        .padding(22)
        .modifier(AppTheme.card())
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.xl, style: .continuous)
                .stroke(AppTheme.accentPurple.opacity(expanded ? 0.22 : 0.10), lineWidth: 1)
        )
    }

    private var titleBar: some View {
        Button {
            withAnimation(.spring(response: 0.38, dampingFraction: 0.86)) {
                expanded.toggle()
            }
        } label: {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(AppTheme.accentPurple.opacity(0.11))
                    Image(systemName: "cpu")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(AppTheme.accentPurple)
                }
                .frame(width: 34, height: 34)

                VStack(alignment: .leading, spacing: 3) {
                    Text(hardwareText("p.geek"))
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(AppTheme.textPrimary)
                    Text(hardwareText("p.hw_intro_title"))
                        .font(.system(size: 10.5))
                        .foregroundStyle(AppTheme.textTertiary)
                }

                Text("\(totalCount)")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(AppTheme.accentPurple)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(AppTheme.accentPurple.opacity(0.09)))

                Spacer()

                Text(data.hardwareDetail.architecture.rawValue)
                    .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                    .foregroundStyle(AppTheme.chargingCyan)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(AppTheme.chargingCyan.opacity(0.08)))

                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(AppTheme.textTertiary)
                    .rotationEffect(.degrees(expanded ? 180 : 0))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pointerOnHover()
    }

    private var intro: some View {
        Text(hardwareText("p.hw_intro_body"
        ).hardwarePlainText)
        .font(.system(size: 11.5))
        .foregroundStyle(AppTheme.textSecondary)
        .fixedSize(horizontal: false, vertical: true)
        .lineSpacing(4)
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 11).fill(AppTheme.accentPurple.opacity(0.035)))
        .overlay(RoundedRectangle(cornerRadius: 11).stroke(AppTheme.accentPurple.opacity(0.10), lineWidth: 1))
    }

    private var searchBar: some View {
        HStack(spacing: 9) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(AppTheme.textTertiary)
            TextField(hardwareText("p.hw_search"), text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 11.5))
                .foregroundStyle(AppTheme.textPrimary)
            if !searchText.isEmpty {
                Button { searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(AppTheme.textTertiary)
                }
                .buttonStyle(.plain)
                .pointerOnHover()
            }
            Text("\(visibleCount) / \(totalCount)")
                .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                .foregroundStyle(AppTheme.textTertiary)
        }
        .padding(.horizontal, 12)
        .frame(height: 36)
        .background(RoundedRectangle(cornerRadius: 9).fill(AppTheme.surfaceSunken))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(AppTheme.contrastOverlay(0.07), lineWidth: 1))
    }

    private var wideHeader: some View {
        HStack(spacing: 9) {
            headerCell(L("hw.field"), width: 232)
            headerCell(L("hw.value"), width: 145)
            headerCell(L("hw.unit"), width: 86)
            headerCell(L("hw.meaning"), width: nil)
            headerCell(hardwareText("p.range"), width: 170)
            headerCell(hardwareText("hw.column.usage"), width: 82)
            headerCell(hardwareText("hw.column.value"), width: 46)
            headerCell(L("hw.rel"), width: 32)
            Color.clear.frame(width: 22, height: 1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 7).fill(AppTheme.contrastOverlay(0.025)))
    }

    private func headerCell(_ text: String, width: CGFloat?) -> some View {
        Text(text.uppercased())
            .font(.system(size: 8.5, weight: .semibold, design: .monospaced))
            .tracking(0.6)
            .foregroundStyle(AppTheme.textTertiary.opacity(0.8))
            .frame(width: width, alignment: .leading)
            .frame(maxWidth: width == nil ? .infinity : nil, alignment: .leading)
    }

    private func groupView(_ group: CompleteHardwareGroup) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    if collapsedGroups.contains(group.id) {
                        collapsedGroups.remove(group.id)
                    } else {
                        collapsedGroups.insert(group.id)
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    Text(group.title)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(AppTheme.chargingCyan)
                    Text("\(group.metrics.count)")
                        .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(AppTheme.chargingCyan.opacity(0.8))
                    Text(group.summary)
                        .font(.system(size: 9.5))
                        .foregroundStyle(AppTheme.textTertiary)
                        .lineLimit(1)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(AppTheme.textTertiary)
                        .rotationEffect(.degrees(collapsedGroups.contains(group.id) ? -90 : 0))
                }
                .padding(.horizontal, 10)
                .padding(.top, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .pointerOnHover()

            if !collapsedGroups.contains(group.id) {
                ForEach(Array(group.metrics.enumerated()), id: \.element.id) { index, metric in
                    metricRow(metric, alternating: index.isMultiple(of: 2))
                }
            }
        }
    }

    private func metricRow(_ metric: CompleteHardwareMetric, alternating: Bool) -> some View {
        HStack(spacing: 9) {
            Text(metric.field)
                .font(.system(size: 9.5, design: .monospaced))
                .foregroundStyle(AppTheme.textSecondary)
                .textSelection(.enabled)
                .lineLimit(2)
                .frame(width: 232, alignment: .leading)
            Text(metric.value)
                .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                .foregroundStyle(metric.value == "—" ? AppTheme.textTertiary : AppTheme.textPrimary)
                .textSelection(.enabled)
                .lineLimit(2)
                .frame(width: 145, alignment: .leading)
            Text(metric.unit)
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(AppTheme.textTertiary)
                .frame(width: 86, alignment: .leading)
            Text(metric.meaning)
                .font(.system(size: 9.5))
                .foregroundStyle(AppTheme.textSecondary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(metric.referenceRange)
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundStyle(AppTheme.chargingCyan.opacity(0.9))
                .lineLimit(2)
                .frame(width: 170, alignment: .leading)
            usageBadge(metric.usage)
                .frame(width: 82, alignment: .leading)
            Text(metric.valueStars > 0 ? String(repeating: "★", count: metric.valueStars) : "—")
                .font(.system(size: 8.5, weight: .medium))
                .foregroundStyle(AppTheme.batteryYellow.opacity(0.85))
                .frame(width: 46, alignment: .leading)
            Text(metric.reliability.badge)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(reliabilityColor(metric.reliability))
                .frame(width: 32)
                .help(L(metric.reliability.labelKey))
            MetricHelpButton(content: metric.help, selection: $selectedHelp)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(minWidth: 1080)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(alternating ? AppTheme.contrastOverlay(0.024) : AppTheme.contrastOverlay(0.012))
        )
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(AppTheme.contrastOverlay(0.035), lineWidth: 1))
    }

    private func compactMetricRow(_ metric: CompleteHardwareMetric) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(metric.field)
                    .font(.system(size: 9.5, design: .monospaced))
                    .foregroundStyle(AppTheme.textSecondary)
                Spacer()
                Text([metric.value, metric.unit].filter { !$0.isEmpty }.joined(separator: " "))
                    .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                    .foregroundStyle(AppTheme.textPrimary)
                MetricHelpButton(content: metric.help, selection: $selectedHelp)
            }
            Text(metric.meaning)
                .font(.system(size: 10))
                .foregroundStyle(AppTheme.textSecondary)
            HStack(spacing: 8) {
                Text(metric.referenceRange)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(AppTheme.chargingCyan)
                Spacer()
                usageBadge(metric.usage)
                Text(metric.reliability.badge)
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(reliabilityColor(metric.reliability))
            }
        }
        .padding(10)
    }

    private func usageBadge(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 8.5, weight: .semibold))
            .foregroundStyle(AppTheme.textSecondary)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Capsule().fill(AppTheme.contrastOverlay(0.045)))
    }

    private func reliabilityColor(_ reliability: FieldReliability) -> Color {
        switch reliability {
        case .verified: return AppTheme.batteryGreen
        case .conditional: return AppTheme.batteryYellow
        case .questionable: return AppTheme.batteryRed
        case .derived: return AppTheme.accentPurple
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 20))
                .foregroundStyle(AppTheme.textTertiary)
            Text(hardwareText("p.hw_no_results"))
                .font(.system(size: 11.5))
                .foregroundStyle(AppTheme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 34)
    }
}

func hardwareText(_ key: String) -> String { L(key) }

private extension String {
    var hardwarePlainText: String {
        replacingOccurrences(of: "<br>", with: "\n")
            .replacingOccurrences(of: "<br/>", with: "\n")
            .replacingOccurrences(of: "<strong>", with: "")
            .replacingOccurrences(of: "</strong>", with: "")
    }
}
