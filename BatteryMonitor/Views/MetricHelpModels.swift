import SwiftUI

/// How often a raw field's number can actually change. This is a cadence axis,
/// deliberately separate from `FieldReliability`'s trust axis: a value can be
/// perfectly trustworthy and never update, or live and only conditionally
/// present. Keeping them apart stops the drawer from claiming that a built-in
/// specification constant is a fresh hardware reading.
enum MetricFieldUpdateClass: Equatable {
    /// Re-read from IOKit on every poll, so it carries the poll's read time.
    /// Note this describes the *read*, not the value: measured with `ioreg`, most
    /// gauge fields hold the same number for minutes at a time.
    case live
    /// A factory rating that IOKit keeps returning unchanged for the life of the
    /// battery. Captioning it with a read cadence implies volatility it lacks.
    case constant
    /// Changes when something is physically plugged or unplugged, not on the
    /// gauge's beat: measured, `AdapterDetails.*` vanished within 2 s of an unplug
    /// while the gauge was mid-cycle. Quoting the gauge's publish time for these
    /// would misdate them, so they keep our own read time.
    case eventDriven
    /// Comes from the built-in model specification table or the hardware
    /// identifier; it cannot change while the app runs.
    case modelSpec
    /// Label-only rows, or rows whose value already *is* an age. Showing a read
    /// time next to those would be noise or would contradict the value itself.
    /// Deliberately not named `none`: this type is often held in an Optional, and
    /// `field?.updateClass == .none` would then silently mean "is nil".
    case untimed
}

/// A read time plus where it came from. The gauge stamps its own publish moment
/// once a minute; our poll time is a different clock that answers a different
/// question ("when did we look" vs "when was this produced"), so the caption has
/// to know which one it is holding.
struct MetricReadStamp: Equatable {
    let at: Date
    let isGaugePublished: Bool
    /// When *we* last polled. The gauge publishing and us noticing are different
    /// moments, and the countdown has to target the second one — see
    /// `MetricFieldFreshness.secondsUntilVisibleRefresh`.
    var polledAt: Date? = nil
    /// The gauge's own observed publish period, learned from two consecutive
    /// `UpdateTime` values. nil until a second publish has been seen.
    var interval: TimeInterval? = nil

    static func gauge(_ date: Date, polledAt: Date? = nil,
                      interval: TimeInterval? = nil) -> MetricReadStamp {
        .init(at: date, isGaugePublished: true, polledAt: polledAt, interval: interval)
    }
    static func ourRead(_ date: Date) -> MetricReadStamp {
        .init(at: date, isGaugePublished: false, polledAt: date)
    }

    /// `polledAt` moves on every poll while `at` holds still for a full gauge
    /// cycle. Diffing on it would make every consumer of this stamp look changed
    /// six times per cycle, so equality stays on the two fields that carry meaning.
    static func == (lhs: MetricReadStamp, rhs: MetricReadStamp) -> Bool {
        lhs.at == rhs.at && lhs.isGaugePublished == rhs.isGaugePublished
    }
}

/// A state-dependent reason the number cannot mean what it usually means.
/// Separate from the cadence axis: the field is still read on every poll, it just
/// has nothing real to report right now.
enum MetricFieldAvailability: Equatable {
    /// The gauge returns its sentinel (65535 minutes) whenever the Mac is on AC,
    /// so the row shows "不可用" for a structural reason, not a stale read.
    case notProvidedOnAC
}

/// A lowest-level field that participates in a displayed metric.
struct MetricRawField: Identifiable, Equatable {
    let name: String
    let value: String
    var unit: String = ""
    var explanation: String = ""
    var updateClass: MetricFieldUpdateClass = .live
    /// Read time for this specific field. When nil, `MetricHelpContent.readAt`
    /// applies — most fields come from the same poll, only a few (such as the
    /// ten-minute median rows) are stamped from their own sample.
    var readAt: MetricReadStamp? = nil
    var availability: MetricFieldAvailability? = nil

    /// Deliberately excludes `readAt`: the freshness line is rendered from a
    /// ticking clock, and letting the age into the identity would rebuild every
    /// row once a second and drop text selection.
    var id: String { "\(name)|\(value)|\(unit)|\(explanation)" }

    /// Factory ratings appear in several cards, so they are recognised by name
    /// rather than annotated at every call site. Only applies when the call site
    /// left the default: an explicit classification always wins.
    /// PackReserve is included on measured evidence: it held 127 across two
    /// 5-minute `ioreg` runs (on AC and on battery, 300 samples) and is a design
    /// reserve rather than a learned value.
    private static let factoryRatingNames: Set<String> = [
        "designcapacity", "designcyclecount9c", "packreserve",
    ]

