# Stress Meter v1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 交付可以在 Xcode 打开的独立中文 watchOS 压力趋势应用，接入真实健康数据，具有诚实的数据状态与时段刷新策略。

**Architecture:** SwiftUI watch app consumes a pure Swift StressCore package. HealthKit supplies bounded snapshots; each successful refresh replaces the previous snapshot so deletions and permission changes cannot retain obsolete current results. Background delivery and refresh are opportunistic, foreground refresh follows a clock policy.

**Tech Stack:** Swift 6, SwiftUI, HealthKit, WatchKit, Swift Package Manager, XCTest. No external runtime dependencies or backend.

**Spec:** `docs/design/2026-09-26-watchos-stress-meter-proposal.md` (approved with dynamic refresh amendment).

## Global Constraints

- Apple Watch Series 11; watchOS 26 minimum; 中文界面；所有健康数据本地处理。
- 只读 HealthKit，无伪造运动会话，无常驻后台承诺，不把 UI 刷新标为新测量。
- 前台 07:00–22:59 每 5 分钟、23:00–06:59 每 10 分钟查询；低电量模式 10 分钟。进入前台补查，HealthKit 通知可触发补查；后台请求不保证时限。
- 使用 SDNN，同一来源建立基线；只提供相对等级，不宣称医学准确率或压力百分比。
- 模拟数据仅通过显式演示入口启动，界面持续标明演示；不能自动回退到演示。
- 无数据、过期、活动影响、基线不足、查询失败各有可见状态；历史不插值。
- 在当前仓库的 `codex/stress-meter-v1` 分支实现；不创建另一个无既有代码可保护的 checkout，不推送或发布。

## Review Focus

- 清除/暂停后到达的旧异步结果不得重新写入健康数据或恢复监测（Task 2）。
- 新一次空查询必须替换旧数据，撤销权限不能留下“当前”结果（Task 2）。
- 低电量、跨午夜和时区变化仍按本地时段计算下一次请求（Task 1/2）。
- 系统中断或查询未回调时，后台任务和 observer 回调必须有限时结束（Task 2）。
- 最新样本有运动干扰时不能回退使用更老“平静”数据伪装当前状态（Task 1）。

## File structure and shared interfaces

- `Package.swift`, `Sources/StressCore/Models.swift`: `MetricSample(id:String,value:Double,date:Date,source:String,motion:MotionContext)`, `ActivityWindow(start:Date,end:Date)`, `HealthSnapshot(hrv:[MetricSample],heartRate:[MetricSample],workouts:[ActivityWindow])`; Codable/Equatable/Sendable.
- `Sources/StressCore/StressEstimator.swift`: `StressEstimator.assess(_ snapshot:HealthSnapshot, now:Date) -> Assessment`; `history(_ snapshot:HealthSnapshot, now:Date) -> [TrendPoint]`.
- `Assessment` includes `state: AssessmentState` (`noData`, `calibrating`, `stale`, `activity`, `ready`), `level: StressLevel?` (`lower`, `usual`, `elevated`), `sampleDate:Date?`, `hrv:Double?`, `heartRate:MetricSample?`, `baselineCount:Int`, `baselineDays:Int`, `contextLimited:Bool`.
- `TrendPoint` includes `id:String`, `date:Date`, `level:StressLevel`.
- `Sources/StressCore/RefreshPolicy.swift`: `RefreshPolicy.interval(at:Date, calendar:Calendar, lowPower:Bool) -> TimeInterval`.
- `Sources/StressCore/MonitoringSession.swift`: injectable `HealthDataProviding` protocol (`requestAuthorization() async throws`, `fetchSnapshot(now:Date) async throws -> HealthSnapshot`), main-actor session with generation invalidation, refresh coalescing, empty replacement, explicit stop/clear and visible error. No UI dependency.
- `WatchApp/HealthKitProvider.swift`: live provider, bounded queries and timeouts, metadata filtering; observer completion once; no timer-based sensor promises.
- `WatchApp/StressMeterApp.swift`, `WatchApp/AppModel.swift`: lifecycle, foreground timer, WatchKit background delegate, monitoring preferences and error handling.
- `WatchApp/Views/`: dashboard, trend, method/settings and onboarding; compact colored arc, accessible text, timestamp independent from refresh time.
- `StressMeter.xcodeproj/`, `WatchApp/Info.plist`, `WatchApp/StressMeter.entitlements`, `WatchApp/Assets.xcassets/`: standalone watch target and resources.
- `Tests/StressCoreTests/`: deterministic behavioral tests for estimator, scheduling and async session.
- `README.md`, `docs/verification.md`: setup, model limitations, exact tested commands, real-device checklist.

### Task 1: Pure Swift estimate and refresh policy

