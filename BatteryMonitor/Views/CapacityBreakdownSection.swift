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
                icon: BatteryMetricIcon.designCapacity.symbol,
                title: dashboardText("p.where_title", fallback: "你买的容量去哪了"),
                color: AppTheme.batteryYellow,
                help: { DashboardHelp.capacityOverview(snapshot) },
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
                              icon: .designCapacity, color: AppTheme.batteryYellow,
                              help: { DashboardHelp.designCapacity(snapshot) }),
                        .init(label: dashboardText("p.capacity_gap", fallback: "长期容量总差额"), value: gap,
                              icon: .capacityGap, color: AppTheme.batteryRed,
                              help: { DashboardHelp.capacityGap(snapshot) }),
                        .init(label: dashboardText("p.current_max", fallback: "目前最大容量"), value: full,
                              icon: .capacity, color: AppTheme.chargingCyan,
                              help: { DashboardHelp.currentMax(snapshot) }),
                    ],
                    operators: ["−", "="],
                    selection: $selectedHelp
                )

                CapacityEquation(
                    title: dashboardText("p.eq_usage_title", fallback: "充满后的电去了哪里"),
                    subtitle: dashboardText("p.eq_usage_sub", fallback: "目前最大容量减去本次已用，就是此刻还剩"),
                    terms: [
                        .init(label: dashboardText("p.current_max", fallback: "目前最大容量"), value: full,
                              icon: .capacity, color: AppTheme.chargingCyan,
                              help: { DashboardHelp.currentMax(snapshot) }),
                        .init(label: dashboardText("p.used_since_full", fallback: "本次已经用掉"), value: used,
                              icon: .usedCapacity, color: AppTheme.chargingBlue,
                              help: { DashboardHelp.usedSinceFull(snapshot) }),
                        .init(label: dashboardText("p.current_actual", fallback: "此刻还剩"), value: current,
                              icon: .stateOfCharge, color: AppTheme.chargingCyan,
                              help: { DashboardHelp.currentActual(snapshot) }),
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
                                  icon: .capacityGap, color: AppTheme.batteryYellow,
                                  help: { DashboardHelp.capacityGap(snapshot) }),
                            .init(label: dashboardText("p.seg_un", fallback: "暂时够不到"), value: inaccessible,
                                  icon: .inaccessibleCapacity, color: AppTheme.batteryYellow,
                                  help: { DashboardHelp.inaccessibleCapacity(snapshot) }),
                            .init(label: dashboardText("p.seg_age", fallback: "真正老化"), value: permanent,
                                  icon: .permanentLoss, color: AppTheme.batteryRed,
                                  help: { DashboardHelp.permanentLoss(snapshot) }),
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
                .background(RoundedRectangle(cornerRadius: 9).fill(AppTheme.surfaceSunken))
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
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(AppTheme.contrastOverlay(0.09)))
            .overlay(alignment: .topLeading) {
                let boundary = min(max(width * CGFloat(full) / CGFloat(total), 0), width)
                let boundaryLabel = dashboardText("p.current_max", fallback: "目前最大容量")
                Rectangle()
                    .fill(AppTheme.contrastOverlay(0.62))
                    .frame(width: 1, height: 78)
                    .offset(x: boundary)
                Text("FCC · \(boundaryLabel) \(formatted(full))")
                    .font(.system(size: 7.5, weight: .semibold, design: .monospaced))
                    .foregroundStyle(AppTheme.textPrimary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(AppTheme.surfaceRaised.opacity(0.92)))
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
        .foregroundStyle(AppTheme.contrastOverlay(0.9))
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
            icon: .designCapacity,
            title: dashboardText("p.design_capacity", fallback: "出厂设计容量"),
            value: design,
            percentage: 100,
            description: dashboardText("p.capacity_sum", fallback: "这是这台机型出厂时的整只水箱：{design} mAh。",
                                       replacements: ["design": formatted(design)]),
            color: AppTheme.batteryYellow,
            help: { DashboardHelp.designCapacity(snapshot) },
            selection: $selectedHelp
        )
        CapacityLegendCard(
            icon: .capacity,
            title: dashboardText("p.current_max", fallback: "目前充满能装"),
            value: full,
            percentage: ratio(full),
            description: dashboardText("p.current_max_desc", fallback: "像现在这只水箱真正能装满、也能放出来的总量。"),
            color: AppTheme.chargingCyan,
            help: { DashboardHelp.currentMax(snapshot) },
            selection: $selectedHelp
        )
        CapacityLegendCard(
            icon: .stateOfCharge,
            title: dashboardText("p.current_actual", fallback: "此刻还剩"),
            value: current,
            percentage: ratio(current),
            description: dashboardText("p.current_actual_desc", fallback: "像水箱里此刻剩下的水；使用会减少，充电会补回来。"),
            color: AppTheme.chargingCyan,
            help: { DashboardHelp.currentActual(snapshot) },
            selection: $selectedHelp
        )
        CapacityLegendCard(
            icon: .usedCapacity,
            title: dashboardText("p.used_since_full", fallback: "本次已经用掉"),
            value: used,
            percentage: ratio(used),
            description: dashboardText(used == 0 ? "p.used_zero_desc" : "p.used_since_full_desc",
                                       fallback: used == 0 ? "刚充满，所以这次还没有用掉；它不是老化。" : "从本次充满到现在已经用掉的电，充电后会回来；它不是老化。"),
            color: AppTheme.chargingBlue,
            help: { DashboardHelp.usedSinceFull(snapshot) },
            selection: $selectedHelp
        )
        if let inaccessible, let permanent {
            CapacityLegendCard(
                icon: .inaccessibleCapacity,
                title: dashboardText("p.seg_un", fallback: "暂时够不到"),
                value: inaccessible,
                percentage: ratio(inaccessible),
                description: dashboardText("p.seg_un_d", fallback: "像吸管够不到的杯底水：电量计认为它还在，但系统会在电压过低前停止放电。"),
                color: AppTheme.batteryYellow,
                help: { DashboardHelp.inaccessibleCapacity(snapshot) },
                selection: $selectedHelp
            )
            CapacityLegendCard(
                icon: .permanentLoss,
                title: dashboardText("p.seg_age", fallback: "真正老化"),
                value: permanent,
                percentage: ratio(permanent),
                description: dashboardText("p.seg_age_d", fallback: "像水箱本身缩小了；这是设计容量与学习到的化学容量之差。"),
                color: AppTheme.batteryRed,
                help: { DashboardHelp.permanentLoss(snapshot) },
                selection: $selectedHelp
            )
        } else {
            CapacityLegendCard(
                icon: .capacityGap,
                title: dashboardText("p.capacity_gap", fallback: "长期容量总差额"),
                value: gap,
                percentage: ratio(gap),
                description: dashboardText("p.capacity_gap_desc", fallback: "目前满充容量比出厂设计少的总差额；Qmax 数据不足时不武断拆成够不到与真正老化。"),
                color: AppTheme.batteryRed,
                help: { DashboardHelp.capacityGap(snapshot) },
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
            return dashboardText(
                "p.capacity_accessibility_four",
                fallback: "{current} mAh 此刻还剩，{used} mAh 本次已用，{unusable} mAh 暂时够不到，{aged} mAh 真正老化；FCC 边界 {full} mAh",
                replacements: [
                    "current": formatted(current), "used": formatted(used),
                    "unusable": formatted(inaccessible), "aged": formatted(permanent),
                    "full": formatted(full),
                ]
            )
        }
        return dashboardText(
            "p.capacity_accessibility_gap",
            fallback: "{current} mAh 此刻还剩，{used} mAh 本次已用，{gap} mAh 长期容量差额；FCC 边界 {full} mAh",
            replacements: [
                "current": formatted(current), "used": formatted(used),
                "gap": formatted(gap), "full": formatted(full),
            ]
        )
    }

    private func ratio(_ value: Int) -> Double {
        design > 0 ? Double(value) / Double(design) * 100 : 0
    }

    private func formatted(_ value: Int) -> String { value.formatted(.number.grouping(.automatic)) }
}

