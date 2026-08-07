import SwiftUI

private enum SystemWorkbenchTab: Hashable, Identifiable {
    case meaningful
    case anomalies
    case source(SystemDataLayer)
    case all

    var id: String {
        switch self {
        case .meaningful: return "meaningful"
        case .anomalies: return "anomalies"
        case .source(let layer): return "source-\(layer.rawValue)"
        case .all: return "all"
        }
    }
}

/// Bottom-level validation console. It keeps all 464 catalog entries while the
/// first tab stays focused on fields that can actually support a user decision.
struct SystemDataWorkbenchView: View {
    let snapshot: SystemDataSnapshot
    /// The gauge's own publish moment. 434 of the 464 fields come from
    /// AppleSmartBattery and therefore move on its ~60 s beat, not on our poll —
    /// the status strip has to state the two cadences separately or it would
    /// promise ten-second freshness for numbers that cannot deliver it.
    let gaugeReadAt: Date?
    let isLive: Bool
    let onToggleLive: () -> Void
    let onRefresh: () -> Void
    @Binding var selectedHelp: MetricHelpContent?

    @State private var selection: SystemWorkbenchTab = .meaningful
    @State private var searchText = ""

    private var tabs: [SystemWorkbenchTab] {
        [.meaningful, .anomalies]
            + SystemDataLayer.allCases.map(SystemWorkbenchTab.source)
            + [.all]
    }

