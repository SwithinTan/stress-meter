public enum PetMood: String, CaseIterable, Sendable {
    case relaxed, balanced, tense, waiting

    public init(assessment: Assessment, hasReadError: Bool = false) {
        guard !hasReadError, assessment.state == .ready, let level = assessment.level else {
            self = .waiting
            return
        }

        switch level {
        case .lower: self = .relaxed
        case .usual: self = .balanced
        case .elevated: self = .tense
        }
    }
}

public enum PetAnimationPolicy {
    public static func allowsAnimation(isVisible: Bool, isActive: Bool,
                                       isLuminanceReduced: Bool, reduceMotion: Bool,
                                       lowPower: Bool) -> Bool {
        isVisible && isActive && !isLuminanceReduced && !reduceMotion && !lowPower
    }
}
