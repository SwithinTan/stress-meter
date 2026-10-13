import Foundation
import XCTest
@testable import StressCore

final class StressEstimatorTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_769_947_200) // 2026-02-01 12:00 UTC
    let estimator = StressEstimator.self

    func sample(_ id: String = "current", _ value: Double = 50, ago: TimeInterval = 0,
                source: String = "watch", motion: MotionContext = .sedentary) -> MetricSample {
        MetricSample(id: id, value: value, date: now.addingTimeInterval(-ago), source: source, motion: motion)
    }

    func baseline(value: Double = 50, source: String = "watch") -> [MetricSample] {
        (1...5).flatMap { day in
            (0..<4).map { index in
                sample("base-\(day)-\(index)", value, ago: Double(day * 86_400 + index * 3_600), source: source)
            }
        }
    }

    func testEmptyAndInvalidHRVAreNoData() {
        let bad = [sample("nan", .nan), sample("inf", .infinity), sample("zero", 0),
                   sample("negative", -1), sample("future", 50, ago: -1),
                   sample("old", 50, ago: 28 * 86_400 + 1)]
        for snapshot in [HealthSnapshot.empty, HealthSnapshot(hrv: bad)] {
            let result = estimator.assess(snapshot, now: now)
            XCTAssertEqual(result.state, .noData)
            XCTAssertNil(result.level)
            XCTAssertNil(result.sampleDate)
        }
    }

    func testBaselineUsesPersonalLogVariationWithScaleFloor() {
        for (value, level) in [(30.0, StressLevel.elevated), (50, .usual), (80, .lower)] {
            let result = estimator.assess(HealthSnapshot(hrv: baseline() + [sample("latest", value)]), now: now)
            XCTAssertEqual(result.state, .ready)
            XCTAssertEqual(result.level, level)
            XCTAssertEqual(result.baselineCount, 20)
            XCTAssertEqual(result.baselineDays, 5)
            XCTAssertEqual(result.sampleDate, now)
        }
    }

    func testRequiresBothTwentySamplesAndFiveUTCDays() {
        let tooFew = estimator.assess(HealthSnapshot(hrv: Array(baseline().dropLast()) + [sample()]), now: now)
        XCTAssertEqual(tooFew.state, .calibrating)
        XCTAssertEqual(tooFew.baselineCount, 19)
        let oneDay = (0..<20).map { sample("same-day-\($0)", ago: 86_400 + Double($0 * 60)) }
        let result = estimator.assess(HealthSnapshot(hrv: oneDay + [sample()]), now: now)
        XCTAssertEqual(result.state, .calibrating)
        XCTAssertEqual(result.baselineDays, 1)
    }

    func testBaselineNeverMixesSourcesOrRecentSamples() {
        var samples = baseline(source: "other")
        samples += (0..<20).map { sample("recent-\($0)", 50, ago: Double($0 * 60 + 1)) }
        samples.append(sample())
        let result = estimator.assess(HealthSnapshot(hrv: samples), now: now)
        XCTAssertEqual(result.state, .calibrating)
        XCTAssertEqual(result.baselineCount, 0)
    }

    func testDuplicateIDsKeepNewestAndDoNotInflateBaseline() {
        let old = sample("latest", 80, ago: 60)
        let newest = sample("latest", 30)
        let result = estimator.assess(HealthSnapshot(hrv: baseline() + baseline() + [newest, old]), now: now)
        XCTAssertEqual(result.hrv, 30)
        XCTAssertEqual(result.level, .elevated)
        XCTAssertEqual(result.baselineCount, 20)
    }

    func testLatestActiveSampleCannotFallBackToOlderCalmSample() {
        let samples = baseline() + [sample("calm", ago: 60), sample("active", 25, motion: .active)]
        let result = estimator.assess(HealthSnapshot(hrv: samples), now: now)
        XCTAssertEqual(result.state, .activity)
        XCTAssertEqual(result.sampleDate, now)
        XCTAssertEqual(result.hrv, 25)
        XCTAssertNil(result.level)
    }

    func testWorkoutAndRecoveryWindowSuppressEstimate() {
        let snapshot = HealthSnapshot(hrv: baseline() + [sample()], workouts: [
            ActivityWindow(start: now.addingTimeInterval(-3_600), end: now.addingTimeInterval(-1_800))
        ])
        XCTAssertEqual(estimator.assess(snapshot, now: now).state, .activity)
        let outside = HealthSnapshot(hrv: baseline() + [sample()], workouts: [
            ActivityWindow(start: now.addingTimeInterval(-3_600), end: now.addingTimeInterval(-1_801))
        ])
        XCTAssertEqual(estimator.assess(outside, now: now).state, .ready)
    }

    func testAdjacentActiveHeartRateSuppressesEstimateButInvalidHRDoesNot() {
        let hrv = baseline() + [sample()]
        let active = sample("hr", 120, ago: 300, motion: .active)
        XCTAssertEqual(estimator.assess(HealthSnapshot(hrv: hrv, heartRate: [active]), now: now).state, .activity)
        let invalid = sample("bad-hr", 300, motion: .active)
        let result = estimator.assess(HealthSnapshot(hrv: hrv, heartRate: [invalid]), now: now)
        XCTAssertEqual(result.state, .ready)
        XCTAssertNil(result.heartRate)
    }

    func testBaselineExcludesActivityAndInvalidValues() {
        var samples = baseline()
        samples[0] = MetricSample(id: samples[0].id, value: 50, date: samples[0].date,
                                  source: "watch", motion: .active)
        samples += [sample("bad", .nan, ago: 7 * 86_400), sample()]
        let result = estimator.assess(HealthSnapshot(hrv: samples), now: now)
        XCTAssertEqual(result.state, .calibrating)
        XCTAssertEqual(result.baselineCount, 19)
    }

    func testFreshnessBoundaryAndClockRollbackDoNotInventCurrentReading() {
        let snapshot = HealthSnapshot(hrv: baseline() + [sample()])
        XCTAssertEqual(estimator.assess(snapshot, now: now.addingTimeInterval(1_200)).state, .ready)
        let stale = estimator.assess(snapshot, now: now.addingTimeInterval(1_201))
        XCTAssertEqual(stale.state, .stale)
        XCTAssertNil(stale.level)
        XCTAssertEqual(stale.sampleDate, now)
        let rollback = estimator.assess(HealthSnapshot(hrv: [sample()]), now: now.addingTimeInterval(-1))
        XCTAssertEqual(rollback.state, .noData)
    }

    func testStaleTakesPrecedenceOverKnownActivity() {
        let result = estimator.assess(HealthSnapshot(hrv: [sample(motion: .active)]), now: now.addingTimeInterval(1_201))
        XCTAssertEqual(result.state, .stale)
    }

    func testHeartRateHasOwnTimestampAndValidity() {
        let hr = sample("hr-valid", 68, ago: 120)
        let result = estimator.assess(HealthSnapshot(hrv: [sample()], heartRate: [
            hr, sample("too-fast", 241), sample("too-slow", 24), sample("hr-future", 60, ago: -1)
        ]), now: now)
        XCTAssertEqual(result.heartRate, hr)
        XCTAssertEqual(result.hrv, 50)
    }

    func testUnknownMotionIsExplicitlyLimited() {
        let unknown = estimator.assess(HealthSnapshot(hrv: baseline() + [sample(motion: .unknown)]), now: now)
        XCTAssertTrue(unknown.contextLimited)
        let resting = estimator.assess(HealthSnapshot(hrv: baseline() + [sample()]), now: now)
        XCTAssertFalse(resting.contextLimited)
    }

    func testDeletingBaselineChangesAssessmentInsteadOfRetainingOldEstimate() {
        let ready = HealthSnapshot(hrv: baseline() + [sample()])
        XCTAssertEqual(estimator.assess(ready, now: now).state, .ready)
        XCTAssertEqual(estimator.assess(HealthSnapshot(hrv: [sample()]), now: now).state, .calibrating)
    }

    func testHistoryHasNoFutureBaselineLeakageAndNoInterpolatedPoints() {
        let early = sample("early", 30, ago: 6 * 86_400)
        let latest = sample("latest", 30)
        let points = estimator.history(HealthSnapshot(hrv: baseline() + [early, latest]), now: now)
        XCTAssertFalse(points.contains { $0.id == "early" })
        XCTAssertEqual(points.last?.id, "latest")
        XCTAssertEqual(points.last?.level, .elevated)
        XCTAssertTrue(points.allSatisfy { point in (baseline() + [early, latest]).contains { $0.id == point.id } })
    }

    func testHistoryAndDashboardBothExcludeKnownActivityJustAfterHRV() {
        let current = sample("latest", 30, ago: 180)
        let active = sample("active-hr", 120, ago: 120, motion: .active)
        let snapshot = HealthSnapshot(hrv: baseline() + [current], heartRate: [active])
        XCTAssertEqual(estimator.assess(snapshot, now: now).state, .activity)
        XCTAssertFalse(estimator.history(snapshot, now: now).contains { $0.id == "latest" })
        let unknownFuture = HealthSnapshot(hrv: baseline() + [current], heartRate: [
            sample("future-hr", 120, ago: -1, motion: .active)
        ])
        XCTAssertTrue(estimator.history(unknownFuture, now: now).contains { $0.id == "latest" })
    }

    func testHistoryIsLimitedToSevenDaysAndTwoHundredActualSamples() {
        let seed = (8...13).flatMap { day in
            (0..<4).map { index in sample("seed-\(day)-\(index)", ago: Double(day * 86_400 + index * 3_600)) }
        }
        let recent = (0..<250).map { sample("recent-\($0)", ago: Double($0 * 1_800)) }
        let points = estimator.history(HealthSnapshot(hrv: seed + recent), now: now)
        XCTAssertEqual(points.count, 200)
        XCTAssertEqual(points.last?.date, now)
        XCTAssertTrue(points.allSatisfy { $0.date >= now.addingTimeInterval(-7 * 86_400) })
        XCTAssertEqual(points.map(\.date), points.map(\.date).sorted())
    }
}
