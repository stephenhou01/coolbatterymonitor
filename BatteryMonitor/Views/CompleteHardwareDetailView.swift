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

    var searchableText: String {
        [field, value, unit, meaning, referenceRange, usage, note]
            .joined(separator: " ")
            .localizedLowercase
    }

    var help: MetricHelpContent {
        let starText = valueStars > 0 ? String(repeating: "★", count: valueStars) : "—"
        let origin: String
        if field == "ModelDesignEnergy" {
            origin = hardwareText("p.help_origin_model", "按 hw.model 匹配 Apple 机型公开规格")
        } else if reliability == .derived || field.hasPrefix("→") {
            origin = hardwareText("p.help_origin_derived", "由上方列出的原始字段推导")
        } else {
            origin = hardwareText("p.help_origin_iokit", "AppleSmartBattery IOKit 实时快照")
        }
        return MetricHelpContent(
            id: "hardware.\(id)",
            title: meaning,
            summary: note.isEmpty ? meaning : note,
            result: [value, unit].filter { !$0.isEmpty }.joined(separator: " "),
            rawFields: rawFields,
            formula: formula,
            substitution: substitution,
            source: "\(origin) · \(L(reliability.labelKey)) · \(usage) · \(hardwareText("hw.column.product_value", "产品价值")) \(starText) · \(referenceRange)"
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
                    Text(hardwareText("p.geek", "完整硬件参数与逐项解释"))
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(AppTheme.textPrimary)
                    Text(hardwareText("p.hw_intro_title", "所有底层证据都在这里"))
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
        Text(hardwareText(
            "p.hw_intro_body",
            "附件清单中的全部原始指标都保留，并补充机型公开规格与必要推导。0 是有效读数；只有系统没有返回字段时才显示 —。"
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
            TextField(hardwareText("p.hw_search", "搜索字段、数值、含义或注意事项"), text: $searchText)
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
        .background(RoundedRectangle(cornerRadius: 9).fill(Color.black.opacity(0.18)))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(Color.white.opacity(0.07), lineWidth: 1))
    }

    private var wideHeader: some View {
        HStack(spacing: 9) {
            headerCell(L("hw.field"), width: 232)
            headerCell(L("hw.value"), width: 145)
            headerCell(L("hw.unit"), width: 86)
            headerCell(L("hw.meaning"), width: nil)
            headerCell(hardwareText("p.range", "参考范围"), width: 170)
            headerCell(hardwareText("hw.column.usage", "当前用途"), width: 82)
            headerCell(hardwareText("hw.column.value", "价值"), width: 46)
            headerCell(L("hw.rel"), width: 32)
            Color.clear.frame(width: 22, height: 1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 7).fill(Color.white.opacity(0.025)))
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
                .fill(alternating ? Color.white.opacity(0.024) : Color.white.opacity(0.012))
        )
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.white.opacity(0.035), lineWidth: 1))
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
            .background(Capsule().fill(Color.white.opacity(0.045)))
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
            Text(hardwareText("p.hw_no_results", "没有匹配的硬件指标"))
                .font(.system(size: 11.5))
                .foregroundStyle(AppTheme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 34)
    }
}

private func hardwareText(_ key: String, _ fallback: String) -> String {
    let value = L(key)
    return value == key ? fallback : value
}

private extension String {
    var hardwarePlainText: String {
        replacingOccurrences(of: "<br>", with: "\n")
            .replacingOccurrences(of: "<br/>", with: "\n")
            .replacingOccurrences(of: "<strong>", with: "")
            .replacingOccurrences(of: "</strong>", with: "")
    }
}

// MARK: - 74-row catalog

