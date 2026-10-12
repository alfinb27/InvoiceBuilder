import Foundation
import InvoiceCore
import Observation
import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    /// `.invoicebackup` (`spec/backup.md` §6), declared in the app's Info.plist.
    static let invoiceBackup = UTType(exportedAs: "com.invoicebuilder.backup", conformingTo: .json)
}

/// Settings → Backup, and "Restore from a backup" in onboarding (`spec/backup.md`). Works without a `Session`, so a
/// new device can restore before any business exists.
@MainActor @Observable
final class BackupViewModel {
    struct State {
        var status: BackupStatus?
        /// An export ready to save or share.
        var export: BackupExport?
        var showsExporter = false
        var showsImporter = false
        /// A file that passed validation, waiting for the user to confirm (§4 step 2).
        var pendingRestore: PendingRestore?
        var isWorking = false
        var errorMessage: String?
        var didRestore = false
        /// With sync on, a restore replaces the data on every device (`spec/backup.md` §4 step 2).
        var syncOn = false
    }

    struct PendingRestore: Identifiable {
        let id = UUID()
        let preview: BackupPreview
    }

    var state = State()

    private let dependencies: AppDependencies
    private let deviceID: String
    private let appVersion: String
    /// Called after a restore committed: drop caches and rebuild the app from the database (§4 step 5).
    private let onRestored: @MainActor () async -> Void

    init(dependencies: AppDependencies, deviceID: String, appVersion: String = AppInfo.version,
         onRestored: @escaping @MainActor () async -> Void) {
        self.dependencies = dependencies
        self.deviceID = deviceID
        self.appVersion = appVersion
        self.onRestored = onRestored
    }

    var today: LocalDate { dependencies.time.today() }

    var isDue: Bool { state.status?.isDue(today: today) ?? false }

    var lastBackupText: String {
        BackupText.lastBackup(days: state.status?.daysSinceLastBackup(today: today))
    }

    /// Keeps `status` and `syncOn` current.
    func observe() async {
        async let backup: Void = observeBackup()
        async let sync: Void = observeSync()
        _ = await (backup, sync)
    }

    private func observeBackup() async {
        do {
            for try await status in dependencies.backup.observeStatus() { state.status = status }
        } catch {
            // The stream only fails with the database; the last value stays.
        }
    }

    private func observeSync() async {
        for await status in dependencies.sync.observeStatus() {
            state.syncOn = status != .off && status != .unavailable
        }
    }

    // MARK: Export (§2)

    /// Builds the file; the view then shows the exporter or the share sheet.
    func prepareExport() async -> BackupExport? {
        state.isWorking = true
        defer { state.isWorking = false }
        do {
            let file = try await dependencies.backup.makeBackup(app: .init(platform: "ios", version: appVersion))
            let export = try BackupExport(file: file, today: today)
            state.export = export
            return export
        } catch {
            state.errorMessage = BackupText.exportFailed
            return nil
        }
    }

    func saveToFiles() async {
        if await prepareExport() != nil { state.showsExporter = true }
    }

    /// The exporter or the share sheet finished; only a completed save counts as a backup.
    func exportFinished(completed: Bool) async {
        guard completed else { return }
        try? await dependencies.backup.recordBackup(at: dependencies.time.now())
    }

    // MARK: Restore (§4)

    func importFinished(_ result: Result<URL, any Error>) async {
        switch result {
        case .success(let url): await open(url)
        case .failure: state.errorMessage = BackupText.unreadable
        }
    }

    /// A file picked, opened from another app or dropped onto Settings (§6).
    func open(_ url: URL) async {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let bytes = try? Data(contentsOf: url) else {
            state.errorMessage = BackupText.unreadable
            return
        }
        load(bytes)
    }

    func load(_ bytes: Data) {
        switch BackupCodec.validate(bytes, appSchemaVersion: dependencies.backup.schemaVersion) {
        case .success(let preview): state.pendingRestore = PendingRestore(preview: preview)
        case .failure(let error): state.errorMessage = BackupText.message(for: error.code)
        }
    }

    func cancelRestore() {
        state.pendingRestore = nil
    }

    func confirmRestore() async {
        guard let pending = state.pendingRestore else { return }
        state.isWorking = true
        defer { state.isWorking = false }
        do {
            try await dependencies.backup.restore(pending.preview.file, deviceID: deviceID)
            state.pendingRestore = nil
            state.didRestore = true
            await onRestored()
        } catch {
            state.pendingRestore = nil
            state.errorMessage = BackupText.restoreFailed
        }
    }

    func dismissError() {
        state.errorMessage = nil
    }
}

/// An exported backup: the bytes, as a file in the temporary directory for the share sheet and as a document for
/// the exporter.
struct BackupExport: Equatable {
    let fileName: String
    let url: URL
    let document: BackupDocument

    init(file: BackupFile, today: LocalDate) throws {
        let data = try BackupCodec.encode(file)
        fileName = BackupFile.fileName(on: today)
        let folder = FileManager.default.temporaryDirectory.appending(path: "Backups")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        url = folder.appending(path: fileName)
        try data.write(to: url, options: [.atomic, .completeFileProtection])
        document = BackupDocument(data: data)
    }
}

struct BackupDocument: FileDocument, Equatable {
    static let readableContentTypes: [UTType] = [.invoiceBackup]

    var data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

enum AppInfo {
    static var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "0"
        let build = info?["CFBundleVersion"] as? String ?? "0"
        return "\(short) (\(build))"
    }
}

/// What the backup screens say (`spec/backup.md` §3, §5).
enum BackupText {
    static func lastBackup(days: Int?) -> String {
        switch days {
        case nil: "Never backed up"
        case 0?: "Last backup: today"
        case 1?: "Last backup: yesterday"
        case let days?: "Last backup: \(days) days ago"
        }
    }

    static func message(for code: BackupError.Code) -> String {
        switch code {
        case .notJSON, .notABackup:
            "This file isn't an InvoiceBuilder backup."
        case .newerFormat, .newerSchema:
            "This backup was made by a newer version of the app. Update the app, then try again."
        case .invalidRecord, .countMismatch, .duplicateID, .assetHashMismatch, .danglingReference:
            "This backup is damaged and can't be restored. Nothing was changed."
        }
    }

    static let unreadable = "The file couldn't be opened."
    static let exportFailed = "The backup couldn't be created. Try again."
    static let restoreFailed = "The backup couldn't be restored. Nothing was changed."
}
