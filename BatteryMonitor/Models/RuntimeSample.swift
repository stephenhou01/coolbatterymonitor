import Foundation

/// macOS / 电量计直接给出的剩余时间历史点。
///
/// 只记录电池供电状态下的有效系统值；插电时的拔电预测不能混进这个序列。
struct RuntimeSample: Identifiable, Codable, Equatable, Sendable {
    let timestamp: Date
    let minutesRemaining: Int
    let percent: Int

    var id: Date { timestamp }

    static let validMinutes = 1...65_534
    static let minimumSamplingInterval: TimeInterval = 56
    static let recentUsageLookback: TimeInterval = 24 * 60 * 60
    static let maximumContinuousSampleGap: TimeInterval = 5 * 60

    static func isValid(minutes: Int) -> Bool {
        validMinutes.contains(minutes)
    }

    static func shouldAppend(
        _ candidate: RuntimeSample,
        after previous: RuntimeSample?,
        minimumInterval: TimeInterval = minimumSamplingInterval
    ) -> Bool {
        guard isValid(minutes: candidate.minutesRemaining) else { return false }
        guard let previous else { return true }
        return candidate.timestamp.timeIntervalSince(previous.timestamp) >= minimumInterval
    }

    /// Sums only intervals that were actually observed while on battery. Long
    /// gaps (app closed, Mac asleep, or connected to power) are deliberately
    /// excluded so elapsed wall-clock time is never presented as actual usage.
    static func observedUsageDuration(
        in samples: [RuntimeSample],
        now: Date = Date(),
        lookback: TimeInterval = recentUsageLookback,
        maximumGap: TimeInterval = maximumContinuousSampleGap
    ) -> TimeInterval {
        guard lookback > 0, maximumGap > 0 else { return 0 }
        let start = now.addingTimeInterval(-lookback)
        let recent = samples
            .filter { $0.timestamp >= start && $0.timestamp <= now }
            .sorted { $0.timestamp < $1.timestamp }
        guard recent.count > 1 else { return 0 }

        return zip(recent, recent.dropFirst()).reduce(0) { total, pair in
            let interval = pair.1.timestamp.timeIntervalSince(pair.0.timestamp)
            guard interval > 0, interval <= maximumGap else { return total }
            return total + interval
        }
    }
}
