import SwiftUI

// MARK: - 4. Capacity: usable charge + explainable long-term difference

struct CapacityBreakdownSection: View {
    let snapshot: DashboardMetricSnapshot
    @Binding var selectedHelp: MetricHelpContent?

    private var design: Int { snapshot.designCapacity }
    private var full: Int { snapshot.fullChargeCapacity }
    private var current: Int { snapshot.currentCapacity }
    private var used: Int { snapshot.usedSinceFull }
    private var gap: Int { snapshot.longTermCapacityGap }
    private var inaccessible: Int? { snapshot.inaccessibleCapacity }
    private var permanent: Int? { snapshot.truePermanentLoss }
    private var hasDetailedSplit: Bool {
        inaccessible != nil && permanent != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            DashboardSectionHeader(
                icon: "battery.100",
                title: dashboardText("p.where_title", fallback: "你买的容量去哪了"),
                color: AppTheme.batteryYellow,
                help: DashboardHelp.capacityOverview(snapshot),
                selection: $selectedHelp
            )

            Text(
                dashboardText(
                    "p.where_head",
                    fallback: "出厂设计 {design} mAh · 现在充满 {full} mAh · 此刻还剩 {current} mAh",
                    replacements: [
                        "a": formatted(design), "b": formatted(full), "c": formatted(current),
                        "design": formatted(design), "full": formatted(full), "current": formatted(current),
                    ]
                )
            )
            .font(.system(size: 21, weight: .bold, design: .rounded))
            .foregroundStyle(AppTheme.textPrimary)
            .fixedSize(horizontal: false, vertical: true)

            capacityBar

            ViewThatFits(in: .horizontal) {
                LazyVGrid(
                    columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)],
                    alignment: .leading,
                    spacing: 10
                ) {
                    capacityCards
                }
                .frame(minWidth: 680)
                VStack(spacing: 10) { capacityCards }
            }

            VStack(spacing: 10) {
                CapacityEquation(
                    title: dashboardText("p.eq_capacity_title", fallback: "这块电池现在最多能装多少"),
                    subtitle: dashboardText("p.eq_capacity_sub", fallback: "出厂设计减去长期容量损失"),
                    terms: [
                        .init(label: dashboardText("p.design_capacity", fallback: "设计容量"), value: design,
                              icon: "shippingbox", color: AppTheme.batteryYellow,
                              help: DashboardHelp.designCapacity(snapshot)),
                        .init(label: dashboardText("p.capacity_gap", fallback: "长期容量总差额"), value: gap,
                              icon: "arrow.triangle.2.circlepath", color: AppTheme.batteryRed,
                              help: DashboardHelp.capacityGap(snapshot)),
                        .init(label: dashboardText("p.current_max", fallback: "目前最大容量"), value: full,
                              icon: "shield", color: AppTheme.chargingCyan,
                              help: DashboardHelp.currentMax(snapshot)),
                    ],
                    operators: ["−", "="],
                    selection: $selectedHelp
                )

                CapacityEquation(
                    title: dashboardText("p.eq_usage_title", fallback: "充满后的电去了哪里"),
                    subtitle: dashboardText("p.eq_usage_sub", fallback: "目前最大容量减去本次已用，就是此刻还剩"),
                    terms: [
                        .init(label: dashboardText("p.current_max", fallback: "目前最大容量"), value: full,
                              icon: "shield", color: AppTheme.chargingCyan,
                              help: DashboardHelp.currentMax(snapshot)),
                        .init(label: dashboardText("p.used_since_full", fallback: "本次已经用掉"), value: used,
                              icon: "bolt", color: AppTheme.chargingBlue,
                              help: DashboardHelp.usedSinceFull(snapshot)),
                        .init(label: dashboardText("p.current_actual", fallback: "此刻还剩"), value: current,
                              icon: "battery.75", color: AppTheme.chargingCyan,
                              help: DashboardHelp.currentActual(snapshot)),
                    ],
                    operators: ["−", "="],
                    selection: $selectedHelp
                )

                if let inaccessible, let permanent {
                    CapacityEquation(
                        title: dashboardText(
                            "p.loss_split_title",
                            fallback: "总差额 {gap} mAh = 取不出来 + 已老化",
                            replacements: ["gap": formatted(gap)]
                        ),
                        subtitle: dashboardText(
                            "p.loss_split_body",
                            fallback: "像一只水杯：有些水只是吸管够不到，真正让杯子变小的才是永久老化。",
                            replacements: [
                                "un": formatted(inaccessible),
                                "aged": formatted(permanent),
                            ]
                        ),
                        terms: [
                            .init(label: dashboardText("p.capacity_gap", fallback: "长期容量总差额"), value: gap,
                                  icon: "arrow.triangle.2.circlepath", color: AppTheme.batteryYellow,
                                  help: DashboardHelp.capacityGap(snapshot)),
                            .init(label: dashboardText("p.seg_un", fallback: "暂时够不到"), value: inaccessible,
                                  icon: "drop.triangle", color: AppTheme.batteryYellow,
                                  help: DashboardHelp.inaccessibleCapacity(snapshot)),
                            .init(label: dashboardText("p.seg_age", fallback: "真正老化"), value: permanent,
                                  icon: "arrow.down.heart", color: AppTheme.batteryRed,
                                  help: DashboardHelp.permanentLoss(snapshot)),
                        ],
                        operators: ["=", "+"],
                        selection: $selectedHelp
                    )
                }
            }

            Text(capacityDerivation)
                .font(.system(size: 9.5, design: .monospaced))
                .foregroundStyle(AppTheme.textTertiary)
                .textSelection(.enabled)
                .padding(11)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 9).fill(Color.black.opacity(0.12)))
        }
        .padding(22)
        .finalDashboardCard(accent: AppTheme.batteryYellow)
    }

    private var capacityBar: some View {
        GeometryReader { geometry in
            let total = max(design, 1)
            let width = geometry.size.width
            HStack(spacing: 1) {
                capacitySegment(width: width * CGFloat(current) / CGFloat(total),
                                value: current,
                                label: dashboardText("p.seg_now", fallback: "此刻还剩"),
                                color: AppTheme.chargingCyan)
                capacitySegment(width: width * CGFloat(used) / CGFloat(total),
                                value: used,
                                label: dashboardText("p.seg_used", fallback: "本次已用"),
                                color: AppTheme.chargingBlue)
                if let inaccessible, let permanent {
                    capacitySegment(width: width * CGFloat(inaccessible) / CGFloat(total),
                                    value: inaccessible,
                                    label: dashboardText("p.seg_un", fallback: "暂时够不到"),
                                    color: AppTheme.batteryYellow)
                    capacitySegment(width: width * CGFloat(permanent) / CGFloat(total),
                                    value: permanent,
                                    label: dashboardText("p.seg_age", fallback: "真正老化"),
                                    color: AppTheme.batteryRed)
                } else {
                    capacitySegment(width: width * CGFloat(gap) / CGFloat(total),
                                    value: gap,
                                    label: dashboardText("p.capacity_gap", fallback: "长期容量总差额"),
                                    color: AppTheme.batteryRed)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.09)))
            .overlay(alignment: .topLeading) {
                let boundary = min(max(width * CGFloat(full) / CGFloat(total), 0), width)
                let boundaryLabel = dashboardText("p.current_max", fallback: "目前最大容量")
                Rectangle()
                    .fill(Color.white.opacity(0.62))
                    .frame(width: 1, height: 78)
                    .offset(x: boundary)
                Text("FCC · \(boundaryLabel) \(formatted(full))")
                    .font(.system(size: 7.5, weight: .semibold, design: .monospaced))
                    .foregroundStyle(AppTheme.textPrimary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.black.opacity(0.62)))
                    .offset(x: min(max(boundary - 64, 4), max(width - 132, 4)), y: 4)
            }
        }
        .frame(height: 78)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(capacityAccessibilityLabel)
    }

    private func capacitySegment(width: CGFloat, value: Int, label: String, color: Color) -> some View {
        VStack(spacing: 3) {
            if width >= 64 {
                Text(formatted(value))
                    .font(.system(size: 18, weight: .semibold, design: .monospaced))
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)
                Text(label)
                    .font(.system(size: 8.5, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)
            }
        }
        .foregroundStyle(Color.white.opacity(0.9))
        .frame(width: max(width - 1, 0))
        .frame(maxHeight: .infinity)
        .background(
            LinearGradient(colors: [color.opacity(0.62), color.opacity(0.22)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        )
    }

    @ViewBuilder
    private var capacityCards: some View {
        CapacityLegendCard(
            icon: "shippingbox.fill",
            title: dashboardText("p.design_capacity", fallback: "出厂设计容量"),
            value: design,
            percentage: 100,
            description: dashboardText("p.capacity_sum", fallback: "这是这台机型出厂时的整只水箱：{design} mAh。",
                                       replacements: ["design": formatted(design)]),
            color: AppTheme.batteryYellow,
            help: DashboardHelp.designCapacity(snapshot),
            selection: $selectedHelp
        )
        CapacityLegendCard(
            icon: "shield.fill",
            title: dashboardText("p.current_max", fallback: "目前充满能装"),
            value: full,
            percentage: ratio(full),
            description: dashboardText("p.current_max_desc", fallback: "像现在这只水箱真正能装满、也能放出来的总量。"),
            color: AppTheme.chargingCyan,
            help: DashboardHelp.currentMax(snapshot),
            selection: $selectedHelp
        )
        CapacityLegendCard(
            icon: "battery.75",
            title: dashboardText("p.current_actual", fallback: "此刻还剩"),
            value: current,
            percentage: ratio(current),
            description: dashboardText("p.current_actual_desc", fallback: "像水箱里此刻剩下的水；使用会减少，充电会补回来。"),
            color: AppTheme.chargingCyan,
            help: DashboardHelp.currentActual(snapshot),
            selection: $selectedHelp
        )
        CapacityLegendCard(
            icon: "bolt.fill",
            title: dashboardText("p.used_since_full", fallback: "本次已经用掉"),
            value: used,
            percentage: ratio(used),
            description: dashboardText(used == 0 ? "p.used_zero_desc" : "p.used_since_full_desc",
                                       fallback: used == 0 ? "刚充满，所以这次还没有用掉；它不是老化。" : "从本次充满到现在已经用掉的电，充电后会回来；它不是老化。"),
            color: AppTheme.chargingBlue,
            help: DashboardHelp.usedSinceFull(snapshot),
            selection: $selectedHelp
        )
        if let inaccessible, let permanent {
            CapacityLegendCard(
                icon: "drop.triangle.fill",
                title: dashboardText("p.seg_un", fallback: "暂时够不到"),
                value: inaccessible,
                percentage: ratio(inaccessible),
                description: dashboardText("p.seg_un_d", fallback: "像吸管够不到的杯底水：电量计认为它还在，但系统会在电压过低前停止放电。"),
                color: AppTheme.batteryYellow,
                help: DashboardHelp.inaccessibleCapacity(snapshot),
                selection: $selectedHelp
            )
            CapacityLegendCard(
                icon: "arrow.down.heart.fill",
                title: dashboardText("p.seg_age", fallback: "真正老化"),
                value: permanent,
                percentage: ratio(permanent),
                description: dashboardText("p.seg_age_d", fallback: "像水箱本身缩小了；这是设计容量与学习到的化学容量之差。"),
                color: AppTheme.batteryRed,
                help: DashboardHelp.permanentLoss(snapshot),
                selection: $selectedHelp
            )
        } else {
            CapacityLegendCard(
                icon: "arrow.triangle.2.circlepath",
                title: dashboardText("p.capacity_gap", fallback: "长期容量总差额"),
                value: gap,
                percentage: ratio(gap),
                description: dashboardText("p.capacity_gap_desc", fallback: "目前满充容量比出厂设计少的总差额；Qmax 数据不足时不武断拆成够不到与真正老化。"),
                color: AppTheme.batteryRed,
                help: DashboardHelp.capacityGap(snapshot),
                selection: $selectedHelp
            )
        }
    }

    private var capacityDerivation: String {
        let key = hasDetailedSplit ? "p.derive_four" : "p.derive_gap"
        return dashboardText(
            key,
            fallback: hasDetailedSplit
                ? "校验链：设计 {d} = 此刻还剩 {c} + 本次已用 {used} + 暂时够不到 {un} + 真正老化 {aged}；目前最大容量 {f} = {c} + {used}。"
                : "校验链：设计 {d} = 此刻还剩 {c} + 本次已用 {used} + 长期容量总差额 {loss}；目前最大容量 {f} = {c} + {used}。Qmax 不足，暂不拆分总差额。",
            replacements: [
                "d": formatted(design), "q": formatted(snapshot.detail.qmax.min() ?? 0),
                "f": formatted(full), "c": formatted(current), "used": formatted(used), "loss": formatted(gap),
                "un": formatted(inaccessible ?? 0), "aged": formatted(permanent ?? 0),
            ]
        )
    }

    private var capacityAccessibilityLabel: String {
        if let inaccessible, let permanent {
            return "\(current) mAh 此刻还剩，\(used) mAh 本次已用，\(inaccessible) mAh 暂时够不到，\(permanent) mAh 真正老化；FCC 边界 \(full) mAh"
        }
        return "\(current) mAh 此刻还剩，\(used) mAh 本次已用，\(gap) mAh 长期容量差额；FCC 边界 \(full) mAh"
    }

    private func ratio(_ value: Int) -> Double {
        design > 0 ? Double(value) / Double(design) * 100 : 0
    }

    private func formatted(_ value: Int) -> String { value.formatted(.number.grouping(.automatic)) }
}

private struct CapacityLegendCard: View {
    let icon: String
    let title: String
    let value: Int
    let percentage: Double
    let description: String
    let color: Color
    let help: MetricHelpContent
    @Binding var selection: MetricHelpContent?

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .top, spacing: 9) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(color)
                    .frame(width: 36, height: 36)
                    .background(RoundedRectangle(cornerRadius: 10).fill(color.opacity(0.10)))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(color.opacity(0.24)))
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(title)
                            .font(.system(size: 9.5, weight: .semibold))
                            .foregroundStyle(AppTheme.textSecondary)
                            .lineLimit(2)
                        MetricHelpButton(content: help, selection: $selection)
                    }
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(value.formatted(.number.grouping(.automatic)))
                            .font(.system(size: 18, weight: .medium, design: .monospaced))
                            .foregroundStyle(color)
                        Text("mAh · \(LNum("%.1f", percentage))%")
                            .font(.system(size: 8, design: .monospaced))
                            .foregroundStyle(AppTheme.textTertiary)
                    }
                }
            }
            Text(description)
                .font(.system(size: 9))
                .foregroundStyle(AppTheme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(2)
            GeometryReader { geo in
                Capsule().fill(Color.white.opacity(0.04))
                    .overlay(alignment: .leading) {
                        Capsule().fill(color.opacity(0.68))
                            .frame(width: geo.size.width * CGFloat(min(max(percentage, 0), 100)) / 100)
                    }
            }
            .frame(height: 3)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 158, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.018)))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.06)))
    }
}

