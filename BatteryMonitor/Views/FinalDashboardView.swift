import SwiftUI
import Charts

/// Native SwiftUI migration of `Prototype/battery-final.html`.
///
/// The view is intentionally an information hierarchy, not a collection of the
/// legacy dashboard widgets: runtime first, then the three supporting signals,
/// followed by explanation and raw evidence.
struct FinalDashboardView: View {
    @EnvironmentObject private var batteryService: BatteryService
    @EnvironmentObject private var processService: ProcessMonitorService
    let batteryData: BatteryData
    let realtimeData: [RealtimeDataPoint]
    var persistedRuntimeSamples: [RuntimeSample] = []
    @Binding var selectedHelp: MetricHelpContent?

    @State private var sessionRuntimeSamples: [RuntimeSample] = []

    private var snapshot: DashboardMetricSnapshot {
        DashboardMetricSnapshot(data: batteryData, realtimeData: realtimeData)
    }

    private var chartSamples: [RuntimeSample] {
        persistedRuntimeSamples.isEmpty ? sessionRuntimeSamples : persistedRuntimeSamples
    }

    var body: some View {
        VStack(spacing: 16) {
            RemainingTimeHeroSection(snapshot: snapshot, selectedHelp: $selectedHelp)

            if let specification = snapshot.specification {
                RuntimeBenchmarkSection(
                    snapshot: snapshot,
                    specification: specification,
                    selectedHelp: $selectedHelp
                )
            }

            PowerCenterSection(
                snapshot: snapshot,
                points: realtimeData,
                processes: processService.topProcesses,
                hasProcessSample: processService.hasSampled,
                isLive: batteryService.isLiveRefreshEnabled,
                onToggleLive: toggleLiveRefresh,
                onRefresh: refreshNow,
                selectedHelp: $selectedHelp
            )

            RemainingTimeHistorySection(
                snapshot: snapshot,
                samples: chartSamples,
                selectedHelp: $selectedHelp
            )

            CapacityBreakdownSection(snapshot: snapshot, selectedHelp: $selectedHelp)
            MetricReferenceSection(snapshot: snapshot, selectedHelp: $selectedHelp)
            ConsumerExplanationSection(snapshot: snapshot)
            CompleteHardwareDetailView(data: batteryData, selectedHelp: $selectedHelp)
            SystemDataWorkbenchView(
                snapshot: batteryService.systemDataSnapshot,
                isLive: batteryService.isLiveRefreshEnabled,
                onToggleLive: toggleLiveRefresh,
                onRefresh: refreshNow,
                selectedHelp: $selectedHelp
            )
        }
        .onAppear(perform: recordRuntimeSampleIfNeeded)
        .onChange(of: batteryData.lastUpdated) { _, _ in recordRuntimeSampleIfNeeded() }
    }

    private func toggleLiveRefresh() {
        let enabled = !batteryService.isLiveRefreshEnabled
        batteryService.setLiveRefreshEnabled(enabled)
        processService.setLiveRefreshEnabled(enabled)
    }

    private func refreshNow() {
        batteryService.refreshNow()
        processService.fetchProcesses()
    }

    /// UI-only session fallback. BatteryService can pass persisted samples once
    /// available; either way, invalid sentinels and sub-56-second duplicates are
    /// rejected by the shared RuntimeSample rules.
    private func recordRuntimeSampleIfNeeded() {
        guard persistedRuntimeSamples.isEmpty,
              !batteryData.isOnAC,
              let minutes = batteryData.timeRemainingMinutes else { return }
        let candidate = RuntimeSample(
            timestamp: batteryData.lastUpdated,
            minutesRemaining: minutes,
            percent: batteryData.percent
        )
        guard RuntimeSample.shouldAppend(candidate, after: sessionRuntimeSamples.last) else { return }
        sessionRuntimeSamples.append(candidate)
        if sessionRuntimeSamples.count > 240 {
            sessionRuntimeSamples.removeFirst(sessionRuntimeSamples.count - 240)
        }
    }
}

// MARK: - Dashboard data adapter

/// Keeps calculations in one place so every card uses the same definitions.
/// All source values remain the real model values; this adapter only chooses
/// fallbacks and formats the prototype's documented derived values.
struct DashboardMetricSnapshot {
    let data: BatteryData
    let realtimeData: [RealtimeDataPoint]

    var detail: BatteryHardwareDetail { data.hardwareDetail }
    var modelIdentifier: String {
        data.modelIdentifier.isEmpty ? BatteryService.hardwareModel() : data.modelIdentifier
    }
    var specification: BatteryModelSpecification? {
        data.modelSpecification ?? BatteryModelSpecification.lookup(modelIdentifier: modelIdentifier)
    }