enum CompleteHardwareMetricCatalog {
    static func build(_ data: BatteryData) -> [CompleteHardwareGroup] {
        let d = data.hardwareDetail
        let spec = data.modelSpecification

        func intText(_ value: Int?, grouped: Bool = false) -> String {
            guard let value else { return "—" }
            return grouped ? value.formatted() : String(value)
        }

        func rawIntText(_ field: String, _ value: Int, grouped: Bool = false) -> String {
            guard d.presentRawFields.contains(field) else { return "—" }
            return grouped ? value.formatted() : String(value)
        }

        func rawDoubleText(_ field: String, _ value: Double, format: String = "%.1f") -> String {
            guard d.presentRawFields.contains(field), value.isFinite else { return "—" }
            return LNum(format, value)
        }

        func rawStringText(_ field: String, _ value: String) -> String {
            guard d.presentRawFields.contains(field) else { return "—" }
            return value.isEmpty ? "\"\"" : value
        }

        func int64Text(_ value: Int64?) -> String {
            value.map { $0.formatted() } ?? "—"
        }

        func doubleText(_ value: Double?, format: String = "%.1f") -> String {
            guard let value, value.isFinite else { return "—" }
            return LNum(format, value)
        }

        func arrayText(_ value: [Int]?) -> String {
            guard let value, !value.isEmpty else { return "—" }
            return value.map(String.init).joined(separator: " / ")
        }

        func rawArrayText(_ field: String, _ value: [Int]) -> String {
            guard d.presentRawFields.contains(field) else { return "—" }
            return value.isEmpty ? "[]" : value.map(String.init).joined(separator: " / ")
        }

        func boolText(_ value: Bool?) -> String {
            guard let value else { return "—" }
            return value ? "true" : "false"
        }

        func timeText(_ value: Int?) -> String {
            guard let value, (1...65_534).contains(value) else { return "—" }
            return value.formatted()
        }

        func text(_ key: String, _ fallback: String) -> String {
            hardwareText(key, fallback)
        }

        let usePrimary = text("hw.usage.primary", "核心展示")
        let useCalculation = text("hw.usage.calculation", "参与计算")
        let useDiagnosis = text("hw.usage.diagnosis", "诊断依据")
        let useTable = text("hw.usage.table", "底表展示")
        let useGuarded = text("hw.usage.guarded", "仅作参考")
        let useUnused = text("hw.usage.unused", "不用于结论")

        func metric(
            _ group: String,
            _ field: String,
            _ value: String,
            _ unit: String,
            _ meaningKey: String,
            _ meaningFallback: String,
            reliability: FieldReliability = .verified,
            usage: String = useTable,
            stars: Int = 1,
            noteKey: String? = nil,
            noteFallback: String = "",
            rawFields: [MetricRawField]? = nil,
            formula: String? = nil,
            substitution: String? = nil
        ) -> CompleteHardwareMetric {
            let meaning = text(meaningKey, meaningFallback)
            let note = noteKey.map { text($0, noteFallback.isEmpty ? meaning : noteFallback) }
                ?? (noteFallback.isEmpty ? meaning : noteFallback)
            let raw = rawFields ?? [MetricRawField(name: field, value: value, unit: unit)]
            let f = formula ?? "IOKit → \(field)"
            let s = substitution ?? "\(field) → \(value)\(unit.isEmpty ? "" : " \(unit)")"
            return CompleteHardwareMetric(
                id: "\(group).\(field)",
                field: field,
                value: value,
                unit: unit,
                meaning: meaning,
                referenceRange: referenceRange(field: field, data: data),
                reliability: reliability,
                usage: usage,
                valueStars: min(max(stars, 0), 3),
                note: note,
                rawFields: raw,
                formula: f,
                substitution: s
            )
        }

        let modelIdentifier = data.modelIdentifier.isEmpty ? BatteryService.hardwareModel() : data.modelIdentifier
        let designWh = spec?.designEnergyWh
        let currentFullWh = data.currentFullEnergyWh
        let healthSystem = data.systemHealthPercent
        let healthRaw = d.rawHealthPercent
        let unusable = d.unusableCharge
        let usedSinceFull = d.usedSinceFullCapacity
        let permanentChemicalLoss = d.permanentChemicalLoss
        let deficit = d.chargeDeficitTotal

        let capacity = [
            metric("capacity", "DesignCapacity", rawIntText("DesignCapacity", d.designCapacity, grouped: true), "mAh",
                   "hw.m.design_capacity", "出厂设计容量", usage: useCalculation, stars: 2),
            metric("capacity", "ModelDesignEnergy", doubleText(designWh, format: "%.1f"), "Wh",
                   "hw.m.model_design_energy", "机型额定设计能量", reliability: .conditional,
                   usage: useCalculation, stars: 3, noteKey: "hw.n.model_design_energy",
                   noteFallback: "按系统机型标识匹配 Apple 公开规格，不由当前电压反推。",
                   rawFields: [
                    .init(name: "hw.model", value: modelIdentifier),
                    .init(name: "Apple published model specification", value: doubleText(designWh, format: "%.1f"), unit: "Wh")
                   ], formula: "hw.model → Apple published battery specification",
                   substitution: "\(modelIdentifier) → \(doubleText(designWh, format: "%.1f")) Wh"),
            metric("capacity", "AppleRawMaxCapacity", rawIntText("AppleRawMaxCapacity", d.appleRawMaxCapacity, grouped: true), "mAh",
                   "hw.m.raw_max", "当前实测满充容量", usage: usePrimary, stars: 3,
                   noteKey: "hw.n.raw_max", noteFallback: "电池当前充满后真正可用的容量，是衰减判断的核心读数。"),
            metric("capacity", "BatteryData.FccComp1 / FccComp2",
                   "\(intText(d.fccComp1)) / \(intText(d.fccComp2))", "mAh",
                   "hw.m.fcc_comp", "满充容量补偿副本", usage: useGuarded, stars: 1,
                   noteKey: "hw.n.fcc_comp", noteFallback: "与 AppleRawMaxCapacity 交叉核验，本机通常相同。",
                   rawFields: [
                    .init(name: "BatteryData.FccComp1", value: intText(d.fccComp1), unit: "mAh"),
                    .init(name: "BatteryData.FccComp2", value: intText(d.fccComp2), unit: "mAh")
                   ]),
            metric("capacity", "AppleRawCurrentCapacity", rawIntText("AppleRawCurrentCapacity", d.appleRawCurrentCapacity, grouped: true), "mAh",
                   "hw.m.raw_current", "当前剩余电量", usage: useCalculation, stars: 2,
                   noteKey: "hw.n.raw_current", noteFallback: "当前真实电荷量；配合机型设计能量折算剩余 Wh。"),
            metric("capacity", "CurrentCapacity", intText(d.currentCapacityRaw), "%",
                   "hw.m.current_capacity", "系统显示电量百分比", usage: usePrimary, stars: 2,
                   noteKey: "hw.n.current_capacity", noteFallback: "这是 macOS 用户口径；容量计算使用 AppleRawCurrentCapacity。"),
            metric("capacity", "NominalChargeCapacity", rawIntText("NominalChargeCapacity", d.nominalChargeCapacity, grouped: true), "mAh",
                   "hw.m.nominal", "标称容量", usage: useGuarded, stars: 2,
                   noteKey: "hw.n.nominal_relation",
                   noteFallback: "用于与满充容量和系统预留量交叉核验，不直接参与主界面健康度公式。",
                   rawFields: [
                    .init(name: "NominalChargeCapacity", value: rawIntText("NominalChargeCapacity", d.nominalChargeCapacity), unit: "mAh"),
                    .init(name: "AppleRawMaxCapacity", value: rawIntText("AppleRawMaxCapacity", d.appleRawMaxCapacity), unit: "mAh"),
                    .init(name: "PackReserve", value: rawIntText("PackReserve", d.packReserve), unit: "mAh")
                   ], formula: "NominalChargeCapacity = AppleRawMaxCapacity + PackReserve",
                   substitution: "\(rawIntText("AppleRawMaxCapacity", d.appleRawMaxCapacity)) + \(rawIntText("PackReserve", d.packReserve)) = \(rawIntText("NominalChargeCapacity", d.nominalChargeCapacity)) mAh"),
            metric("capacity", "PackReserve", rawIntText("PackReserve", d.packReserve), "mAh",
                   "hw.m.reserve", "系统保留缓冲容量", usage: useCalculation, stars: 3,
                   noteKey: "hw.n.reserve", noteFallback: "不向用户电量百分比开放的缓冲容量；健康度对齐公式只在当前机器反向校验过。"),
            metric("capacity", "MaxCapacity", intText(d.maxCapacityRaw), "% / mAh",
                   "hw.m.max_capacity_raw", "平台相关的 MaxCapacity 原始值", reliability: .conditional,
                   usage: useGuarded, stars: 1, noteKey: "hw.n.max_capacity_raw",
                   noteFallback: "Apple Silicon 上常是百分比，Intel 上也可能是 mAh，不能直接混用。"),
            metric("capacity", "CycleCount", rawIntText("CycleCount", d.cycleCount), "count",
                   "hw.m.cycles", "充放电循环数", usage: usePrimary, stars: 3),
            metric("capacity", "DesignCycleCount9C", rawIntText("DesignCycleCount9C", d.designCycleCount, grouped: true), "count",
                   "hw.m.design_cycles", "额定循环寿命", usage: useCalculation, stars: 3,
                   noteKey: "hw.n.design_cycles", noteFallback: "剩余寿命基准应以额定循环数为主，不线性外推容量衰减。"),
            metric("capacity", "BatteryData.Qmax", rawArrayText("BatteryData.Qmax", d.qmax), "mAh",
                   "hw.m.qmax", "各电芯库仑计实测最大容量", usage: useDiagnosis, stars: 2,
                   noteKey: "hw.n.qmax", noteFallback: "串联电芯以最弱一节限制整包；变化趋势可反映电芯学习结果。"),
            metric("capacity", "→ current full energy", doubleText(currentFullWh, format: "%.2f"), "Wh",
                   "hw.m.current_full_energy", "当前满充能量（折算）", reliability: .derived,
                   usage: useCalculation, stars: 2, noteKey: "hw.n.current_full_energy",
                   noteFallback: "用机型设计 Wh 按当前满充容量比例缩放。",
                   rawFields: [
                    .init(name: "ModelDesignEnergy", value: doubleText(designWh, format: "%.1f"), unit: "Wh"),
                    .init(name: "AppleRawMaxCapacity", value: rawIntText("AppleRawMaxCapacity", d.appleRawMaxCapacity), unit: "mAh"),
                    .init(name: "DesignCapacity", value: rawIntText("DesignCapacity", d.designCapacity), unit: "mAh")
                   ], formula: "currentFullWh = modelDesignWh × AppleRawMaxCapacity ÷ DesignCapacity",
                   substitution: "\(doubleText(designWh, format: "%.1f")) × \(d.appleRawMaxCapacity) ÷ \(d.designCapacity) = \(doubleText(currentFullWh, format: "%.2f")) Wh"),
            metric("capacity", "→ health (system)", doubleText(healthSystem, format: "%.1f"), "%",
                   "hw.m.health_system", "系统对齐健康度", reliability: .derived,
                   usage: usePrimary, stars: 2, noteKey: "hw.n.health_system",
                   noteFallback: "这是对本机系统显示反向校验的口径，不代表 Apple 公开公式。",
                   rawFields: [
                    .init(name: "AppleRawMaxCapacity", value: rawIntText("AppleRawMaxCapacity", d.appleRawMaxCapacity), unit: "mAh"),
                    .init(name: "PackReserve", value: rawIntText("PackReserve", d.packReserve), unit: "mAh"),
                    .init(name: "DesignCapacity", value: rawIntText("DesignCapacity", d.designCapacity), unit: "mAh")
                   ], formula: "health = (FCC + reserve) ÷ (design − reserve) × 100",
                   substitution: "(\(d.appleRawMaxCapacity) + \(d.packReserve)) ÷ (\(d.designCapacity) − \(d.packReserve)) × 100 = \(doubleText(healthSystem, format: "%.1f"))%"),
            metric("capacity", "→ health (raw)", doubleText(healthRaw, format: "%.1f"), "%",
                   "hw.m.health_raw", "直接容量保持率", reliability: .derived,
                   usage: useDiagnosis, stars: 3, noteKey: "hw.n.health_raw",
                   noteFallback: "用于看长期变化时应始终使用同一口径。",
                   rawFields: [
                    .init(name: "AppleRawMaxCapacity", value: rawIntText("AppleRawMaxCapacity", d.appleRawMaxCapacity), unit: "mAh"),
                    .init(name: "DesignCapacity", value: rawIntText("DesignCapacity", d.designCapacity), unit: "mAh")
                   ], formula: "rawHealth = AppleRawMaxCapacity ÷ DesignCapacity × 100",
                   substitution: "\(d.appleRawMaxCapacity) ÷ \(d.designCapacity) × 100 = \(doubleText(healthRaw, format: "%.1f"))%"),
            metric("capacity", "→ Qmax − FCC", intText(unusable), "mAh",
                   "hw.m.unusable", "化学上仍在但当前取不出来的容量", reliability: .derived,
                   usage: useDiagnosis, stars: 3, noteKey: "hw.n.unusable",
                   noteFallback: "Qmax 与 FCC 都来自电量计；这是两个读数相减后的解释性推导。",
                   rawFields: [
                    .init(name: "BatteryData.Qmax.min", value: intText(d.qmax.min()), unit: "mAh"),
                    .init(name: "AppleRawMaxCapacity", value: rawIntText("AppleRawMaxCapacity", d.appleRawMaxCapacity), unit: "mAh")
                   ], formula: "unusable = min(Qmax cells) − FCC",
                   substitution: "\(intText(d.qmax.min())) − \(d.appleRawMaxCapacity) = \(intText(unusable)) mAh"),
            metric("capacity", "→ deficit total", intText(deficit), "mAh",
                   "hw.m.deficit_total", "设计容量与当前满充的总差额", reliability: .derived,
                   usage: useDiagnosis, stars: 2, noteKey: "hw.n.deficit_total",
                   noteFallback: "Design − FCC；这是消费者看到的长期容量差，不应再与本次已用电量混在一起。",
                   rawFields: [
                    .init(name: "DesignCapacity", value: rawIntText("DesignCapacity", d.designCapacity), unit: "mAh"),
                    .init(name: "AppleRawMaxCapacity", value: rawIntText("AppleRawMaxCapacity", d.appleRawMaxCapacity), unit: "mAh")
                   ], formula: "totalDeficit = DesignCapacity − AppleRawMaxCapacity",
                   substitution: "\(d.designCapacity) − \(d.appleRawMaxCapacity) = \(intText(deficit)) mAh"),
            metric("capacity", "→ FCC − current", intText(usedSinceFull), "mAh",
                   "p.used_since_full", "本次已经用掉", reliability: .derived,
                   usage: useCalculation, stars: 3, noteKey: "hw.n.used_since_full",
                   noteFallback: "从本次充满到现在已经用掉的电；再次充电可以补回来，它不是老化。",
                   rawFields: [
                    .init(name: "AppleRawMaxCapacity", value: rawIntText("AppleRawMaxCapacity", d.appleRawMaxCapacity), unit: "mAh"),
                    .init(name: "AppleRawCurrentCapacity", value: rawIntText("AppleRawCurrentCapacity", d.appleRawCurrentCapacity), unit: "mAh")
                   ], formula: "usedSinceFull = AppleRawMaxCapacity − AppleRawCurrentCapacity",
                   substitution: "\(d.appleRawMaxCapacity) − \(d.appleRawCurrentCapacity) = \(intText(usedSinceFull)) mAh"),
            metric("capacity", "→ Design − min(Qmax)", intText(permanentChemicalLoss), "mAh",
                   "p.permanent_loss", "真正老化掉的容量", reliability: .derived,
                   usage: useDiagnosis, stars: 3, noteKey: "hw.n.permanent_chemical",
                   noteFallback: "只有 Qmax 有效且落在合理边界时才拆出这部分；否则只显示设计容量与当前满充的总差额。",
                   rawFields: [
                    .init(name: "DesignCapacity", value: rawIntText("DesignCapacity", d.designCapacity), unit: "mAh"),
                    .init(name: "BatteryData.Qmax.min", value: intText(d.learnedChemicalCapacity), unit: "mAh")
                   ], formula: "permanentChemicalLoss = DesignCapacity − min(Qmax cells)",
                   substitution: "\(d.designCapacity) − \(intText(d.learnedChemicalCapacity)) = \(intText(permanentChemicalLoss)) mAh")
        ]

        let dischargeRuntimeValue = data.isOnAC
            ? "—"
            : "\(timeText(d.timeRemainingRaw)) / \(timeText(d.avgTimeToEmpty))"
        let chargeRuntimeValue = data.isCharging ? timeText(d.avgTimeToFull) : "—"
        let runtime = [
            metric("runtime", "TimeRemaining / AvgTimeToEmpty",
                   dischargeRuntimeValue, "min",
                   "hw.m.time_remaining", "电量计剩余时间预测", usage: usePrimary, stars: 3,
                   noteKey: "hw.n.time_remaining", noteFallback: "直接采用系统电量计读数；65535 是未就绪哨兵，不是分钟数。",
                   rawFields: [
                    .init(name: "TimeRemaining", value: intText(d.timeRemainingRaw), unit: "min raw"),
                    .init(name: "AvgTimeToEmpty", value: intText(d.avgTimeToEmpty), unit: "min raw")
                   ], formula: "valid(value) when 1 ≤ value ≤ 65,534; otherwise unavailable",
                   substitution: "TimeRemaining \(intText(d.timeRemainingRaw)) / AvgTimeToEmpty \(intText(d.avgTimeToEmpty))"),
            metric("runtime", "AvgTimeToFull", chargeRuntimeValue, "min",
                   "hw.m.time_to_full", "预计充满剩余时间", reliability: .conditional,
                   usage: useTable, stars: 2, noteKey: "hw.n.time_to_full",
                   noteFallback: "仅充电且算法就绪时有效；65535 表示不适用或未就绪。",
                   rawFields: [.init(name: "AvgTimeToFull", value: intText(d.avgTimeToFull), unit: "min raw")],
                   formula: "valid(value) when charging and value < 65,535",
                   substitution: "AvgTimeToFull = \(intText(d.avgTimeToFull))"),
            metric("runtime", "BatteryInvalidWakeSeconds", intText(d.batteryInvalidWakeSeconds), "s",
                   "hw.m.invalid_wake", "唤醒后估算保护窗", usage: useTable, stars: 1,
                   noteKey: "hw.n.invalid_wake", noteFallback: "刚唤醒的这段时间内，系统续航估算可能尚未稳定。")
        ]

        let cells = [
            metric("cells", "BatteryData.CellVoltage", rawArrayText("BatteryData.CellVoltage", d.cellVoltages), "mV",
                   "hw.m.cell_voltage", "各电芯电压", usage: useDiagnosis, stars: 3,
                   noteKey: "hw.n.cell_voltage", noteFallback: "最大值减最小值是电芯一致性的敏感指标。"),
            metric("cells", "→ CellVoltage.delta", intText(d.cellVoltageDelta), "mV",
                   "hw.m.cell_delta", "各电芯最大压差", reliability: .derived,
                   usage: useDiagnosis, stars: 3,
                   rawFields: [.init(name: "BatteryData.CellVoltage", value: rawArrayText("BatteryData.CellVoltage", d.cellVoltages), unit: "mV")],
                   formula: "delta = max(CellVoltage) − min(CellVoltage)",
                   substitution: "max − min = \(intText(d.cellVoltageDelta)) mV"),
            metric("cells", "BatteryData.PresentDOD", rawArrayText("BatteryData.PresentDOD", d.presentDOD), "%",
                   "hw.m.dod", "各电芯当前放电深度", usage: useTable, stars: 1),
            metric("cells", "BatteryData.CellWom", arrayText(d.cellWom), "—",
                   "hw.m.cell_wom", "电芯健康辅助字段", reliability: .questionable,
                   usage: useUnused, stars: 0, noteKey: "hw.n.cell_wom",
                   noteFallback: "本机元素数与电芯数不符且全为 0，不用于评分。"),
            metric("cells", "BatteryCellDisconnectCount", rawIntText("BatteryCellDisconnectCount", d.cellDisconnectCount), "count",
                   "hw.m.cell_disconnect", "电芯断连次数", usage: useDiagnosis, stars: 2,
                   noteFallback: "0 是正常且有效的读数；非 0 需要重点排查硬件。"),
            metric("cells", "PermanentFailureStatus", rawIntText("PermanentFailureStatus", d.permanentFailureStatus), "bitmask",
                   "hw.m.pf_status", "永久故障标志", usage: useDiagnosis, stars: 3,
                   noteFallback: "0 表示未报告永久故障；非 0 是需要维修的一票否决项。")
        ]

        let resistance = [
            metric("resistance", "BatteryData.WeightedRa", rawArrayText("BatteryData.WeightedRa", d.weightedRa), "mΩ",
                   "hw.m.weighted_ra", "各电芯加权内阻", usage: useDiagnosis, stars: 3,
                   noteKey: "hw.n.weighted_ra", noteFallback: "Apple 未公开统一阈值，绝对值只作参考，增长趋势更可靠。"),
            metric("resistance", "BatteryData.Ra00–Ra14", arrayText(d.raCurve), "mΩ",
                   "hw.m.ra_curve", "15 点内阻—放电深度曲线", reliability: .conditional,
                   usage: useDiagnosis, stars: 3, noteKey: "hw.n.ra_curve",
                   noteFallback: "曲线可解释低电量阶段的电压塌陷；端点噪声应结合趋势看。",
                   rawFields: (d.raCurve ?? []).enumerated().map {
                    .init(name: String(format: "BatteryData.Ra%02d", $0.offset), value: String($0.element), unit: "mΩ")
                   }),
            metric("resistance", "BatteryData.ChemicalWeightedRa", intText(d.chemicalWeightedRa), "mΩ",
                   "hw.m.chemical_ra", "化学加权内阻", reliability: .questionable,
                   usage: useUnused, stars: 0, noteKey: "hw.n.chemical_ra",
                   noteFallback: "本机 0 是实际返回值，但当前没有可解释的有效信号。")
        ]

        let virtualTemperatureRaw = d.virtualTemperatureRaw
        let electrical = [
            metric("electrical", "Voltage / AppleRawBatteryVoltage",
                   "\(intText(d.voltageRaw)) / \(intText(d.appleRawBatteryVoltage))", "mV",
                   "hw.m.pack_voltage", "电池组电压", usage: useDiagnosis, stars: 2,
                   rawFields: [
                    .init(name: "Voltage", value: intText(d.voltageRaw), unit: "mV"),
                    .init(name: "AppleRawBatteryVoltage", value: intText(d.appleRawBatteryVoltage), unit: "mV")
                   ]),
            metric("electrical", "Amperage", rawIntText("Amperage", d.smoothedAmperage), "mA",
                   "hw.m.smoothed_amperage", "平滑后的电池电流", usage: usePrimary, stars: 2,
                   noteFallback: "负值代表放电、正值代表充电；比瞬时值更适合展示。"),
            metric("electrical", "InstantAmperage", rawIntText("InstantAmperage", d.instantAmperage), "mA",
                   "hw.m.instant_amperage", "瞬时电池电流", usage: useDiagnosis, stars: 2,
                   noteFallback: "波动大，适合实时曲线，不单独用来下结论。"),
            metric("electrical", "Temperature", d.temperatureRaw == nil ? "—" : doubleText(data.temperatureCelsius, format: "%.2f"), "°C",
                   "hw.m.temperature", "电芯实测温度原始值", reliability: .conditional,
                   usage: usePrimary, stars: 2, noteKey: "hw.n.temp_unit",
                   noteFallback: "不同平台标度可能不同；本 App 按量级转换为摄氏度。",
                   rawFields: [.init(name: "Temperature", value: intText(d.temperatureRaw), unit: "raw")],
                   formula: "if raw > 1000: °C = raw ÷ 100; else if raw > 100: °C = raw ÷ 10; else °C = raw",
                   substitution: "\(intText(d.temperatureRaw)) → \(LNum("%.2f", data.temperatureCelsius)) °C"),
            metric("electrical", "VirtualTemperature", virtualTemperatureRaw == nil ? "—" : doubleText(d.virtualTemperature, format: "%.2f"), "°C",
                   "hw.m.virtual_temp", "含热模型补偿的虚拟温度", reliability: .conditional,
                   usage: useTable, stars: 1, noteKey: "hw.n.temp_unit",
                   noteFallback: "用于反映热模型热点；同样必须按平台标度转换。",
                   rawFields: [.init(name: "VirtualTemperature", value: intText(virtualTemperatureRaw), unit: "raw")],
                   formula: "decodeTemperature(VirtualTemperature): ÷100, ÷10 or direct by magnitude",
                   substitution: "\(intText(virtualTemperatureRaw)) → \(LNum("%.2f", d.virtualTemperature)) °C"),
            metric("electrical", "BatteryData.SystemPower", rawDoubleText("BatteryData.SystemPower", d.systemPowerWatts, format: "%.2f"), "W",
                   "hw.m.system_power", "系统总功耗", usage: usePrimary, stars: 3,
                   noteKey: "hw.n.system_power", noteFallback: "直接就是瓦特，是主界面功率的首选；不再用电压乘电流重算。")
        ]

        let voltageInPath = d.presentRawFields.contains("PowerTelemetryData.VoltageIn")
            ? "PowerTelemetryData.VoltageIn" : "PowerTelemetryData.SystemVoltageIn"
        let currentInPath = d.presentRawFields.contains("PowerTelemetryData.CurrentIn")
            ? "PowerTelemetryData.CurrentIn" : "PowerTelemetryData.SystemCurrentIn"
        let inputValue = "\(rawIntText("PowerTelemetryData.SystemPowerIn", d.systemPowerIn)) / \(rawIntText(voltageInPath, d.systemVoltageIn)) / \(rawIntText(currentInPath, d.systemCurrentIn))"
        let telemetry = [
            metric("telemetry", "PowerTelemetryData.SystemLoad", rawIntText("PowerTelemetryData.SystemLoad", d.systemLoad, grouped: true), "mW",
                   "hw.m.system_load", "系统负载功耗", usage: useCalculation, stars: 3,
                   noteFallback: "BatteryData.SystemPower 缺失时的备选读数。"),
            metric("telemetry", "PowerTelemetryData.BatteryPower", rawIntText("PowerTelemetryData.BatteryPower", d.batteryPower, grouped: true), "mW",
                   "hw.m.battery_power", "电池功率流向", usage: useDiagnosis, stars: 2,
                   noteFallback: "负值代表电池正在向系统供电。"),
            metric("telemetry", "PowerTelemetryData.SystemPowerIn/VoltageIn/CurrentIn", inputValue, "mW / mV / mA",
                   "hw.m.system_input", "适配器输入功率、电压、电流", reliability: .conditional,
                   usage: useTable, stars: 2, noteKey: "hw.n.ac_only",
                   noteFallback: "只在连接电源时有意义；电池供电时 0 是当前不适用，不是缺行。",
                   rawFields: [
                    .init(name: "PowerTelemetryData.SystemPowerIn", value: rawIntText("PowerTelemetryData.SystemPowerIn", d.systemPowerIn), unit: "mW"),
                    .init(name: "PowerTelemetryData.VoltageIn / SystemVoltageIn", value: rawIntText(voltageInPath, d.systemVoltageIn), unit: "mV"),
                    .init(name: "PowerTelemetryData.CurrentIn / SystemCurrentIn", value: rawIntText(currentInPath, d.systemCurrentIn), unit: "mA")
                   ]),
            metric("telemetry", "PowerTelemetryData.AdapterEfficiencyLoss", rawIntText("PowerTelemetryData.AdapterEfficiencyLoss", d.adapterEfficiencyLoss), "mW",
                   "hw.m.adapter_efficiency_loss", "适配器效率损耗原始值", reliability: .questionable,
                   usage: useUnused, stars: 0, noteKey: "hw.n.adapter_efficiency_loss",
                   noteFallback: "瞬时值可能为负且累计缩放未知，不据此生成充电效率。"),
            metric("telemetry", "PowerTelemetryData.AccumulatedSystemLoad ÷ Count",
                   doubleText(d.averageTelemetryPowerWatts, format: "%.2f"), "W",
                   "hw.m.accumulated_avg_power", "遥测累计平均系统功耗", reliability: .derived,
                   usage: useCalculation, stars: 2, noteKey: "hw.n.accumulated_avg_power",
                   noteFallback: "适合作为这台 Mac 的长期功耗基线。",
                   rawFields: [
                    .init(name: "PowerTelemetryData.AccumulatedSystemLoad", value: int64Text(d.accumulatedSystemLoad)),
                    .init(name: "PowerTelemetryData.SystemLoadAccumulatorCount", value: int64Text(d.systemLoadAccumulatorCount))
                   ], formula: "averagePower = AccumulatedSystemLoad ÷ Count ÷ 1000",
                   substitution: "\(int64Text(d.accumulatedSystemLoad)) ÷ \(int64Text(d.systemLoadAccumulatorCount)) ÷ 1000 = \(doubleText(d.averageTelemetryPowerWatts, format: "%.2f")) W"),
            metric("telemetry", "PowerTelemetryData.AccumulatedWallEnergyEstimate", rawIntText("PowerTelemetryData.AccumulatedWallEnergyEstimate", d.accumulatedWallEnergy, grouped: true), "raw",
                   "hw.m.wall_energy", "累计市电取电原始值", reliability: .questionable,
                   usage: useUnused, stars: 0, noteKey: "hw.n.wall_energy",
                   noteFallback: "公开结构未确认单位和缩放，只保留原始诊断值。")
        ]

        let lifetime = [
            metric("lifetime", "LifetimeData.MaximumTemperature", rawIntText("LifetimeData.MaximumTemperature", d.maximumTemperature), "°C",
                   "hw.m.temp_max", "历史最高温", usage: useDiagnosis, stars: 3),
            metric("lifetime", "LifetimeData.MinimumTemperature", rawIntText("LifetimeData.MinimumTemperature", d.minimumTemperature), "°C",
                   "hw.m.temp_min", "历史最低温", usage: useTable, stars: 1),
            metric("lifetime", "LifetimeData.AverageTemperature", rawDoubleText("LifetimeData.AverageTemperature", d.averageTemperature, format: "%.1f"), "°C",
                   "hw.m.temp_avg", "终生平均温度", reliability: .conditional,
                   usage: useDiagnosis, stars: 2, noteKey: "hw.n.temp_avg",
                   noteFallback: "原始字段是 0.1°C，与同字典中的最小/最大温度标度不同。",
                   rawFields: [.init(name: "LifetimeData.AverageTemperature", value: d.presentRawFields.contains("LifetimeData.AverageTemperature") ? String(Int((d.averageTemperature * 10).rounded())) : "—", unit: "0.1°C")],
                   formula: "averageTemperature°C = raw ÷ 10",
                   substitution: "\(Int((d.averageTemperature * 10).rounded())) ÷ 10 = \(doubleText(d.averageTemperature, format: "%.1f")) °C"),
            metric("lifetime", "LifetimeData.TemperatureSamples", rawIntText("LifetimeData.TemperatureSamples", d.temperatureSamples, grouped: true), "count",
                   "hw.m.temp_samples", "温度采样次数", usage: useDiagnosis, stars: 2),
            metric("lifetime", "LifetimeData.MaximumChargeCurrent", rawIntText("LifetimeData.MaximumChargeCurrent", d.maximumChargeCurrent, grouped: true), "mA",
                   "hw.m.max_charge_current", "历史最大充电电流", usage: useDiagnosis, stars: 2),
            metric("lifetime", "LifetimeData.MaximumDischargeCurrent", rawIntText("LifetimeData.MaximumDischargeCurrent", d.maximumDischargeCurrent, grouped: true), "mA",
                   "hw.m.max_discharge_current", "历史最大放电电流", usage: useDiagnosis, stars: 2,
                   noteKey: "hw.n.max_discharge", noteFallback: "已经是有符号负值，不做 UInt64 补码二次转换。"),
            metric("lifetime", "LifetimeData.MinimumPackVoltage", rawIntText("LifetimeData.MinimumPackVoltage", d.minimumPackVoltage), "mV",
                   "hw.m.min_pack_voltage", "历史最低组电压", usage: useDiagnosis, stars: 3,
                   noteKey: "hw.n.min_pack_voltage", noteFallback: "实测截止电压，是解释低电量电压塌陷的重要锚点。"),
            metric("lifetime", "LifetimeData.MaximumPackVoltage", rawIntText("LifetimeData.MaximumPackVoltage", d.maximumPackVoltage), "mV",
                   "hw.m.max_pack_voltage", "历史最高组电压", usage: useTable, stars: 1),
            metric("lifetime", "LifetimeData.CycleCountLastQmax", rawIntText("LifetimeData.CycleCountLastQmax", d.cycleCountLastQmax), "cycle",
                   "hw.m.last_qmax_cycle", "上次成功容量标定时的循环数", usage: useDiagnosis, stars: 3,
                   noteKey: "hw.n.last_qmax_cycle", noteFallback: "当前循环数减去它，可判断健康度读数有多新鲜。"),
            metric("lifetime", "→ since last Qmax", intText(d.calibrationAgeCycles), "cycle",
                   "hw.m.calib_age", "距上次 Qmax 标定的循环数", reliability: .derived,
                   usage: useDiagnosis, stars: 3, noteKey: "hw.n.calib_age",
                   noteFallback: "差值越小，当前容量读数通常越新鲜。",
                   rawFields: [
                    .init(name: "CycleCount", value: rawIntText("CycleCount", d.cycleCount)),
                    .init(name: "LifetimeData.CycleCountLastQmax", value: rawIntText("LifetimeData.CycleCountLastQmax", d.cycleCountLastQmax))
                   ], formula: "calibrationAge = CycleCount − CycleCountLastQmax",
                   substitution: "\(d.cycleCount) − \(d.cycleCountLastQmax) = \(intText(d.calibrationAgeCycles)) cycles"),
            metric("lifetime", "LifetimeData.TotalOperatingTime", rawIntText("LifetimeData.TotalOperatingTime", d.totalOperatingMinutes, grouped: true), "min",
                   "hw.m.total_runtime", "累计运行计数", reliability: .questionable,
                   usage: useUnused, stars: 0, noteKey: "hw.n.total_runtime",
                   noteFallback: "语义与墙钟时长不吻合，不用于推断电池年龄。"),
            metric("lifetime", "BatteryData.DataFlashWriteCount", rawIntText("BatteryData.DataFlashWriteCount", d.dataFlashWriteCount, grouped: true), "count",
                   "hw.m.flash_writes", "电量计 Flash 写入次数", usage: useTable, stars: 1),
            metric("lifetime", "BatteryData.QmaxDisqualificationReason", intText(d.qmaxDisqualificationReason), "code",
                   "hw.m.qmax_disqualification", "Qmax 标定失效原因码", usage: useTable, stars: 3,
                   noteKey: "hw.n.qmax_disqualification",
                   noteFallback: "0 是当前有效原始状态；非 0 说明容量学习可能被判无效，但具体位义未公开。"),
            metric("lifetime", "BatteryData.DailyMaxSoc / DailyMinSoc",
                   "\(rawIntText("BatteryData.DailyMaxSoc", d.dailyMaxSoc)) / \(rawIntText("BatteryData.DailyMinSoc", d.dailyMinSoc))", "%",
                   "hw.m.daily_soc_pair", "当日最高/最低电量", reliability: .conditional,
                   usage: useDiagnosis, stars: 2, noteKey: "hw.n.daily_soc",
                   noteFallback: "只有当天快照；跨天趋势必须由 App 自己持续积累。",
                   rawFields: [
                    .init(name: "BatteryData.DailyMaxSoc", value: rawIntText("BatteryData.DailyMaxSoc", d.dailyMaxSoc), unit: "%"),
                    .init(name: "BatteryData.DailyMinSoc", value: rawIntText("BatteryData.DailyMinSoc", d.dailyMinSoc), unit: "%")
                   ])
        ]

        let adapterValue: (String, Int) -> String = { field, value in rawIntText(field, value) }
        let adapterWattsPath = d.presentRawFields.contains("AdapterDetails.Watts")
            ? "AdapterDetails.Watts" : "AdapterDetails.AdapterWatts"
        let pdMenu = !d.presentRawFields.contains("AdapterDetails.UsbHvcMenu") ? "—" : d.usbHvcMenu.isEmpty ? "[]" : d.usbHvcMenu.map {
            "\(LNum("%.1f", Double($0.voltage) / 1000))V/\(LNum("%.1f", Double($0.current) / 1000))A"
        }.joined(separator: " · ")
        let carrier = d.carrierMode
        let carrierValue = carrier.map {
            "\(intText($0.highVoltage)) / \(intText($0.lowVoltage)) / \(intText($0.status))"
        } ?? "—"
        let portCycles = d.portControllers.isEmpty ? "—" : d.portControllers.map {
            "C\($0.index + 1) \(intText($0.attachCount))/\(intText($0.detachCount))"
        }.joined(separator: " · ")
        let portFailures = d.portControllers.isEmpty ? "—" : d.portControllers.map {
            "C\($0.index + 1) \(intText($0.capabilityMismatch))/\(intText($0.electionFailReason))"
        }.joined(separator: " · ")

        let charger = [
            metric("charger", "AdapterDetails.Watts", adapterValue(adapterWattsPath, d.adapterWatts), "W",
                   "hw.m.adapter_watts", "充电器额定功率", reliability: .conditional,
                   usage: useDiagnosis, stars: 2, noteKey: "hw.n.ac_only",
                   noteFallback: "仅插电时存在；拔电后显示 —。"),
            metric("charger", "AdapterDetails.AdapterVoltage / Current",
                   "\(adapterValue("AdapterDetails.AdapterVoltage", d.adapterVoltage)) / \(adapterValue("AdapterDetails.Current", d.adapterCurrent))", "mV / mA",
                   "hw.m.adapter_contract", "PD 协商电压与电流", reliability: .conditional,
                   usage: useDiagnosis, stars: 2, noteKey: "hw.n.ac_only",
                   noteFallback: "仅插电时可判断当前协商档位。",
                   rawFields: [
                    .init(name: "AdapterDetails.AdapterVoltage", value: adapterValue("AdapterDetails.AdapterVoltage", d.adapterVoltage), unit: "mV"),
                    .init(name: "AdapterDetails.Current", value: adapterValue("AdapterDetails.Current", d.adapterCurrent), unit: "mA")
                   ]),
            metric("charger", "AdapterDetails.UsbHvcMenu", pdMenu, "raw",
                   "hw.m.adapter_menu", "PD 可协商档位表", reliability: .conditional,
                   usage: useDiagnosis, stars: 2, noteKey: "hw.n.adapter_menu",
                   noteFallback: "最高档反映当前适配器和设备公开的协商能力。"),
            metric("charger", "AdapterDetails.Description", rawStringText("AdapterDetails.Description", d.adapterDescription), "string",
                   "hw.m.adapter_description", "适配器接口类型", reliability: .conditional,
                   usage: useTable, stars: 1, noteKey: "hw.n.ac_only", noteFallback: "原始小写英文只作为诊断证据。"),
            metric("charger", "ChargerData.ChargingVoltage / ChargingCurrent",
                   "\(rawIntText("ChargerData.ChargingVoltage", d.chargingVoltageLimit)) / \(rawIntText("ChargerData.ChargingCurrent", d.chargingCurrentLimit))", "mV / mA",
                   "hw.m.charge_limits", "充电限压与限流", reliability: .conditional,
                   usage: useDiagnosis, stars: 2, noteKey: "hw.n.charge_i_limit",
                   noteFallback: "ChargingCurrent 为 0 可能是满电保持或刚插入，不能单独判断故障。",
                   rawFields: [
                    .init(name: "ChargerData.ChargingVoltage", value: rawIntText("ChargerData.ChargingVoltage", d.chargingVoltageLimit), unit: "mV"),
                    .init(name: "ChargerData.ChargingCurrent", value: rawIntText("ChargerData.ChargingCurrent", d.chargingCurrentLimit), unit: "mA")
                   ]),
            metric("charger", "ChargerData.NotChargingReason", rawIntText("ChargerData.NotChargingReason", d.notChargingReason), "bitmask",
                   "hw.m.not_charging_reason", "不充电原因原始位掩码", reliability: .questionable,
                   usage: useUnused, stars: 0, noteKey: "hw.n.not_charging_reason",
                   noteFallback: "位义未公开，不生成看似确定的消费者结论。"),
            metric("charger", "CarrierMode.CarrierModeHighVoltage/LowVoltage/Status", carrierValue, "mV / mV / code",
                   "hw.m.carrier_mode", "运输模式阈值与状态", usage: useTable, stars: 2,
                   noteKey: "hw.n.carrier_mode", noteFallback: "Status 需结合系统状态，不能直接当作 80% 充电上限。",
                   rawFields: [
                    .init(name: "CarrierMode.CarrierModeHighVoltage", value: intText(carrier?.highVoltage), unit: "mV"),
                    .init(name: "CarrierMode.CarrierModeLowVoltage", value: intText(carrier?.lowVoltage), unit: "mV"),
                    .init(name: "CarrierMode.CarrierModeStatus", value: intText(carrier?.status))
                   ]),
            metric("charger", "PortControllerInfo[].AttachCount/DetachCount", portCycles, "count",
                   "hw.m.port_cycles", "端口控制器插入/拔出计数", usage: useTable, stars: 2,
                   noteKey: "hw.n.port_cycles", noteFallback: "控制器数组不能安全映射左右端口；异常增长可提示接触问题。",
                   rawFields: d.portControllers.flatMap { port in [
                    .init(name: "PortControllerInfo[\(port.index)].PortControllerAttachCount", value: intText(port.attachCount)),
                    .init(name: "PortControllerInfo[\(port.index)].PortControllerDetachCount", value: intText(port.detachCount))
                   ] }),
            metric("charger", "PortControllerInfo[].CapMismatch / ElectionFailReason", portFailures, "count / code",
                   "hw.m.port_failures", "端口能力不匹配与协商失败", usage: useTable, stars: 3,
                   noteKey: "hw.n.port_failures", noteFallback: "非 0 可直接指向线缆、适配器或 PD 协商问题。",
                   rawFields: d.portControllers.flatMap { port in [
                    .init(name: "PortControllerInfo[\(port.index)].PortControllerCapMismatch", value: intText(port.capabilityMismatch)),
                    .init(name: "PortControllerInfo[\(port.index)].PortControllerElectionFailReason", value: intText(port.electionFailReason))
                   ] })
        ]

        let manufactureValue = manufactureDisplay(d.manufactureDateRaw)
        let identity = [
            metric("identity", "Serial", rawStringText("Serial", d.serialNumber), "string",
                   "hw.m.serial", "电池序列号", usage: useDiagnosis, stars: 1,
                   noteFallback: "更换电池后会改变，可用来识别电池是否被换过。"),
            metric("identity", "DeviceName", rawStringText("DeviceName", d.gaugeChip), "string",
                   "hw.m.gauge_chip", "电量计芯片型号", usage: useDiagnosis, stars: 2,
                   noteFallback: "芯片型号帮助理解 TimeRemaining 背后的电量计算模型。"),
            metric("identity", "BatteryData.ChemID / AlgoChemID",
                   "\(rawIntText("BatteryData.ChemID", d.chemistryID)) / \(intText(d.algorithmChemistryID))", "code",
                   "hw.m.chem_ids", "电芯化学体系与算法化学 ID", usage: useTable, stars: 1,
                   rawFields: [
                    .init(name: "BatteryData.ChemID", value: rawIntText("BatteryData.ChemID", d.chemistryID)),
                    .init(name: "BatteryData.AlgoChemID", value: intText(d.algorithmChemistryID))
                   ]),
            metric("identity", "BatteryData.ManufactureDate", manufactureValue, "raw / ASCII",
                   "hw.m.manufacture_batch", "制造批号原始整数", reliability: .questionable,
                   usage: useUnused, stars: 0, noteKey: "hw.n.manufacture_batch",
                   noteFallback: "可解出厂商 ASCII 批号，但不是经验证的日历日期。",
                   rawFields: [.init(name: "BatteryData.ManufactureDate", value: intText(d.manufactureDateRaw))],
                   formula: "integer → hexadecimal bytes → printable ASCII",
                   substitution: manufactureValue),
            metric("identity", "BatteryData.DateOfFirstUse", intText(d.dateOfFirstUseRaw), "raw",
                   "hw.m.first_use", "首次使用日期原始值", reliability: .questionable,
                   usage: useUnused, stars: 0, noteKey: "hw.n.first_use",
                   noteFallback: "本机为 0，无法据此获得真实电池年龄。"),
            metric("identity", "GasGaugeFirmwareVersion", rawIntText("GasGaugeFirmwareVersion", d.gaugeFirmwareVersion), "version",
                   "hw.m.gauge_fw", "电量计固件版本", usage: useTable, stars: 1),
            metric("identity", "BatteryInstalled / built-in",
                   "\(boolText(d.batteryInstalled)) / \(boolText(d.isBuiltIn))", "bool",
                   "hw.m.installed", "电池安装与内置状态", usage: useTable, stars: 1,
                   rawFields: [
                    .init(name: "BatteryInstalled", value: boolText(d.batteryInstalled)),
                    .init(name: "built-in", value: boolText(d.isBuiltIn))
                   ]),
            metric("identity", "hw.model", modelIdentifier.isEmpty ? "—" : modelIdentifier, "identifier",
                   "hw.m.machine_model", "Mac 硬件机型标识", usage: useCalculation, stars: 2)
        ]

        return [
            group("capacity", "hw.group.capacity", "容量与健康", "p.hw_group_capacity", "容量基准、当前容量、健康度与必要推导", capacity),
            group("runtime", "hw.group.runtime", "续航与系统估算", "p.hw_group_runtime", "系统直接返回的剩余时间和估算状态", runtime),
            group("cells", "hw.group.cells", "电芯", "p.hw_group_cells", "每节电芯的电压、放电深度和故障状态", cells),
            group("resistance", "hw.group.resistance", "内阻与放电曲线", "p.hw_group_resistance", "用于解释低电量电压塌陷的阻抗证据", resistance),
            group("electrical", "hw.group.electrical", "电气", "p.hw_group_electrical", "电压、电流、温度与直接系统功耗", electrical),
            group("telemetry", "hw.group.telemetry", "功耗遥测", "p.hw_group_telemetry", "当前与累计功率数据；存疑字段保留但不下结论", telemetry),
            group("lifetime", "hw.group.lifetime", "寿命统计", "p.hw_group_lifetime", "电量计积累的历史极值、计数与标定状态", lifetime),
            group("charger", "hw.group.charger", "充电器与端口", "p.hw_group_charger", "插电协商、充电限制与端口故障证据", charger),
            group("identity", "hw.group.identity", "身份", "p.hw_group_identity", "电池、电量计、化学体系和 Mac 机型", identity)
        ]
    }

