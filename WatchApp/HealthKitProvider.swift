import Foundation
import HealthKit
import StressCore

enum HealthProviderError: LocalizedError {
    case unavailable
    case queryTimedOut
    case invalidDate

    var errorDescription: String? {
        switch self {
        case .unavailable: "此设备暂不支持健康数据。"
        case .queryTimedOut: "读取健康数据超时，请稍后重试。"
        case .invalidDate: "设备时间无效，请检查日期设置。"
        }
    }
}

/// A single owner for continuation, query cancellation and deadline. The lock also
/// serializes execute/stop, so cancellation can never stop a not-yet-started query
/// and then accidentally allow it to execute afterward.
final class HealthQueryOperation<Value: Sendable>: @unchecked Sendable {
    private let lock = NSRecursiveLock()
    private var continuation: CheckedContinuation<Value, any Error>?
    private var outcome: Result<Value, any Error>?
    private var stopQuery: (@Sendable () -> Void)?
    private var deadline: Task<Void, Never>?

    func run(
        timeout: Duration,
        start: @escaping @Sendable () -> Void,
        stop: @escaping @Sendable () -> Void
    ) async throws -> Value {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                lock.withLock {
                    if let outcome {
                        continuation.resume(with: outcome)
                        return
                    }
                    self.continuation = continuation
                    stopQuery = stop
                    deadline = Task { [weak self] in
                        do { try await Task.sleep(for: timeout) }
                        catch { return }
                        self?.finish(.failure(HealthProviderError.queryTimedOut))
                    }
                    start()
                }
            }
        } onCancel: {
            self.finish(.failure(CancellationError()))
        }
    }

    func finish(_ result: Result<Value, any Error>) {
        let completion = lock.withLock { () -> (CheckedContinuation<Value, any Error>?, (@Sendable () -> Void)?, Task<Void, Never>?)? in
            guard outcome == nil else { return nil }
            outcome = result
            let completion = (continuation, stopQuery, deadline)
            continuation = nil
            stopQuery = nil
            deadline = nil
            return completion
        }
        guard let completion else { return }
        completion.2?.cancel()
        completion.1?()
        completion.0?.resume(with: result)
    }
}

/// HealthKit's completion block is not annotated Sendable; this box guarantees
/// that only one caller invokes it, including deadline and stop races.
final class HealthObserverDelivery: @unchecked Sendable {
    private let lock = NSLock()
    private var completion: (() -> Void)?
    private let onFinish: @Sendable () -> Void
    private var work: Task<Void, Never>?
    private var deadline: Task<Void, Never>?

    init(completion: @escaping () -> Void, onFinish: @escaping @Sendable () -> Void) {
        self.completion = completion
        self.onFinish = onFinish
    }

    func start(onChange: @escaping @Sendable () async -> Void) {
        lock.withLock {
            guard completion != nil else { return }
            work = Task { [weak self] in
                await onChange()
                self?.finish()
            }
            deadline = Task { [weak self] in
                do { try await Task.sleep(for: .seconds(10)) }
                catch { return }
                self?.finish()
            }
        }
    }

    func finish() {
        let action = lock.withLock { () -> (() -> Void)? in
            guard let completion else { return nil }
            self.completion = nil
            work?.cancel()
            deadline?.cancel()
            work = nil
            deadline = nil
            return completion
        }
        guard let action else { return }
        action()
        onFinish()
    }
}

/// HealthKit is thread-safe. All mutable provider state is protected by stateLock;
/// snapshots contain only Sendable value models and are never cached here.
final class HealthKitProvider: HealthDataProviding, @unchecked Sendable {
    private let store = HKHealthStore()
    private let stateLock = NSRecursiveLock()
    private var generation: UInt64 = 0
    private var observing = false
    private var observers: [HKObserverQuery] = []
    private var deliveries: [UUID: HealthObserverDelivery] = [:]
    private var queryCancellations: [UUID: @Sendable () -> Void] = [:]

    private var observedTypes: [HKSampleType] {
        [.quantityType(forIdentifier: .heartRateVariabilitySDNN),
         .quantityType(forIdentifier: .heartRate),
         .workoutType()].compactMap { $0 }
    }

    func requestAuthorization() async throws {
        guard HKHealthStore.isHealthDataAvailable() else { throw HealthProviderError.unavailable }
        // Requesting authorization does not reveal whether read access was granted.
        try await store.requestAuthorization(toShare: [], read: Set(observedTypes))
    }

