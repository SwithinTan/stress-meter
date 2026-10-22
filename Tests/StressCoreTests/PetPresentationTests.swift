import Foundation
import XCTest
@testable import StressCore

final class PetPresentationTests: XCTestCase {
    func testPetReflectsTheCurrentEstimatorAssessment() {
        let now = Date(timeIntervalSince1970: 1_769_947_200)
        let baseline = (1...5).flatMap { day in
            (0..<4).map { index in
                MetricSample(id: "base-\(day)-\(index)", value: 50,
                             date: now.addingTimeInterval(-Double(day * 86_400 + index * 3_600)),
                             source: "watch", motion: .sedentary)
            }
        }

        for (hrv, expectedMood) in [(80.0, PetMood.relaxed), (50, .balanced), (30, .tense)] {
            let current = MetricSample(id: "current", value: hrv, date: now,
                                       source: "watch", motion: .sedentary)
            let assessment = StressEstimator.assess(HealthSnapshot(hrv: baseline + [current]), now: now)

            XCTAssertEqual(PetMood(assessment: assessment), expectedMood, "Current HRV: \(hrv)")
        }
    }

    func testUnavailableAssessmentNeverReusesAnOldStressMood() {
        for state in [AssessmentState.noData, .calibrating, .stale, .activity] {
            for retainedLevel in StressLevel.allCases {
                let assessment = Assessment(state: state, level: retainedLevel)

                XCTAssertEqual(PetMood(assessment: assessment), .waiting,
                               "\(state) must not present the retained \(retainedLevel) level")
            }
        }
    }

    func testReadyAssessmentWithoutALevelWaits() {
        XCTAssertEqual(PetMood(assessment: Assessment(state: .ready)), .waiting)
    }

    func testReadErrorSuppressesTheLastAvailableStressMood() {
        for level in StressLevel.allCases {
            let previousAssessment = Assessment(state: .ready, level: level)

            XCTAssertEqual(PetMood(assessment: previousAssessment, hasReadError: true), .waiting,
                           "A read error must hide the previous \(level) mood")
        }
    }

    func testVisibleActivePetCanAnimateWhenNoRestrictionApplies() {
        XCTAssertTrue(PetAnimationPolicy.allowsAnimation(isVisible: true, isActive: true,
                                                        isLuminanceReduced: false,
                                                        reduceMotion: false, lowPower: false))
    }

    func testHiddenPetDoesNotAnimate() {
        XCTAssertFalse(PetAnimationPolicy.allowsAnimation(isVisible: false, isActive: true,
                                                         isLuminanceReduced: false,
                                                         reduceMotion: false, lowPower: false))
    }

    func testInactivePetDoesNotAnimate() {
        XCTAssertFalse(PetAnimationPolicy.allowsAnimation(isVisible: true, isActive: false,
                                                         isLuminanceReduced: false,
                                                         reduceMotion: false, lowPower: false))
    }

    func testReducedLuminanceStopsAnimation() {
        XCTAssertFalse(PetAnimationPolicy.allowsAnimation(isVisible: true, isActive: true,
                                                         isLuminanceReduced: true,
                                                         reduceMotion: false, lowPower: false))
    }

    func testReduceMotionStopsAnimation() {
        XCTAssertFalse(PetAnimationPolicy.allowsAnimation(isVisible: true, isActive: true,
                                                         isLuminanceReduced: false,
                                                         reduceMotion: true, lowPower: false))
    }

    func testLowPowerStopsAnimation() {
        XCTAssertFalse(PetAnimationPolicy.allowsAnimation(isVisible: true, isActive: true,
                                                         isLuminanceReduced: false,
                                                         reduceMotion: false, lowPower: true))
    }
}