- [x] Write failing XCTest fixtures then run `swift test` to establish missing implementation.
- [x] Implement validation/deduplication: reject nonfinite/nonpositive HRV, implausible HR outside 25…240, dates in future, samples older than 28 days; preserve newest unique sample per id. Never mix sources in baseline.
- [x] Assessment uses newest valid HRV, stale after 20 minutes (engineering freshness bound). Latest measurement inside workout or within 30 minutes after it, or adjacent HR marked active within 5 minutes, yields activity state. Keep latest timestamp even when not estimable.
- [x] Baseline excludes current sample, last 30 minutes, activity-contaminated samples; use same source from previous 28 days, minimum 20 samples spanning 5 UTC days. Engineering thresholds: log-SDNN robust z=(median(log baseline)-log current)/max(1.4826*MAD,0.15); z>=1 elevated, z<=-1 lower, else usual. No clinical claims; limited activity context visible.
- [x] History evaluates each sample using only earlier baseline; keep 7 days and at most 200 points, only ready points, no interpolation. Test no future leakage, deletion/snapshot replacement, duplicate ids, invalid values, clock rollback, stale vs activity, source isolation, minimum baseline.
- [x] Implement refresh policy with 5/10-minute behavior and test day/night boundaries, low power, alternate timezone.
- [x] Run `swift test`; expected all tests pass without external SDK dependencies.

### Task 2: Health data and lifecycle

- [x] Write failing session tests for coalescing refreshes, clear during pending fetch, empty replacement and recoverable error. Use a controllable provider and await observable state, no arbitrary sleeps.
- [x] Implement session and explicit demo provider; demo never writes to HealthKit and is never enabled automatically.
- [x] Implement HealthKit requests for SDNN, heart rate and workouts only. Read 28-day HRV (bounded), last-hour HR, 28-day workout context; exclude user-entered metrics. All query paths have cancellation/timeout and no force unwrap.
- [x] Run watchOS typecheck/build and session tests; resolve Swift concurrency and platform API issues from actual compiler output.
- [x] Hook hourly HealthKit delivery and best-effort WatchKit refresh; complete callbacks even if reading fails, coalesce duplicate notifications and stop queries on disable. No continuous runtime or workout capability.
- [x] User monitoring preference survives relaunch; live samples remain in memory and are requeried, avoiding retained raw health caches. Clear means pause and remove in-memory results; HealthKit source records untouched. Document this minimal-storage implementation choice.

### Task 3: Native app and presentation

- [x] Build standalone Watch app target using the package; configure read explanation, HealthKit entitlement and background delivery.
- [x] Dashboard shows estimate, current sample age, available HR/HRV, freshness and data quality. Onboarding has live authorization and explicit demo entry. Trend is actual discrete points; settings explains method, cadence, source, stop and clear.
- [x] Foreground timer only while active; entering foreground refreshes and reevaluates stale state. Scene inactivation cancels timer. Time-based display aging must not refresh sample timestamps.
- [x] Include accessible labels, Dynamic Type scroll layouts, reduced-motion-friendly styling and no continual decorative animation. Add an original simple icon asset and reproducible geometry generator.
- [x] Build watch simulator and device generic targets with signing disabled; install/launch on Series 11 42/46mm simulated devices and capture screenshots. Welcome/demo layouts inspected; no-data behavior verified in core tests. Real permission UI and sensor delivery remain in the device checklist.

### Task 4: Review and delivery

- [x] Independent review of runtime/state handling, estimator boundaries and app target configuration; resolve actionable findings with focused regressions.
- [x] Run final `swift test` plus generic watch simulator/device builds. Verify compiled artifacts exist; record platform/tooling limitations honestly.
- [x] Write Chinese README with Xcode opening, bundle id/team setup and real-watch install steps. Provide model caveats and 24-hour real-device verification checklist.
- [x] Mark plan execution state, link the Xcode project and evidence; no claim of Series 11 stability until device validation occurs.

## Execution record — 2026-10-12

The implementation and local review are complete. The user explicitly authorized development after approving the design and dynamic cadence; execution continued without another design approval loop.

- Core: 30 deterministic tests, including a regression that prevents history from plotting an HRV sample rejected by the dashboard for adjacent activity.
- Provider: five executable cancellation/completion checks.
- Review fixes: synchronous observer registration at cold launch, 10-second outer background completion limit, consistent history activity filtering, zsh test invocation. Scoped re-review found no remaining actionable defects.
- Storage decision: raw health records stay in memory; only the enabled preference is persisted. Each query replaces the snapshot. This minimizes retained health data; history must be reconstructed on launch.
- UI: 42mm first-screen layout reduced so the estimate and sample age remain visible. Explicit demo data never substitutes for unavailable live data.
- Engineering rules: UTC baseline day counts; stale after 20 minutes takes precedence over activity; baseline strictly precedes the current sample by more than 30 minutes. These are model rules, not clinical thresholds.
- Device acceptance and 24-hour wear testing remain incomplete; see `docs/verification.md`. No App Store submission or remote push is part of this delivery.
