import SwiftUI
import Charts

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

enum MetricHelpResultStyle: Equatable {
    case primary
    case stable
    case current

    var tint: Color {
        switch self {
        case .primary: return AppTheme.chargingCyan
        case .stable: return AppTheme.accentPurple
        case .current: return AppTheme.batteryYellow
        }
    }
}

/// A comparison value shown alongside the primary result. Runtime uses this to
/// keep the macOS value visually dominant while exposing two clearly-derived
/// estimates in the same question-mark drawer.
struct MetricHelpResult: Identifiable, Equatable {
    let id: String
    let title: String
    let value: String
    let note: String
    let style: MetricHelpResultStyle
}

struct MetricHelpTrendPoint: Identifiable, Equatable {
    let timestamp: Date
    let value: Double

    var id: Date { timestamp }
}

/// A trend chart carried by a help panel. Kept as data rather than a view so
/// every metric can offer one without the drawer knowing which metric it is.
struct MetricHelpTrend: Equatable {
    let title: String
    /// The headline figure shown beside the title — normally the latest sample.
    let latestText: String
    let note: String
    /// Suffix for the hover readout and the y-axis labels, e.g. `W` or `℃`.
    let unit: String
    let tint: Color
    let points: [MetricHelpTrendPoint]
    /// Dashed reference line, e.g. an adapter's negotiated ceiling.
    var ceiling: Double? = nil
    /// Power starts the y axis at zero, because "half the wattage" should look
    /// like half. Temperature does not: a 0℃ floor would flatten every real
    /// swing a battery actually makes.
    var baselineAtZero: Bool = true
    /// Shown instead of the chart when there are not yet two samples.
    var waitingText: String = dashboardText("p.adapter_trend_waiting", fallback: "正在积累历史数据")

    var isPlottable: Bool { points.count >= 2 }
}

/// Consumer-facing explanation of an adapter's negotiated PD contract. The
/// rated contract and the Mac's live input are deliberately kept separate:
/// 20V × 3.25A describes what the adapter can provide, not what the Mac is
/// necessarily drawing at this instant.
struct MetricPowerContract: Equatable {
    let stateTitle: String
    let stateDetail: String
    let isConnected: Bool
    let isNegotiated: Bool
    let voltageLabel: String
    let voltageText: String
    let currentLabel: String
    let currentText: String
    let powerLabel: String
    let powerText: String
    let equationText: String
    let equationNote: String
    let trendTitle: String
    let trendValue: String
    let trendNote: String
    let trendPoints: [MetricHelpTrendPoint]
    let ceilingWatts: Double?
}

/// Content shared by every question-mark affordance on the final dashboard.
/// Keeping the explanation as data lets the same drawer serve top-level answers,
/// formulas, reference rows, and the hardware table.
struct MetricHelpContent: Identifiable, Equatable {
    let id: String
    let title: String
    let summary: String
    let result: String
    let rawFields: [MetricRawField]
    let formula: String
    let substitution: String
    let source: String
    /// The read time shared by every `.live` field in this card. One IOKit
    /// property snapshot backs the whole card, so one read time is honest.
    var readAt: MetricReadStamp? = nil
    var comparisonResults: [MetricHelpResult] = []
    var powerContract: MetricPowerContract? = nil
    /// Optional history for metrics that actually move within the ten-minute
    /// buffer. Cycle count and health are deliberately left without one: over
    /// ten minutes they are a flat line, and drawing one would imply the app
    /// has resolution it does not.
    var trend: MetricHelpTrend? = nil
}

/// Carries the poll timestamp down to every help button so an open drawer can
/// refresh without any card having to build its help content speculatively.
/// Defaults to `.distantPast`, so a button outside the dashboard simply never
/// auto-refreshes instead of crashing.
private struct DashboardDataVersionKey: EnvironmentKey {
    static let defaultValue = Date.distantPast
}

extension EnvironmentValues {
    var dashboardDataVersion: Date {
        get { self[DashboardDataVersionKey.self] }
        set { self[DashboardDataVersionKey.self] = newValue }
    }
}

