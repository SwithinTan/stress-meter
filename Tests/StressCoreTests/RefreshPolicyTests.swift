import Foundation
import XCTest
@testable import StressCore

final class RefreshPolicyTests: XCTestCase {
    func testDayNightBoundariesUseLocalCalendar() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        for (hour, minute, expected) in [(6, 59, 600.0), (7, 0, 300.0), (22, 59, 300.0), (23, 0, 600.0), (0, 0, 600.0)] {
            let date = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 2, day: 2, hour: hour, minute: minute)))
            XCTAssertEqual(RefreshPolicy.interval(at: date, calendar: calendar, lowPower: false), expected)
            XCTAssertEqual(RefreshPolicy.interval(at: date, calendar: calendar, lowPower: true), 600)
        }
    }

    func testTimezoneChangeRecomputesLocalHour() throws {
        let date = Date(timeIntervalSince1970: 1_769_947_200)
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        var west = utc
        west.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: -8 * 3_600))
        XCTAssertEqual(RefreshPolicy.interval(at: date, calendar: utc, lowPower: false), 300)
        XCTAssertEqual(RefreshPolicy.interval(at: date, calendar: west, lowPower: false), 600)
    }
}