    var effectiveUpdateClass: MetricFieldUpdateClass {
        guard updateClass == .live else { return updateClass }
        return Self.factoryRatingNames.contains(name.lowercased()) ? .constant : .live
    }

    /// Every raw field must remain understandable in the currently selected
    /// language. Call sites can provide a more specific explanation, while the
    /// resolver guarantees that newly-added diagnostic fields never fall back
    /// to showing an implementation name on its own.
    var localizedExplanation: String {
        let explicit = explanation.trimmingCharacters(in: .whitespacesAndNewlines)
        return explicit.isEmpty ? MetricRawFieldExplanation.text(for: name) : explicit
    }
}

private enum MetricRawFieldExplanation {
    static func text(for rawName: String) -> String {
        let name = rawName.lowercased()

        // Named fields describe exactly what they are, including whether the
        // number is a direct system reading or a derived one. The keyword
        // heuristics further down only cover diagnostic fields that have no
        // dedicated copy yet, so they must never win over these.
        if name == "timeremaining" {
            return localized("p.raw_explain_time_remaining",
                             "电量计直接给出的剩余可用分钟数；插电或尚未学习完成时为不可用")
        }
        if name.contains("avgtimetoempty") {
            return localized("p.raw_explain_avg_time_to_empty",
                             "按平均电流推算的放空分钟数，是 TimeRemaining 无效时的备用来源")
        }
        if name.contains("modeldesignenergy") {
            return localized("p.raw_explain_model_design_energy",
                             "Apple 公布的本机型出厂设计电量，用于把 mAh 换算成 Wh")
        }
        if name.contains("recent10mmedianpower") {
            return localized("p.raw_explain_median_power",
                             "最近 10 分钟功耗样本的中位数，不是此刻的功率")
        }
        if name.contains("recent10mvalidsamples") {
            return localized("p.raw_explain_valid_samples",
                             "最近 10 分钟里参与中位数计算的有效样本数")
        }
        if name.contains("currentpowersampleage") {
            return localized("p.raw_explain_sample_age",
                             "此刻功率读数已经过去的秒数，超过 120 秒就不再用于估算")
        }
        if name.contains("applerawcurrentcapacity") {
            return localized("p.raw_explain_current_capacity_raw",
                             "电池此刻剩余电量的原始 mAh 读数，不是百分比")
        }
        if name.contains("applerawmaxcapacity") {
            return localized("p.raw_explain_max_capacity",
                             "电池现在实际能充到的满充容量")
        }
        if name == "designcapacity" {
            return localized("p.raw_explain_design_capacity",
                             "电池出厂时的设计容量，是容量与健康度对比的基准")
        }

        if name.contains("systemloadaccumulatorcount") || name.contains("recentsamples") {
            return localized("p.raw_explain_sample_count", "累计总量中包含的采样次数")
        }
        if name.contains("accumulatedsystemload") {
            return localized("p.raw_explain_accumulated_load", "用于计算长期平均功耗的累计用电总量")
        }
        if name.contains("adapter") || name.contains("charger") || name.contains("portcontroller")
            || name.contains("carriermode") || name.contains("voltagein") || name.contains("currentin")
            || name.contains("systempowerin") || name.contains("powerout") {
            return localized("p.raw_explain_adapter", "充电器输入、额定能力或协商状态读数")
        }
        if name.contains("systempower") || name == "systempower" {
            return localized("p.raw_explain_system_power", "系统报告的整台 Mac 当前使用功率")
        }
        if name.contains("systemload") || name.contains("power sample") || name.contains("medianpower") {
            return localized("p.raw_explain_system_load", "Mac 当前运行负载实际使用的功率")
        }
        if name.contains("derived") || name.hasPrefix("→") || name.contains("remainingenergy")
            || name.contains("truepermanentloss") || name.contains("min(qmax)") {
            return localized("p.raw_explain_derived", "由电池教练根据原始读数算出的中间值")
        }
        if name.contains("capacity") || name.contains("packreserve") || name.contains("fcc")
            || name.contains("qmax") || name.contains("soc") || name.contains("dod") {
            return localized("p.raw_explain_capacity", "这个指标使用的电量或容量读数")
        }
        if name.contains("voltage") {
            return localized("p.raw_explain_battery_voltage", "电池组当前的实时电压")
        }
        if name.contains("amperage") || name.contains("batterycurrent") {
            return localized("p.raw_explain_battery_current", "电池实时电流；正数充电，负数放电")
        }
        if name.contains("timeremaining") || name.contains("timetofull") || name.contains("timetoempty")
            || name.contains("time to") || name.contains("avgtime") {
            return localized("p.raw_explain_time", "macOS 为这个指标提供的时间估算")
        }
        if name.contains("temperature") {
            return localized("p.raw_explain_temperature", "电池或电量计报告的温度读数")
        }
        if name.contains("weightedra") || name.contains("resistance") {
            return localized("p.raw_explain_resistance", "用于判断供电阻力的电池内阻读数")
        }
        if name.contains("cell") || name.contains("chem") {
            return localized("p.raw_explain_cell", "用于比较各节电芯状态的底层读数")
        }
        if name.contains("cycle") {
            return localized("p.raw_explain_cycle", "记录电池累计使用程度或寿命的计数")
        }
        if name.contains("model") || name.contains("apple published") || name.contains("apple design")
            || name.contains("apple streaming") || name.contains("apple wireless")
            || name.contains("reference") {
            return localized("p.raw_explain_reference", "这台 Mac 对应的机型规格或参考值")
        }
        if name.contains("status") || name.contains("state") || name.contains("charging")
            || name.contains("installed") || name.contains("built-in") || name.contains("fault")
            || name.contains("failure") || name.contains("invalid") {
            return localized("p.raw_explain_state", "macOS 返回的状态或诊断标记")
        }

        return localized("p.raw_explain_generic", "用于解释上方指标的 macOS 底层读数")
    }

