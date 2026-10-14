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

    /// The app went to the background: a backup if one is due, inside the few seconds iOS grants.
    static func appDidEnterBackground(_ model: AppModel) {
        guard model.hasCloudBackup else { return }
        scheduleDaily()
        let id = UIApplication.shared.beginBackgroundTask(withName: "drive-backup")
        Task {
            try? await Task.sleep(for: .seconds(1)) // let the draft autosave land first
            await model.syncDrive()
            await model.backUpIfDue()
            UIApplication.shared.endBackgroundTask(id)
        }
    }

    private static func run(_ box: TaskBox, model: AppModel) {
        scheduleDaily()
        let work = Task {
            await model.syncDrive()
            await model.backUpIfDue()
            box.task.setTaskCompleted(success: true)
        }
        box.task.expirationHandler = { work.cancel() }
    }

    /// `BGTask` isn't `Sendable`; it is only touched on the main queue.
    private final class TaskBox: @unchecked Sendable {
        let task: BGTask
        init(task: BGTask) { self.task = task }
    }
}
