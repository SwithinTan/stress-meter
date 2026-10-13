import Foundation

public enum MotionContext: String, Codable, CaseIterable, Sendable {
    case unknown, sedentary, active
}

public struct MetricSample: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let value: Double
    public let date: Date
    public let source: String
    public let motion: MotionContext

    public init(id: String, value: Double, date: Date, source: String, motion: MotionContext = .unknown) {
        self.id = id
        self.value = value
        self.date = date
        self.source = source
        self.motion = motion
    }
}

public struct ActivityWindow: Codable, Equatable, Sendable {
    public let start: Date
    public let end: Date

    public init(start: Date, end: Date) {
        self.start = start
        self.end = end
    }
}

public struct HealthSnapshot: Codable, Equatable, Sendable {
    public let hrv: [MetricSample]
    public let heartRate: [MetricSample]
    public let workouts: [ActivityWindow]

    public static let empty = HealthSnapshot()

    public init(hrv: [MetricSample] = [], heartRate: [MetricSample] = [], workouts: [ActivityWindow] = []) {
        self.hrv = hrv
        self.heartRate = heartRate
        self.workouts = workouts
    }
}

public enum AssessmentState: String, Codable, CaseIterable, Sendable {
    case noData, calibrating, stale, activity, ready
}

public enum StressLevel: String, Codable, CaseIterable, Sendable {
    case lower, usual, elevated

    public var rank: Int {
        switch self {
        case .lower: 0
        case .usual: 1
        case .elevated: 2
        }
    }
}

public struct Assessment: Codable, Equatable, Sendable {
    public let state: AssessmentState
    public let level: StressLevel?
    public let sampleDate: Date?
    public let hrv: Double?
    public let heartRate: MetricSample?
    public let baselineCount: Int
    public let baselineDays: Int
    public let contextLimited: Bool

    public init(state: AssessmentState, level: StressLevel? = nil, sampleDate: Date? = nil,
                hrv: Double? = nil, heartRate: MetricSample? = nil, baselineCount: Int = 0,
                baselineDays: Int = 0, contextLimited: Bool = true) {
        self.state = state
        self.level = level
        self.sampleDate = sampleDate
        self.hrv = hrv
        self.heartRate = heartRate
        self.baselineCount = baselineCount
        self.baselineDays = baselineDays
        self.contextLimited = contextLimited
    }
}

public struct TrendPoint: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let date: Date
    public let level: StressLevel

    public init(id: String, date: Date, level: StressLevel) {
        self.id = id
        self.date = date
        self.level = level
    }
}