    private var visibleFields: [SystemFieldReading] {
        let base: [SystemFieldReading]
        switch selection {
        case .meaningful:
            base = snapshot.fields.filter(\.isMeaningful)
        case .anomalies:
            base = snapshot.fields.filter { $0.anomalyLevel > .none }
        case .source(let layer):
            base = snapshot.fields.filter { $0.metadata.source == layer.sourceName }
        case .all:
            base = snapshot.fields
        }

        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).localizedLowercase
        guard !query.isEmpty else { return base }
        // Search what the user can actually read: path/value/source are English
        // identifiers in every language, the rest follows the current language.
        // Deliberately not searching the raw Chinese too — in an English UI,
        // matching 温度 would leak implementation details and make the result
        // count disagree with the visible text. Reliability and unit are new
        // here: both are visible columns that were previously unsearchable.
        return base.filter {
            [
                $0.metadata.path, $0.value, $0.metadata.source,
                $0.metadata.localizedGroup, $0.metadata.localizedMeaning,
                $0.metadata.localizedNote, $0.metadata.localizedUnit,
                $0.metadata.localizedReliability,
            ].joined(separator: " ").localizedLowercase.contains(query)
        }
    }

    var body: some View {
        // Computed once per redraw and handed down. These were computed
        // properties read four times per body, each re-filtering all 464 fields
        // and re-running isMeaningfulByDefault on every one of them.
        let fields = visibleFields
        let counts = tabCounts
        return VStack(alignment: .leading, spacing: 15) {
            header
            description
            tabBar(counts)
            toolbar(fields.count)
            table(fields)
        }
        .padding(20)
        .finalDashboardCard(accent: AppTheme.accentPurple)
    }

    private var header: some View {
        HStack(spacing: 9) {
            ZStack {
                RoundedRectangle(cornerRadius: 10).fill(AppTheme.accentPurple.opacity(0.12))
                Image(systemName: "server.rack")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(AppTheme.accentPurple)
            }
            .frame(width: 38, height: 38)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 7) {
                    Text(dashboardText("p.system_data_title", fallback: "所有系统数据 · 四层核验台"))
                        .font(.system(size: 15.5, weight: .bold))
                        .foregroundStyle(AppTheme.textPrimary)
                    Text("\(snapshot.fields.count)")
                        .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(AppTheme.accentPurple)
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(Capsule().fill(AppTheme.accentPurple.opacity(0.10)))
                }
                Text(dashboardText("p.system_data_source", fallback: "实时读取 macOS；Excel 仅提供字段含义，不提供页面数值"))
                    .font(.system(size: 10))
                    .foregroundStyle(AppTheme.textTertiary)
            }
            Spacer()
            snapshotBadge("\(snapshot.availableCount)", dashboardText("p.system_data_available", fallback: "本次有值"), AppTheme.chargingCyan)
            snapshotBadge("\(snapshot.anomalyCount)", dashboardText("p.system_data_anomaly", fallback: "需关注"), anomalyColor)
            liveControls
        }
    }

    private var description: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "checkmark.shield")
                .foregroundStyle(AppTheme.batteryGreen)
            Text(dashboardText(
                "p.system_data_description",
                fallback: "默认只显示能帮助判断续航、健康、功耗和温度的字段。切到异常可一键筛查；切到任一数据源或全部，可逐项对照上面的结论。Apple 未公开的内部字段会明确标为诊断项，不给它编造标准答案。"
            ))
            .font(.system(size: 10.5))
            .foregroundStyle(AppTheme.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(AppTheme.batteryGreen.opacity(0.035)))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(AppTheme.batteryGreen.opacity(0.10), lineWidth: 1))
    }

    private func tabBar(_ counts: [SystemWorkbenchTab: Int]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(tabs) { tab in
                    Button {
                        withAnimation(.easeOut(duration: 0.16)) { selection = tab }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: tabIcon(tab)).font(.system(size: 9, weight: .semibold))
                            Text(tabTitle(tab)).font(.system(size: 9.5, weight: .semibold))
                            Text("\(counts[tab] ?? 0)")
                                .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                                .opacity(0.75)
                        }
                        .foregroundStyle(selection == tab ? Color.black : AppTheme.textSecondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(Capsule().fill(selection == tab ? tabColor(tab) : AppTheme.contrastOverlay(0.035)))
                        .overlay(Capsule().stroke(selection == tab ? tabColor(tab) : AppTheme.contrastOverlay(0.06), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .pointerOnHover()
                    .accessibilityLabel(tabTitle(tab))
                }
            }
        }
    }

    private func toolbar(_ visibleCount: Int) -> some View {
        HStack(spacing: 9) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 10.5))
                .foregroundStyle(AppTheme.textTertiary)
            TextField(dashboardText("p.system_data_search", fallback: "搜索字段、当前值、含义或说明"), text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 10.5))
            if !searchText.isEmpty {
                Button { searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(AppTheme.textTertiary)
                }
                .buttonStyle(.plain)
            }
            Spacer()
            Text("\(visibleCount) / \(snapshot.fields.count)")
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundStyle(AppTheme.textTertiary)
        }
        .padding(.horizontal, 11)
        .frame(height: 34)
        .background(RoundedRectangle(cornerRadius: 8).fill(AppTheme.surfaceSunken))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(AppTheme.contrastOverlay(0.06), lineWidth: 1))
    }

    private func table(_ fields: [SystemFieldReading]) -> some View {
        ScrollView([.horizontal, .vertical]) {
            LazyVStack(spacing: 4, pinnedViews: [.sectionHeaders]) {
                Section(header: tableHeader) {
                    if fields.isEmpty {
                        emptyState.frame(width: 1450, height: 180)
                    } else {
                        ForEach(fields) { field in
                            fieldRow(field)
                        }
                    }
                }
            }
            .frame(minWidth: 1450, alignment: .leading)
        }
        .frame(height: min(610, max(260, CGFloat(fields.count) * 41 + 44)))
        .background(RoundedRectangle(cornerRadius: 11).fill(AppTheme.surfaceSunken))
        .overlay(RoundedRectangle(cornerRadius: 11).stroke(AppTheme.contrastOverlay(0.05), lineWidth: 1))
    }

    private var tableHeader: some View {
        HStack(spacing: 8) {
            headerCell("", width: 26)
            headerCell(dashboardText("p.system_data_field", fallback: "字段路径"), width: 285)
            headerCell(dashboardText("p.system_data_value", fallback: "系统实测值"), width: 210)
            headerCell(dashboardText("p.system_data_unit", fallback: "单位"), width: 86)
            headerCell(dashboardText("p.system_data_meaning", fallback: "这个数字说明什么"), width: 355)
            headerCell(dashboardText("p.system_data_group", fallback: "分组"), width: 105)
            headerCell(dashboardText("p.system_data_reliability", fallback: "来源可靠性"), width: 210)
            headerCell(dashboardText("p.system_data_value_level", fallback: "价值"), width: 54)
            Color.clear.frame(width: 22)
        }
        .padding(.horizontal, 10).padding(.vertical, 9)
        .background(AppTheme.surfaceRaised)
    }

    private func fieldRow(_ field: SystemFieldReading) -> some View {
        HStack(spacing: 8) {
            anomalyIcon(field).frame(width: 26)
            Text(field.metadata.path)
                .font(.system(size: 9.2, design: .monospaced))
                .foregroundStyle(field.isAvailable ? AppTheme.textSecondary : AppTheme.textTertiary.opacity(0.6))
                .textSelection(.enabled)
                .lineLimit(2)
                .frame(width: 285, alignment: .leading)
            Text(field.convertedValue)
                .font(.system(size: 9.7, weight: .semibold, design: .monospaced))
                .foregroundStyle(field.isAvailable ? valueColor(field) : AppTheme.textTertiary.opacity(0.55))
                .textSelection(.enabled)
                .lineLimit(2)
                .frame(width: 210, alignment: .leading)
            Text(field.metadata.localizedUnit.isEmpty ? "—" : field.metadata.localizedUnit)
                .font(.system(size: 8.8, design: .monospaced))
                .foregroundStyle(AppTheme.textTertiary)
                .frame(width: 86, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(field.metadata.localizedMeaning)
                    .font(.system(size: 9.2))
                    .foregroundStyle(AppTheme.textSecondary)
                    .lineLimit(2)
                if field.anomalyLevel > .none {
                    Text(field.anomalyReason)
                        .font(.system(size: 8.5, weight: .semibold))
                        .foregroundStyle(valueColor(field))
                        .lineLimit(2)
                }
            }
            .frame(width: 355, alignment: .leading)
            Text(field.metadata.localizedGroup)
                .font(.system(size: 8.7, weight: .semibold))
                .foregroundStyle(AppTheme.chargingCyan.opacity(0.85))
                .frame(width: 105, alignment: .leading)
            Text(field.metadata.localizedReliability)
                .font(.system(size: 8.6))
                .foregroundStyle(AppTheme.textTertiary)
                .lineLimit(2)
                .frame(width: 210, alignment: .leading)
            Text(field.metadata.valueStars > 0 ? String(repeating: "★", count: field.metadata.valueStars) : "—")
                .font(.system(size: 8.5))
                .foregroundStyle(AppTheme.batteryYellow)
                .frame(width: 54, alignment: .leading)
            MetricHelpButton(content: field.help, selection: $selectedHelp)
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 7).fill(rowBackground(field)))
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(rowStroke(field), lineWidth: 1))
    }

    private var liveControls: some View {
        HStack(spacing: 7) {
            // One ticking clock for the whole strip; the per-source countdown is
            // the only thing that changes between polls.
            TimelineView(.periodic(from: Date(), by: 1)) { timeline in
                VStack(alignment: .trailing, spacing: 2) {
                    sourceCadenceLine(
                        label: dashboardText("p.system_source_gauge", fallback: "电量计"),
                        text: gaugeCadenceText(now: timeline.date)
                    )
                    sourceCadenceLine(
                        label: dashboardText("p.system_source_others", fallback: "其他数据源"),
                        text: otherSourcesCadenceText
                    )
                }
            }
            Button(action: onToggleLive) {
                Label(isLive
                      ? dashboardText("p.pause_refresh", fallback: "暂停 10 秒更新")
                      : dashboardText("p.resume_refresh", fallback: "继续 10 秒更新"),
                      systemImage: isLive ? "pause.fill" : "play.fill")
                    .font(.system(size: 9.5, weight: .semibold))
            }
            .buttonStyle(.plain).foregroundStyle(AppTheme.chargingCyan).pointerOnHover()
            .accessibilityLabel(isLive
                ? dashboardText("p.pause_refresh", fallback: "暂停 10 秒更新")
                : dashboardText("p.resume_refresh", fallback: "继续 10 秒更新"))
            Button(action: onRefresh) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(AppTheme.chargingCyan)
            }
            .buttonStyle(.plain).pointerOnHover()
            .help(dashboardText("p.refresh_now", fallback: "立即刷新"))
        }
    }

    private func sourceCadenceLine(label: String, text: String) -> some View {
        HStack(spacing: 5) {
            Text(label)
                .font(.system(size: 8.5, weight: .semibold))
                .foregroundStyle(AppTheme.textTertiary.opacity(0.75))
            Text(text)
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(AppTheme.textTertiary)
        }
    }

    /// Same wording the help drawer uses for gauge-published fields, so the two
    /// screens cannot disagree about the beat.
    private func gaugeCadenceText(now: Date) -> String {
        guard let gaugeReadAt else {
            return dashboardText("p.runtime_raw_unavailable", fallback: "不可用")
        }
        let remaining = MetricFieldFreshness.gaugeRefreshSeconds
            - MetricFieldFreshness.seconds(from: gaugeReadAt, to: now)
        let stamp = ["time": MetricFieldFreshness.clockText(gaugeReadAt)]
        guard remaining > 0 else {
            return dashboardText("p.field_read_at_gauge_due",
                                 fallback: "预计随时刷新 · 上次 {time}",
                                 replacements: stamp)
        }
        return dashboardText("p.field_read_at_gauge",
                             fallback: "还有约 {countdown} 秒刷新 · 上次 {time}",
                             replacements: stamp.merging(["countdown": "\(remaining)"]) { a, _ in a })
    }

    /// IOPowerSources / legacy IOPM / ProcessInfo are re-read on every poll, so
    /// their freshness is our interval, not the gauge's.
    private var otherSourcesCadenceText: String {
        guard snapshot.timestamp != .distantPast else {
            return dashboardText("p.runtime_raw_unavailable", fallback: "不可用")
        }
        return dashboardText(
            "p.system_others_cadence",
            fallback: "每 {interval} 秒重读 · 上次 {time}",
            replacements: [
                "interval": "\(Int(BatteryService.liveRefreshInterval.rounded()))",
                "time": MetricFieldFreshness.clockText(snapshot.timestamp),
            ]
        )
    }

    /// Every tab badge in one pass over the 464 readings. The per-tab version
    /// this replaces walked the whole array once per tab — seven full scans, five
    /// of which re-ran the meaningfulness test on every field.
    private var tabCounts: [SystemWorkbenchTab: Int] {
        var counts: [SystemWorkbenchTab: Int] = [
            .meaningful: 0, .anomalies: 0, .all: snapshot.fields.count,
        ]
        for layer in SystemDataLayer.allCases { counts[.source(layer)] = 0 }
        for field in snapshot.fields {
            if field.isMeaningful { counts[.meaningful, default: 0] += 1 }
            if field.anomalyLevel > .none { counts[.anomalies, default: 0] += 1 }
            if let layer = SystemDataLayer.allCases.first(where: { $0.sourceName == field.metadata.source }) {
                counts[.source(layer), default: 0] += 1
            }
        }
        return counts
    }

    private func tabTitle(_ tab: SystemWorkbenchTab) -> String {
        switch tab {
        case .meaningful: return dashboardText("p.system_tab_meaningful", fallback: "有意义")
        case .anomalies: return dashboardText("p.system_tab_anomaly", fallback: "异常")
        case .source(.powerSources): return "IOPowerSources"
        case .source(.smartBattery): return "AppleSmartBattery"
        case .source(.legacyIOPM): return "Legacy IOPM"
        case .source(.processInfo): return "ProcessInfo"
        case .all: return dashboardText("p.system_tab_all", fallback: "全部展开")
        }
    }

    private func tabIcon(_ tab: SystemWorkbenchTab) -> String {
        switch tab {
        case .meaningful: return "sparkles"
        case .anomalies: return "exclamationmark.triangle"
        case .source(.powerSources): return "battery.75percent"
        case .source(.smartBattery): return "cpu"
        case .source(.legacyIOPM): return "clock.arrow.circlepath"
        case .source(.processInfo): return "thermometer.medium"
        case .all: return "square.grid.3x3"
        }
    }

    private func tabColor(_ tab: SystemWorkbenchTab) -> Color {
        switch tab {
        case .anomalies: return anomalyColor
        case .meaningful: return AppTheme.chargingCyan
        case .all: return AppTheme.accentPurple
        default: return AppTheme.chargingBlue
        }
    }

    private var anomalyColor: Color {
        snapshot.anomalyCount > 0 ? AppTheme.batteryYellow : AppTheme.batteryGreen
    }

    private func snapshotBadge(_ value: String, _ label: String, _ color: Color) -> some View {
        VStack(alignment: .trailing, spacing: 1) {
            Text(value).font(.system(size: 13, weight: .bold, design: .monospaced)).foregroundStyle(color)
            Text(label).font(.system(size: 8.5)).foregroundStyle(AppTheme.textTertiary)
        }
        .padding(.horizontal, 9).padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 8).fill(color.opacity(0.055)))
    }

    private func headerCell(_ text: String, width: CGFloat) -> some View {
        Text(text.uppercased())
            .font(.system(size: 8.2, weight: .semibold, design: .monospaced))
            .tracking(0.4)
            .foregroundStyle(AppTheme.textTertiary)
            .frame(width: width, alignment: .leading)
    }

    @ViewBuilder
    private func anomalyIcon(_ field: SystemFieldReading) -> some View {
        switch field.anomalyLevel {
        case .none:
            Image(systemName: field.isAvailable ? "checkmark.circle" : "minus.circle")
                .foregroundStyle(field.isAvailable ? AppTheme.batteryGreen.opacity(0.65) : AppTheme.textTertiary.opacity(0.4))
        case .attention:
            Image(systemName: "eye.circle.fill").foregroundStyle(AppTheme.batteryYellow)
        case .warning:
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(AppTheme.batteryYellow)
        case .critical:
            Image(systemName: "exclamationmark.octagon.fill").foregroundStyle(AppTheme.batteryRed)
        }
    }

    private func valueColor(_ field: SystemFieldReading) -> Color {
        switch field.anomalyLevel {
        case .critical: return AppTheme.batteryRed
        case .warning, .attention: return AppTheme.batteryYellow
        case .none: return AppTheme.textPrimary
        }
    }

    private func rowBackground(_ field: SystemFieldReading) -> Color {
        switch field.anomalyLevel {
        case .critical: return AppTheme.batteryRed.opacity(0.055)
        case .warning, .attention: return AppTheme.batteryYellow.opacity(0.045)
        case .none: return AppTheme.contrastOverlay(field.isAvailable ? 0.017 : 0.008)
        }
    }

    private func rowStroke(_ field: SystemFieldReading) -> Color {
        switch field.anomalyLevel {
        case .critical: return AppTheme.batteryRed.opacity(0.20)
        case .warning, .attention: return AppTheme.batteryYellow.opacity(0.16)
        case .none: return AppTheme.contrastOverlay(0.035)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: selection == .anomalies ? "checkmark.shield.fill" : "magnifyingglass")
                .font(.system(size: 24))
                .foregroundStyle(selection == .anomalies ? AppTheme.batteryGreen : AppTheme.textTertiary)
            Text(selection == .anomalies
                 ? dashboardText("p.system_no_anomaly", fallback: "本次快照没有命中已定义的异常规则")
                 : dashboardText("p.system_no_results", fallback: "没有匹配的系统字段"))
                .font(.system(size: 11))
                .foregroundStyle(AppTheme.textSecondary)
        }
    }
}
