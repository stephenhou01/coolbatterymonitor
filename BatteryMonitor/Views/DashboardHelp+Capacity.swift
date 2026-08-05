import Foundation
import SwiftUI

extension DashboardHelp {
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
            source: "AppleSmartBattery CurrentCapacity / macOS visible state of charge.",
            readAt: s.rawFieldReadAt,
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
            source: "Derived from IOKit fields and aligned to this Mac's system reading. This inferred formula is labelled rather than presented as an Apple-published formula.",
            readAt: s.rawFieldReadAt,
        )
    }
    static func cycleCount(_ s: DashboardMetricSnapshot) -> MetricHelpContent {
        let count = s.detail.cycleCount > 0 ? s.detail.cycleCount : s.data.cycleCount
        let rated = s.detail.designCycleCount
        let usage = rated > 0 ? Double(count) / Double(rated) * 100 : nil
        let substitution: String
        if let usage {
            substitution = "\(count) ÷ \(rated) × 100 = \(LNum("%.1f%%", usage))"
        } else {
            substitution = "CycleCount → \(count)"
        }
        return content(
            id: "cycles.count",
            title: MenuBarMetric.cycles.title,
            summary: dashboardText(
                "p.help_summary_cycle_count",
                fallback: "一次循环等于累计用掉 100% 的设计电量，可以由多次浅充浅放累加。它像里程表，不能单独代表电池健康。"
            ),
            result: "\(count)",
            fields: [
                field("CycleCount", count, "cycles"),
                field("DesignCycleCount9C", rated, "cycles"),
            ],
            formula: rated > 0
                ? "cycleUse = CycleCount ÷ DesignCycleCount × 100"
                : dashboardText("p.help_direct", fallback: "无公式：直接读取系统字段。"),
            substitution: substitution,
            source: dashboardText(
                "p.help_source_cycle_count",
                fallback: "IOKit CycleCount；额定参考来自 DesignCycleCount9C。达到额定循环数不等于电池会立即失效。"
            ),
            readAt: s.rawFieldReadAt,
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
            source: "IOKit Temperature with platform-aware scale decoding; lifetime minimum and maximum are shown separately.",
            readAt: s.rawFieldReadAt,
            trend: MetricHelpTrend(
                title: trendTitle(),
                latestText: LNum("%.1f ℃", s.data.temperatureCelsius),
                note: dashboardText(
                    "p.trend_note_temperature",
                    fallback: "纵轴贴着实际区间画，不从 0 ℃ 起——否则电池真实的几度波动会被压成一条直线。鼠标移到线上可看该分钟读数。"
                ),
                unit: "℃",
                tint: AppTheme.batteryYellow,
                points: trendPoints(s) { $0.temperature > 0 ? $0.temperature : nil },
                baselineAtZero: false,
                waitingText: trendWaiting()
            )
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
            source: "IOKit capacity fields. Qmax decomposition is shown only when min(Qmax) lies between FCC and DesignCapacity.",
            readAt: s.rawFieldReadAt,
        )
    }

    static func designCapacity(_ s: DashboardMetricSnapshot) -> MetricHelpContent {
        directCapacity(id: "capacity.design", title: dashboardText("p.design_capacity", fallback: "设计容量"),
                       summary: dashboardText("p.help_summary_design_capacity", fallback: "这台电池出厂时的标称容量，是容量拆解的总尺。"),
                       fieldName: "DesignCapacity", value: s.designCapacity, readAt: s.rawFieldReadAt)
    }

    static func currentMax(_ s: DashboardMetricSnapshot) -> MetricHelpContent {
        directCapacity(id: "capacity.current-max", title: dashboardText("p.current_max", fallback: "目前最大容量"),
                       summary: dashboardText("p.help_summary_full_capacity", fallback: "这块电池现在充满后，系统允许实际使用的总容量。"),
                       fieldName: "AppleRawMaxCapacity", value: s.fullChargeCapacity, readAt: s.rawFieldReadAt)
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
            source: "IOKit live capacity, capped at full-charge capacity to reject transient over-range readings.",
            readAt: s.rawFieldReadAt,
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
            source: "Derived from two IOKit capacity readings on the same scale.",
            readAt: s.rawFieldReadAt,
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
            source: "Derived from IOKit design and FCC readings. Qmax is required before this total can be split responsibly.",
            readAt: s.rawFieldReadAt,
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
            source: "Battery gauge learned Qmax and FCC. Shown only when FCC ≤ min(Qmax) ≤ DesignCapacity.",
            readAt: s.rawFieldReadAt,
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
            source: "Derived from design capacity and the weakest cell's learned Qmax. The UI uses this label only when Qmax passes the FCC/design consistency gate.",
            readAt: s.rawFieldReadAt,
        )
    }

    static func specOverview(_ s: DashboardMetricSnapshot) -> MetricHelpContent {
        content(
            id: "references.overview",
            title: dashboardText("p.spec_other_title", fallback: "其余 4 项关键指标"),
            summary: dashboardText("p.spec_source_note", fallback: "每个合理范围都会说明依据，不把 Apple 规格、个人历史和通用资料混成一个标准答案。"),
            result: "4 × REFERENCE",
            // Label-only rows: these three name groups of fields, they are not
            // readings, so they carry neither a read time nor a cadence.
            fields: [field("IOKit live fields", "current values", "", "", updateClass: .untimed),
                     field("LifetimeData", "personal extremes", "", "", updateClass: .untimed),
                     field("Apple/general references", "labelled ranges", "", "", updateClass: .untimed)],
            formula: dashboardText("p.help_direct", fallback: "每一行分别使用自己的字段或明确标注的推导。"),
            substitution: "current value + range + history + low/high impact + source",
            source: "Mixed sources, labelled per metric.",
            readAt: s.rawFieldReadAt,
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
            source: "IOKit cell voltages; 0–20 mV is a general lithium-pack reference, not an Apple service specification.",
            readAt: s.rawFieldReadAt,
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
            source: "IOKit gauge value. 0–130 mΩ is a presentation reference; Apple publishes no fixed service range for this field.",
            readAt: s.rawFieldReadAt,
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
            source: "IOKit CycleCount and rated design-cycle field; Apple's 80% capacity threshold is not the same thing as reaching the cycle rating.",
            readAt: s.rawFieldReadAt,
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
            source: "IOKit live pack voltage and lifetime extremes from this battery.",
            readAt: s.rawFieldReadAt,
        )
    }
}
