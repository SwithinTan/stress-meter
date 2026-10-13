import Foundation
import XCTest
@testable import StressCore

private enum TestFailure: Error { case unavailable }

/// Controls external I/O completion without clocks or sleeps. Session behavior remains real.
private actor ControlledHealthProvider: HealthDataProviding {
    private var fetches: [Int: CheckedContinuation<HealthSnapshot, any Error>] = [:]
    private var authorization: CheckedContinuation<Void, any Error>?
    private let holdAuthorization: Bool
    private let immediateFetch: HealthSnapshot?
    private let fetchStarted: @Sendable (Int) -> Void
    private let authorizationStarted: @Sendable () -> Void
    private(set) var fetchCount = 0
    private(set) var authorizationCount = 0
    private(set) var requestedDates: [Date] = []

    init(holdAuthorization: Bool = false, immediateFetch: HealthSnapshot? = nil,
         authorizationStarted: @escaping @Sendable () -> Void = {},
         fetchStarted: @escaping @Sendable (Int) -> Void = { _ in }) {
        self.holdAuthorization = holdAuthorization
        self.immediateFetch = immediateFetch
        self.authorizationStarted = authorizationStarted
        self.fetchStarted = fetchStarted
    }

    func requestAuthorization() async throws {
        authorizationCount += 1
        if holdAuthorization {
            try await withCheckedThrowingContinuation { continuation in
                authorization = continuation
                authorizationStarted()
            }
        } else {
            authorizationStarted()
        }
    }

    func fetchSnapshot(now: Date) async throws -> HealthSnapshot {
        fetchCount += 1
        requestedDates.append(now)
        let index = fetchCount
        if let immediateFetch { return immediateFetch }
        return try await withCheckedThrowingContinuation { continuation in
            fetches[index] = continuation
            fetchStarted(index)
        }
    }

    func finish(_ index: Int, with result: Result<HealthSnapshot, any Error>) {
        fetches.removeValue(forKey: index)?.resume(with: result)
    }

    func finishAll(with result: Result<HealthSnapshot, any Error>) {
        let pending = fetches.values
        fetches.removeAll()
        for continuation in pending { continuation.resume(with: result) }
    }

    func finishAuthorization(with result: Result<Void, any Error>) {
        authorization?.resume(with: result)
        authorization = nil
    }
}

@MainActor
final class MonitoringSessionTests: XCTestCase {
    private var snapshot: HealthSnapshot {
        HealthSnapshot(hrv: [MetricSample(id: "sample", value: 45, date: Date(timeIntervalSince1970: 10), source: "watch")])
    }

    func testResumeEnablesMonitoringAndReplacesSnapshotWithoutAuthorization() async {
        let started = expectation(description: "fetch started")
        let provider = ControlledHealthProvider(fetchStarted: { _ in started.fulfill() })
        let session = MonitoringSession(provider: provider)
        let task = Task { await session.resume() }
        await fulfillment(of: [started], timeout: 2)
        XCTAssertTrue(session.isMonitoring)
        XCTAssertTrue(session.isRefreshing)
        await provider.finish(1, with: .success(snapshot))
        await task.value
        XCTAssertEqual(session.snapshot, snapshot)
        XCTAssertFalse(session.isRefreshing)
        let authorizations = await provider.authorizationCount
        XCTAssertEqual(authorizations, 0)
    }

    func testConcurrentRefreshesCoalesceAndAllCallersAwaitResult() async {
        let started = expectation(description: "first fetch started")
        let secondEntered = expectation(description: "second caller entered")
        let provider = ControlledHealthProvider(fetchStarted: { index in if index == 1 { started.fulfill() } })
        let session = MonitoringSession(provider: provider)
        let first = Task { await session.resume() }
        await fulfillment(of: [started], timeout: 2)
        var secondFinished = false
        let second = Task {
            secondEntered.fulfill()
            await session.refresh()
            secondFinished = true
        }
        await fulfillment(of: [secondEntered], timeout: 2)
        XCTAssertFalse(secondFinished)
        let count = await provider.fetchCount
        XCTAssertEqual(count, 1)
        await provider.finishAll(with: .success(snapshot))
        await first.value
        await second.value
        XCTAssertEqual(session.snapshot, snapshot)
        XCTAssertTrue(secondFinished)
    }

    func testStopDuringFetchCannotRestoreSamplesOrMonitoring() async {
        let started = expectation(description: "fetch started")
        let provider = ControlledHealthProvider(fetchStarted: { _ in started.fulfill() })
        let session = MonitoringSession(provider: provider)
        let task = Task { await session.resume() }
        await fulfillment(of: [started], timeout: 2)
        session.stopAndClear()
        XCTAssertFalse(session.isMonitoring)
        XCTAssertFalse(session.isRefreshing)
        await provider.finish(1, with: .success(snapshot))
        await task.value
        XCTAssertEqual(session.snapshot, .empty)
        XCTAssertFalse(session.isMonitoring)
        XCTAssertNil(session.errorMessage)
    }

    func testFailureArrivingAfterStopCannotRepopulateError() async {
        let started = expectation(description: "fetch started")
        let provider = ControlledHealthProvider(fetchStarted: { _ in started.fulfill() })
        let session = MonitoringSession(provider: provider)
        let task = Task { await session.resume() }
        await fulfillment(of: [started], timeout: 2)
        session.stopAndClear()
        await provider.finish(1, with: .failure(TestFailure.unavailable))
        await task.value
        XCTAssertNil(session.errorMessage)
        XCTAssertEqual(session.snapshot, .empty)
    }

