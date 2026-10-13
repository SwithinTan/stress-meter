import Foundation

// Build alongside HealthKitProvider.swift and StressCore using test-health-provider.sh.
private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = 0
    func increment() { lock.withLock { storage += 1 } }
    var value: Int { lock.withLock { storage } }
}

@main
struct HealthQueryLifecycleTests {
    static func main() async throws {
        let stopped = Counter()
        let started = Counter()
        let cancelled = HealthQueryOperation<Int>()
        cancelled.finish(.failure(CancellationError()))
        do {
            _ = try await cancelled.run(timeout: .seconds(8), start: { started.increment() }, stop: { stopped.increment() })
            fatalError("Cancellation before installation must throw")
        } catch is CancellationError {}
        precondition(started.value == 0, "A cancelled query must never execute")

        let timedOut = HealthQueryOperation<Int>()
        do {
            _ = try await timedOut.run(timeout: .zero, start: { started.increment() }, stop: { stopped.increment() })
            fatalError("A query that never calls back must time out")
        } catch HealthProviderError.queryTimedOut {}
        precondition(started.value == 1 && stopped.value == 1, "Timeout must stop the actual query exactly once")

        let running = HealthQueryOperation<Int>()
        let liveStops = Counter()
        let signal = AsyncStream<Void>.makeStream()
        let task = Task {
            try await running.run(timeout: .seconds(8), start: {
                signal.continuation.yield(())
            }, stop: { liveStops.increment() })
        }
        var iterator = signal.stream.makeAsyncIterator()
        _ = await iterator.next()
        task.cancel()
        do {
            _ = try await task.value
            fatalError("Cancelling a running task must throw")
        } catch is CancellationError {}
        running.finish(.success(123))
        precondition(liveStops.value == 1, "Cancellation must stop the query and ignore a late callback")
        signal.continuation.finish()

        let completed = HealthQueryOperation<Int>()
        let stopsAfterSuccess = Counter()
        let value = try await completed.run(timeout: .seconds(8), start: {
            completed.finish(.success(42))
            completed.finish(.success(99))
        }, stop: { stopsAfterSuccess.increment() })
        precondition(value == 42, "First query completion must win")
        precondition(stopsAfterSuccess.value == 1, "Completion must release the query once")

        let callbacks = Counter()
        let delivery = HealthObserverDelivery(completion: { callbacks.increment() }, onFinish: {})
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<100 { group.addTask { delivery.finish() } }
        }
        precondition(callbacks.value == 1, "Racing observer completion/cancellation must complete once")
        print("PASS: cancellation before execution, bounded timeout, active cancellation ignores late result, first completion wins, observer completion once")
    }
}