private struct CapacityLegendCard: View {
    let icon: BatteryMetricIcon
    let title: String
    let value: Int
    let percentage: Double
    let description: String
    let color: Color
    /// Lazy so the sheet is built on tap, not on every redraw of the card.
    let help: () -> MetricHelpContent
    @Binding var selection: MetricHelpContent?

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .top, spacing: 9) {
                MetricGlyph(icon, tint: color, scale: .card)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(title)
                            .font(.system(size: 9.5, weight: .semibold))
                            .foregroundStyle(AppTheme.textSecondary)
                            .lineLimit(2)
                        MetricHelpButton(content: help(), selection: $selection)
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
                Capsule().fill(AppTheme.contrastOverlay(0.04))
                    .overlay(alignment: .leading) {
                        Capsule().fill(color.opacity(0.68))
                            .frame(width: geo.size.width * CGFloat(min(max(percentage, 0), 100)) / 100)
                    }
            }
            .frame(height: 3)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 158, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 12).fill(AppTheme.contrastOverlay(0.018)))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(AppTheme.contrastOverlay(0.06)))
    }
}

private struct CapacityEquationTerm {
    let label: String
    let value: Int
    let icon: BatteryMetricIcon
    let color: Color
    /// Lazy so the sheet is built on tap, not on every redraw of the card.
    let help: () -> MetricHelpContent
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
        .background(RoundedRectangle(cornerRadius: 11).fill(AppTheme.surfaceSunken))
        .overlay(RoundedRectangle(cornerRadius: 11).stroke(AppTheme.contrastOverlay(0.055)))
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
                    MetricGlyph(term.icon, tint: term.color, scale: .compact)
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 3) {
                            Text(term.label)
                                .font(.system(size: 8.5))
                                .foregroundStyle(AppTheme.textTertiary)
                                .lineLimit(1)
                            MetricHelpButton(content: term.help(), selection: $selection)
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