private struct CapacityEquationTerm {
    let label: String
    let value: Int
    let icon: String
    let color: Color
    let help: MetricHelpContent
}

private struct CapacityEquation: View {
    let title: String
    let subtitle: String
    let terms: [CapacityEquationTerm]
    let operators: [String]
    @Binding var selection: MetricHelpContent?

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 9) {
                equationTitle.frame(width: 190, alignment: .leading)
                equationTerms
            }
            VStack(alignment: .leading, spacing: 10) {
                equationTitle
                equationTerms
            }
        }
        .padding(13)
        .background(RoundedRectangle(cornerRadius: 11).fill(Color.black.opacity(0.12)))
        .overlay(RoundedRectangle(cornerRadius: 11).stroke(Color.white.opacity(0.055)))
    }

    private var equationTitle: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.system(size: 10.5, weight: .semibold)).foregroundStyle(AppTheme.textPrimary)
            Text(subtitle).font(.system(size: 8.5)).foregroundStyle(AppTheme.textTertiary)
        }
    }

    private var equationTerms: some View {
        HStack(spacing: 7) {
            ForEach(Array(terms.enumerated()), id: \.offset) { index, term in
                HStack(spacing: 6) {
                    Image(systemName: term.icon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(term.color)
                        .frame(width: 28, height: 28)
                        .background(RoundedRectangle(cornerRadius: 8).fill(term.color.opacity(0.08)))
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 3) {
                            Text(term.label)
                                .font(.system(size: 8.5))
                                .foregroundStyle(AppTheme.textTertiary)
                                .lineLimit(1)
                            MetricHelpButton(content: term.help, selection: $selection)
                        }
                        Text("\(term.value.formatted(.number.grouping(.automatic))) mAh")
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundStyle(AppTheme.textPrimary)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if index < operators.count {
                    Text(operators[index])
                        .font(.system(size: 16, weight: .light, design: .monospaced))
                        .foregroundStyle(AppTheme.textTertiary)
                }
            }
        }
    }
}