    var currentPowerWatts: Double {
        if detail.systemPowerWatts > 0.1 { return detail.systemPowerWatts }
        if detail.systemLoad > 0 { return Double(detail.systemLoad) / 1000.0 }
        return max(0, data.currentPowerWatts)
    }

    var usualPowerWatts: Double {
        detail.averageTelemetryPowerWatts ?? max(currentPowerWatts, 0.1)
    }

    var peakPowerWatts: Double {
        max(realtimeData.map(\.power).max() ?? 0, currentPowerWatts)
    }

    var healthPercent: Double {
        detail.systemHealthPercent ?? Double(data.maxCapacityPercent)
    }

    var rawHealthPercent: Double {
        detail.rawHealthPercent ?? Double(data.maxCapacityPercent)
    }

    var designCapacity: Int { max(detail.designCapacity, data.designCapacity) }
    var fullChargeCapacity: Int { max(detail.appleRawMaxCapacity, data.maxCapacity) }
    var currentCapacity: Int {
        guard detail.presentRawFields.contains("AppleRawCurrentCapacity") else { return 0 }
        let raw = detail.appleRawCurrentCapacity
        guard fullChargeCapacity > 0 else { return max(0, raw) }
        return min(max(0, raw), fullChargeCapacity)
    }
    var usedSinceFull: Int { max(0, fullChargeCapacity - currentCapacity) }
    /// The consumer-facing difference between the original design and today's FCC.
    /// When Qmax is trustworthy it is split below into charge that is still present
    /// but outside the usable voltage window, and true learned chemical loss.
    var longTermCapacityGap: Int { max(0, designCapacity - fullChargeCapacity) }

    /// Qmax is useful for the split only when it sits between FCC and design.
    /// Outside that interval it is stale/incompatible, so the UI keeps the total
    /// gap intact instead of presenting a confident but false decomposition.
    var qmaxCapacityForBreakdown: Int? {
        guard let qmax = detail.qmax.filter({ $0 > 0 }).min(),
              fullChargeCapacity > 0,
              designCapacity > 0,
              qmax >= fullChargeCapacity,
              qmax <= designCapacity else { return nil }
        return qmax
    }

    var inaccessibleCapacity: Int? {
        qmaxCapacityForBreakdown.map { max(0, $0 - fullChargeCapacity) }
    }

    var truePermanentLoss: Int? {
        qmaxCapacityForBreakdown.map { max(0, designCapacity - $0) }
    }

    var designEnergyWh: Double? { specification?.designEnergyWh }
    var currentFullEnergyWh: Double? {
        guard let designEnergyWh, designCapacity > 0, fullChargeCapacity > 0 else { return nil }
        return designEnergyWh * Double(fullChargeCapacity) / Double(designCapacity)
    }
    var remainingEnergyWh: Double? {
        guard detail.presentRawFields.contains("AppleRawCurrentCapacity"),
              let designEnergyWh, designCapacity > 0, currentCapacity > 0 else { return nil }
        return designEnergyWh * Double(currentCapacity) / Double(designCapacity)
    }
    var unplugEstimateMinutes: Int? {
        guard let remainingEnergyWh, currentPowerWatts > 0.1 else { return nil }
        return max(1, Int((remainingEnergyWh / currentPowerWatts * 60).rounded()))
    }

    var displayedRuntimeMinutes: Int? {
        data.isOnAC ? unplugEstimateMinutes : data.timeRemainingMinutes
    }

    var temperatureHistoryText: String {
        guard detail.minimumTemperature != 0 || detail.maximumTemperature != 0 else {
            return dashboardText("p.history_learning", fallback: "历史范围正在积累")
        }
        return "\(detail.minimumTemperature)–\(detail.maximumTemperature)°C"
    }

    var voltageVolts: Double {
        if detail.packVoltage > 0 { return Double(detail.packVoltage) / 1000.0 }
        return data.voltage
    }

    var voltageHistoryText: String {
        guard detail.minimumPackVoltage > 0, detail.maximumPackVoltage > 0 else {
            return dashboardText("p.history_learning", fallback: "历史范围正在积累")
        }
        return LNum("%.2f–%.2f V", Double(detail.minimumPackVoltage) / 1000,
                    Double(detail.maximumPackVoltage) / 1000)
    }
}

// MARK: - 1. Runtime hero

private struct RemainingTimeHeroSection: View {
    let snapshot: DashboardMetricSnapshot
    @Binding var selectedHelp: MetricHelpContent?

