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
}