// MARK: - 5. Current values beside their ranges

struct MetricReferenceSection: View {
    let snapshot: DashboardMetricSnapshot
    @Binding var selectedHelp: MetricHelpContent?

    private var metrics: [ReferenceMetric] {
        let detail = snapshot.detail
        let delta = detail.cellVoltageDelta ?? 0
        let maxResistance = detail.weightedRa.max() ?? 0
        let cycleUsage = (detail.cycleUsage ?? 0) * 100
        let packVoltage = snapshot.voltageVolts

        return [
            ReferenceMetric(
                title: dashboardText("insight.factor.balance", fallback: "各单元均衡度"),
                current: "\(delta) mV",
                range: "0–20 mV",
                history: detail.cellVoltages.isEmpty
                    ? dashboardText("p.history_learning", fallback: "历史范围正在积累")
                    : detail.cellVoltages.map(String.init).joined(separator: " / ") + " mV",
                low: dashboardText("p.cb_ok", fallback: "压差小，电芯步调一致，可用容量不容易被最弱的一节拖累"),
                high: dashboardText("p.cb_bad", fallback: "压差明显时，最弱的一节会先到截止电压，整包可用容量随之变少"),
                source: dashboardText("p.src_lit", fallback: "锂电通用文献"),
                color: delta <= 20 ? AppTheme.chargingCyan : AppTheme.batteryYellow,
                help: DashboardHelp.cellBalance(snapshot)
            ),
            ReferenceMetric(
                title: dashboardText("insight.factor.resistance", fallback: "电池内部阻力"),
                current: "\(maxResistance) mΩ",
                range: "0–130 mΩ",
                history: detail.weightedRa.isEmpty
                    ? dashboardText("p.history_learning", fallback: "历史范围正在积累")
                    : detail.weightedRa.map(String.init).joined(separator: " / ") + " mΩ",
                low: dashboardText("p.ra_ok", fallback: "阻力低，重负载时电压更稳、发热更少"),
                high: dashboardText("p.ra_bad", fallback: "阻力高时更容易压降和发热，也可能更早触发低电关机"),
                source: dashboardText("p.src_none_short", fallback: "只看趋势"),
                color: maxResistance <= 130 ? AppTheme.chargingCyan : AppTheme.batteryYellow,
                help: DashboardHelp.resistance(snapshot)
            ),
            ReferenceMetric(
                title: dashboardText("insight.factor.cycles", fallback: "循环使用率"),
                current: LNum("%.1f%%", cycleUsage),
                range: "0–50%",
                history: "\(detail.cycleCount) / \(max(detail.designCycleCount, 0))",
                low: dashboardText("p.cycle_low_short", fallback: "累计使用更少；但仍需结合容量与内阻判断状态"),
                high: dashboardText("p.cycle_high_short", fallback: "越接近额定循环寿命，越应该结合容量、内阻与温度看趋势"),
                source: dashboardText("p.src_apple", fallback: "Apple 官方额定值"),
                color: cycleUsage <= 50 ? AppTheme.chargingCyan : AppTheme.batteryYellow,
                help: DashboardHelp.cycles(snapshot)
            ),
            ReferenceMetric(
                title: dashboardText("hw.m.pack_voltage", fallback: "电池组电压"),
                current: LNum("%.2f V", packVoltage),
                range: detail.minimumPackVoltage > 0 && detail.maximumPackVoltage > 0
                    ? snapshot.voltageHistoryText : "—",
                history: snapshot.voltageHistoryText,
                low: dashboardText("p.pv_low", fallback: "接近历史最低值时，系统可能为了保护电芯而关机"),
                high: dashboardText("p.pv_high", fallback: "接近历史最高值通常只会在刚充满时出现"),
                source: dashboardText("p.src_personal", fallback: "你自己的历史数据"),
                color: AppTheme.accentPurple,
                help: DashboardHelp.packVoltage(snapshot)
            ),
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            DashboardSectionHeader(
                icon: "scale.3d",
                title: dashboardText("p.spec_other_title", fallback: "其余 4 项关键指标"),
                color: AppTheme.accentPurple,
                help: DashboardHelp.specOverview(snapshot),
                selection: $selectedHelp
            )

            Text(dashboardText("p.spec_other_sub", fallback: "当前值、合理范围、历史极限与高低影响放在一起，不让 benchmark 和实际读数分家。"))
                .font(.system(size: 11))
                .foregroundStyle(AppTheme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)

            ViewThatFits(in: .horizontal) {
                referenceTable
                    .frame(minWidth: 890)
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    referenceCards
                }
                VStack(spacing: 10) { referenceCards }
            }

            Text(dashboardText("p.spec_source_note", fallback: "范围来源会分开标注：Apple 规格、你自己的历史、通用锂电资料，或仅观察趋势。"))
                .font(.system(size: 9))
                .foregroundStyle(AppTheme.textTertiary)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.018)))
        }
        .padding(22)
        .finalDashboardCard(accent: AppTheme.accentPurple)
    }

    private var referenceTable: some View {
        VStack(spacing: 0) {
            ReferenceTableRow(
                values: [
                    dashboardText("p.spec_metric", fallback: "指标"),
                    dashboardText("p.spec_current", fallback: "当前值"),
                    dashboardText("p.good_range", fallback: "合理范围"),
                    dashboardText("p.history_extreme", fallback: "历史极限"),
                    dashboardText("p.low_effect", fallback: "低时影响"),
                    dashboardText("p.high_effect", fallback: "高时影响"),
                    dashboardText("p.spec_source", fallback: "范围依据"),
                ],
                weights: [1.25, 0.72, 0.8, 1.0, 1.75, 1.75, 0.9],
                isHeader: true
            )
            ForEach(metrics) { metric in
                ReferenceMetricRow(metric: metric, selection: $selectedHelp)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.06)))
    }

    @ViewBuilder
    private var referenceCards: some View {
        ForEach(metrics) { metric in
            ReferenceMetricCard(metric: metric, selection: $selectedHelp)
        }
    }
}