    private static func group(
        _ id: String,
        _ titleKey: String,
        _ titleFallback: String,
        _ summaryKey: String,
        _ summaryFallback: String,
        _ metrics: [CompleteHardwareMetric]
    ) -> CompleteHardwareGroup {
        CompleteHardwareGroup(
            id: id,
            title: hardwareText(titleKey, titleFallback),
            summary: hardwareText(summaryKey, summaryFallback),
            metrics: metrics
        )
    }

    private static func referenceRange(field: String, data: BatteryData) -> String {
        let d = data.hardwareDetail
        let noRange = hardwareText("p.no_fixed_range", "无公开固定范围")
        let trend = hardwareText("p.counter_range", "看历史趋势，不设固定上限")
        let identifier = hardwareText("p.id_no_range", "标识/状态字段，无数值范围")

        switch field {
        case "→ CellVoltage.delta": return "0–20 mV"
        case "BatteryData.WeightedRa": return hardwareText("hw.range.weighted_ra", "Apple 未公开阈值 · 只看本机趋势")
        case "BatteryData.ChemicalWeightedRa": return "0 = N/A · \(noRange)"
        case "BatteryData.PresentDOD", "CurrentCapacity", "BatteryData.DailyMaxSoc / DailyMinSoc": return "0–100 %"
        case "AppleRawMaxCapacity", "BatteryData.FccComp1 / FccComp2":
            return d.designCapacity > 0
                ? hardwareText("hw.range.compare_design", "对比设计值 {value} mAh")
                    .replacingOccurrences(of: "{value}", with: d.designCapacity.formatted())
                : noRange
        case "AppleRawCurrentCapacity":
            return d.designCapacity > 0
                ? hardwareText("hw.range.current_capacity", "0–{value} mAh")
                    .replacingOccurrences(of: "{value}", with: d.designCapacity.formatted())
                : noRange
        case "NominalChargeCapacity": return hardwareText("hw.range.nominal_relation", "应≈ FCC + PackReserve")
        case "TimeRemaining / AvgTimeToEmpty", "AvgTimeToFull": return hardwareText("hw.range.time_valid", "1–65,534 min · 65,535 = 不可用")
        case "BatteryInvalidWakeSeconds": return "0+ s · \(trend)"
        case "CycleCount": return d.designCycleCount > 0
            ? hardwareText("hw.range.cycle_rated", "额定 {value} 次 · 超过不等于立即故障")
                .replacingOccurrences(of: "{value}", with: d.designCycleCount.formatted())
            : trend
        case "DesignCycleCount9C": return d.designCycleCount > 0
            ? hardwareText("hw.range.design_cycle_rated", "额定 {value} 次")
                .replacingOccurrences(of: "{value}", with: d.designCycleCount.formatted())
            : noRange
        case "MaxCapacity":
            return d.architecture == .appleSilicon
                ? hardwareText("hw.range.max_percent", "0–100 % · Apple Silicon 原始口径")
                : hardwareText("hw.range.max_platform", "平台相关 · 可能为 mAh")
        case "→ health (system)", "→ health (raw)": return "80–100 %"
        case "Temperature", "VirtualTemperature": return hardwareText("hw.range.temperature", "15–35°C 常见舒适区")
        case "BatteryData.SystemPower":
            if let baseline = d.averageTelemetryPowerWatts {
                return hardwareText("hw.range.power_baseline", "本机累计基线 ≈ {value} W")
                    .replacingOccurrences(of: "{value}", with: LNum("%.1f", baseline))
            }
            return noRange
        case "LifetimeData.MinimumTemperature": return hardwareText("hw.range.lifetime_min", "历史低点 · 低温会暂时缩短续航")
        case "LifetimeData.MaximumTemperature": return hardwareText("hw.range.lifetime_max", "历史峰值 · ≥45°C 需关注热暴露")
        case "LifetimeData.AverageTemperature": return hardwareText("hw.range.lifetime_avg", "15–35°C 常见使用区间")
        case "PermanentFailureStatus", "BatteryCellDisconnectCount": return hardwareText("hw.range.fault_zero", "0 = 正常 · 非 0 需排查")
        case "BatteryData.QmaxDisqualificationReason": return hardwareText("hw.range.qmax_valid", "0 = 当前有效 · 非 0 需核验")
        case "PortControllerInfo[].CapMismatch / ElectionFailReason": return hardwareText("hw.range.port_zero", "0 = 未记录失败 · 非 0 需排查")
        case "LifetimeData.MinimumPackVoltage", "LifetimeData.MaximumPackVoltage", "Voltage / AppleRawBatteryVoltage":
            if d.minimumPackVoltage > 0, d.maximumPackVoltage > 0 {
                return "\(d.minimumPackVoltage)–\(d.maximumPackVoltage) mV"
            }
            return noRange
        case "DesignCapacity", "ModelDesignEnergy": return hardwareText("p.rated_value", "机型额定值")
        case "BatteryData.Qmax", "→ current full energy", "→ Qmax − FCC", "→ Design − min(Qmax)": return noRange
        default:
            if field.contains("Serial") || field.contains("DeviceName") || field.contains("Firmware")
                || field.contains("ChemID") || field.contains("ManufactureDate")
                || field.contains("DateOfFirstUse") || field.contains("installed")
                || field.contains("hw.model") || field.contains("topology")
                || field.contains("Reason") || field.contains("Status")
                || field.contains("Description") {
                return identifier
            }
            if field.contains("Count") || field.contains("Samples")
                || field.contains("OperatingTime") || field.contains("FlashWrite")
                || field.contains("since last") || field.contains("deficit") {
                return trend
            }
            return noRange
        }
    }

    private static func manufactureDisplay(_ raw: Int?) -> String {
        guard let raw else { return "—" }
        let hex = String(raw, radix: 16)
        let padded = hex.count.isMultiple(of: 2) ? hex : "0" + hex
        var bytes: [UInt8] = []
        var index = padded.startIndex
        while index < padded.endIndex {
            let end = padded.index(index, offsetBy: 2)
            guard let byte = UInt8(padded[index..<end], radix: 16) else { return String(raw) }
            bytes.append(byte)
            index = end
        }
        guard let ascii = String(bytes: bytes, encoding: .ascii),
              ascii.unicodeScalars.allSatisfy({ $0.value >= 32 && $0.value < 127 }) else {
            return String(raw)
        }
        return "\(raw) / ASCII \(ascii)"
    }
}
