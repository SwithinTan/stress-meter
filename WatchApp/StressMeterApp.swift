import SwiftUI
import WatchKit

@main
struct StressMeterApp: App {
    @WKApplicationDelegateAdaptor(StressApplicationDelegate.self) private var delegate
    @Environment(\.scenePhase) private var scenePhase
    @State private var model = AppModel.shared

    var body: some Scene {
        WindowGroup {
            RootView(model: model)
                .tint(Palette.mint)
                .onChange(of: scenePhase, initial: true) { _, phase in
                    model.sceneChanged(active: phase == .active)
                }
        }
    }
}

@MainActor
final class StressApplicationDelegate: NSObject, WKApplicationDelegate {
    func applicationDidFinishLaunching() {
        AppModel.shared.restoreAtLaunch()
    }

    func handle(_ backgroundTasks: Set<WKRefreshBackgroundTask>) {
        for task in backgroundTasks {
            if let refresh = task as? WKApplicationRefreshBackgroundTask {
                let completion = BackgroundCompletion(task: refresh)
                let work = Task {
                    await AppModel.shared.backgroundRefresh()
                    completion.finish()
                }
                Task {
                    try? await Task.sleep(for: .seconds(10))
                    guard !completion.isFinished else { return }
                    work.cancel()
                    completion.finish()
                }
            } else if let snapshot = task as? WKSnapshotRefreshBackgroundTask {
                snapshot.setTaskCompleted(restoredDefaultState: true,
                                          estimatedSnapshotExpiration: .distantFuture, userInfo: nil)
            } else {
                task.setTaskCompletedWithSnapshot(false)
            }
        }
    }
}

@MainActor
private final class BackgroundCompletion {
    let task: WKApplicationRefreshBackgroundTask
    private(set) var isFinished = false

    init(task: WKApplicationRefreshBackgroundTask) { self.task = task }

    func finish() {
        guard !isFinished else { return }
        isFinished = true
        task.setTaskCompletedWithSnapshot(false)
    }
}