    private static func localized(_ key: String, _ fallback: String) -> String {
        dashboardText(key, fallback: fallback)
    }
}

/// Builds the one-line "read at / how often" caption under each raw field.
enum MetricFieldFreshness {
    /// How often AppleSmartBattery itself publishes new measurements. Measured,
    /// not assumed: across two 5-minute `ioreg` runs (300 samples, on AC and on
    /// battery) every changing field moved on a 58-60 s beat, and `UpdateTime`
    /// advanced by exactly 60 s each cycle. Our own poll is 6x faster than this,
    /// so quoting `BatteryService.liveRefreshInterval` here would overstate how
    /// fresh the numbers can be.
    static let gaugeRefreshSeconds = 60

    /// The countdown line on its own, for surfaces that show a live value outside
    /// the help drawer. Same wording and same clock as the drawer so the two can
    /// never quote different refresh times for the same reading.
    static func countdownText(_ read: MetricReadStamp, now: Date) -> String {
        let time = clockText(read.at)
        guard read.isGaugePublished else {
            return dashboardText("p.field_read_at",
                                 fallback: "{time} 读取（{age}前）· 电量计约 {interval} 秒刷新一次",
                                 replacements: ["time": time,
                                                "age": ageText(seconds: seconds(from: read.at, to: now)),
                                                "interval": "\(gaugeRefreshSeconds)"])
        }
        let remaining = secondsUntilVisibleRefresh(read, now: now)
        guard remaining > 0 else {
            return dashboardText("p.field_read_at_gauge_due",
                                 fallback: "预计随时刷新 · 上次 {time}",
                                 replacements: ["time": time])
        }
        return dashboardText("p.field_read_at_gauge",
                             fallback: "还有约 {countdown} 秒刷新 · 上次 {time}",
                             replacements: ["time": time, "countdown": "\(remaining)"])
    }

    /// Returns nil when the row must stay silent rather than imply a cadence it
    /// does not have.
    static func text(for field: MetricRawField, cardReadAt: MetricReadStamp?, now: Date) -> String? {
        switch field.effectiveUpdateClass {
        case .untimed:
            return nil
        case .modelSpec:
            return dashboardText("p.field_spec_static", fallback: "内置机型规格，不随时间变化")
        case .constant:
            return dashboardText("p.field_constant", fallback: "出厂固定值，不随使用变化")
        case .eventDriven, .live:
            guard let read = field.readAt ?? cardReadAt else { return nil }
            let stamp = [
                "time": clockText(read.at),
                "age": ageText(seconds: seconds(from: read.at, to: now)),
            ]
            if field.availability == .notProvidedOnAC {
                // The read is current; the value is missing by design. Naming the
                // reason beats letting "不可用" look like a stale or failed read,
                // and the gauge cadence is irrelevant when there is no value.
                return dashboardText("p.field_read_at_unavailable",
                                     fallback: "{time} 读取（{age}前）· 插电时系统不提供此值",
                                     replacements: stamp)
            }
            if field.effectiveUpdateClass == .eventDriven {
                return dashboardText("p.field_read_at_event",
                                     fallback: "{time} 读取（{age}前）· 插拔时立即变化",
                                     replacements: stamp)
            }
            let cadence = stamp.merging(["interval": "\(gaugeRefreshSeconds)"]) { a, _ in a }
            if read.isGaugePublished {
                // Knowing the gauge's own publish moment means the phase is known,
                // so the useful number is when the next value lands rather than how
                // old this one is. A countdown is only honest here: without
                // `UpdateTime` (branch below) we have no idea where the beat sits.
                let remaining = secondsUntilVisibleRefresh(read, now: now)
                guard remaining > 0 else {
                    // Past due: after a sleep or a beat reset the next publish can
                    // be any moment, so do not keep counting down into negatives.
                    return dashboardText("p.field_read_at_gauge_due",
                                         fallback: "预计随时刷新 · 上次 {time}",
                                         replacements: stamp)
                }
                return dashboardText("p.field_read_at_gauge",
                                     fallback: "还有约 {countdown} 秒刷新 · 上次 {time}",
                                     replacements: stamp.merging(["countdown": "\(remaining)"]) { a, _ in a })
            }
            // No UpdateTime from this Mac: all we can honestly stamp is our own
            // read, and the age then understates the number's true age.
            return dashboardText("p.field_read_at",
                                 fallback: "{time} 读取（{age}前）· 电量计约 {interval} 秒刷新一次",
                                 replacements: cadence)
        }
    }