    var body: some View {
        VStack(alignment: .leading, spacing: 17) {
            DashboardSectionHeader(
                icon: "clock",
                title: dashboardText("p.remaining", fallback: "还能用多久"),
                color: AppTheme.chargingCyan,
                help: DashboardHelp.runtime(snapshot),
                selection: $selectedHelp
            )

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 18) {
                    runtimePrimary
                        .frame(minWidth: 335, idealWidth: 390, maxWidth: 430)
                    priorityGrid(columns: 3)
                }
                VStack(spacing: 14) {
                    runtimePrimary
                    priorityGrid(columns: 1)
                }
            }
        }
        .padding(22)
        .finalDashboardCard(accent: AppTheme.chargingCyan)
    }

    private var runtimePrimary: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(snapshot.data.isOnAC
                         ? dashboardText("p.unplug_kicker", fallback: "按当前电脑状态，拔掉电源后大约还能用")
                         : dashboardText("p.src_note", fallback: "macOS 直接给出的系统估算"))
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(AppTheme.textSecondary)
                    if snapshot.data.isOnAC {
                        Text(dashboardText("p.unplug_badge", fallback: "拔电预计"))
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundStyle(AppTheme.batteryYellow)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(RoundedRectangle(cornerRadius: 5).fill(AppTheme.batteryYellow.opacity(0.09)))
                            .overlay(RoundedRectangle(cornerRadius: 5).stroke(AppTheme.batteryYellow.opacity(0.35)))
                    }
                }
                Spacer()
                MetricHelpButton(content: DashboardHelp.runtime(snapshot), selection: $selectedHelp)
            }

            runtimeNumber

            Text(snapshot.data.isOnAC
                 ? dashboardText("p.unplug_note", fallback: "预计值 · 按当前功耗估算拔电后的可用时间")
                 : dashboardText("p.usage_basis", fallback: "由 macOS 报告，不按功率重新计算"))
                .font(.system(size: 10.5))
                .foregroundStyle(AppTheme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)

            Divider().overlay(Color.white.opacity(0.06))

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text("\(snapshot.data.percent)%")
                        .font(.system(size: 24, weight: .semibold, design: .monospaced))
                        .foregroundStyle(AppTheme.textPrimary)
                    Text(dashboardText("p.system_charge", fallback: "macOS 电量"))
                        .font(.system(size: 10.5))
                        .foregroundStyle(AppTheme.textTertiary)
                    MetricHelpButton(content: DashboardHelp.stateOfCharge(snapshot), selection: $selectedHelp)
                    Spacer()
                    Text(snapshot.data.isOnAC ? L("gauge.ac") : L("gauge.battery"))
                        .font(.system(size: 10.5))
                        .foregroundStyle(AppTheme.textSecondary)
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.06))
                        Capsule()
                            .fill(AppTheme.chargingGradient)
                            .frame(width: geo.size.width * CGFloat(min(max(snapshot.data.percent, 0), 100)) / 100)
                    }
                }
                .frame(height: 8)
                .accessibilityHidden(true)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, minHeight: 218, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(AppTheme.chargingCyan.opacity(0.025))
        )
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(AppTheme.chargingCyan.opacity(0.15), lineWidth: 1))
    }

    @ViewBuilder
    private var runtimeNumber: some View {
        if let minutes = snapshot.displayedRuntimeMinutes, minutes > 0 {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(minutes / 60)")
                    .font(.system(size: 60, weight: .light, design: .monospaced))
                    .foregroundStyle(AppTheme.chargingCyan)
                    .contentTransition(.numericText())
                Text("h")
                    .font(.system(size: 15, weight: .medium, design: .monospaced))
                    .foregroundStyle(AppTheme.textTertiary)
                Text(String(format: "%02d", minutes % 60))
                    .font(.system(size: 60, weight: .light, design: .monospaced))
                    .foregroundStyle(AppTheme.chargingCyan)
                    .contentTransition(.numericText())
                Text("m")
                    .font(.system(size: 15, weight: .medium, design: .monospaced))
                    .foregroundStyle(AppTheme.textTertiary)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.68)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(minutes / 60) 小时 \(minutes % 60) 分钟")
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Text("—")
                    .font(.system(size: 60, weight: .light, design: .monospaced))
                    .foregroundStyle(AppTheme.chargingCyan)
                Text(L("calculating"))
                    .font(.system(size: 11))
                    .foregroundStyle(AppTheme.textTertiary)
            }
        }
    }

    private func priorityGrid(columns: Int) -> some View {
        let gridItems = Array(repeating: GridItem(.flexible(), spacing: 10), count: columns)
        return LazyVGrid(columns: gridItems, alignment: .leading, spacing: 10) {
            PriorityMetricCard(
                icon: "heart",
                title: dashboardText("p.priority_health", fallback: "整块电池的健康状况"),
                value: LNum("%.0f", snapshot.healthPercent), unit: "%",
                status: snapshot.healthPercent >= 90 ? L("stat.health_excellent") : L("stat.health_good"),
                range: "80–100%",
                history: dashboardText("p.history_learning", fallback: "历史范围正在积累"),
                lowImpact: dashboardText("p.health_low_short", fallback: "低于 80% 可能提示检修，续航缩短"),
                highImpact: dashboardText("p.health_high_short", fallback: "续航更接近新机"),
                color: AppTheme.batteryYellow,
                help: DashboardHelp.health(snapshot),
                selection: $selectedHelp
            )
            PriorityMetricCard(
                icon: "bolt.fill",
                title: dashboardText("p.priority_power", fallback: "当前电脑的使用功率"),
                value: LNum("%.1f", snapshot.currentPowerWatts), unit: "W",
                status: LNum("%.0f%% %@", snapshot.currentPowerWatts / max(snapshot.usualPowerWatts, 0.1) * 100,
                             dashboardText("p.p_ratio", fallback: "相对平时")),
                range: LNum("%.1f–%.1fW", snapshot.usualPowerWatts * 0.85, snapshot.usualPowerWatts * 1.3),
                history: LNum("%@ %.1fW", dashboardText("p.history_peak", fallback: "本次监控峰值"), snapshot.peakPowerWatts),
                lowImpact: dashboardText("p.power_low_short", fallback: "续航更长，发热更少"),
                highImpact: dashboardText("p.power_high_short", fallback: "续航更短，发热增加"),
                color: AppTheme.chargingBlue,
                help: DashboardHelp.power(snapshot),
                selection: $selectedHelp
            )
            PriorityMetricCard(
                icon: "thermometer.medium",
                title: dashboardText("p.priority_temp", fallback: "当前电池温度"),
                value: LNum("%.1f", snapshot.data.temperatureCelsius), unit: "°C",
                status: snapshot.data.temperatureCelsius < 35 ? L("stat.temp_normal") : L("stat.temp_high"),
                range: "15–35°C",
                history: snapshot.temperatureHistoryText,
                lowImpact: dashboardText("p.temp_low_short", fallback: "续航和功率会暂时下降"),
                highImpact: dashboardText("p.temp_high_short", fallback: "发热增加并加速老化"),
                color: snapshot.data.temperatureCelsius < 35 ? AppTheme.chargingCyan : AppTheme.batteryYellow,
                help: DashboardHelp.temperature(snapshot),
                selection: $selectedHelp
            )
        }
    }
}

