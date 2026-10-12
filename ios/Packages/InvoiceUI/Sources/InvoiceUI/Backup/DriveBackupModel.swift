import Foundation
import InvoiceCore
import Observation

/// The Google Drive part of Settings → Backup and of onboarding's restore (`spec/backup.md` §7): connect, back up
/// now, the last result, disconnect, and the list of backups to restore from.
@MainActor @Observable
final class DriveBackupModel {
    struct State {
        var cloud = CloudBackupState()
        var isWorking = false
        /// The restore list (§7.6): nil until loaded.
        var backups: [CloudBackupEntry]?
        var showsBackups = false
        var errorMessage: String?
    }

    var state = State()

    private let runner: AutoBackupRunner
    private let store: any CloudBackupStateStore
    private let time: TimeSource

    init(runner: AutoBackupRunner, store: any CloudBackupStateStore, time: TimeSource) {
        self.runner = runner
        self.store = store
        self.time = time
    }

    var isConnected: Bool { state.cloud.isConnected }

    /// Under the toggle: the account, then the last result.
    var statusText: String {
        guard isConnected else { return DriveBackupText.notConnected }
        if let error = state.cloud.lastError { return DriveBackupText.failed(error) }
        return DriveBackupText.lastBackup(at: state.cloud.lastBackupAt, now: time.now())
    }

    var hasError: Bool { isConnected && state.cloud.lastError != nil }

    func observe() async {
        do {
            for try await cloud in store.observeCloudBackupState() { state.cloud = cloud }
        } catch {
            // The stream only fails with the database; the last value stays.
        }
    }

    /// §7.1: sign in, find or create the folder, back up at once.
    func connect() async {
        await work {
            try await runner.connect()
        }
    }

    func backUpNow() async {
        await work { try await runner.backUpNow() }
    }

    /// §7.1: files stay in Drive.
    func disconnect() async {
        await work { try await runner.disconnect() }
    }

    /// §7.6: signs in first when needed, then lists the backups, newest first.
    func showBackups() async {
        await work {
            if !(try await store.cloudBackupState().isConnected) { try await runner.connect() }
            state.backups = try await runner.list()
            state.showsBackups = true
        }
    }

    /// Downloads a backup for the restore flow (§4 step 1).
    func download(_ entry: CloudBackupEntry) async -> Data? {
        var bytes: Data?
        await work { bytes = try await runner.download(entry) }
        return bytes
    }

    func dismissError() {
        state.errorMessage = nil
    }

    private func work(_ body: () async throws -> Void) async {
        state.isWorking = true
        defer { state.isWorking = false }
        do {
            try await body()
        } catch CloudBackupError.cancelled {
            // The user closed Google's page: nothing to say.
        } catch {
            state.errorMessage = DriveBackupText.failed((error as? CloudBackupError) ?? .other)
        }
        if let cloud = try? await store.cloudBackupState() { state.cloud = cloud }
    }
}

/// What the Google Drive rows say (`spec/backup.md` §7.5–7.6).
enum DriveBackupText {
    static let notConnected = "Back up automatically to your own Google Drive. Restore on any phone, iPhone or Android."

    static func failed(_ error: CloudBackupError) -> String {
        switch error {
        case .signedOut: "Couldn't back up to Google Drive: you're signed out. Connect again to carry on."
        case .quotaExceeded: "Couldn't back up to Google Drive: your Google Drive is full."
        case .networkUnavailable: "Couldn't back up to Google Drive: no internet connection. It will try again."
        case .cancelled, .other: "Couldn't back up to Google Drive. It will try again later."
        }
    }

    static func lastBackup(at timestamp: Int64?, now: Int64, calendar: Calendar = .current) -> String {
        guard let timestamp else { return "Not backed up to Google Drive yet" }
        return "Last backup to Google Drive: \(when(timestamp, now: now, calendar: calendar))"
    }

    /// "today at 14:02", "yesterday at 09:10" or "8 Oct 2026 at 18:30".
    static func when(_ timestamp: Int64, now: Int64, calendar: Calendar = .current) -> String {
        let date = Date(timeIntervalSince1970: Double(timestamp) / 1000)
        let reference = Date(timeIntervalSince1970: Double(now) / 1000)
        let time = date.formatted(date: .omitted, time: .shortened)
        if calendar.isDate(date, inSameDayAs: reference) { return "today at \(time)" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: reference),
           calendar.isDate(date, inSameDayAs: yesterday) { return "yesterday at \(time)" }
        return "\(date.formatted(date: .abbreviated, time: .omitted)) at \(time)"
    }

    /// The restore list's first line: when, and from which device.
    static func title(_ entry: CloudBackupEntry, now: Int64) -> String {
        let platform = entry.platform == "android" ? "Android" : entry.platform == "ios" ? "iOS" : nil
        let device = [entry.deviceName, platform.map { "(\($0))" }].compactMap { $0 }.joined(separator: " ")
        let time = entry.createdAt.map { when($0, now: now) } ?? entry.name
        return device.isEmpty ? time.capitalizedFirst : "\(time.capitalizedFirst) · \(device)"
    }

    /// The second line: businesses and counts.
    static func detail(_ entry: CloudBackupEntry) -> String {
        var parts: [String] = []
        if let businesses = entry.businesses, !businesses.isEmpty { parts.append(businesses) }
        if let invoices = entry.invoiceCount { parts.append(invoices == 1 ? "1 invoice" : "\(invoices) invoices") }
        if let clients = entry.clientCount { parts.append(clients == 1 ? "1 client" : "\(clients) clients") }
        return parts.joined(separator: " · ")
    }
}

private extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
