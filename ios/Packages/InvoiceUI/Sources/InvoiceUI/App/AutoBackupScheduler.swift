import BackgroundTasks
import InvoiceCore
import UIKit

/// When automatic Google Drive backups run (`spec/backup.md` §7.2): as the app goes to the background, and once a
/// day from a `BGProcessingTask` that needs the network (the OS picks the moment). The identifier is listed in
/// App-Info.plist's `BGTaskSchedulerPermittedIdentifiers`.
@MainActor
enum AutoBackupScheduler {
    static let identifier = "app.invoicebuilder.drivebackup"
    private static var registered = false

    /// Once per process, during launch (the system requires it before launch finishes).
    static func register(_ model: AppModel) {
        guard !registered else { return }
        registered = true
        BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: .main) { task in
            let box = TaskBox(task: task)
            MainActor.assumeIsolated { run(box, model: model) }
        }
    }

    /// Asks for the next daily run.
    static func scheduleDaily() {
        let request = BGProcessingTaskRequest(identifier: identifier)
        request.requiresNetworkConnectivity = true
        request.earliestBeginDate = Date(timeIntervalSinceNow: 12 * 60 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }

    /// The app went to the background: a backup if one is due, inside the time iOS grants (about 30 s). If that runs
    /// out first, the work is cancelled (its requests stop; the next trigger tries again) and the task still ends.
    static func appDidEnterBackground(_ model: AppModel) {
        guard model.hasCloudBackup else { return }
        scheduleDaily()
        let assertion = BackgroundAssertion(name: "drive-backup")
        let work = Task {
            try? await Task.sleep(for: .seconds(1)) // let the draft autosave land first
            await model.syncDrive()
            await model.backUpIfDue()
            assertion.end()
        }
        assertion.onExpiry = { work.cancel() }
    }

    private static func run(_ box: TaskBox, model: AppModel) {
        scheduleDaily()
        let work = Task {
            await model.syncDrive()
            await model.backUpIfDue()
            box.task.setTaskCompleted(success: !Task.isCancelled) // cancelled: the system expired the task
        }
        box.task.expirationHandler = { work.cancel() }
    }

    /// `BGTask` isn't `Sendable`; it is only touched on the main queue.
    private final class TaskBox: @unchecked Sendable {
        let task: BGTask
        init(task: BGTask) { self.task = task }
    }
}

/// A `beginBackgroundTask` that ends exactly once: from `end()` when the work is done, or when iOS says the time is
/// up, after `onExpiry` (which cancels the work). iOS terminates an app whose background task outlives its time, so
/// the expiration handler must always end it.
@MainActor
final class BackgroundAssertion {
    typealias Begin = @MainActor (_ name: String, _ expiry: @escaping @MainActor @Sendable () -> Void) -> UIBackgroundTaskIdentifier
    typealias End = @MainActor (UIBackgroundTaskIdentifier) -> Void

    var onExpiry: () -> Void = {}
    private var id = UIBackgroundTaskIdentifier.invalid
    private let endTask: End

    init(name: String,
         begin: Begin = { name, expiry in UIApplication.shared.beginBackgroundTask(withName: name, expirationHandler: expiry) },
         end: @escaping End = { UIApplication.shared.endBackgroundTask($0) }) {
        endTask = end
        id = begin(name) { [self] in
            onExpiry()
            self.end()
        }
    }

    /// Safe to call more than once; only the first call ends the task.
    func end() {
        guard id != .invalid else { return }
        endTask(id)
        id = .invalid
    }
}