private struct PriorityMetricCard: View {
    let icon: String
    let title: String
    let value: String
    let unit: String
    let status: String
    let range: String
    let history: String
    let lowImpact: String
    let highImpact: String
    let color: Color
    let help: MetricHelpContent
    @Binding var selection: MetricHelpContent?

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(color)
                Text(title)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(AppTheme.textTertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                Spacer(minLength: 2)
                MetricHelpButton(content: help, selection: $selection)
            }

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(.system(size: 23, weight: .semibold, design: .monospaced))
                    .foregroundStyle(AppTheme.textPrimary)
                    .contentTransition(.numericText())
                Text(unit)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(AppTheme.textTertiary)
            }
            Text(status)
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.72)

            Divider().overlay(Color.white.opacity(0.055))

            HStack(alignment: .firstTextBaseline) {
                Text(dashboardText("p.good_range", fallback: "合理范围"))
                    .font(.system(size: 8.5))
                    .foregroundStyle(AppTheme.textTertiary)
                Spacer()
                Text(range)
                    .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(AppTheme.chargingCyan)
            }
            Text(history)
                .font(.system(size: 8.5))
                .foregroundStyle(AppTheme.textTertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            HStack(alignment: .top, spacing: 5) {
                impact(text: lowImpact, arrow: "arrow.down", tint: AppTheme.chargingBlue)
                impact(text: highImpact, arrow: "arrow.up", tint: AppTheme.batteryYellow)
            }
        }
        .padding(13)
        .frame(maxWidth: .infinity, minHeight: 205, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.022)))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.06), lineWidth: 1))
    }

    private func impact(text: String, arrow: String, tint: Color) -> some View {
        HStack(alignment: .top, spacing: 3) {
            Image(systemName: arrow)
                .font(.system(size: 7, weight: .bold))
                .foregroundStyle(tint)
                .padding(.top, 2)
            Text(text)
                .font(.system(size: 8))
                .foregroundStyle(AppTheme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(6)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 7).fill(Color.white.opacity(0.018)))
    }
}

// MARK: - 2. Published benchmark x this Mac