struct MetricHelpButton: View {
    /// An autoclosure, which is the whole point: a heavy page holds ~50 of these
    /// buttons, and building every card's formula, substitution and raw-field
    /// list on every redraw — for panels nobody has opened — was the largest
    /// single cost of a page. Taking it unevaluated keeps every call site
    /// unchanged while deferring the work to the tap.
    let content: () -> MetricHelpContent
    @Binding var selection: MetricHelpContent?

    @Environment(\.dashboardDataVersion) private var dataVersion
    /// Set only while this button's own panel is the one on screen, so exactly
    /// one content object gets rebuilt per poll instead of fifty.
    @State private var presentedID: String?

    init(content: @autoclosure @escaping () -> MetricHelpContent,
         selection: Binding<MetricHelpContent?>) {
        self.content = content
        self._selection = selection
    }

    var body: some View {
        Button {
            let built = content()
            presentedID = built.id
            selection = built
        } label: {
            Text("?")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.textSecondary)
                .frame(width: 20, height: 20)
                .background(Circle().fill(AppTheme.contrastOverlay(0.055)))
                .overlay(Circle().stroke(AppTheme.contrastOverlay(0.10), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .pointerOnHover()
        .accessibilityLabel(dashboardText("p.help_open", fallback: "查看定义和计算方法"))
        .help(dashboardText("p.help_open", fallback: "查看定义和计算方法"))
        // The drawer holds a value copy, so it would otherwise freeze at the
        // moment of the tap. Rebuild on each poll, but only for the panel that is
        // actually open — `content()` here is the closure from the current body
        // pass, so it reads current data.
        .onChange(of: dataVersion) { _, _ in
            guard let presentedID, selection?.id == presentedID else { return }
            selection = content()
        }
        // Another button took over, or the drawer was dismissed: stop refreshing.
        .onChange(of: selection?.id) { _, newID in
            if newID != presentedID { presentedID = nil }
        }
    }
}

/// One chart shape for every help panel, so hovering behaves identically
/// wherever a trend appears. Selection state lives here rather than in the
/// drawer: each chart tracks its own pointer, and nothing has to be reset when
/// the drawer swaps to another metric.
struct MetricTrendChart: View {
    let trend: MetricHelpTrend
    var height: CGFloat = 132

    /// Where the pointer is on the x axis, driven by Charts' own
    /// `chartXSelection`. nil whenever the pointer is outside the plot.
    @State private var selectedDate: Date?

    var body: some View {
        Chart {
            ForEach(trend.points) { point in
                AreaMark(
                    x: .value("Time", point.timestamp),
                    yStart: .value("Baseline", domain.lowerBound),
                    yEnd: .value("Value", point.value)
                )
                .foregroundStyle(trend.tint.opacity(0.08))

                LineMark(
                    x: .value("Time", point.timestamp),
                    y: .value("Value", point.value)
                )
                .foregroundStyle(trend.tint)
                .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            }

            if let ceiling = trend.ceiling, ceiling > 0 {
                RuleMark(y: .value("Ceiling", ceiling))
                    .foregroundStyle(AppTheme.batteryYellow.opacity(0.7))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
            }

            if let hovered = MetricHelpDrawer.nearestTrendPoint(trend.points, to: selectedDate) {
                RuleMark(x: .value("Hovered", hovered.timestamp))
                    .foregroundStyle(trend.tint.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .annotation(position: .top, alignment: .leading, spacing: 2, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        Text(MetricHelpDrawer.trendHoverText(hovered, unit: trend.unit))
                            .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                            .foregroundStyle(AppTheme.textPrimary)
                            .monospacedDigit()
                            .fixedSize()
                            .padding(.horizontal, 7)
                            .padding(.vertical, 4)
                            .background(RoundedRectangle(cornerRadius: 7)
                                .fill(AppTheme.surfaceRaised.opacity(0.96)))
                            .overlay(RoundedRectangle(cornerRadius: 7)
                                .stroke(AppTheme.cardBorder))
                    }
                PointMark(x: .value("Hovered", hovered.timestamp),
                          y: .value("Value", hovered.value))
                    .foregroundStyle(trend.tint)
                    .symbolSize(46)
            }
        }
        // Charts' own pointer tracking. The hand-rolled chartOverlay +
        // onContinuousHover this replaces never fired; the two charts elsewhere
        // in the app that do work use this API, and copying the proven one was
        // the right move from the start.
        .chartXSelection(value: $selectedDate)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 3)) { _ in
                AxisGridLine().foregroundStyle(AppTheme.contrastOverlay(0.04))
                AxisValueLabel(format: .dateTime.hour().minute())
                    .foregroundStyle(AppTheme.textTertiary)
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                AxisGridLine().foregroundStyle(AppTheme.contrastOverlay(0.05))
                AxisValueLabel {
                    if let number = value.as(Double.self) {
                        Text("\(Int(number.rounded()))\(trend.unit)")
                    }
                }
                .foregroundStyle(AppTheme.textTertiary)
            }
        }
        .chartYScale(domain: domain)
        .frame(height: height)
    }

