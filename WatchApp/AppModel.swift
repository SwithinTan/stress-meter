import Foundation
import Observation
import StressCore
import WatchKit

@MainActor
@Observable
final class AppModel {
    static let shared = AppModel()

    private(set) var session: MonitoringSession
    private(set) var isDemo = false
    private(set) var hasStarted: Bool
    private(set) var now = Date()
    private(set) var lastReadDate: Date?
    private(set) var nextReadDate: Date?
    private(set) var history: [TrendPoint] = []
    private(set) var backgroundNotice: String?
    private(set) var isConnecting = false

    @ObservationIgnored private let liveProvider = HealthKitProvider()
    @ObservationIgnored private var ticker: Task<Void, Never>?
    @ObservationIgnored private var lifecycleTask: Task<Void, Never>?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var isForeground = false
    private static let enabledKey = "healthMonitoringEnabled"

    private init() {
        session = MonitoringSession(provider: liveProvider)
        hasStarted = UserDefaults.standard.bool(forKey: Self.enabledKey)
    }

    var assessment: Assessment { StressEstimator.assess(session.snapshot, now: now) }
    var intervalMinutes: Int {
        Int(RefreshPolicy.interval(at: now, calendar: .current,
                                   lowPower: ProcessInfo.processInfo.isLowPowerModeEnabled) / 60)
    }

    func startLive() async {
        guard !isConnecting else { return }
        isConnecting = true
        generation += 1
        let token = generation
        defer { if generation == token { isConnecting = false } }
        session.stopAndClear()
        liveProvider.stopObserving()
        hasStarted = false
        UserDefaults.standard.set(false, forKey: Self.enabledKey)
        isDemo = false
        history = []
        lastReadDate = nil
        session = MonitoringSession(provider: liveProvider)
        await session.start()
        guard generation == token, session.isMonitoring else { return }
        hasStarted = true
        UserDefaults.standard.set(true, forKey: Self.enabledKey)
        recordRefresh()
        observeLiveData()
        guard generation == token, !isDemo, session.isMonitoring else { return }
        scheduleBackgroundRefresh()
    }

    func startDemo() async {
        generation += 1
        let token = generation
        liveProvider.stopObserving()
        session.stopAndClear()
        isDemo = true
        isConnecting = false
        history = []
        lastReadDate = nil
        session = MonitoringSession(provider: DemoHealthProvider())
        await session.start()
        guard token == generation else { return }
        recordRefresh()
    }

    func stopAndClear() {
        generation += 1
        liveProvider.stopObserving()
        session.stopAndClear()
        hasStarted = false
        isDemo = false
        isConnecting = false
        history = []
        lastReadDate = nil
        nextReadDate = nil
        backgroundNotice = nil
        UserDefaults.standard.set(false, forKey: Self.enabledKey)
    }

    func refresh() async {
        let token = generation
        now = Date()
        await session.refresh(now: now)
        guard generation == token, session.isMonitoring else { return }
        recordRefresh()
    }

    func sceneChanged(active: Bool) {
        isForeground = active
        ticker?.cancel()
        ticker = nil
        lifecycleTask?.cancel()
        if active {
            lifecycleTask = Task { [weak self] in
                guard let self else { return }
                if ProcessInfo.processInfo.arguments.contains("--demo"), !isDemo, !hasStarted {
                    await startDemo()
                } else if hasStarted && !session.isMonitoring && !isDemo {
                    await resumeLive()
                } else if session.isMonitoring {
                    await refresh()
                }
            }
            ticker = Task { [weak self] in
                while !Task.isCancelled {
                    do { try await Task.sleep(for: .seconds(15)) }
                    catch { return }
                    guard let self, isForeground else { return }
                    now = Date()
                    guard session.isMonitoring else { continue }
                    // Recompute from local time each tick, including timezone and power changes.
                    let target = (lastReadDate ?? .distantPast).addingTimeInterval(
                        RefreshPolicy.interval(at: now, calendar: .current,
                                               lowPower: ProcessInfo.processInfo.isLowPowerModeEnabled))
                    nextReadDate = target
                    if now >= target || (lastReadDate.map { $0 > now } ?? false) {
                        await refresh()
                    }
                }
            }
        } else {
            scheduleBackgroundRefresh()
        }
    }

    func backgroundRefresh() async {
        guard UserDefaults.standard.bool(forKey: Self.enabledKey), !isDemo else { return }
        if session.isMonitoring { await refresh() }
        else { await resumeLive() }
        scheduleBackgroundRefresh()
    }

    /// HealthKit can launch the process without activating a scene or delivering
    /// a WatchKit refresh task. Register synchronously in didFinishLaunching.
    func restoreAtLaunch() {
        guard hasStarted, !isDemo else { return }
        observeLiveData()
    }

    private func resumeLive() async {
        let token = generation
        observeLiveData()
        await session.resume()
        guard generation == token, session.isMonitoring, !isDemo else { return }
        recordRefresh()
    }

    private func observeLiveData() {
        liveProvider.startObserving { [weak self] in
            await self?.backgroundRefresh()
        }
    }

    private func recordRefresh() {
        now = Date()
        lastReadDate = now
        history = StressEstimator.history(session.snapshot, now: now)
        nextReadDate = now.addingTimeInterval(
            RefreshPolicy.interval(at: now, calendar: .current,
                                   lowPower: ProcessInfo.processInfo.isLowPowerModeEnabled))
    }

    private func scheduleBackgroundRefresh() {
        guard hasStarted, !isDemo else { return }
        let token = generation
        let date = Date().addingTimeInterval(
            RefreshPolicy.interval(at: Date(), calendar: .current,
                                   lowPower: ProcessInfo.processInfo.isLowPowerModeEnabled))
        WKApplication.shared().scheduleBackgroundRefresh(withPreferredDate: date, userInfo: nil) { [weak self] error in
            let failed = error != nil
            Task { @MainActor in
                guard let self, self.generation == token else { return }
                self.backgroundNotice = failed ? "后台更新暂不可用，打开应用可重新读取。" : nil
            }
        }
    }
}
