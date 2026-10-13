import Foundation

/// Experimental relative SDNN trends. These engineering thresholds are not clinical cutoffs.
public enum StressEstimator {
    private static let baselineWindow: TimeInterval = 28 * 86_400
    private static let freshnessWindow: TimeInterval = 20 * 60
    private static let recoveryWindow: TimeInterval = 30 * 60
    private static let adjacentWindow: TimeInterval = 5 * 60

    public static func assess(_ snapshot: HealthSnapshot, now: Date) -> Assessment {
        let samples = validated(snapshot.hrv, now: now, isHeartRate: false)
        let heartRate = validated(snapshot.heartRate, now: now, isHeartRate: true)
        guard let current = samples.last else {
            return Assessment(state: .noData, heartRate: heartRate.last)
        }
        let eligible = samples.filter { !isActive($0, heartRate: heartRate, workouts: snapshot.workouts) }
        return assess(current, samples: eligible, heartRate: heartRate, workouts: snapshot.workouts, now: now)
    }

    public static func history(_ snapshot: HealthSnapshot, now: Date) -> [TrendPoint] {
        let samples = validated(snapshot.hrv, now: now, isHeartRate: false)
        let heartRate = validated(snapshot.heartRate, now: now, isHeartRate: true)
        // Activity evidence known at query time applies to historical samples too.
        // Compute this once, rather than scanning workouts for every baseline in every point.
        let eligible = samples.filter { !isActive($0, heartRate: heartRate, workouts: snapshot.workouts) }
        let historyStart = now.addingTimeInterval(-7 * 86_400)
        var points: [TrendPoint] = []
        // Work newest-first so the cap bounds expensive baseline calculations as well as output.
        for sample in samples.reversed() where sample.date >= historyStart {
            let result = assess(sample, samples: eligible, heartRate: heartRate,
                                workouts: snapshot.workouts, now: sample.date)
            if result.state == .ready, let level = result.level {
                points.append(TrendPoint(id: sample.id, date: sample.date, level: level))
                if points.count == 200 { break }
            }
        }
        return points.reversed()
    }

    private static func assess(_ current: MetricSample, samples: [MetricSample], heartRate: [MetricSample],
                               workouts: [ActivityWindow], now: Date) -> Assessment {
        // Already validated against the actual query time; history's `now` only
        // anchors its baseline. Adjacent active HR after HRV still disqualifies it.
        let context = heartRate
        let baselineStart = now.addingTimeInterval(-baselineWindow)
        let recentCutoff = current.date.addingTimeInterval(-recoveryWindow)
        let baseline = samples.filter {
            $0.id != current.id && $0.source == current.source && $0.date >= baselineStart &&
            $0.date < recentCutoff
        }
        // Epoch-aligned 24-hour bins are UTC calendar days, independent of the watch's timezone.
        let days = Set(baseline.map { floor($0.date.timeIntervalSince1970 / 86_400) }).count
        let contextLimited = current.motion == .unknown && !context.contains {
            $0.motion == .sedentary && abs($0.date.timeIntervalSince(current.date)) <= adjacentWindow
        }
        let state: AssessmentState
        var level: StressLevel?
        if now.timeIntervalSince(current.date) > freshnessWindow {
            state = .stale
        } else if isActive(current, heartRate: context, workouts: workouts) {
            state = .activity
        } else if baseline.count < 20 || days < 5 {
            state = .calibrating
        } else {
            state = .ready
            let logarithms = baseline.map { log($0.value) }
            let center = median(logarithms)
            let mad = median(logarithms.map { abs($0 - center) })
            let z = (center - log(current.value)) / max(1.4826 * mad, 0.15)
            level = z >= 1 ? .elevated : (z <= -1 ? .lower : .usual)
        }
        return Assessment(state: state, level: level, sampleDate: current.date, hrv: current.value,
                          heartRate: context.last, baselineCount: baseline.count, baselineDays: days,
                          contextLimited: contextLimited)
    }

    private static func isActive(_ sample: MetricSample, heartRate: [MetricSample],
                                 workouts: [ActivityWindow]) -> Bool {
        if sample.motion == .active { return true }
        if heartRate.contains(where: {
            $0.motion == .active && abs($0.date.timeIntervalSince(sample.date)) <= adjacentWindow
        }) { return true }
        return workouts.contains {
            $0.start.timeIntervalSince1970.isFinite && $0.end.timeIntervalSince1970.isFinite &&
            $0.start <= $0.end && sample.date >= $0.start &&
            sample.date <= $0.end.addingTimeInterval(recoveryWindow)
        }
    }

    private static func validated(_ samples: [MetricSample], now: Date, isHeartRate: Bool) -> [MetricSample] {
        guard now.timeIntervalSince1970.isFinite else { return [] }
        var unique: [String: MetricSample] = [:]
        for sample in samples where sample.date.timeIntervalSince1970.isFinite {
            if let existing = unique[sample.id], existing.date >= sample.date { continue }
            unique[sample.id] = sample
        }
        let oldest = now.addingTimeInterval(-baselineWindow)
        return unique.values.filter {
            $0.value.isFinite && (isHeartRate ? (25...240).contains($0.value) : $0.value > 0) &&
            $0.date <= now && $0.date >= oldest
        }.sorted {
            $0.date == $1.date ? $0.id < $1.id : $0.date < $1.date
        }
    }

    private static func median(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
    }
}