    /// Power reads from zero so "half the wattage" looks like half. Temperature
    /// gets a padded window around its own range instead, because a 0℃ floor
    /// would render every real swing as a flat line.
    private var domain: ClosedRange<Double> {
        let values = trend.points.map(\.value)
        let peak = max(values.max() ?? 0, trend.ceiling ?? 0)
        guard !trend.baselineAtZero else {
            return 0...(max(peak, 1) * 1.08)
        }
        let low = values.min() ?? 0
        let pad = max((peak - low) * 0.18, 0.5)
        return (low - pad)...(peak + pad)
    }
}

/// Window-level trailing drawer. ContentView owns the selection so the panel is
/// not clipped by the dashboard's ScrollView.
struct MetricHelpDrawer: View {
    let content: MetricHelpContent
    let onClose: () -> Void
    @FocusState private var closeFocused: Bool
    var body: some View {
        HStack(spacing: 0) {
            Button(action: onClose) {
                Color.black.opacity(0.58)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHidden(true)

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    drawerHeader

                    VStack(alignment: .leading, spacing: 7) {
                        Text(content.title)
                            .font(.system(size: 23, weight: .bold, design: .rounded))
                            .foregroundStyle(AppTheme.textPrimary)
                        Text(content.summary)
                            .font(.system(size: 12.5))
                            .foregroundStyle(AppTheme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .lineSpacing(4)
                    }

                    resultBlock
                    adapterTrendBlock
                    trendBlock
                    rawFieldsBlock
                    formulaBlock
                    sourceBlock
                }
                .padding(.horizontal, 26)
                .padding(.vertical, 24)
            }
            .frame(width: 470)
            .background(
                LinearGradient(
                    colors: [AppTheme.surfaceRaised, AppTheme.cardBackground],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(AppTheme.chargingCyan.opacity(0.22))
                    .frame(width: 1)
            }
            .shadow(color: .black.opacity(0.55), radius: 30, x: -12)
        }
        .ignoresSafeArea()
        .transition(.opacity.combined(with: .move(edge: .trailing)))
        .onAppear { closeFocused = true }
        .onExitCommand(perform: onClose)
        .accessibilityElement(children: .contain)
    }

    private var drawerHeader: some View {
        HStack {
            Text(dashboardText("p.help_title", fallback: "这个指标从哪里来？"))
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .tracking(1.1)
                .foregroundStyle(AppTheme.chargingCyan)
            Spacer()
            Button(action: onClose) {
                Label(dashboardText("p.help_close", fallback: "关闭"), systemImage: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AppTheme.textSecondary)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 7).fill(AppTheme.contrastOverlay(0.05)))
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
            .focused($closeFocused)
            .pointerOnHover()
        }
        .padding(.bottom, 14)
        .overlay(alignment: .bottom) {
            Rectangle().fill(AppTheme.contrastOverlay(0.07)).frame(height: 1)
        }
    }