private struct ReferenceMetric: Identifiable {
    let title: String
    let current: String
    let range: String
    let history: String
    let low: String
    let high: String
    let source: String
    let color: Color
    let help: MetricHelpContent
    var id: String { help.id }
}

private struct ReferenceTableRow: View {
    let values: [String]
    let weights: [CGFloat]
    var isHeader = false

    var body: some View {
        GeometryReader { geometry in
            let total = max(weights.reduce(0, +), 0.1)
            HStack(alignment: .top, spacing: 0) {
                ForEach(values.indices, id: \.self) { index in
                    Text(values[index])
                        .font(.system(size: isHeader ? 8.5 : 9, weight: isHeader ? .medium : .regular))
                        .foregroundStyle(isHeader ? AppTheme.textTertiary : AppTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(width: geometry.size.width * weights[index] / total, alignment: .topLeading)
                        .padding(.horizontal, 8)
                }
            }
        }
        .frame(height: isHeader ? 34 : 76)
        .padding(.vertical, isHeader ? 8 : 10)
        .background(isHeader ? Color.white.opacity(0.032) : Color.white.opacity(0.012))
    }
}

private struct ReferenceMetricRow: View {
    let metric: ReferenceMetric
    @Binding var selection: MetricHelpContent?

    private let weights: [CGFloat] = [1.25, 0.72, 0.8, 1.0, 1.75, 1.75, 0.9]

    var body: some View {
        GeometryReader { geometry in
            let total = max(weights.reduce(0, +), 0.1)
            HStack(alignment: .top, spacing: 0) {
                metricLabel
                    .frame(width: geometry.size.width * weights[0] / total, alignment: .topLeading)
                tableText(metric.current, color: metric.color)
                    .frame(width: geometry.size.width * weights[1] / total, alignment: .topLeading)
                tableText(metric.range, color: AppTheme.chargingCyan)
                    .frame(width: geometry.size.width * weights[2] / total, alignment: .topLeading)
                tableText(metric.history)
                    .frame(width: geometry.size.width * weights[3] / total, alignment: .topLeading)
                tableText(metric.low)
                    .frame(width: geometry.size.width * weights[4] / total, alignment: .topLeading)
                tableText(metric.high)
                    .frame(width: geometry.size.width * weights[5] / total, alignment: .topLeading)
                tableText(metric.source, color: AppTheme.accentPurple)
                    .frame(width: geometry.size.width * weights[6] / total, alignment: .topLeading)
            }
        }
        .frame(height: 94)
        .padding(.horizontal, 8)
        .padding(.vertical, 12)
        .background(Color.white.opacity(0.012))
        .overlay(alignment: .top) { Rectangle().fill(Color.white.opacity(0.05)).frame(height: 1) }
    }

    private var metricLabel: some View {
        HStack(spacing: 4) {
            Text(metric.title)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(AppTheme.textPrimary)
            MetricHelpButton(content: metric.help, selection: $selection)
        }
        .padding(.horizontal, 8)
    }

    private func tableText(_ text: String, color: Color = AppTheme.textSecondary) -> some View {
        Text(text)
            .font(.system(size: 8.5))
            .foregroundStyle(color)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 8)
    }
}

private struct ReferenceMetricCard: View {
    let metric: ReferenceMetric
    @Binding var selection: MetricHelpContent?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 4) {
                        Text(metric.title)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(AppTheme.textPrimary)
                        MetricHelpButton(content: metric.help, selection: $selection)
                    }
                    Text(metric.current)
                        .font(.system(size: 20, weight: .medium, design: .monospaced))
                        .foregroundStyle(metric.color)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(dashboardText("p.good_range", fallback: "合理范围"))
                    Text(metric.range).foregroundStyle(AppTheme.chargingCyan)
                }
                .font(.system(size: 8.5, design: .monospaced))
                .foregroundStyle(AppTheme.textTertiary)
            }

            labeledText(dashboardText("p.history_extreme", fallback: "历史极限"), metric.history)
            HStack(alignment: .top, spacing: 8) {
                effectBox(title: dashboardText("p.low_effect", fallback: "低时"), text: metric.low, color: AppTheme.chargingBlue)
                effectBox(title: dashboardText("p.high_effect", fallback: "高时"), text: metric.high, color: AppTheme.batteryYellow)
            }
            labeledText(dashboardText("p.spec_source", fallback: "范围依据"), metric.source)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 235, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.018)))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.06)))
    }

    private func labeledText(_ label: String, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            Text(label).foregroundStyle(AppTheme.textTertiary)
            Text(text).foregroundStyle(AppTheme.textSecondary)
            Spacer()
        }
        .font(.system(size: 8.5))
    }

    private func effectBox(title: String, text: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.system(size: 8, weight: .semibold)).foregroundStyle(color)
            Text(text).font(.system(size: 8.5)).foregroundStyle(AppTheme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 8).fill(color.opacity(0.035)))
    }
}

// MARK: - 6. Consumer explanations

struct ConsumerExplanationSection: View {
    let snapshot: DashboardMetricSnapshot

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 14) { explanationCards }
            VStack(spacing: 14) { explanationCards }
        }
    }

    @ViewBuilder
    private var explanationCards: some View {
        ExplanationCard(
            icon: "gauge.with.dots.needle.33percent",
            color: AppTheme.batteryRed,
            eyebrow: dashboardText("p.aging_judge_title", fallback: "判断电池是不是老化"),
            title: dashboardText("p.aging_judge_lead", fallback: "循环次数像里程表：说明用过多少，不单独决定健康"),
            message: dashboardText("p.aging_judge_body", fallback: "真正要一起看的是：充满容量是否持续下降、内阻是否上升、电芯是否开始不同步，以及高温是否变得常见。"),
            proof: dashboardText(
                "p.aging_proof",
                fallback: "这台电脑已完成 {cyc} 次循环；目前最大容量比设计少 {loss} mAh。平均每循环 {per} mAh 只用于回顾，不能线性预测寿命。",
                replacements: [
                    "cyc": snapshot.detail.cycleCount.formatted(),
                    "loss": snapshot.longTermCapacityGap.formatted(),
                    "per": LNum("%.1f mAh", snapshot.detail.chargeDeficitPerCycle ?? 0),
                ]
            )
        )

        ExplanationCard(
            icon: "arrow.up.arrow.down.circle",
            color: AppTheme.batteryYellow,
            eyebrow: dashboardText("p.time_jump_title", fallback: "剩余时间为什么会跳"),
            title: dashboardText("p.time_jump_lead", fallback: "开始编译时下降，停下来阅读时又上升，并不代表电量回来了"),
            message: dashboardText("p.time_jump_body", fallback: "macOS 会不断用最近的使用状态重估还能维持多久。功耗会影响估算，但本页在电池供电时只记录系统给出的答案，不另算一套。"),
            proof: dashboardText("p.time_jump_proof", fallback: "电池供电：记录 macOS 剩余时间。连接电源：显示“当前储能 ÷ 当前功率”，并明确标成拔电预计。")
        )
    }
}