    func fetchSnapshot(now: Date) async throws -> HealthSnapshot {
        guard now.timeIntervalSinceReferenceDate.isFinite else { throw HealthProviderError.invalidDate }
        guard HKHealthStore.isHealthDataAvailable(),
              let hrvType = HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN),
              let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate)
        else { throw HealthProviderError.unavailable }
        try Task.checkCancellation()
        let start = now.addingTimeInterval(-28 * 86_400)
        let heartRateStart = now.addingTimeInterval(-3_600)
        async let hrv = readSamples(type: hrvType, start: start, end: now, limit: 4_000) { samples in
            Self.metrics(samples, unit: .secondUnit(with: .milli), start: start, end: now, heartRate: false)
        }
        async let heartRate = readSamples(type: heartRateType, start: heartRateStart, end: now, limit: 300) { samples in
            Self.metrics(samples, unit: .count().unitDivided(by: .minute()), start: heartRateStart, end: now, heartRate: true)
        }
        // Include context immediately before the oldest baseline sample.
        async let workouts = readSamples(type: HKObjectType.workoutType(), start: start.addingTimeInterval(-1_800), end: now, limit: 500) { samples in
            samples.compactMap { sample -> ActivityWindow? in
                guard let workout = sample as? HKWorkout,
                      workout.startDate.timeIntervalSinceReferenceDate.isFinite,
                      workout.endDate.timeIntervalSinceReferenceDate.isFinite,
                      workout.endDate >= workout.startDate,
                      workout.startDate <= now, workout.endDate <= now,
                      workout.endDate >= start.addingTimeInterval(-1_800)
                else { return nil }
                return ActivityWindow(start: workout.startDate, end: workout.endDate)
            }
        }
        return try await HealthSnapshot(hrv: hrv, heartRate: heartRate, workouts: workouts)
    }

    private static func metrics(_ samples: [HKSample], unit: HKUnit, start: Date, end: Date, heartRate: Bool) -> [MetricSample] {
        samples.compactMap { sample in
            guard let sample = sample as? HKQuantitySample,
                  (sample.metadata?[HKMetadataKeyWasUserEntered] as? NSNumber)?.boolValue != true,
                  sample.startDate.timeIntervalSinceReferenceDate.isFinite,
                  sample.endDate.timeIntervalSinceReferenceDate.isFinite,
                  sample.endDate >= sample.startDate,
                  sample.endDate >= start, sample.endDate <= end
            else { return nil }
            let value = sample.quantity.doubleValue(for: unit)
            guard value.isFinite, value > 0, !heartRate || (25...240).contains(value) else { return nil }
            let motion: MotionContext
            switch (sample.metadata?[HKMetadataKeyHeartRateMotionContext] as? NSNumber)?.intValue {
            case HKHeartRateMotionContext.sedentary.rawValue: motion = .sedentary
            case HKHeartRateMotionContext.active.rawValue: motion = .active
            default: motion = .unknown
            }
            return MetricSample(id: sample.uuid.uuidString, value: value, date: sample.endDate,
                                source: sample.sourceRevision.source.bundleIdentifier, motion: motion)
        }
    }

    private func readSamples<Value: Sendable>(
        type: HKSampleType, start: Date, end: Date, limit: Int,
        transform: @escaping @Sendable ([HKSample]) -> Value
    ) async throws -> Value {
        let operation = HealthQueryOperation<Value>()
        let id = UUID()
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictEndDate)
        let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: limit,
                                  sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)]) { _, samples, error in
            if let error { operation.finish(.failure(error)) }
            else { operation.finish(.success(transform(samples ?? []))) }
        }
        stateLock.withLock { queryCancellations[id] = { operation.finish(.failure(CancellationError())) } }
        defer { _ = stateLock.withLock { queryCancellations.removeValue(forKey: id) } }
        return try await operation.run(timeout: .seconds(8), start: { [store] in
            store.execute(query)
        }, stop: { [store] in
            store.stop(query)
        })
    }

    // The UI lifecycle calls start/stop on the main actor. Keep registration in
    // that same turn (there is no await below), so a suspended old start cannot
    // register observers after the user has paused on the main actor.
    @MainActor
    func startObserving(onChange: @escaping @Sendable () async -> Void) {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        let newGeneration: UInt64? = stateLock.withLock {
            guard !observing else { return nil }
            generation &+= 1
            let current = generation
            observing = true
            observers = observedTypes.map { type in
                HKObserverQuery(sampleType: type, predicate: nil) { [weak self] _, completion, error in
                    guard let self, error == nil else { completion(); return }
                    self.receiveChange(generation: current, completion: completion, onChange: onChange)
                }
            }
            for query in observers { store.execute(query) }
            return current
        }
        guard newGeneration != nil else { return }
        for type in observedTypes { reconcileBackgroundDelivery(for: type) }
    }

    private func receiveChange(generation: UInt64, completion: @escaping () -> Void, onChange: @escaping @Sendable () async -> Void) {
        let id = UUID()
        let delivery = HealthObserverDelivery(completion: completion) { [weak self] in
            guard let self else { return }
            _ = self.stateLock.withLock { self.deliveries.removeValue(forKey: id) }
        }
        let accepted = stateLock.withLock {
            guard observing, self.generation == generation else { return false }
            deliveries[id] = delivery
            delivery.start(onChange: { [weak self] in
                guard let self, self.isCurrent(generation), !Task.isCancelled else { return }
                await onChange()
            })
            return true
        }
        if !accepted { delivery.finish() }
    }

    private func isCurrent(_ generation: UInt64) -> Bool {
        stateLock.withLock { observing && self.generation == generation }
    }

    func stopObserving() {
        let pending = stateLock.withLock { () -> ([HealthObserverDelivery], [@Sendable () -> Void]) in
            generation &+= 1
            observing = false
            for query in observers { store.stop(query) }
            observers.removeAll()
            let pending = (Array(deliveries.values), Array(queryCancellations.values))
            deliveries.removeAll()
            queryCancellations.removeAll()
            return pending
        }
        for delivery in pending.0 { delivery.finish() }
        for cancel in pending.1 { cancel() }
        for type in observedTypes { reconcileBackgroundDelivery(for: type) }
    }

    /// An old enable completion must not revive delivery after stop. An old
    /// disable must likewise not disable a later start. Every stale completion
    /// reconciles to the latest desired generation, in either direction.
    private func reconcileBackgroundDelivery(for type: HKSampleType) {
        stateLock.withLock {
            let requestedGeneration = generation
            let completion: @Sendable (Bool, (any Error)?) -> Void = { [weak self] _, _ in
                guard let self else { return }
                let stale = self.stateLock.withLock { self.generation != requestedGeneration }
                if stale { self.reconcileBackgroundDelivery(for: type) }
            }
            if observing { store.enableBackgroundDelivery(for: type, frequency: .hourly, withCompletion: completion) }
            else { store.disableBackgroundDelivery(for: type, withCompletion: completion) }
        }
    }
}
