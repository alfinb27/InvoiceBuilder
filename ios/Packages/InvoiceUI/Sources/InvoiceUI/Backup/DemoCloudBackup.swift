import Foundation
import InvoiceCore

/// An in-memory Google Drive for UI tests and screenshots (`-fakeDrive`): sign-in always succeeds and files live
/// until the app quits.
actor DemoCloudBackup: CloudBackupDestination {
    static let shared = DemoCloudBackup()

    private struct File {
        var name: String
        var properties: [String: String]
        var data: Data
        var folder: String
    }

    private var files: [String: File] = [:]
    private var folders: [String] = []
    private var counter = 0

    func connect() async throws -> String { "you@example.com" }

    func disconnect() async {}

    func folder(knownID: String?) async throws -> String {
        if let knownID, folders.contains(knownID) { return knownID }
        if let first = folders.first { return first }
        let id = nextID("folder")
        folders.append(id)
        return id
    }

    func list(folderID: String) async throws -> [CloudBackupEntry] {
        files.filter { $0.value.folder == folderID }
            .map { CloudBackupEntry(id: $0.key, name: $0.value.name, properties: $0.value.properties) }
    }

    func upload(_ data: Data, name: String, properties: [String: String], target: CloudBackupTarget,
                folderID: String) async throws -> String {
        let id: String
        switch target {
        case .create: id = nextID("file")
        case .update(let existing): id = existing
        }
        files[id] = File(name: name, properties: properties, data: data, folder: folderID)
        return id
    }

    func download(id: String) async throws -> Data {
        guard let file = files[id] else { throw CloudBackupError.other }
        return file.data
    }

    func delete(id: String) async throws {
        files[id] = nil
    }

    private func nextID(_ prefix: String) -> String {
        counter += 1
        return "\(prefix)-\(counter)"
    }
}
