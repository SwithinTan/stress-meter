import Foundation
import Observation

public protocol HealthDataProviding: Sendable {
    func requestAuthorization() async throws
    func fetchSnapshot(now: Date) async throws -> HealthSnapshot
}

/// In-memory health state. Clearing invalidates even providers that finish after cancellation.
@Observable @MainActor
public final class MonitoringSession {
    public private(set) var snapshot: HealthSnapshot = .empty
    public private(set) var isRefreshing = false
    public private(set) var isMonitoring = false
    public private(set) var errorMessage: String?

    @ObservationIgnored private let provider: any HealthDataProviding
    @ObservationIgnored private var generation: UInt = 0
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var authorizationTask: Task<Void, Never>?

    public init(provider: any HealthDataProviding) {
        self.provider = provider
    }

    public func start() async {
        if let authorizationTask {
            await authorizationTask.value
            return
        }
        if isMonitoring {
            await refresh()
            return
        }
        let token = generation
        let task = Task { [provider] in
            defer {
                if generation == token && !Task.isCancelled { authorizationTask = nil }
            }
            do {
                try await provider.requestAuthorization()
                guard generation == token, !Task.isCancelled else { return }
                // Successful authorization means the request completed, not that read access was granted.
                isMonitoring = true
                await refresh()
            } catch {
                guard generation == token, !Task.isCancelled else { return }
                snapshot = .empty
                errorMessage = error.localizedDescription
                isMonitoring = false
            }
        }
        authorizationTask = task
        await task.value
    }

    public func resume() async {
        // A persisted monitoring preference may resume without presenting authorization again.
        authorizationTask?.cancel()
        authorizationTask = nil
        isMonitoring = true
        await refresh()
    }

    public func refresh(now: Date = Date()) async {
        guard isMonitoring else { return }
        if let refreshTask {
            await refreshTask.value
            return
        }
        let token = generation
        isRefreshing = true
        let task = Task { [provider] in
            defer {
                if generation == token && !Task.isCancelled {
                    isRefreshing = false
                    refreshTask = nil
                }
            }
            do {
                let replacement = try await provider.fetchSnapshot(now: now)
                guard generation == token, isMonitoring, !Task.isCancelled else { return }
                // Empty successful reads replace old data: deletions and changed access must be respected.
                snapshot = replacement
                errorMessage = nil
            } catch {
                guard generation == token, isMonitoring, !Task.isCancelled else { return }
                snapshot = .empty
                errorMessage = error.localizedDescription
            }
        }
        refreshTask = task
        await task.value
    }

    public func stopAndClear() {
        generation &+= 1
        authorizationTask?.cancel()
        authorizationTask = nil
        refreshTask?.cancel()
        refreshTask = nil
        isMonitoring = false
        isRefreshing = false
        snapshot = .empty
        errorMessage = nil
    }
}