    func testEmptySuccessfulRefreshReplacesPreviousSnapshot() async {
        let firstStarted = expectation(description: "first fetch")
        let secondStarted = expectation(description: "second fetch")
        let provider = ControlledHealthProvider(fetchStarted: { index in
            (index == 1 ? firstStarted : secondStarted).fulfill()
        })
        let session = MonitoringSession(provider: provider)
        let first = Task { await session.resume() }
        await fulfillment(of: [firstStarted], timeout: 2)
        await provider.finish(1, with: .success(snapshot))
        await first.value
        let second = Task { await session.refresh() }
        await fulfillment(of: [secondStarted], timeout: 2)
        await provider.finish(2, with: .success(.empty))
        await second.value
        XCTAssertEqual(session.snapshot, .empty)
        XCTAssertNil(session.errorMessage)
    }

    func testQueryErrorClearsStaleSnapshotAndSuccessfulRetryClearsError() async {
        let starts = (1...3).map { expectation(description: "fetch \($0)") }
        let provider = ControlledHealthProvider(fetchStarted: { starts[$0 - 1].fulfill() })
        let session = MonitoringSession(provider: provider)
        let first = Task { await session.resume() }
        await fulfillment(of: [starts[0]], timeout: 2)
        await provider.finish(1, with: .success(snapshot))
        await first.value
        let failed = Task { await session.refresh() }
        await fulfillment(of: [starts[1]], timeout: 2)
        await provider.finish(2, with: .failure(TestFailure.unavailable))
        await failed.value
        XCTAssertEqual(session.snapshot, .empty)
        XCTAssertNotNil(session.errorMessage)
        XCTAssertTrue(session.isMonitoring)
        let retry = Task { await session.refresh() }
        await fulfillment(of: [starts[2]], timeout: 2)
        await provider.finish(3, with: .success(snapshot))
        await retry.value
        XCTAssertEqual(session.snapshot, snapshot)
        XCTAssertNil(session.errorMessage)
    }

    func testStopDuringAuthorizationPreventsEnableAndFetch() async {
        let authorizationStarted = expectation(description: "authorization started")
        let provider = ControlledHealthProvider(holdAuthorization: true,
                                               authorizationStarted: { authorizationStarted.fulfill() })
        let session = MonitoringSession(provider: provider)
        let task = Task { await session.start() }
        await fulfillment(of: [authorizationStarted], timeout: 2)
        session.stopAndClear()
        await provider.finishAuthorization(with: .failure(TestFailure.unavailable))
        await task.value
        XCTAssertFalse(session.isMonitoring)
        XCTAssertNil(session.errorMessage)
        let count = await provider.fetchCount
        XCTAssertEqual(count, 0)
    }


    func testAuthorizationSuccessAfterStopCannotEnableMonitoring() async {
        let started = expectation(description: "authorization started")
        let provider = ControlledHealthProvider(holdAuthorization: true, immediateFetch: .empty,
                                               authorizationStarted: { started.fulfill() })
        let session = MonitoringSession(provider: provider)
        let task = Task { await session.start() }
        await fulfillment(of: [started], timeout: 2)
        session.stopAndClear()
        await provider.finishAuthorization(with: .success(()))
        await task.value
        XCTAssertFalse(session.isMonitoring)
        let count = await provider.fetchCount
        XCTAssertEqual(count, 0)
    }

    func testStartRequestsAuthorizationBeforeEnablingAndFetching() async {
        let authorizationStarted = expectation(description: "authorization started")
        let fetchStarted = expectation(description: "fetch started")
        let provider = ControlledHealthProvider(holdAuthorization: true,
                                               authorizationStarted: { authorizationStarted.fulfill() },
                                               fetchStarted: { _ in fetchStarted.fulfill() })
        let session = MonitoringSession(provider: provider)
        let task = Task { await session.start() }
        await fulfillment(of: [authorizationStarted], timeout: 2)
        XCTAssertFalse(session.isMonitoring)
        let before = await provider.fetchCount
        XCTAssertEqual(before, 0)
        await provider.finishAuthorization(with: .success(()))
        await fulfillment(of: [fetchStarted], timeout: 2)
        await provider.finish(1, with: .success(snapshot))
        await task.value
        XCTAssertTrue(session.isMonitoring)
        XCTAssertEqual(session.snapshot, snapshot)
        XCTAssertNil(session.errorMessage)
    }

    func testLateOldFetchCannotOverwriteNewGeneration() async {
        let oldStarted = expectation(description: "old fetch")
        let newStarted = expectation(description: "new fetch")
        let provider = ControlledHealthProvider(fetchStarted: { index in
            (index == 1 ? oldStarted : newStarted).fulfill()
        })
        let session = MonitoringSession(provider: provider)
        let old = Task { await session.resume() }
        await fulfillment(of: [oldStarted], timeout: 2)
        session.stopAndClear()
        let new = Task { await session.resume() }
        await fulfillment(of: [newStarted], timeout: 2)
        await provider.finish(2, with: .success(snapshot))
        await new.value
        await provider.finish(1, with: .success(.empty))
        await old.value
        XCTAssertEqual(session.snapshot, snapshot)
        XCTAssertTrue(session.isMonitoring)
        XCTAssertFalse(session.isRefreshing)
    }

    func testStoppedRefreshDoesNotQueryOrEnableMonitoring() async {
        let provider = ControlledHealthProvider()
        let session = MonitoringSession(provider: provider)
        // A stopped refresh should return immediately, so use a Task and finish any accidental query.
        let task = Task { await session.refresh() }
        await Task.yield()
        let count = await provider.fetchCount
        await provider.finishAll(with: .success(.empty))
        await task.value
        XCTAssertEqual(count, 0)
        XCTAssertFalse(session.isMonitoring)
    }
}
