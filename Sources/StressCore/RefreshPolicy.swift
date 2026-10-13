import Foundation

public enum RefreshPolicy {
    /// A request cadence only; neither HealthKit delivery nor new sensor samples are guaranteed.
    public static func interval(at date: Date, calendar: Calendar, lowPower: Bool) -> TimeInterval {
        guard !lowPower else { return 10 * 60 }
        return (7..<23).contains(calendar.component(.hour, from: date)) ? 5 * 60 : 10 * 60
    }
}