    private var resultBlock: some View {
        VStack(alignment: .leading, spacing: 9) {
            drawerEyebrow(dashboardText("p.help_current", fallback: "当前结果"))

            if let contract = content.powerContract {
                adapterContractBlock(contract)
            } else if content.comparisonResults.isEmpty {
                Text(content.result)
                    .font(.system(size: 27, weight: .medium, design: .monospaced))
                    .foregroundStyle(AppTheme.chargingCyan)
                    .minimumScaleFactor(0.75)
                    .lineLimit(2)
            } else {
                if let primary = content.comparisonResults.first {
                    comparisonResultCard(primary, primary: true)
                }
                HStack(alignment: .top, spacing: 9) {
                    ForEach(content.comparisonResults.dropFirst()) { item in
                        comparisonResultCard(item, primary: false)
                    }
                }
            }
        }
    }

    private func adapterContractBlock(_ contract: MetricPowerContract) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 11) {
                Image(systemName: contract.isConnected ? "powerplug.fill" : "powerplug")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(contract.isConnected ? AppTheme.chargingCyan : AppTheme.textTertiary)
                    .frame(width: 40, height: 40)
                    .background(
                        RoundedRectangle(cornerRadius: 11)
                            .fill((contract.isConnected ? AppTheme.chargingCyan : AppTheme.textTertiary).opacity(0.08))
                    )
                VStack(alignment: .leading, spacing: 3) {
                    Text(contract.stateTitle)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(AppTheme.textPrimary)
                    Text(contract.stateDetail)
                        .font(.system(size: 9.5))
                        .foregroundStyle(AppTheme.textTertiary)
                        .lineLimit(2)
                }
                Spacer(minLength: 8)
                Text(contract.isNegotiated
                     ? dashboardText("p.adapter_status_ready_badge", fallback: "PD READY")
                     : dashboardText("p.adapter_status_waiting_badge", fallback: "WAITING"))
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .tracking(0.8)
                    .foregroundStyle(contract.isNegotiated ? AppTheme.batteryGreen : AppTheme.textTertiary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Capsule().fill((contract.isNegotiated ? AppTheme.batteryGreen : AppTheme.textTertiary).opacity(0.08)))
            }

            HStack(spacing: 7) {
                contractMetric(icon: "bolt.circle.fill", label: contract.voltageLabel,
                               value: contract.voltageText, tint: AppTheme.chargingBlue)
                equationOperator("×")
                contractMetric(icon: "waveform.path.ecg", label: contract.currentLabel,
                               value: contract.currentText, tint: AppTheme.batteryGreen)
                equationOperator("=")
                contractMetric(icon: "bolt.fill", label: contract.powerLabel,
                               value: contract.powerText, tint: AppTheme.batteryYellow)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(contract.equationText)
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(AppTheme.textPrimary)
                    .textSelection(.enabled)
                Text(contract.equationNote)
                    .font(.system(size: 9.5))
                    .foregroundStyle(AppTheme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(2)
            }
            .padding(11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 9).fill(AppTheme.chargingCyan.opacity(0.045)))
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(AppTheme.chargingCyan.opacity(0.13), lineWidth: 1))
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12).fill(AppTheme.contrastOverlay(0.025)))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(AppTheme.contrastOverlay(0.08), lineWidth: 1))
    }

    private func contractMetric(icon: String, label: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tint)
            Text(label)
                .font(.system(size: 8.5, weight: .medium))
                .foregroundStyle(AppTheme.textTertiary)
                .lineLimit(1)
            Text(value)
                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                .foregroundStyle(AppTheme.textPrimary)
                .minimumScaleFactor(0.72)
                .lineLimit(1)
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 78, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 9).fill(tint.opacity(0.045)))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(tint.opacity(0.13), lineWidth: 1))
    }

    private func equationOperator(_ value: String) -> some View {
        Text(value)
            .font(.system(size: 13, weight: .bold, design: .rounded))
            .foregroundStyle(AppTheme.textTertiary)
            .frame(width: 10)
    }

    /// The adapter panel keeps its own trend so the negotiated-ceiling rule line
    /// stays attached to the contract it belongs to; everything else goes
    /// through `content.trend`. Both render the same chart.
    @ViewBuilder
    private var adapterTrendBlock: some View {
        if let contract = content.powerContract {
            trendCard(MetricHelpTrend(
                title: contract.trendTitle,
                latestText: contract.trendValue,
                note: contract.trendNote,
                unit: "W",
                tint: AppTheme.chargingCyan,
                points: contract.trendPoints,
                ceiling: contract.ceilingWatts,
                waitingText: dashboardText("p.adapter_trend_waiting", fallback: "正在积累输入功率历史")
            ))
        }
    }

    @ViewBuilder
    private var trendBlock: some View {
        if let trend = content.trend {
            trendCard(trend)
        }
    }

    private func trendCard(_ trend: MetricHelpTrend) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline) {
                drawerEyebrow(trend.title)
                Spacer()
                Text(trend.latestText)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(trend.tint)
            }

            if trend.isPlottable {
                MetricTrendChart(trend: trend)
            } else {
                HStack(spacing: 9) {
                    Image(systemName: "chart.xyaxis.line")
                        .foregroundStyle(AppTheme.textTertiary)
                    Text(trend.waitingText)
                        .font(.system(size: 10.5))
                        .foregroundStyle(AppTheme.textTertiary)
                }
                .frame(maxWidth: .infinity, minHeight: 72, alignment: .center)
            }

            Text(trend.note)
                .font(.system(size: 9.5))
                .foregroundStyle(AppTheme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(2)
        }
        .padding(13)
        .background(RoundedRectangle(cornerRadius: 11).fill(AppTheme.contrastOverlay(0.02)))
        .overlay(RoundedRectangle(cornerRadius: 11).stroke(AppTheme.contrastOverlay(0.07), lineWidth: 1))
    }

    /// Snaps the pointer's x position to a recorded sample. Snapping rather than
    /// interpolating keeps the readout honest: every figure it shows was
    /// measured, not drawn between two measurements.
    ///
    /// nil in, nil out — no selection means no readout, rather than defaulting to
    /// the latest point and looking like a permanent marker.
    static func nearestTrendPoint(_ points: [MetricHelpTrendPoint], to date: Date?) -> MetricHelpTrendPoint? {
        guard let date else { return nil }
        return points.min { lhs, rhs in
            abs(lhs.timestamp.timeIntervalSince(date)) < abs(rhs.timestamp.timeIntervalSince(date))
        }
    }

    /// Minute granularity, as asked: these are 10-second samples of values that
    /// mostly republish once a minute, so seconds would imply a precision the
    /// series does not have.
    static func trendHoverText(_ point: MetricHelpTrendPoint, unit: String = "W") -> String {
        "\(MetricFieldFreshness.minuteText(point.timestamp)) · \(LNum("%.1f", point.value)) \(unit)"
    }

    private func comparisonResultCard(_ item: MetricHelpResult, primary: Bool) -> some View {
        let tint = item.style.tint
        return VStack(alignment: .leading, spacing: primary ? 7 : 5) {
            Text(item.title)
                .font(.system(size: primary ? 10.5 : 9.5, weight: .semibold))
                .foregroundStyle(primary ? tint : AppTheme.textSecondary)
                .lineLimit(1)
            Text(item.value)
                .font(.system(size: primary ? 27 : 18, weight: .medium, design: .monospaced))
                .foregroundStyle(tint)
                .minimumScaleFactor(0.72)
                .lineLimit(1)
            Text(item.note)
                .font(.system(size: primary ? 10 : 9))
                .foregroundStyle(AppTheme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(2)
        }
        .padding(primary ? 14 : 11)
        .frame(maxWidth: .infinity, minHeight: primary ? 94 : 106, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 11).fill(tint.opacity(0.045)))
        .overlay(RoundedRectangle(cornerRadius: 11).stroke(tint.opacity(0.16), lineWidth: 1))
    }

    @ViewBuilder
    private var rawFieldsBlock: some View {
        if !content.rawFields.isEmpty {
            VStack(alignment: .leading, spacing: 9) {
                drawerEyebrow(dashboardText("p.help_raw", fallback: "字段说明与原始值"))
                // One ticking clock for the whole list so the "N s ago" part
                // keeps counting between the ten-second polls. It only drives
                // the freshness lines, and stops when the drawer closes.
                TimelineView(.periodic(from: Date(), by: 1)) { timeline in
                    VStack(alignment: .leading, spacing: 9) {
                        ForEach(content.rawFields) { field in
                            rawFieldRow(field, now: timeline.date)
                        }
                    }
                }
            }
        }
    }

    private func rawFieldRow(_ field: MetricRawField, now: Date) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(field.localizedExplanation)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AppTheme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(field.name)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(AppTheme.textTertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.68)
                    .allowsTightening(true)
                    .textSelection(.enabled)
                if let freshness = MetricFieldFreshness.text(for: field, cardReadAt: content.readAt, now: now) {
                    Text(freshness)
                        .font(.system(size: 9))
                        .foregroundStyle(AppTheme.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text([field.value, field.unit].filter { !$0.isEmpty }.joined(separator: " "))
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(AppTheme.chargingCyan)
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
                .minimumScaleFactor(0.72)
                .textSelection(.enabled)
                .frame(maxWidth: 145, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 8).fill(AppTheme.contrastOverlay(0.025)))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(AppTheme.contrastOverlay(0.065), lineWidth: 1))
    }

    private var formulaBlock: some View {
        VStack(alignment: .leading, spacing: 9) {
            drawerEyebrow(dashboardText("p.help_formula", fallback: "公式"))
            formulaText(content.formula, tint: AppTheme.accentPurple)
            drawerEyebrow(dashboardText("p.help_substitution", fallback: "代入这台电脑的数值"))
                .padding(.top, 3)
            formulaText(content.substitution, tint: AppTheme.chargingCyan)
        }
    }

    private var sourceBlock: some View {
        VStack(alignment: .leading, spacing: 9) {
            drawerEyebrow(dashboardText("p.help_source", fallback: "来源与可靠性"))
            Text(content.source)
                .font(.system(size: 11.5))
                .foregroundStyle(AppTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(3)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 9).fill(AppTheme.batteryYellow.opacity(0.04)))
                .overlay(RoundedRectangle(cornerRadius: 9).stroke(AppTheme.batteryYellow.opacity(0.14), lineWidth: 1))
        }
    }

    private func drawerEyebrow(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 9, weight: .medium, design: .monospaced))
            .tracking(1)
            .foregroundStyle(AppTheme.textTertiary)
    }

    private func formulaText(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(AppTheme.textPrimary)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
            .lineSpacing(4)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 8).fill(tint.opacity(0.055)))
            .overlay(alignment: .leading) { Rectangle().fill(tint).frame(width: 2) }
    }
}

