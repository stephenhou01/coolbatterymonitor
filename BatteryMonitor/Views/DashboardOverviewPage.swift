import SwiftUI

struct DashboardOverviewPage: View {
    @EnvironmentObject private var batteryService: BatteryService
    @Binding var selectedHelp: MetricHelpContent?

    private var data: BatteryData { batteryService.batteryData }
    private var snapshot: DashboardMetricSnapshot {
        DashboardMetricSnapshot(
            data: data,
            realtimeData: batteryService.realtimeData,
            systemRuntimeFallbackSample: batteryService.runtimeSamples.last
        )
    }
    private var presentation: MenuBarPresentation {
        .init(data: data, chargeSpeed: batteryService.chargeSpeed)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                DashboardPageHeader(
                    title: L("app.title"),
                    subtitle: data.modelIdentifier.isEmpty ? L("app.subtitle") : data.modelIdentifier,
                    trailing: AppearanceModePicker()
                )

                overviewHero
                metricRail
                statusBanner
            }
            .frame(maxWidth: 980)
            .padding(.horizontal, 34)
            .padding(.top, 28)
            .padding(.bottom, 34)
            .frame(maxWidth: .infinity)
        }
        .background(overviewBackground)
    }

    private var overviewBackground: some View {
        ZStack {
            AppTheme.background
            LinearGradient(colors: [AppTheme.chargingBlue.opacity(0.08), .clear, AppTheme.batteryGreen.opacity(0.035)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }

    private var overviewHero: some View {
        // One snapshot for the whole card: it is a computed property that refilters
        // the realtime buffer on every read, and this card needs six values from it.
        let s = snapshot
        // Stacked rather than side by side: charge and the three runtime
        // estimates answer "how much is left", the diagram answers "where is it
        // going". Putting the second beside the first forced the card wide enough
        // that both halves ran cramped.
        return VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 22) {
                Text(presentation.percentText)
                    .font(.system(size: 68, weight: .light, design: .rounded))
                    .foregroundStyle(AppTheme.textPrimary)
                    .monospacedDigit()
                    .fixedSize()

                VStack(alignment: .leading, spacing: 9) {
                    HStack(spacing: 7) {
                        Text(dashboardText("shell.runtime_comparison", fallback: "续航时间对照"))
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(AppTheme.textSecondary)
                        MetricHelpButton(content: DashboardHelp.runtime(s),
                                         selection: $selectedHelp)
                    }

                    if s.designEnergyWh == nil {
                        // Both derived calibres depend on design energy, so an
                        // unrecognised model blanks them together. One honest line
                        // beats two cards showing "—".
                        VStack(spacing: 9) {
                            runtimeCard(
                                title: dashboardText("p.runtime_system_label", fallback: "macOS 系统时间"),
                                minutes: s.systemRuntimeMinutes,
                                basis: systemRuntimeBasis(s),
                                color: AppTheme.chargingCyan,
                                emphasised: true
                            )
                            derivedUnavailableCard
                        }
                    } else {
                        // All three share one vertical shape. The Apple estimate
                        // used to be a wide horizontal card, which stopped fitting
                        // the moment the row became three columns instead of one:
                        // its 32pt figure squeezed the title down to one character
                        // per line.
                        HStack(spacing: 10) {
                            runtimeCard(
                                title: dashboardText("p.runtime_system_label", fallback: "macOS 系统时间"),
                                minutes: s.systemRuntimeMinutes,
                                basis: systemRuntimeBasis(s),
                                color: AppTheme.chargingCyan,
                                emphasised: true
                            )
                            runtimeCard(
                                title: dashboardText("p.runtime_stable_label", fallback: "稳健估算"),
                                minutes: s.stableRuntimeMinutes,
                                basis: stableRuntimeBasis(s),
                                color: AppTheme.accentPurple
                            )
                            runtimeCard(
                                title: dashboardText("p.runtime_current_label", fallback: "当前负载估算"),
                                minutes: s.currentLoadRuntimeMinutes,
                                basis: currentRuntimeBasis(s),
                                color: AppTheme.batteryYellow
                            )
                        }
                    }
                }
            }

            Divider().overlay(AppTheme.cardBorder)

            batteryStatusPanel(s)
        }
        .padding(28)
        .background(RoundedRectangle(cornerRadius: 16).fill(AppTheme.cardBackground))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppTheme.cardBorder))
        .shadow(color: Color.black.opacity(0.10), radius: 22, y: 8)
    }

    /// One shape for all three estimates. `emphasised` is the Apple calibre: it
    /// gets the tinted background and a larger figure, but the same geometry, so
    /// the row cannot break the way a mixed horizontal/vertical row did.
    ///
    /// Fixed height on purpose. With `Spacer` doing the vertical work, one card
    /// growing dragged the other two with it and left them mostly empty.
    private func runtimeCard(
        title: String,
        minutes: Int?,
        basis: String,
        color: Color,
        emphasised: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                if emphasised {
                    Image(systemName: "apple.logo")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(color)
                }
                Text(title)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(emphasised ? AppTheme.textPrimary : AppTheme.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            Text(basis)
                .font(.system(size: 9))
                .foregroundStyle(AppTheme.textTertiary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                // Reserve both lines whether or not the basis needs them, so the
                // three figures always sit on the same baseline.
                .frame(maxWidth: .infinity, minHeight: 24, alignment: .topLeading)
            Text(MenuBarPresentation.durationText(minutes))
                .font(.system(size: emphasised ? 26 : 22, weight: .medium, design: .rounded))
                .foregroundStyle(color)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.55)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: 92, maxHeight: 92, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 11)
            .fill(emphasised ? color.opacity(0.06) : AppTheme.contrastOverlay(0.025)))
        .overlay(RoundedRectangle(cornerRadius: 11)
            .stroke(emphasised ? color.opacity(0.20) : AppTheme.cardBorder))
        .accessibilityElement(children: .combine)
    }

    private var derivedUnavailableCard: some View {
        Text(dashboardText("shell.derived_runtime_unavailable",
                           fallback: "本机型号缺少额定电量数据，无法换算稳健估算与当前负载估算"))
            .font(.system(size: 10))
            .foregroundStyle(AppTheme.textTertiary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 11).fill(AppTheme.contrastOverlay(0.025)))
            .overlay(RoundedRectangle(cornerRadius: 11).stroke(AppTheme.cardBorder))
    }

    /// Concise basis lines. Each says where the number comes from in one breath;
    /// the question mark next to the section title carries the long version.
    private func systemRuntimeBasis(_ s: DashboardMetricSnapshot) -> String {
        guard s.systemRuntimeMinutes != nil else {
            return dashboardText("shell.apple_runtime_unavailable", fallback: "Apple 官方系统预估 · 拔电使用后生成")
        }
        // On AC the gauge parks its estimate, so what is on screen is the last
        // valid reading rather than a live one — say so instead of implying live.
        guard data.timeRemainingMinutes != nil else {
            return dashboardText("shell.apple_runtime_last_note",
                                 fallback: "接电状态下保留最近一次有效的 Apple 官方系统预估")
        }
        return dashboardText("shell.system_runtime_basis", fallback: "Apple 官方算法 · 与菜单栏一致")
    }

    private func stableRuntimeBasis(_ s: DashboardMetricSnapshot) -> String {
        guard s.stableRuntimeMinutes != nil else {
            return dashboardText("shell.stable_runtime_collecting",
                                 fallback: "正在积累样本 {samples}/5",
                                 replacements: ["samples": "\(s.recentStablePowerSamples.count)"])
        }
        return dashboardText("shell.stable_runtime_basis", fallback: "近 10 分钟功耗中位数")
    }

    private func currentRuntimeBasis(_ s: DashboardMetricSnapshot) -> String {
        guard s.currentLoadRuntimeMinutes != nil else {
            return dashboardText("shell.instant_runtime_waiting", fallback: "等待有效的瞬时功率数据")
        }
        return dashboardText("shell.current_runtime_basis",
                             fallback: "按此刻 {power} W 计算",
                             replacements: ["power": LNum("%.1f", s.currentPowerWatts)])
    }


    private var batterySymbol: String {
        switch data.percent {
        case 76...: return "battery.100percent"
        case 51...: return "battery.75percent"
        case 26...: return "battery.50percent"
        default: return "battery.25percent"
        }
    }

    /// State plus the two numbers that are not already in the metric rail one row
    /// below: signed battery current, and time to full while charging.
    private func batteryStatusPanel(_ s: DashboardMetricSnapshot) -> some View {
        let state = BatteryPowerState.resolve(s)
        // Diagram left, readings right. Stacking these vertically left the 290pt
        // drawing marooned in the middle of a very wide card with a full-width
        // capsule under it. Pairing them keeps the row compact and reads as one
        // thing: the picture and the numbers behind it.
        return HStack(alignment: .center, spacing: 26) {
            Spacer(minLength: 0)

            PowerFlowDiagram(
                flow: PowerFlow.resolve(s),
                batteryPercent: data.percent,
                batterySymbol: batterySymbol,
                chargeSpeed: batteryService.chargeSpeed,
                isLive: batteryService.isLiveRefreshEnabled
            )
            .fixedSize()

            VStack(alignment: .leading, spacing: 8) {
                Text(stateTitle(state))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(stateTint(state))
                    .fixedSize(horizontal: false, vertical: true)

                if state != .full {
                    statusDetailRow(
                        label: dashboardText("shell.battery_current", fallback: "电流"),
                        value: batteryCurrentText(s),
                        tint: stateTint(state)
                    )
                }
                if state == .charging {
                    statusDetailRow(
                        label: dashboardText("shell.time_to_full", fallback: "充满还需"),
                        value: MenuBarPresentation.durationText(s.timeToFullMinutes),
                        tint: AppTheme.batteryGreen
                    )
                }

                // Every number in this row comes from one gauge publish, so one
                // stamp covers it. Same wording as the help drawer's field lines.
                TimelineView(.periodic(from: Date(), by: 1)) { timeline in
                    Text(MetricFieldFreshness.countdownText(s.rawFieldReadAt, now: timeline.date))
                        .font(.system(size: 9))
                        .foregroundStyle(AppTheme.textTertiary)
                        .monospacedDigit()
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(width: 230, alignment: .leading)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
    }

    private func statusDetailRow(label: String, value: String, tint: Color) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(AppTheme.textTertiary)
            Spacer(minLength: 6)
            Text(value)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(tint)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 8).fill(AppTheme.contrastOverlay(0.03)))
        .accessibilityElement(children: .combine)
    }

    /// Signed on purpose: the sign is the direction, and a negative current while
    /// plugged in is exactly the state the old single status line hid.
    private func batteryCurrentText(_ s: DashboardMetricSnapshot) -> String {
        guard let milliamps = s.batteryCurrentMilliamps else { return "—" }
        return LNum("%+.2f A", Double(milliamps) / 1000)
    }

    private func stateTitle(_ state: BatteryPowerState) -> String {
        switch state {
        case .charging: return dashboardText("shell.charging", fallback: "正在充电")
        case .full: return dashboardText("shell.state_full", fallback: "已充满 · 电源供电")
        case .pluggedIdle: return dashboardText("shell.state_plugged_idle", fallback: "已接电源 · 未充电")
        case .pluggedDischarging:
            return dashboardText("shell.state_plugged_discharging", fallback: "已接电源 · 电池放电中")
        case .discharging: return dashboardText("shell.on_battery", fallback: "正在使用电池")
        }
    }

    private func stateTint(_ state: BatteryPowerState) -> Color {
        switch state {
        case .charging, .full: return AppTheme.batteryGreen
        case .pluggedIdle: return AppTheme.batteryYellow
        case .pluggedDischarging: return AppTheme.chargingCyan
        case .discharging: return AppTheme.chargingCyan
        }
    }

    private var metricRail: some View {
        // ViewThatFits builds both candidates, so the grid is constructed twice.
        // Building the snapshot once here means 2 rebuilds instead of ~26: each
        // of the seven cards used to re-read `snapshot` for its value and again
        // for its help sheet.
        let s = snapshot
        return ViewThatFits(in: .horizontal) {
            metricGrid(s, columnCount: 7)
                .frame(minWidth: 760)
            metricGrid(s, columnCount: 4)
        }
        .padding(.vertical, 18)
        .background(RoundedRectangle(cornerRadius: 15).fill(AppTheme.cardBackground))
        .overlay(RoundedRectangle(cornerRadius: 15).stroke(AppTheme.cardBorder))
    }

    private func metricGrid(_ s: DashboardMetricSnapshot, columnCount: Int) -> some View {
        // Last ten minutes at our 10 s poll. Sliced once for all four trend lines
        // rather than per card, which ViewThatFits would have doubled.
        let recent = Array(s.realtimeData.suffix(60))
        let stamp = s.rawFieldReadAt
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: columnCount), spacing: 0) {
            overviewMetric(.power, MenuBarMetric.power.title,
                           LNum("%.1f W", s.currentPowerWatts), AppTheme.chargingBlue,
                           dashboardText("shell.power_hint", fallback: "整机实时功率"),
                           field: "BatteryData.SystemPower", cadence: .gauge, stamp: stamp,
                           series: recent.map(\.power),
                           help: { DashboardHelp.power(s) })
            overviewMetric(.adapter, dashboardText("shell.adapter", fallback: "适配器功率"),
                           "\(data.chargerWattage) W", AppTheme.textSecondary,
                           data.isOnAC ? dashboardText("shell.adapter_connected", fallback: "当前额定功率") : dashboardText("shell.not_connected", fallback: "未连接"),
                           // A rating negotiated once at plug-in, not a measurement.
                           field: "AdapterDetails.Watts", cadence: .onPlug, stamp: stamp,
                           help: { DashboardHelp.adapterPower(s) })
            overviewMetric(.adapterOutput, dashboardText("shell.adapter_output_power", fallback: "适配器输出功率"),
                           s.adapterOutputPowerWatts.map { LNum("%.1f W", $0) } ?? "—",
                           AppTheme.chargingCyan,
                           data.isOnAC ? dashboardText("shell.whole_mac_input", fallback: "整机实时输入") : dashboardText("shell.not_connected", fallback: "未连接"),
                           // Derived, and labelled as such: SystemPowerIn was
                           // measured reading 0 mW while plugged in and charging.
                           field: "SystemPower + Voltage × Amperage", cadence: .gauge, stamp: stamp,
                           series: recent.compactMap { point -> Double? in
                               guard point.isOnAC else { return nil }
                               return max(0, point.power) + max(0, point.amperage / 1000 * point.voltage)
                           },
                           help: { DashboardHelp.adapterOutputPower(s) })
            overviewMetric(.charging, dashboardText("shell.charge_power", fallback: "充电功率"),
                           chargingPowerText(s), AppTheme.batteryGreen,
                           data.isCharging ? dashboardText("shell.charging", fallback: "正在充电") : dashboardText("shell.not_charging", fallback: "当前未充电"),
                           field: "Voltage × Amperage", cadence: .gauge, stamp: stamp,
                           series: recent.map { max(0, $0.amperage) / 1000 * $0.voltage },
                           help: { DashboardHelp.chargingPower(s) })
            overviewMetric(.temperature, MenuBarMetric.temperature.title,
                           LNum("%.1f ℃", data.temperatureCelsius), AppTheme.textSecondary,
                           dashboardText("shell.temp_range", fallback: "建议 20–35℃"),
                           field: "Temperature", cadence: .gauge, stamp: stamp,
                           series: recent.map(\.temperature),
                           help: { DashboardHelp.temperature(s) })
            overviewMetric(.cycles, MenuBarMetric.cycles.title, "\(data.cycleCount)", AppTheme.accentPurple,
                           dashboardText("shell.cycle_reference", fallback: "参考额定 1000 次"),
                           // Re-read on the gauge's beat like everything else; it
                           // just rarely moves. Saying "constant" here would be a lie.
                           field: "CycleCount", cadence: .gauge, stamp: stamp,
                           help: { DashboardHelp.cycleCount(s) })
            overviewMetric(.health, MenuBarMetric.health.title,
                           LNum("%.1f%%", s.healthPercent), AppTheme.batteryGreen,
                           healthLabel,
                           field: "AppleRawMaxCapacity ÷ DesignCapacity",
                           cadence: .gauge, stamp: stamp,
                           help: { DashboardHelp.health(s) })
        }
    }

    private func chargingPowerText(_ s: DashboardMetricSnapshot) -> String {
        s.chargingPowerText
    }

    private func overviewMetric(
        _ icon: BatteryMetricIcon,
        _ title: String,
        _ value: String,
        _ color: Color,
        _ hint: String,
        /// The lowest-level key this number comes from. Shown verbatim so the
        /// card can be checked against `ioreg` without opening the drawer.
        field: String,
        cadence: MetricCardCadence,
        stamp: MetricReadStamp,
        /// Recent samples for the trend line. Empty means no series exists for
        /// this metric — a rated wattage has nothing to plot.
        series: [Double] = [],
        /// Built on tap: the rail holds seven of these and ViewThatFits renders
        /// it twice, so eager construction meant fourteen unused help sheets per
        /// redraw.
        help: @escaping () -> MetricHelpContent
    ) -> some View {
        VStack(spacing: 7) {
            MetricGlyph(icon, tint: color, scale: .card)
            Text(title)
                .font(.system(size: 10.5))
                .foregroundStyle(AppTheme.textSecondary)
                .lineLimit(2)
                .minimumScaleFactor(0.82)
                .multilineTextAlignment(.center)
            // The trend sits behind the value instead of under it: a chart row of
            // its own would add its height to all seven columns.
            Text(value)
                .font(.system(size: 20, weight: .medium, design: .rounded))
                .foregroundStyle(AppTheme.textPrimary)
                .monospacedDigit()
                .lineLimit(1)
                .frame(maxWidth: .infinity, minHeight: 30)
                .background(alignment: .bottom) {
                    MetricSparkline(values: series, tint: color)
                        .frame(height: 26)
                        .padding(.horizontal, 2)
                }
            Text(hint)
                .font(.system(size: 8.5))
                .foregroundStyle(AppTheme.textTertiary)
                .lineLimit(2)
                .multilineTextAlignment(.center)

            Spacer(minLength: 0)

            // Fixed height so all seven footers share a baseline regardless of
            // how many lines each cadence sentence needs.
            VStack(spacing: 2) {
                Text(field)
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundStyle(AppTheme.textTertiary.opacity(0.75))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                TimelineView(.periodic(from: Date(), by: 1)) { timeline in
                    Text(cadence.text(stamp, now: timeline.date))
                        .font(.system(size: 8))
                        .foregroundStyle(AppTheme.textTertiary.opacity(0.75))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
            .frame(height: 24)
        }
        // Sized to the content. It was 186 while the stack only needed ~145, and
        // the Spacer turned that slack into a gap under the hint line.
        .frame(maxWidth: .infinity, minHeight: 148)
        .padding(.horizontal, 8)
        .padding(.bottom, 6)
        .overlay(alignment: .topTrailing) {
            MetricHelpButton(content: help(), selection: $selectedHelp)
                .padding(9)
        }
        .overlay(alignment: .trailing) { Rectangle().fill(AppTheme.divider).frame(width: 1) }
    }

    private var healthLabel: String {
        let health = snapshot.healthPercent
        if health >= 90 { return dashboardText("shell.health_good", fallback: "状态良好") }
        if health >= 80 { return dashboardText("shell.health_fair", fallback: "正常使用") }
        return dashboardText("shell.health_attention", fallback: "建议关注")
    }

    private var statusBanner: some View {
        // One snapshot for the banner. needsAttention reads healthPercent, and it
        // used to be re-evaluated by statusColor, statusSymbol and statusHeadline
        // separately — three snapshot rebuilds for one boolean.
        let attention = needsAttention
        return HStack(spacing: 16) {
            ZStack {
                Circle().fill(attention ? AppTheme.batteryOrange : AppTheme.batteryGreen)
                    .frame(width: 48, height: 48)
                Image(systemName: attention ? "exclamationmark" : "checkmark")
                    .font(.system(size: 20, weight: .bold)).foregroundStyle(AppTheme.selectionText)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(attention
                     ? dashboardText("shell.status_attention", fallback: "有一项指标需要关注")
                     : dashboardText("shell.status_good", fallback: "状态良好 · 各项指标处于可接受范围"))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppTheme.textPrimary)
                Text(statusSubtitle)
                    .font(.system(size: 10.5))
                    .foregroundStyle(AppTheme.textTertiary)
            }
            Spacer()
            Text(batteryService.isLiveRefreshEnabled
                 ? dashboardText("p.live_10s", fallback: "每 10 秒更新")
                 : dashboardText("p.live_paused", fallback: "已暂停"))
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(AppTheme.textTertiary)
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 15).fill(AppTheme.cardBackground))
        .overlay(RoundedRectangle(cornerRadius: 15).stroke(AppTheme.cardBorder))
    }

    private var needsAttention: Bool { snapshot.healthPercent < 80 || data.temperatureCelsius >= 45 }
    private var statusSubtitle: String {
        dashboardText("shell.status_subtitle", fallback: "续航以系统读数为准；详细来源和公式可在技术参数中核验。")
    }
}
