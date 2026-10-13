import Foundation
import StressCore

/// Explicit preview data. Never selected because a live query is empty or fails.
struct DemoHealthProvider: HealthDataProviding {
    func requestAuthorization() async throws {}

    func fetchSnapshot(now: Date) async throws -> HealthSnapshot {
        let source = "demo.only"
        let baseline: [MetricSample] = (1...21).flatMap { day in
            (0..<4).map { reading in
                let date = now.addingTimeInterval(-Double(day) * 86_400 - Double(reading) * 3_600)
                let value = 48.0 + Double((day * 7 + reading * 3) % 17)
                return MetricSample(id: "demo-\(day)-\(reading)", value: value,
                                    date: date, source: source, motion: .sedentary)
            }
        }
        let recent = MetricSample(id: "demo-latest", value: 36,
                                  date: now.addingTimeInterval(-180), source: source, motion: .sedentary)
        let heart = MetricSample(id: "demo-heart", value: 76,
                                 date: recent.date, source: source, motion: .sedentary)
        return HealthSnapshot(hrv: baseline + [recent], heartRate: [heart], workouts: [])
    }
}