private struct ExplanationCard: View {
    let icon: String
    let color: Color
    let eyebrow: String
    let title: String
    let message: String
    let proof: String

    var body: some View {
        HStack(alignment: .top, spacing: 17) {
            Image(systemName: icon)
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(color)
                .frame(width: 58, height: 58)
                .background(
                    RadialGradient(colors: [color.opacity(0.18), color.opacity(0.035)],
                                   center: .center, startRadius: 0, endRadius: 42)
                )
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(color.opacity(0.22)))

            VStack(alignment: .leading, spacing: 9) {
                Text(eyebrow.uppercased())
                    .font(.system(size: 8.5, weight: .semibold, design: .monospaced))
                    .tracking(0.9)
                    .foregroundStyle(color)
                Text(title)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(message)
                    .font(.system(size: 10.5))
                    .foregroundStyle(AppTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(3)
                Text(proof)
                    .font(.system(size: 9.5, design: .monospaced))
                    .foregroundStyle(AppTheme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(2)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 8).fill(color.opacity(0.035)))
                    .overlay(alignment: .leading) { Rectangle().fill(color).frame(width: 2) }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, minHeight: 235, alignment: .topLeading)
        .finalDashboardCard(accent: color)
    }
}

// MARK: - Question-mark definitions and lowest-level formulas

enum DashboardHelp {
    static func runtime(_ s: DashboardMetricSnapshot) -> MetricHelpContent {
        let detail = s.detail
        if s.data.isOnAC {
            let minutes = s.unplugEstimateMinutes ?? 0
            return content(
                id: "runtime.unplug",
                title: dashboardText("p.unplug_badge", fallback: "拔电预计"),
                summary: dashboardText("p.unplug_note", fallback: "插电时系统不提供放电剩余时间，因此用这台电脑当前储能和当前功率做清晰标注的预计。"),
                result: runtime(minutes),
                fields: [
                    field("ModelDesignEnergy", f(s.designEnergyWh), "Wh"),
                    field("AppleRawCurrentCapacity", s.currentCapacity, "mAh"),
                    field("DesignCapacity", s.designCapacity, "mAh"),
                    field("BatteryData.SystemPower", f(s.currentPowerWatts), "W"),
                ],
                formula: "remainingWh = designWh × currentCapacity ÷ designCapacity\nunplugMinutes = remainingWh ÷ systemPower × 60",
                substitution: "\(f(s.designEnergyWh)) × \(s.currentCapacity) ÷ \(s.designCapacity) = \(f(s.remainingEnergyWh)) Wh\n\(f(s.remainingEnergyWh)) ÷ \(f(s.currentPowerWatts)) × 60 = \(minutes) min",
                source: "IOKit live capacity and BatteryData.SystemPower + Apple model specification. Derived forecast; it is never stored as macOS runtime history."
            )
        }

        let minutes = s.data.timeRemainingMinutes ?? 0
        return content(
            id: "runtime.system",
            title: dashboardText("p.remaining", fallback: "还能用多久"),
            summary: dashboardText("p.src_note", fallback: "电池供电时优先显示 macOS 电量计直接给出的剩余时间；页面不再根据功率另算一个相互矛盾的数字。"),
            result: runtime(minutes),
            fields: [
                field("TimeRemaining", detail.timeRemainingRaw, "min"),
                field("AvgTimeToEmpty", detail.avgTimeToEmpty, "min"),
            ],
            formula: dashboardText("p.help_direct", fallback: "无公式：直接读取系统字段。"),
            substitution: "TimeRemaining / AvgTimeToEmpty → \(optional(detail.timeRemainingRaw)) / \(optional(detail.avgTimeToEmpty)) min → \(minutes) min",
            source: "AppleSmartBattery IOKit fields. 65,535 is treated as unavailable, never as minutes."
        )
    }

    static func stateOfCharge(_ s: DashboardMetricSnapshot) -> MetricHelpContent {
        content(
            id: "state-of-charge",
            title: dashboardText("p.system_charge", fallback: "macOS 电量"),
            summary: dashboardText("p.help_summary_soc", fallback: "这里与系统菜单栏采用同一用户口径。原始 mAh 只用于容量拆解，不拿来覆盖 macOS 的 0–100%。"),
            result: "\(s.data.percent)%",
            fields: [
                field("CurrentCapacity", s.detail.currentCapacityRaw, "%"),
                field("AppleRawCurrentCapacity", s.detail.appleRawCurrentCapacity, "mAh"),
                field("AppleRawMaxCapacity", s.detail.appleRawMaxCapacity, "mAh"),
            ],
            formula: dashboardText("p.help_direct", fallback: "无公式：直接读取系统用户可见百分比。"),
            substitution: "CurrentCapacity → \(s.data.percent)%",
            source: "AppleSmartBattery CurrentCapacity / macOS visible state of charge."
        )
    }

    static func health(_ s: DashboardMetricSnapshot) -> MetricHelpContent {
        content(
            id: "health.system",
            title: dashboardText("p.priority_health", fallback: "整块电池的健康状况"),
            summary: dashboardText("p.help_summary_health", fallback: "主界面采用与系统设置更接近的口径；容量条另给出不含安全预留的直接容量比例，两者分母不同。"),
            result: LNum("%.1f%%", s.healthPercent),
            fields: [
                field("AppleRawMaxCapacity", s.fullChargeCapacity, "mAh"),
                field("PackReserve", s.detail.packReserve, "mAh"),
                field("DesignCapacity", s.designCapacity, "mAh"),
            ],
            formula: "health = (FullChargeCapacity + PackReserve) ÷ (DesignCapacity − PackReserve) × 100",
            substitution: "(\(s.fullChargeCapacity) + \(s.detail.packReserve)) ÷ (\(s.designCapacity) − \(s.detail.packReserve)) × 100 = \(LNum("%.1f%%", s.healthPercent))",
            source: "Derived from IOKit fields and aligned to this Mac's system reading. This inferred formula is labelled rather than presented as an Apple-published formula."
        )
    }