/// The prototype adds many new keys while the native language packs are being
/// migrated in parallel. Falling back here keeps the UI readable during that
/// migration and automatically yields to the selected language once a key lands.
func dashboardText(
    _ key: String,
    fallback: String,
    replacements: [String: String] = [:]
) -> String {
    let localized = L(key)
    let source = localized == key ? fallback : localized
    return dashboardNativeText(source, replacements: replacements)
}

/// Prototype copy occasionally contains small HTML fragments and named
/// placeholders. Native SwiftUI text must never expose those implementation
/// details, so normalize them at the localization boundary.
private func dashboardNativeText(_ source: String, replacements: [String: String]) -> String {
    var result = source
    // A dashboard redraw makes hundreds of these calls, and almost none of the
    // shipped copy contains markup — the seven scans below (six of them
    // case-insensitive, so ICU case folding) were pure waste on every one of
    // them. One cheap probe for the only two characters that can start a
    // fragment cuts the string cost of a full page redraw roughly in half.
    if source.contains("<") || source.contains("&") {
        result = result
            .replacingOccurrences(of: "<br>", with: "\n", options: .caseInsensitive)
            .replacingOccurrences(of: "<br/>", with: "\n", options: .caseInsensitive)
            .replacingOccurrences(of: "<br />", with: "\n", options: .caseInsensitive)
            .replacingOccurrences(of: "<strong>", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "</strong>", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "&nbsp;", with: " ", options: .caseInsensitive)
            .replacingOccurrences(of: "&amp;", with: "&", options: .caseInsensitive)
    }

    guard !replacements.isEmpty else { return result }
    for (name, value) in replacements {
        result = result.replacingOccurrences(of: "{\(name)}", with: value)
    }
    return result
}
