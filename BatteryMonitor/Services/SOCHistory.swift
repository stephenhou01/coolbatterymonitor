import Foundation

// MARK: - 自记录的每日用电快照
//
// IOKit 的 DailyMaxSoc / DailyMinSoc 只有当天单点，没有历史；而充电习惯评分、
// 周报、以及「剩余寿命换算成年份」都需要跨天数据。所以 app 自己攒。
//
// 关键用途：observedCyclesPerDay 是**实测**的用户循环速率（用首末记录的
// CycleCount 差除以跨越天数），有了它才能把「剩余 N 次循环」诚实地换算成年份，
// 而不是套一个行业均值假装是事实。

struct DailyRecord: Codable, Equatable {
    let date: String              // yyyy-MM-dd
    var minSoc: Int
    var maxSoc: Int
    var maxChargingTemp: Double   // 充电期间观测到的最高温
    var fullHoldSamples: Int      // 约 56 秒一个「满充且仍插电」有效样本
    var cycleCount: Int           // 当天末次观测到的循环数
    /// 仅用于把 10 秒 UI 轮询节流到电量计约 56 秒的真实采样节奏。
    /// Optional + 默认值保证旧版 JSON 没有这个字段时仍能直接解码。
    var lastFullHoldSampleAt: Date? = nil
}

struct SOCHistory: Codable, Equatable {
    var records: [DailyRecord] = []

    /// 只保留最近这么多天
    static let retentionDays = 90
    /// 与 RuntimeSample 的真实电量计节奏一致，避免 10 秒 UI 轮询重复计算同一状态。
    static let fullHoldSampleInterval: TimeInterval = 56
    /// 32 × 56 秒 ≈ 30 分钟；习惯评分按每 30 分钟满充停留计一次事件。
    static let fullHoldSamplesPerEvent = 32

    // MARK: - 派生指标

    var observedDays: Int { records.count }

    var averageMaxSoc: Int? {
        guard !records.isEmpty else { return nil }
        return Int((Double(records.map(\.maxSoc).reduce(0, +)) / Double(records.count)).rounded())
    }

    var averageMinSoc: Int? {
        guard !records.isEmpty else { return nil }
        return Int((Double(records.map(\.minSoc).reduce(0, +)) / Double(records.count)).rounded())
    }

    var maxChargingTemp: Double? {
        let t = records.map(\.maxChargingTemp).max() ?? 0
        return t > 0 ? t : nil
    }

    /// 满充存放次数
    var fullChargeHoldEvents: Int {
        records.map { $0.fullHoldSamples / Self.fullHoldSamplesPerEvent }.reduce(0, +)
    }

    /// **实测**每日循环数。需要至少两天且循环数确实增长过。
    var observedCyclesPerDay: Double? {
        let sorted = records.sorted { $0.date < $1.date }
        guard let first = sorted.first, let last = sorted.last,
              first.date != last.date,
              let d0 = Self.formatter.date(from: first.date),
              let d1 = Self.formatter.date(from: last.date) else { return nil }
        let days = d1.timeIntervalSince(d0) / 86400
        let delta = last.cycleCount - first.cycleCount
        guard days >= 1, delta > 0 else { return nil }
        return Double(delta) / days
    }

    // MARK: - 记录

    static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    func date(from string: String) -> Date? { Self.formatter.date(from: string) }

    /// 每次 UI 轮询调用。同一天的记录原地更新，不新增。
    mutating func record(percent: Int, cycleCount: Int, temperature: Double,
                         isCharging: Bool, isFullyCharged: Bool, isOnAC: Bool,
                         now: Date = Date()) {
        let today = Self.formatter.string(from: now)
        var r = records.first { $0.date == today }
            ?? DailyRecord(date: today, minSoc: percent, maxSoc: percent,
                           maxChargingTemp: 0, fullHoldSamples: 0, cycleCount: cycleCount)
        r.minSoc = min(r.minSoc, percent)
        r.maxSoc = max(r.maxSoc, percent)
        r.cycleCount = max(r.cycleCount, cycleCount)
        if isCharging { r.maxChargingTemp = max(r.maxChargingTemp, temperature) }

        if isFullyCharged && isOnAC {
            let shouldCount: Bool
            if let previous = r.lastFullHoldSampleAt {
                let elapsed = now.timeIntervalSince(previous)
                // 时钟回拨时也允许重新建立基准；否则负间隔会让计数永久卡住。
                shouldCount = elapsed < 0 || elapsed >= Self.fullHoldSampleInterval
            } else {
                shouldCount = true
            }
            if shouldCount {
                r.fullHoldSamples += 1
                r.lastFullHoldSampleAt = now
            }
        }

        records.removeAll { $0.date == today }
        records.append(r)

        // 裁剪过期记录
        if let cutoff = Calendar.current.date(byAdding: .day, value: -Self.retentionDays, to: now) {
            let cutoffStr = Self.formatter.string(from: cutoff)
            records.removeAll { $0.date < cutoffStr }
        }
        records.sort { $0.date < $1.date }
    }
}