    static func power(_ s: DashboardMetricSnapshot) -> MetricHelpContent {
        let directPower = s.detail.systemPowerWatts
        let telemetryPower = s.detail.systemLoad == 0
            ? nil
            : Double(abs(s.detail.systemLoad)) / 1000.0
        let currentVoltagePower = abs(Double(s.data.amperage)) / 1000.0 * s.data.voltage
        let selectedSource: String
        if directPower.isFinite, directPower > 0 {
            selectedSource = "BatteryData.SystemPower"
        } else if telemetryPower != nil {
            selectedSource = "PowerTelemetryData.SystemLoad ÷ 1000"
        } else {
            selectedSource = "|Amperage| ÷ 1000 × Voltage"
        }

        return content(
            id: "power.current",
            title: dashboardText("p.priority_power", fallback: "当前电脑的使用功率"),
            summary: dashboardText("p.help_summary_power", fallback: "优先读取 BatteryData.SystemPower；不可用时才依次退回 SystemLoad 或电压×电流。长期基线来自电量计累计遥测。"),
            result: LNum("%.2f W", s.currentPowerWatts),
            fields: [
                field("BatteryData.SystemPower", f(s.detail.systemPowerWatts), "W"),
                field("PowerTelemetryData.SystemLoad", s.detail.systemLoad, "mW"),
                field("Voltage", f(s.data.voltage), "V"),
                field("Amperage", s.data.amperage, "mA"),
                field("AccumulatedSystemLoad", s.detail.accumulatedSystemLoad, "raw"),
                field("SystemLoadAccumulatorCount", s.detail.systemLoadAccumulatorCount, "samples"),
            ],
            formula: "1. SystemPower, when valid\n2. |SystemLoad| ÷ 1000\n3. |Amperage| ÷ 1000 × Voltage\naveragePower = AccumulatedSystemLoad ÷ sampleCount ÷ 1000",
            substitution: "SystemPower = \(f(directPower)) W\n|SystemLoad| ÷ 1000 = \(f(telemetryPower)) W\n|\(s.data.amperage)| ÷ 1000 × \(f(s.data.voltage)) = \(f(currentVoltagePower)) W\nSelected: \(selectedSource) → \(f(s.currentPowerWatts)) W\n\(optional(s.detail.accumulatedSystemLoad)) ÷ \(optional(s.detail.systemLoadAccumulatorCount)) ÷ 1000 = \(f(s.detail.averageTelemetryPowerWatts)) W",
            source: "IOKit BatteryData.SystemPower and PowerTelemetryData. The UI labels fallbacks instead of pretending every source is identical."
        )
    }

    static func temperature(_ s: DashboardMetricSnapshot) -> MetricHelpContent {
        let raw = s.detail.temperatureRaw
        let divisor: Double
        let rawUnit: String
        if (raw ?? 0) > 1_000 {
            divisor = 100
            rawUnit = "0.01°C"
        } else if (raw ?? 0) > 100 {
            divisor = 10
            rawUnit = "0.1°C"
        } else {
            divisor = 1
            rawUnit = "°C"
        }
        return content(
            id: "temperature.current",
            title: dashboardText("p.priority_temp", fallback: "当前电池温度"),
            summary: dashboardText("p.help_summary_temperature", fallback: "电量计字段在不同平台可能使用不同标度；服务层按原始量级解码，并保留原始值供核验。"),
            result: LNum("%.1f °C", s.data.temperatureCelsius),
            fields: [field("Temperature", raw, rawUnit)],
            formula: "if raw > 1000: °C = raw ÷ 100; else if raw > 100: °C = raw ÷ 10; else °C = raw",
            substitution: divisor == 1
                ? "\(optional(raw)) → \(LNum("%.2f °C", s.data.temperatureCelsius))"
                : "\(optional(raw)) ÷ \(Int(divisor)) = \(LNum("%.2f °C", s.data.temperatureCelsius))",
            source: "IOKit Temperature with platform-aware scale decoding; lifetime minimum and maximum are shown separately."
        )
    }

    static func officialBenchmark(_ s: DashboardMetricSnapshot, specification spec: BatteryModelSpecification) -> MetricHelpContent {
        let impliedPower = spec.designEnergyWh / max(spec.officialWebHours, 0.1)
        let sameLoad = (s.currentFullEnergyWh ?? 0) / impliedPower
        return content(
            id: "runtime.official-benchmark",
            title: dashboardText("p.runtime_audit_tag", fallback: "公开基准 × 这台电脑"),
            summary: dashboardText("p.audit_conditions", fallback: "官方网页续航来自固定亮度、Wi‑Fi 和轻负载条件，不等于任何满电电脑都能跑同样久。"),
            result: LNum("%.0f h WEB · %.0f h VIDEO", spec.officialWebHours, spec.officialVideoHours),
            fields: [
                field("hw.model", s.modelIdentifier),
                field("Apple design energy", f(spec.designEnergyWh), "Wh"),
                field("Apple wireless web", f(spec.officialWebHours), "h"),
                field("Apple streaming video", f(spec.officialVideoHours), "h"),
                field("AppleRawMaxCapacity", s.fullChargeCapacity, "mAh"),
                field("DesignCapacity", s.designCapacity, "mAh"),
            ],
            formula: "officialImpliedPower = designEnergy ÷ officialRuntime\ncurrentFullWh = designWh × FCC ÷ DesignCapacity\nsameLoadRuntime = currentFullWh ÷ officialImpliedPower",
            substitution: "\(f(spec.designEnergyWh)) ÷ \(f(spec.officialWebHours)) = \(f(impliedPower)) W\n\(f(s.currentFullEnergyWh)) ÷ \(f(impliedPower)) = \(f(sameLoad)) h",
            source: "\(spec.sourceName) · \(spec.sourceURL.absoluteString) · controlled Apple test. Current capacity and power come from this Mac's IOKit fields."
        )
    }

    static func runtimeHistory(_ s: DashboardMetricSnapshot, isForecast: Bool) -> MetricHelpContent {
        if isForecast {
            return content(
                id: "runtime.history.forecast",
                title: dashboardText("p.unplug_trend", fallback: "拔电后的预计续航"),
                summary: dashboardText("p.forecast_only", fallback: "虚线只是当前拔电预计，不会冒充系统历史。"),
                result: runtime(s.unplugEstimateMinutes ?? 0),
                fields: [field("remainingEnergy", f(s.remainingEnergyWh), "Wh"), field("SystemPower", f(s.currentPowerWatts), "W")],
                formula: "unplugRuntime = remainingEnergy ÷ currentPower",
                substitution: "\(f(s.remainingEnergyWh)) Wh ÷ \(f(s.currentPowerWatts)) W = \(f(Double(s.unplugEstimateMinutes ?? 0) / 60)) h",
                source: "Derived forecast while connected to power; dashed and excluded from system history."
            )
        }
        return content(
            id: "runtime.history.system",
            title: dashboardText("p.remaining_trend", fallback: "系统剩余时间记录"),
            summary: dashboardText("p.help_summary_time_history", fallback: "纵轴逐点记录 macOS 当时报告的剩余小时，横轴是采样时刻；相邻系统读数用阶梯连接，不按功率重算。"),
            result: runtime(s.data.timeRemainingMinutes ?? 0),
            fields: [field("TimeRemaining", s.detail.timeRemainingRaw, "min"), field("AvgTimeToEmpty", s.detail.avgTimeToEmpty, "min")],
            formula: dashboardText("p.help_direct", fallback: "无公式：每次保存有效系统读数。"),
            substitution: "validMinutes(TimeRemaining) → history point; minimum interval = 56 s",
            source: "AppleSmartBattery runtime fields; sentinel values and duplicate sub-56-second samples are rejected."
        )
    }