private struct RuntimeBenchmarkSection: View {
    let snapshot: DashboardMetricSnapshot
    let specification: BatteryModelSpecification
    @Binding var selectedHelp: MetricHelpContent?

    private var officialPower: Double { specification.designEnergyWh / specification.officialWebHours }
    private var sameLoadHours: Double {
        (snapshot.currentFullEnergyWh ?? specification.designEnergyWh) / officialPower
    }
    private var actualHours: Double {
        if !snapshot.data.isOnAC, let minutes = snapshot.data.timeRemainingMinutes { return Double(minutes) / 60 }
        return Double(snapshot.unplugEstimateMinutes ?? 0) / 60
    }
    private var powerRatio: Double { snapshot.currentPowerWatts / max(officialPower, 0.1) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            DashboardSectionHeader(
                icon: "scale.3d",
                title: dashboardText("p.runtime_audit_tag", fallback: "公开基准 × 这台电脑"),
                color: AppTheme.accentPurple,
                help: DashboardHelp.officialBenchmark(snapshot, specification: specification),
                selection: $selectedHelp,
                trailing: AnyView(
                    Link(destination: specification.sourceURL) {
                        Text("APPLE TECH SPECS ↗")
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundStyle(AppTheme.textTertiary)
                    }
                )
            )

            Text(dashboardText("p.runtime_audit_title", fallback: "为什么官方 15 小时，到现在可能只剩几小时？"))
                .font(.system(size: 19, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.textPrimary)

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 16) {
                    benchmarkBody
                    verdict
                        .frame(width: 255)
                }
                VStack(spacing: 14) {
                    benchmarkBody
                    verdict
                }
            }

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 16) { methodNote; conditionNote }
                VStack(alignment: .leading, spacing: 9) { methodNote; conditionNote }
            }
        }
        .padding(22)
        .finalDashboardCard(accent: AppTheme.accentPurple)
    }

    private var benchmarkBody: some View {
        VStack(spacing: 12) {
            VStack(spacing: 10) {
                RuntimeAuditRow(
                    title: dashboardText("p.audit_official", fallback: "Apple 新机无线网页测试"),
                    note: LNum("%.1fWh · %.2fW · VIDEO %.0fh", specification.designEnergyWh, officialPower,
                               specification.officialVideoHours),
                    hours: specification.officialWebHours,
                    maximum: specification.officialWebHours,
                    color: AppTheme.accentPurple
                )
                RuntimeAuditRow(
                    title: dashboardText("p.audit_same_load", fallback: "这块电池在同样轻负载下"),
                    note: LNum("%.1fWh", snapshot.currentFullEnergyWh ?? 0),
                    hours: sameLoadHours,
                    maximum: specification.officialWebHours,
                    color: AppTheme.chargingCyan
                )
                deltaText(
                    dashboardText("p.audit_capacity_note", fallback: "容量影响：相比新机约少 %.1f 小时"),
                    value: max(0, specification.officialWebHours - sameLoadHours),
                    color: AppTheme.chargingCyan
                )
                RuntimeAuditRow(
                    title: dashboardText("p.audit_actual", fallback: snapshot.data.isOnAC ? "当前状态的拔电预计" : "现在的系统剩余时间"),
                    note: snapshot.data.isOnAC
                        ? LNum("%.1fWh ÷ %.1fW", snapshot.remainingEnergyWh ?? 0, snapshot.currentPowerWatts)
                        : dashboardText("p.direct_source", fallback: "macOS 系统直读"),
                    hours: actualHours,
                    maximum: specification.officialWebHours,
                    color: AppTheme.batteryYellow
                )
            }
            .padding(15)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.black.opacity(0.12)))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.055), lineWidth: 1))

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 9) { officialConfiguration; currentConfiguration }
                VStack(spacing: 9) { officialConfiguration; currentConfiguration }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var verdict: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(LNum("%.1f×", powerRatio))
                .font(.system(size: 40, weight: .light, design: .monospaced))
                .foregroundStyle(AppTheme.batteryYellow)
            Text(dashboardText("p.audit_cause", fallback: "主要原因：当前负载"))
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(AppTheme.textPrimary)
            Text(
                dashboardText(
                    "p.audit_cause_body",
                    fallback: "当前功率约为 Apple 无线网页测试隐含平均功率的 {ratio} 倍。满电只代表电池装满，不代表电脑正在运行官方轻负载。",
                    replacements: ["ratio": LNum("%.1f", powerRatio)]
                )
            )
                .font(.system(size: 10.5))
                .foregroundStyle(AppTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(3)
        }
        .padding(17)
        .frame(maxWidth: .infinity, minHeight: 175, alignment: .topLeading)
        .background(
            RadialGradient(colors: [AppTheme.batteryYellow.opacity(0.13), AppTheme.batteryYellow.opacity(0.025)],
                           center: .topTrailing, startRadius: 0, endRadius: 230)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(AppTheme.batteryYellow.opacity(0.18), lineWidth: 1))
    }

    private var officialConfiguration: some View {
        configurationTile(
            label: dashboardText("p.audit_test_config", fallback: "Apple 测试机"),
            value: "M4 · \(specification.testCPUCoreCount)C CPU / \(specification.testGPUCoreCount)C GPU · \(specification.testMemoryGB)GB / \(specification.testStorageGB)GB"
        )
    }

    private var currentConfiguration: some View {
        let memoryGB = Int(ProcessInfo.processInfo.physicalMemory / 1_073_741_824)
        return configurationTile(
            label: dashboardText("p.audit_your_config", fallback: "你的电脑"),
            value: "\(snapshot.detail.chipModel.isEmpty ? snapshot.modelIdentifier : snapshot.detail.chipModel) · \(ProcessInfo.processInfo.processorCount)C CPU · \(memoryGB)GB"
        )
    }

    private func configurationTile(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 8.5))
                .foregroundStyle(AppTheme.textTertiary)
            Text(value)
                .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                .foregroundStyle(AppTheme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 55, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.018)))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.05)))
    }

    private func deltaText(_ format: String, value: Double, color: Color) -> some View {
        let number = LNum("%.1f", value)
        let rendered = format.contains("{hours}")
            ? format.replacingOccurrences(of: "{hours}", with: number)
            : String(format: format, locale: Locale(identifier: L10n.shared.effectiveCode), value)
        return Text("↳ " + rendered)
            .font(.system(size: 9))
            .foregroundStyle(color)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 178)
    }

    private var methodNote: some View {
        Text(dashboardText("p.audit_method", fallback: "方法：53.8Wh ÷ 15h ≈ 3.59W，先分离容量影响，再与当前系统功耗比较。"))
            .font(.system(size: 9))
            .foregroundStyle(AppTheme.textTertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
    private var conditionNote: some View {
        Text(dashboardText("p.audit_conditions", fallback: "官方无线网页测试使用 25 个网站、Wi‑Fi、固定亮度与关闭键盘背光；它不是满负载测试。"))
            .font(.system(size: 9))
            .foregroundStyle(AppTheme.textTertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct RuntimeAuditRow: View {
    let title: String
    let note: String
    let hours: Double
    let maximum: Double
    let color: Color

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 11) { label; bar; hoursLabel }
            VStack(alignment: .leading, spacing: 7) { label; HStack { bar; hoursLabel } }
        }
    }

    private var label: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(AppTheme.textPrimary)
            Text(note)
                .font(.system(size: 8, design: .monospaced))
                .foregroundStyle(AppTheme.textTertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(minWidth: 160, idealWidth: 190, alignment: .leading)
    }
    private var bar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 5).fill(Color.white.opacity(0.04))
                RoundedRectangle(cornerRadius: 5)
                    .fill(LinearGradient(colors: [color.opacity(0.35), color], startPoint: .leading, endPoint: .trailing))
                    .frame(width: geo.size.width * CGFloat(min(1, max(0.03, hours / max(maximum, 0.1)))))
            }
        }
        .frame(minWidth: 120, maxWidth: .infinity, minHeight: 18, maxHeight: 18)
    }
    private var hoursLabel: some View {
        Text(LNum("%.1f h", hours))
            .font(.system(size: 14, weight: .medium, design: .monospaced))
            .foregroundStyle(AppTheme.textPrimary)
            .frame(width: 62, alignment: .trailing)
    }
}