    static func seconds(from readAt: Date, to now: Date) -> Int {
        max(0, Int(now.timeIntervalSince(readAt).rounded()))
    }

    /// Seconds until the number on screen actually changes — not until the gauge
    /// publishes.
    ///
    /// Those are two different moments and the gap was visible: the countdown ran
    /// to zero and the row sat on the old value for another ten seconds. The
    /// gauge publishes at `UpdateTime + 60`, but we only read the registry on our
    /// own timer, so the new value appears at the first poll at or after that
    /// instant. Projecting onto our poll grid makes zero mean zero.
    ///
    /// Without a poll timestamp (older call sites) this degrades to the publish
    /// time, which is the previous behaviour.
    static func secondsUntilVisibleRefresh(_ read: MetricReadStamp, now: Date) -> Int {
        // Observed period beats the constant: this Mac has published on a 56 s
        // beat as well as a 60 s one, and a plug event resets the phase entirely.
        // One real observation is enough to make the next prediction right.
        let period = read.interval ?? TimeInterval(gaugeRefreshSeconds)
        let nextPublish = read.at.addingTimeInterval(period)
        var nextVisible = nextPublish
        let poll = BatteryService.liveRefreshInterval
        if let polledAt = read.polledAt, poll > 0 {
            let untilPublish = nextPublish.timeIntervalSince(polledAt)
            if untilPublish > 0 {
                let ticks = (untilPublish / poll).rounded(.up)
                // Cap at one interval past the publish: after a sleep or a clock
                // jump the poll stamp can be far enough off to project absurdly.
                nextVisible = min(polledAt.addingTimeInterval(ticks * poll),
                                  nextPublish.addingTimeInterval(poll))
            }
        }
        return Int(nextVisible.timeIntervalSince(now).rounded(.up))
    }

    /// Coarser units past a minute: after a sleep or a stalled poll the raw
    /// second count becomes unreadable.
    static func ageText(seconds: Int) -> String {
        if seconds < 60 {
            return dashboardText("p.field_age_seconds", fallback: "{n} 秒",
                                 replacements: ["n": "\(seconds)"])
        }
        if seconds < 3600 {
            return dashboardText("p.field_age_minutes", fallback: "{n} 分钟",
                                 replacements: ["n": "\(seconds / 60)"])
        }
        return dashboardText("p.field_age_hours", fallback: "{n} 小时",
                             replacements: ["n": "\(seconds / 3600)"])
    }

    /// `HH:mm` in the user's locale. Separate from `clockText`, which keeps
    /// seconds because a read stamp is a precise instant; a trend readout is not.
    static func minuteText(_ date: Date) -> String {
        let code = L10n.shared.effectiveCode
        if cachedMinuteLanguageCode != code || cachedMinuteFormatter == nil {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: code)
            formatter.setLocalizedDateFormatFromTemplate("Hm")
            cachedMinuteFormatter = formatter
            cachedMinuteLanguageCode = code
        }
        return cachedMinuteFormatter?.string(from: date) ?? ""
    }

    private static var cachedMinuteFormatter: DateFormatter?
    private static var cachedMinuteLanguageCode: String?

    private static var cachedFormatter: DateFormatter?
    private static var cachedLanguageCode: String?

    /// Bare wall clock, no date: these reads are always from the current poll or
    /// the in-memory sample buffer. Cached because the ticking list would
    /// otherwise build a formatter per row per second.
    static func clockText(_ date: Date) -> String {
        let code = L10n.shared.effectiveCode
        if cachedLanguageCode != code || cachedFormatter == nil {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: code)
            formatter.dateStyle = .none
            formatter.timeStyle = .medium
            cachedFormatter = formatter
            cachedLanguageCode = code
        }
        return cachedFormatter?.string(from: date) ?? ""
    }
}