    static func capacityOverview(_ s: DashboardMetricSnapshot) -> MetricHelpContent {
        var fields = [
            field("DesignCapacity", s.designCapacity, "mAh"),
            field("AppleRawMaxCapacity (FCC)", s.fullChargeCapacity, "mAh"),
            field("AppleRawCurrentCapacity", s.currentCapacity, "mAh"),
        ]
        if let qmax = s.qmaxCapacityForBreakdown {
            fields.append(field("min(Qmax)", qmax, "mAh"))
        }
        let formula: String
        let substitution: String
        if let inaccessible = s.inaccessibleCapacity,
           let permanent = s.truePermanentLoss {
            formula = "DesignCapacity = CurrentRemaining + UsedSinceFull + (minQmax − FCC) + (DesignCapacity − minQmax)"
            substitution = "\(s.designCapacity) = \(s.currentCapacity) + \(s.usedSinceFull) + \(inaccessible) + \(permanent) mAh; FCC = \(s.currentCapacity) + \(s.usedSinceFull) = \(s.fullChargeCapacity) mAh"
        } else {
            formula = "DesignCapacity = CurrentRemaining + UsedSinceFull + LongTermCapacityGap"
            substitution = "\(s.designCapacity) = \(s.currentCapacity) + \(s.usedSinceFull) + \(s.longTermCapacityGap) mAh; Qmax unavailable, so the long-term gap is not split"
        }
        return content(
            id: "capacity.overview",
            title: dashboardText("p.where_title", fallback: "你买的容量去哪了"),
            summary: dashboardText("p.help_summary_capacity", fallback: "同一把尺下，先用 FCC 把容量分成可用与长期差额；Qmax 可信时，再把长期差额拆成暂时够不到和真正老化。"),
            result: "\(s.designCapacity.formatted()) mAh",
            fields: fields,
            formula: formula,
            substitution: substitution,
            source: "IOKit capacity fields. Qmax decomposition is shown only when min(Qmax) lies between FCC and DesignCapacity."
        )
    }

    static func designCapacity(_ s: DashboardMetricSnapshot) -> MetricHelpContent {
        directCapacity(id: "capacity.design", title: dashboardText("p.design_capacity", fallback: "设计容量"),
                       summary: dashboardText("p.help_summary_design_capacity", fallback: "这台电池出厂时的标称容量，是容量拆解的总尺。"),
                       fieldName: "DesignCapacity", value: s.designCapacity)
    }

    static func currentMax(_ s: DashboardMetricSnapshot) -> MetricHelpContent {
        directCapacity(id: "capacity.current-max", title: dashboardText("p.current_max", fallback: "目前最大容量"),
                       summary: dashboardText("p.help_summary_full_capacity", fallback: "这块电池现在充满后，系统允许实际使用的总容量。"),
                       fieldName: "AppleRawMaxCapacity", value: s.fullChargeCapacity)
    }

    static func currentActual(_ s: DashboardMetricSnapshot) -> MetricHelpContent {
        content(
            id: "capacity.current",
            title: dashboardText("p.current_actual", fallback: "此刻还剩"),
            summary: dashboardText("p.current_actual_desc", fallback: "本次剩余电量；会随使用减少，充电后可以回来。"),
            result: "\(s.currentCapacity.formatted()) mAh",
            fields: [field("AppleRawCurrentCapacity", s.detail.appleRawCurrentCapacity, "mAh"), field("AppleRawMaxCapacity", s.fullChargeCapacity, "mAh")],
            formula: "currentActual = min(AppleRawCurrentCapacity, AppleRawMaxCapacity)",
            substitution: "min(\(s.detail.appleRawCurrentCapacity), \(s.fullChargeCapacity)) = \(s.currentCapacity) mAh",
            source: "IOKit live capacity, capped at full-charge capacity to reject transient over-range readings."
        )
    }

    static func usedSinceFull(_ s: DashboardMetricSnapshot) -> MetricHelpContent {
        content(
            id: "capacity.used",
            title: dashboardText("p.used_since_full", fallback: "本次已经用掉"),
            summary: dashboardText("p.help_summary_used", fallback: "这是从本次满充到现在流出的电，会在下一次充电时补回来；它和永久老化不能相加。"),
            result: "\(s.usedSinceFull.formatted()) mAh",
            fields: [field("AppleRawMaxCapacity", s.fullChargeCapacity, "mAh"), field("AppleRawCurrentCapacity", s.currentCapacity, "mAh")],
            formula: "usedSinceFull = FullChargeCapacity − CurrentCapacity",
            substitution: "\(s.fullChargeCapacity) − \(s.currentCapacity) = \(s.usedSinceFull) mAh",
            source: "Derived from two IOKit capacity readings on the same scale."
        )
    }

    static func capacityGap(_ s: DashboardMetricSnapshot) -> MetricHelpContent {
        content(
            id: "capacity.long-term-gap",
            title: dashboardText("p.capacity_gap", fallback: "长期容量总差额"),
            summary: dashboardText("p.capacity_gap_summary", fallback: "这是设计容量与当前满充 FCC 的总差额。它可能同时包含真正化学老化、截止电压与标定影响，不能全部直接叫作永久损失。"),
            result: "\(s.longTermCapacityGap.formatted()) mAh",
            fields: [field("DesignCapacity", s.designCapacity, "mAh"), field("AppleRawMaxCapacity (FCC)", s.fullChargeCapacity, "mAh")],
            formula: "longTermCapacityGap = DesignCapacity − FCC",
            substitution: "\(s.designCapacity) − \(s.fullChargeCapacity) = \(s.longTermCapacityGap) mAh",
            source: "Derived from IOKit design and FCC readings. Qmax is required before this total can be split responsibly."
        )
    }

    static func inaccessibleCapacity(_ s: DashboardMetricSnapshot) -> MetricHelpContent {
        let qmax = s.qmaxCapacityForBreakdown ?? 0
        let inaccessible = s.inaccessibleCapacity ?? 0
        return content(
            id: "capacity.inaccessible",
            title: dashboardText("p.seg_un", fallback: "暂时够不到"),
            summary: dashboardText("p.unusable_ex", fallback: "化学容量仍在，但没有进入当前可用满充 FCC；像吸管够不到的杯底水。"),
            result: "\(inaccessible.formatted()) mAh",
            fields: [field("min(Qmax)", qmax, "mAh"), field("AppleRawMaxCapacity (FCC)", s.fullChargeCapacity, "mAh")],
            formula: "inaccessibleCapacity = min(Qmax) − FCC",
            substitution: "\(qmax) − \(s.fullChargeCapacity) = \(inaccessible) mAh",
            source: "Battery gauge learned Qmax and FCC. Shown only when FCC ≤ min(Qmax) ≤ DesignCapacity."
        )
    }