// MARK: - 3. System runtime history / unplug forecast

private struct RemainingTimeHistorySection: View {
    let snapshot: DashboardMetricSnapshot
    let samples: [RuntimeSample]
    @Binding var selectedHelp: MetricHelpContent?
    @State private var selectedDate: Date?
    @State private var showLearning = false

    private var directPoints: [RuntimeChartPoint] {
        samples
            .filter { RuntimeSample.isValid(minutes: $0.minutesRemaining) }
            .sorted { $0.timestamp < $1.timestamp }
            .map { .init(date: $0.timestamp, hours: Double($0.minutesRemaining) / 60, isForecast: false) }
    }

    private var forecastPoints: [RuntimeChartPoint] {
        guard directPoints.isEmpty, snapshot.data.isOnAC,
              let minutes = snapshot.unplugEstimateMinutes, minutes > 0 else { return [] }
        let start = snapshot.data.lastUpdated
        return [
            .init(date: start, hours: Double(minutes) / 60, isForecast: true),
            .init(date: start.addingTimeInterval(Double(minutes) * 60), hours: 0, isForecast: true),
        ]
    }

    private var points: [RuntimeChartPoint] { directPoints.isEmpty ? forecastPoints : directPoints }
    private var isForecast: Bool { directPoints.isEmpty && !forecastPoints.isEmpty }
    private var selectedPoint: RuntimeChartPoint? {
        guard let selectedDate, !points.isEmpty else { return nil }
        return points.min { abs($0.date.timeIntervalSince(selectedDate)) < abs($1.date.timeIntervalSince(selectedDate)) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            DashboardSectionHeader(
                icon: "waveform.path.ecg",
                title: isForecast
                    ? dashboardText("p.unplug_trend", fallback: "拔电后的预计续航")
                    : dashboardText("p.remaining_trend", fallback: "系统剩余时间记录"),
                color: isForecast ? AppTheme.batteryYellow : AppTheme.chargingCyan,
                help: DashboardHelp.runtimeHistory(snapshot, isForecast: isForecast),
                selection: $selectedHelp
            )

            Text(isForecast
                 ? dashboardText("p.unplug_head", fallback: "还没有放电历史，先按当前电脑状态展示拔电后的虚线预测")
                 : dashboardText("p.dual_head", fallback: "横轴是时间，纵轴是 macOS 当时给出的剩余小时；悬停可看每个时刻"))
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(AppTheme.textPrimary)

            chart
                .frame(height: 270)

            HStack(spacing: 16) {
                legend(color: isForecast ? AppTheme.batteryYellow : AppTheme.chargingCyan,
                       text: isForecast
                        ? dashboardText("p.unplug_legend", fallback: "拔电预计 · 不是系统历史")
                        : dashboardText("p.chart_hours", fallback: "系统剩余小时"))
                Spacer()
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 18) { historyMeta }
                VStack(alignment: .leading, spacing: 5) { historyMeta }
            }

            DisclosureGroup(isExpanded: $showLearning) {
                HStack(alignment: .top, spacing: 9) {
                    learningItem(title: dashboardText("p.ul_minutes", fallback: "使用几分钟"),
                                 body: dashboardText("p.learn_minutes", fallback: "看出当前功率变化如何影响剩余时间"))
                    learningItem(title: dashboardText("p.ul_hours", fallback: "使用几小时"),
                                 body: dashboardText("p.learn_hours", fallback: "形成今天的功率、温度与续航范围"))
                    learningItem(title: dashboardText("p.ul_days", fallback: "使用几天"),
                                 body: dashboardText("p.learn_days", fallback: "开始识别常用场景，解释哪些习惯影响续航"))
                }
                .padding(.top, 10)
            } label: {
                Text(dashboardText("p.learn_summary", fallback: "继续使用后，这项数据还能告诉我什么？"))
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(AppTheme.textSecondary)
            }
            .tint(AppTheme.accentPurple)
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.018)))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.055)))
        }
        .padding(22)
        .finalDashboardCard(accent: isForecast ? AppTheme.batteryYellow : AppTheme.chargingCyan)
    }

    @ViewBuilder
    private var chart: some View {
        if points.isEmpty {
            ZStack {
                RoundedRectangle(cornerRadius: 13).fill(Color.black.opacity(0.18))
                VStack(spacing: 9) {
                    Image(systemName: "waveform.path.ecg")
                        .font(.system(size: 25, weight: .light))
                        .foregroundStyle(AppTheme.textTertiary)
                    Text(dashboardText("p.no_history", fallback: "当前还没有可用的系统续航历史；拔下电源后会开始记录"))
                        .font(.system(size: 11.5))
                        .foregroundStyle(AppTheme.textTertiary)
                }
            }
            .overlay(RoundedRectangle(cornerRadius: 13).stroke(Color.white.opacity(0.055)))
        } else {
            Chart {
                ForEach(points) { point in
                    AreaMark(
                        x: .value(dashboardText("p.chart_time", fallback: "时间"), point.date),
                        y: .value(dashboardText("p.chart_hours", fallback: "剩余小时"), point.hours)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [(isForecast ? AppTheme.batteryYellow : AppTheme.chargingCyan).opacity(0.22), .clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .interpolationMethod(isForecast ? .linear : .stepStart)

                    LineMark(
                        x: .value(dashboardText("p.chart_time", fallback: "时间"), point.date),
                        y: .value(dashboardText("p.chart_hours", fallback: "剩余小时"), point.hours)
                    )
                    .foregroundStyle(isForecast ? AppTheme.batteryYellow : AppTheme.chargingCyan)
                    .lineStyle(StrokeStyle(lineWidth: 2.3, dash: isForecast ? [7, 6] : []))
                    .interpolationMethod(isForecast ? .linear : .stepStart)
                }

                if let selectedPoint {
                    RuleMark(x: .value("selected", selectedPoint.date))
                        .foregroundStyle(Color.white.opacity(0.35))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    PointMark(
                        x: .value("selected-time", selectedPoint.date),
                        y: .value("selected-hours", selectedPoint.hours)
                    )
                    .foregroundStyle(isForecast ? AppTheme.batteryYellow : AppTheme.chargingCyan)
                    .symbolSize(42)
                    .annotation(position: .top, spacing: 9) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(selectedPoint.date.formatted(date: .omitted, time: .shortened))
                            Text(LNum("%.1f h · %d min", selectedPoint.hours, Int((selectedPoint.hours * 60).rounded())))
                                .foregroundStyle(isForecast ? AppTheme.batteryYellow : AppTheme.chargingCyan)
                        }
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .padding(9)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color(red: 0.045, green: 0.065, blue: 0.075)))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(AppTheme.chargingCyan.opacity(0.18)))
                    }
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) { value in
                    AxisGridLine().foregroundStyle(AppTheme.chargingCyan.opacity(0.055))
                    AxisValueLabel {
                        if let date = value.as(Date.self) {
                            Text(date, format: .dateTime.hour().minute())
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundStyle(AppTheme.textTertiary)
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                    AxisGridLine().foregroundStyle(AppTheme.chargingCyan.opacity(0.055))
                    AxisValueLabel {
                        if let h = value.as(Double.self) {
                            Text(LNum("%.1f h", h))
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundStyle(isForecast ? AppTheme.batteryYellow : AppTheme.chargingCyan)
                        }
                    }
                }
            }
            .chartXSelection(value: $selectedDate)
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 13).fill(Color.black.opacity(0.18)))
            .overlay(RoundedRectangle(cornerRadius: 13).stroke(Color.white.opacity(0.055)))
        }
    }

    @ViewBuilder
    private var historyMeta: some View {
        metaPill(isForecast
                 ? dashboardText("p.unplug_note", fallback: "来源：当前状态估算")
                 : dashboardText("p.direct_source", fallback: "来源：macOS 系统值"))
        metaPill(isForecast
                 ? dashboardText("p.forecast_only", fallback: "虚线不会写入系统历史")
                 : dashboardText("p.sample_cadence_short", fallback: "约每 56 秒记录一次"))
        metaPill(isForecast
                 ? dashboardText("p.unplug_method", fallback: "当前储能 ÷ 当前功率")
                 : dashboardText("p.no_recalc", fallback: "不按功率二次换算"))
    }

    private func metaPill(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 9.5))
            .foregroundStyle(AppTheme.textTertiary)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(Capsule().fill(Color.white.opacity(0.025)))
    }

    private func legend(color: Color, text: String) -> some View {
        HStack(spacing: 6) {
            Capsule().fill(color).frame(width: 22, height: 2)
            Text(text).font(.system(size: 9.5)).foregroundStyle(AppTheme.textTertiary)
        }
    }

    private func learningItem(title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(AppTheme.chargingCyan)
            Text(body)
                .font(.system(size: 9))
                .foregroundStyle(AppTheme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

private struct RuntimeChartPoint: Identifiable {
    let date: Date
    let hours: Double
    let isForecast: Bool
    var id: String { "\(date.timeIntervalSince1970)-\(isForecast)" }
}

// MARK: - Shared dashboard chrome

struct DashboardSectionHeader: View {
    let icon: String
    let title: String
    let color: Color
    let help: MetricHelpContent?
    @Binding var selection: MetricHelpContent?
    var trailing: AnyView? = nil

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(color)
            Text(title)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(AppTheme.textPrimary)
            if let help { MetricHelpButton(content: help, selection: $selection) }
            Spacer()
            if let trailing { trailing }
        }
    }
}

private struct FinalDashboardCardModifier: ViewModifier {
    let accent: Color
    @State private var hovering = false

    func body(content: Content) -> some View {
        content
            .background(
                LinearGradient(
                    colors: [Color(red: 0.09, green: 0.115, blue: 0.13),
                             Color(red: 0.065, green: 0.08, blue: 0.095)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 17, style: .continuous)
                    .stroke(hovering ? accent.opacity(0.26) : Color.white.opacity(0.065), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.30), radius: hovering ? 26 : 18, y: 8)
            .onHover { hovering = $0 }
            .animation(.easeOut(duration: 0.18), value: hovering)
    }
}

extension View {
    func finalDashboardCard(accent: Color) -> some View {
        modifier(FinalDashboardCardModifier(accent: accent))
    }
}
