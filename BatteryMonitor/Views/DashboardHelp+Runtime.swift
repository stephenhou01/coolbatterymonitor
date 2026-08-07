import Foundation
import SwiftUI

extension DashboardHelp {
    static func runtime(_ s: DashboardMetricSnapshot) -> MetricHelpContent {
        let detail = s.detail
        let systemMinutes = s.systemRuntimeMinutes
        let stableMinutes = s.stableRuntimeMinutes
        let currentMinutes = s.currentLoadRuntimeMinutes
        let referenceMinutes = currentMinutes ?? stableMinutes
        let hasLiveSystemReading = !s.data.isOnAC
            && s.data.timeRemainingMinutes.map(RuntimeSample.isValid(minutes:)) == true
        let systemNote: String
        if systemMinutes == nil, let referenceMinutes {
            let key = s.data.isOnAC
                ? "p.runtime_system_on_ac_estimate"
                : "p.runtime_system_unavailable_estimate"
            let fallback = s.data.isOnAC
                ? "当前接电，macOS 不提供放电剩余时间 · 按实测功耗估算 {time}，仅作拔电参考"
                : "按实测功耗预计可用 {time} · 拔掉电源后约等 10 分钟再查看系统时间"
            systemNote = dashboardText(
                key,
                fallback: fallback,
                replacements: ["time": runtime(referenceMinutes)]
            )
        } else if systemMinutes == nil {
            let key = s.data.isOnAC
                ? "p.runtime_system_on_ac_note"
                : "p.runtime_system_unavailable_note"
            let fallback = s.data.isOnAC
                ? "当前接电，macOS 不提供放电剩余时间 · 拔电使用后生成"
                : "暂无可靠的系统时间 · 拔掉电源后约等 10 分钟再查看"
            systemNote = dashboardText(
                key,
                fallback: fallback
            )
        } else if hasLiveSystemReading {
            // Lead with what the number means, then how it is kept up to date:
            // the mechanism alone left readers unable to tell the three cards
            // apart, or to know when to distrust one.
            let meaning = dashboardText(
                "p.runtime_system_meaning",
                fallback: "和菜单栏同一个数字，由电池里的电量计芯片自己算出来，我们不参与计算：优先读 TimeRemaining，它无效时才退到 AvgTimeToEmpty，65535 和超过 24 小时的值一律当无效丢弃；接电时这两个字段不可用，界面明确显示不可用，不再回填历史值。电量计按平均电流估算，负载突然变重后要过一两分钟才跟上"
            )
            systemNote = meaning + " · " + dashboardText(
                "p.runtime_system_read_live",
                fallback: "TimeRemaining / AvgTimeToEmpty · 上次刷新 {time} · 电量计约 {interval} 秒刷新一次，每次有效读数存一条历史",
                replacements: [
                    "time": runtimeReadTimestamp(s.data.lastUpdated),
                    "interval": "\(MetricFieldFreshness.gaugeRefreshSeconds)",
                ]
            )
        } else {
            systemNote = dashboardText("p.chart_waiting", fallback: "等待电量计给出续航预测")
        }

        let systemValue = systemMinutes.map(runtime)
            ?? dashboardText("p.runtime_unavailable", fallback: "不可用")

        // The two derived rows are not live readings: state which sample they
        // were computed from and how often that sample is refreshed.
        var stableNote = dashboardText(
            "p.runtime_stable_note",
            fallback: "回答「按最近这段时间的用法还能撑多久」：取窗口内功耗的中间值（中位数）而不是平均值，一闪而过的高负载不会带偏它。窗口最长 10 分钟，但只要 5 个有效样本就出结果，所以刚启动时它可能只覆盖几十秒——卡片副标题写的是实际覆盖的时长，不是固定的 10 分钟"
        )
        if let stableSampleTime = s.latestStablePowerSampleTime {
            stableNote += " · " + dashboardText(
                "p.runtime_stable_read",
                fallback: "最新样本读取于 {time}（窗口内 {samples} 个有效样本）· 每 10 秒采样一次",
                replacements: [
                    "time": runtimeReadTimestamp(stableSampleTime),
                    "samples": "\(s.recentStablePowerSamples.count)",
                ]
            )
        }

        let currentAge = s.currentPowerAgeSeconds
        var currentNote = dashboardText(
            "p.runtime_current_note",
            fallback: "回答「如果一直像现在这样用」：按最新一次功率读数换算，不做任何平滑，所以对负载变化最敏感，也最容易偏高或偏低。电量计约每 60 秒才发布一次，这个「最新」最多可能已有一分钟历史；超过 120 秒就停用并等新数据"
        )
        let isCurrentSampleStale = currentAge > 120
        currentNote += " · " + dashboardText(
            isCurrentSampleStale ? "p.runtime_current_read_stale" : "p.runtime_current_read",
            fallback: isCurrentSampleStale
                ? "上次读取于 {time}，已过 {age} 秒 · 每 10 秒刷新一次"
                : "读取于 {time}（{age} 秒前）· 每 10 秒刷新一次",
            replacements: [
                // Must be the same clock the age is measured from, otherwise the
                // timestamp and "N 秒前" in one sentence contradict each other.
                // A stale sample can predate a sleep, so that variant keeps the date.
                "time": runtimeReadTimestamp(s.rawFieldReadAt.at, includeDate: isCurrentSampleStale),
                "age": "\(currentAge)",
            ]
        )

        return content(
            id: "runtime.comparison",
            title: dashboardText("p.runtime_compare_title", fallback: "三种续航口径"),
            summary: dashboardText("p.runtime_compare_summary", fallback: "主结果以 macOS 系统时间为准；下面两项是同一份剩余电量分别按稳健功耗和当前功耗换算的参考值。"),
            result: systemValue,
            fields: [
                runtimeRawField("TimeRemaining", detail.timeRemainingRaw, onAC: s.data.isOnAC),
                runtimeRawField("AvgTimeToEmpty", detail.avgTimeToEmpty, onAC: s.data.isOnAC),
                field("ModelDesignEnergy", f(s.designEnergyWh), "Wh", updateClass: .modelSpec),
                field("AppleRawCurrentCapacity", s.currentCapacity, "mAh"),
                field("DesignCapacity", s.designCapacity, "mAh"),
                // Stamped from the newest sample feeding the median, not from
                // this poll: the window is up to ten minutes wide. Named for the
                // window rather than "10m" because five samples are enough, so
                // the span can be much shorter than ten minutes.
                field("Derived.StableWindowMedianPower", f(s.stablePowerWatts), "W",
                      readAt: s.latestStablePowerSampleTime.map(MetricReadStamp.ourRead)),
                field("Derived.StableWindowSamples", s.recentStablePowerSamples.count, "",
                      readAt: s.latestStablePowerSampleTime.map(MetricReadStamp.ourRead)),
                field("BatteryData.SystemPower", f(s.currentPowerWatts), "W"),
                // This row's value already is the read age; a second age next to
                // it would only contradict itself as the clock ticks.
                field("Derived.CurrentPowerSampleAge", s.currentPowerAgeSeconds, "s",
                      updateClass: .untimed),
            ],
            formula: "systemMinutes = onBattery ? (valid(TimeRemaining) ?? valid(AvgTimeToEmpty)) : unavailable\nremainingWh = designWh × currentCapacity ÷ designCapacity\nstableMinutes = remainingWh ÷ median(last10mPower) × 60\ncurrentLoadMinutes = remainingWh ÷ currentSystemPower × 60",
            substitution: "system: \(runtimeRawValue(detail.timeRemainingRaw)) / \(runtimeRawValue(detail.avgTimeToEmpty)) → \(systemValue)\nremaining: \(f(s.designEnergyWh)) × \(s.currentCapacity) ÷ \(s.designCapacity) = \(f(s.remainingEnergyWh)) Wh\nstable: \(f(s.remainingEnergyWh)) ÷ \(f(s.stablePowerWatts)) × 60 = \(optional(stableMinutes)) min\ncurrent: \(f(s.remainingEnergyWh)) ÷ \(f(s.currentPowerWatts)) × 60 = \(optional(currentMinutes)) min",
            source: dashboardText("p.runtime_compare_source", fallback: "macOS 系统时间来自 AppleSmartBattery；两项计算值由本机剩余能量和实测功耗推导，只作对照，不写入系统续航历史。"),
            readAt: s.rawFieldReadAt,
            results: [
                MetricHelpResult(
                    id: "runtime.system",
                    title: dashboardText("p.runtime_system_label", fallback: "macOS 系统时间"),
                    value: systemValue,
                    note: systemNote,
                    style: .primary
                ),
                MetricHelpResult(
                    id: "runtime.stable",
                    title: dashboardText("p.runtime_stable_label", fallback: "稳健估算"),
                    value: runtime(stableMinutes),
                    note: stableNote,
                    style: .stable
                ),
                MetricHelpResult(
                    id: "runtime.current-load",
                    title: dashboardText("p.runtime_current_label", fallback: "短时间估算"),
                    value: runtime(currentMinutes),
                    note: currentNote,
                    style: .current
                ),
            ]
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
                field("hw.model", s.modelIdentifier, "", updateClass: .modelSpec),
                field("Apple design energy", f(spec.designEnergyWh), "Wh", updateClass: .modelSpec),
                field("Apple wireless web", f(spec.officialWebHours), "h", updateClass: .modelSpec),
                field("Apple streaming video", f(spec.officialVideoHours), "h", updateClass: .modelSpec),
                field("AppleRawMaxCapacity", s.fullChargeCapacity, "mAh"),
                field("DesignCapacity", s.designCapacity, "mAh"),
            ],
            formula: "officialImpliedPower = designEnergy ÷ officialRuntime\ncurrentFullWh = designWh × FCC ÷ DesignCapacity\nsameLoadRuntime = currentFullWh ÷ officialImpliedPower",
            substitution: "\(f(spec.designEnergyWh)) ÷ \(f(spec.officialWebHours)) = \(f(impliedPower)) W\n\(f(s.currentFullEnergyWh)) ÷ \(f(impliedPower)) = \(f(sameLoad)) h",
            source: "\(spec.sourceName) · \(spec.sourceURL.absoluteString) · controlled Apple test. Current capacity and power come from this Mac's IOKit fields.",
            readAt: s.rawFieldReadAt,
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
                source: "Derived forecast while connected to power; dashed and excluded from system history.",
                readAt: s.rawFieldReadAt
            )
        }
        return content(
            id: "runtime.history.system",
            title: dashboardText("p.remaining_trend", fallback: "系统剩余时间记录"),
            summary: dashboardText("p.help_summary_time_history", fallback: "纵轴逐点记录 macOS 当时报告的剩余小时，横轴是采样时刻；相邻系统读数用阶梯连接，不按功率重算。"),
            result: runtime(s.data.timeRemainingMinutes ?? 0),
            fields: [runtimeRawField("TimeRemaining", s.detail.timeRemainingRaw, onAC: s.data.isOnAC),
                     runtimeRawField("AvgTimeToEmpty", s.detail.avgTimeToEmpty, onAC: s.data.isOnAC)],
            formula: dashboardText("p.help_direct", fallback: "无公式：每次保存有效系统读数。"),
            substitution: "validMinutes(TimeRemaining) → history point; minimum interval = 56 s",
            source: "AppleSmartBattery runtime fields; sentinel values and duplicate sub-56-second samples are rejected.",
            readAt: s.rawFieldReadAt,
        )
    }

}
