import Foundation

/// Permanent, local-only telemetry is stored as one three-minute aggregate per
/// bucket. Daily files stay small (at most 480 rows) and are never pruned; only
/// the trailing 24 hours are loaded into memory for today's charts.
enum TelemetryHistoryArchive {
    static let bucketDuration: TimeInterval = 3 * 60

    static func bucketStart(for date: Date) -> Date {
        Date(timeIntervalSince1970:
            floor(date.timeIntervalSince1970 / bucketDuration) * bucketDuration)
    }

    static func appending(
        _ sample: RealtimeDataPoint,
        to archive: [RealtimeDataPoint]
    ) -> [RealtimeDataPoint] {
        let bucket = bucketStart(for: sample.timestamp)
        var result = archive
        if let last = result.last, last.timestamp == bucket {
            result[result.count - 1] = merged(last, with: sample, timestamp: bucket)
        } else {
            result.append(RealtimeDataPoint(
                timestamp: bucket,
                voltage: sample.voltage,
                amperage: sample.amperage,
                power: sample.power,
                temperature: sample.temperature,
                percent: sample.percent,
                inputPower: sample.inputPower,
                adapterVoltage: sample.adapterVoltage,
                adapterCurrent: sample.adapterCurrent,
                isOnAC: sample.isOnAC,
                rawCurrentCapacity: sample.rawCurrentCapacity,
                adapterRatedPower: sample.adapterRatedPower,
                adapterOutputPower: sample.adapterOutputPower,
                chargingPower: sample.chargingPower,
                cycleCount: sample.cycleCount,
                healthPercent: sample.healthPercent,
                sampleCount: sample.sampleCount
            ))
        }
        return result
    }

    static func retainedForCharts(
        _ points: [RealtimeDataPoint],
        now: Date
    ) -> [RealtimeDataPoint] {
        let start = now.addingTimeInterval(-24 * 60 * 60 - bucketDuration)
        return points
            .filter { $0.timestamp >= start && $0.timestamp <= now.addingTimeInterval(bucketDuration) }
            .sorted { $0.timestamp < $1.timestamp }
    }

    static func mergedHistory(
        archive: [RealtimeDataPoint],
        raw: [RealtimeDataPoint]
    ) -> [RealtimeDataPoint] {
        let sortedRaw = raw.sorted { $0.timestamp < $1.timestamp }
        guard let firstRaw = sortedRaw.first?.timestamp else {
            return archive.sorted { $0.timestamp < $1.timestamp }
        }
        return archive.filter { $0.timestamp < firstRaw } + sortedRaw
    }

    private static func merged(
        _ aggregate: RealtimeDataPoint,
        with sample: RealtimeDataPoint,
        timestamp: Date
    ) -> RealtimeDataPoint {
        let oldCount = max(1, aggregate.sampleCount)
        let newCount = max(1, sample.sampleCount)
        let total = oldCount + newCount

        func mean(_ old: Double, _ new: Double) -> Double {
            (old * Double(oldCount) + new * Double(newCount)) / Double(total)
        }
        func optionalMean(_ old: Double?, _ new: Double?) -> Double? {
            switch (old, new) {
            case let (.some(lhs), .some(rhs)): return mean(lhs, rhs)
            case let (.some(lhs), .none): return lhs
            case let (.none, .some(rhs)): return rhs
            case (.none, .none): return nil
            }
        }
        func optionalIntegerMean(_ old: Int?, _ new: Int?) -> Int? {
            optionalMean(old.map(Double.init), new.map(Double.init)).map { Int($0.rounded()) }
        }

        return RealtimeDataPoint(
            timestamp: timestamp,
            voltage: mean(aggregate.voltage, sample.voltage),
            amperage: mean(aggregate.amperage, sample.amperage),
            power: mean(aggregate.power, sample.power),
            temperature: mean(aggregate.temperature, sample.temperature),
            percent: Int(mean(Double(aggregate.percent), Double(sample.percent)).rounded()),
            inputPower: optionalMean(aggregate.inputPower, sample.inputPower),
            adapterVoltage: optionalMean(aggregate.adapterVoltage, sample.adapterVoltage),
            adapterCurrent: optionalMean(aggregate.adapterCurrent, sample.adapterCurrent),
            isOnAC: sample.isOnAC,
            rawCurrentCapacity: optionalIntegerMean(aggregate.rawCurrentCapacity, sample.rawCurrentCapacity),
            adapterRatedPower: optionalMean(aggregate.adapterRatedPower, sample.adapterRatedPower),
            adapterOutputPower: optionalMean(aggregate.adapterOutputPower, sample.adapterOutputPower),
            chargingPower: optionalMean(aggregate.chargingPower, sample.chargingPower),
            cycleCount: optionalIntegerMean(aggregate.cycleCount, sample.cycleCount),
            healthPercent: optionalMean(aggregate.healthPercent, sample.healthPercent),
            sampleCount: total
        )
    }
}