    static func permanentLoss(_ s: DashboardMetricSnapshot) -> MetricHelpContent {
        let qmax = s.qmaxCapacityForBreakdown ?? s.fullChargeCapacity
        let permanent = s.truePermanentLoss ?? s.longTermCapacityGap
        return content(
            id: "capacity.true-permanent-loss",
            title: dashboardText("p.seg_age", fallback: "真正老化"),
            summary: dashboardText("p.seg_age_d", fallback: "设计容量与电量计学习到的化学容量之差，像水箱本身缩小了。"),
            result: "\(permanent.formatted()) mAh",
            fields: [field("DesignCapacity", s.designCapacity, "mAh"), field("min(Qmax)", qmax, "mAh")],
            formula: "truePermanentLoss = DesignCapacity − min(Qmax)",
            substitution: "\(s.designCapacity) − \(qmax) = \(permanent) mAh",
            source: "Derived from design capacity and the weakest cell's learned Qmax. The UI uses this label only when Qmax passes the FCC/design consistency gate."
        )
    }

    static func specOverview(_ s: DashboardMetricSnapshot) -> MetricHelpContent {
        content(
            id: "references.overview",
            title: dashboardText("p.spec_other_title", fallback: "其余 4 项关键指标"),
            summary: dashboardText("p.spec_source_note", fallback: "每个合理范围都会说明依据，不把 Apple 规格、个人历史和通用资料混成一个标准答案。"),
            result: "4 × REFERENCE",
            fields: [field("IOKit live fields", "current values"), field("LifetimeData", "personal extremes"), field("Apple/general references", "labelled ranges")],
            formula: dashboardText("p.help_direct", fallback: "每一行分别使用自己的字段或明确标注的推导。"),
            substitution: "current value + range + history + low/high impact + source",
            source: "Mixed sources, labelled per metric."
        )
    }

    static func cellBalance(_ s: DashboardMetricSnapshot) -> MetricHelpContent {
        let cells = s.detail.cellVoltages
        let delta = s.detail.cellVoltageDelta ?? 0
        return content(
            id: "reference.cell-balance",
            title: dashboardText("insight.factor.balance", fallback: "各单元均衡度"),
            summary: dashboardText("p.help_summary_balance", fallback: "串联电芯中最弱的一节会先触及截止线，因此压差越小，整包越同步。"),
            result: "\(delta) mV",
            fields: [field("BatteryData.CellVoltage", cells.map(String.init).joined(separator: " / "), "mV")],
            formula: "cellBalance = max(CellVoltage) − min(CellVoltage)",
            substitution: cells.isEmpty ? "no valid cell-voltage array" : "\(cells.max() ?? 0) − \(cells.min() ?? 0) = \(delta) mV",
            source: "IOKit cell voltages; 0–20 mV is a general lithium-pack reference, not an Apple service specification."
        )
    }

    static func resistance(_ s: DashboardMetricSnapshot) -> MetricHelpContent {
        let values = s.detail.weightedRa
        let maximum = values.max() ?? 0
        return content(
            id: "reference.resistance",
            title: dashboardText("insight.factor.resistance", fallback: "电池内部阻力"),
            summary: dashboardText("p.help_summary_resistance", fallback: "显示最差一节的加权内阻，因为串联电池组会被阻力最高的一节限制；更重要的是观察同一台电脑的变化趋势。"),
            result: "\(maximum) mΩ",
            fields: [field("BatteryData.WeightedRa", values.map(String.init).joined(separator: " / "), "mΩ")],
            formula: "displayedResistance = max(WeightedRa)",
            substitution: "max(\(values.map(String.init).joined(separator: ", "))) = \(maximum) mΩ",
            source: "IOKit gauge value. 0–130 mΩ is a presentation reference; Apple publishes no fixed service range for this field."
        )
    }

    static func cycles(_ s: DashboardMetricSnapshot) -> MetricHelpContent {
        let rated = s.detail.designCycleCount
        let usage = (s.detail.cycleUsage ?? 0) * 100
        return content(
            id: "reference.cycles",
            title: dashboardText("insight.factor.cycles", fallback: "循环使用率"),
            summary: dashboardText("p.help_summary_cycles", fallback: "循环次数像里程表，只说明累计使用；是否需要检修仍需结合容量、内阻、电芯差和温度。"),
            result: LNum("%.1f%%", usage),
            fields: [field("CycleCount", s.detail.cycleCount), field("DesignCycleCount9C", rated)],
            formula: "cycleUse = CycleCount ÷ DesignCycleCount × 100",
            substitution: rated > 0 ? "\(s.detail.cycleCount) ÷ \(rated) × 100 = \(LNum("%.1f%%", usage))" : "DesignCycleCount unavailable",
            source: "IOKit CycleCount and rated design-cycle field; Apple's 80% capacity threshold is not the same thing as reaching the cycle rating."
        )
    }

    static func packVoltage(_ s: DashboardMetricSnapshot) -> MetricHelpContent {
        content(
            id: "reference.pack-voltage",
            title: dashboardText("hw.m.pack_voltage", fallback: "电池组电压"),
            summary: dashboardText("p.help_summary_voltage", fallback: "电压会随电量和负载变化；单次高低不等于健康好坏，所以与这块电池自己的历史极限一起展示。"),
            result: LNum("%.2f V", s.voltageVolts),
            fields: [
                field("Voltage", s.detail.voltageRaw ?? s.detail.packVoltage, "mV"),
                field("AppleRawBatteryVoltage", s.detail.appleRawBatteryVoltage, "mV"),
                field("LifetimeData.MinimumPackVoltage", s.detail.minimumPackVoltage, "mV"),
                field("LifetimeData.MaximumPackVoltage", s.detail.maximumPackVoltage, "mV"),
            ],
            formula: "packVoltageV = packVoltageMillivolts ÷ 1000",
            substitution: "\(s.detail.packVoltage) ÷ 1000 = \(LNum("%.3f V", s.voltageVolts))",
            source: "IOKit live pack voltage and lifetime extremes from this battery."
        )
    }

    private static func directCapacity(id: String, title: String, summary: String, fieldName: String, value: Int) -> MetricHelpContent {
        content(
            id: id, title: title, summary: summary, result: "\(value.formatted()) mAh",
            fields: [field(fieldName, value, "mAh")],
            formula: dashboardText("p.help_direct", fallback: "无公式：直接读取系统字段。"),
            substitution: "\(fieldName) → \(value) mAh",
            source: "AppleSmartBattery IOKit field."
        )
    }

    private static func content(
        id: String,
        title: String,
        summary: String,
        result: String,
        fields: [MetricRawField],
        formula: String,
        substitution: String,
        source: String
    ) -> MetricHelpContent {
        MetricHelpContent(
            id: id,
            title: title,
            summary: summary,
            result: result,
            rawFields: fields,
            formula: formula,
            substitution: substitution,
            source: source
        )
    }

    private static func field(_ name: String, _ value: String, _ unit: String = "") -> MetricRawField {
        MetricRawField(name: name, value: value.isEmpty ? "—" : value, unit: unit)
    }

    private static func field<T: BinaryInteger>(_ name: String, _ value: T?, _ unit: String = "") -> MetricRawField {
        MetricRawField(name: name, value: value.map { String($0) } ?? "—", unit: unit)
    }

    private static func f(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "—" }
        return LNum("%.2f", value)
    }

    private static func optional<T>(_ value: T?) -> String { value.map(String.init(describing:)) ?? "—" }

    private static func runtime(_ minutes: Int) -> String {
        guard minutes > 0 else { return "—" }
        return "\(minutes / 60) h \(String(format: "%02d", minutes % 60)) m"
    }
}
