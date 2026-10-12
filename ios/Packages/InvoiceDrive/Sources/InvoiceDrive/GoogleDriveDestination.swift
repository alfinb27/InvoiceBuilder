import Foundation
import InvoiceCore

/// Backups in a visible "InvoiceBuilder backups" folder of the user's Google Drive (`spec/backup.md` §7), through
/// Drive REST v3 with the `drive.file` scope: the app sees only the files it created.
public struct GoogleDriveDestination: CloudBackupDestination {
    static let api = URL(string: "https://www.googleapis.com/drive/v3/")!
    static let uploadAPI = URL(string: "https://www.googleapis.com/upload/drive/v3/")!
    static let folderName = "InvoiceBuilder backups"
    static let folderType = "application/vnd.google-apps.folder"
    static let fileType = "application/json"

    let auth: GoogleAuth
    let http: any HTTPClient

    public init(auth: GoogleAuth, http: any HTTPClient) {
        self.auth = auth
        self.http = http
    }

    // MARK: CloudBackupDestination

    public func connect() async throws -> String {
        try await auth.signIn()
        // `about` answers with any Drive scope, so no extra profile scope is needed for the email.
        struct About: Decodable {
            struct User: Decodable { let emailAddress: String? }
            let user: User?
        }
        let about: About = try await json(get("about", ["fields": "user(emailAddress)"]))
        return about.user?.emailAddress ?? "Google Drive"
    }

    public func disconnect() async {
        await auth.signOut()
    }

    public func folder(knownID: String?) async throws -> String {
        if let knownID {
            struct Meta: Decodable { let id: String; let trashed: Bool? }
            do {
                let meta: Meta = try await json(get("files/\(knownID)", ["fields": "id,trashed"]))
                if meta.trashed != true { return meta.id }
            } catch DriveFailure.notFound {}
        }
        let query = "mimeType = '\(Self.folderType)' and name = '\(Self.folderName)' and trashed = false and 'root' in parents"
        let found: FileList = try await json(get("files", ["q": query, "orderBy": "createdTime",
                                                             "fields": "files(id)", "spaces": "drive"]))
        if let first = found.files.first { return first.id }
        struct Created: Decodable { let id: String }
        var request = try await authorized(URL(string: "files?fields=id", relativeTo: Self.api)!)
        request.httpMethod = "POST"
        request.setValue("application/json; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "name": Self.folderName, "mimeType": Self.folderType, "parents": ["root"],
        ])
        let created: Created = try await json(request)
        return created.id
    }

    public func list(folderID: String) async throws -> [CloudBackupEntry] {
        var entries: [CloudBackupEntry] = []
        var pageToken: String?
        repeat {
            var query = ["q": "'\(folderID)' in parents and trashed = false", "pageSize": "200", "spaces": "drive",
                         "fields": "nextPageToken,files(id,name,appProperties)"]
            query["pageToken"] = pageToken
            let page: FileList = try await json(get("files", query))
            entries += page.files.map { CloudBackupEntry(id: $0.id, name: $0.name ?? "", properties: $0.appProperties ?? [:]) }
            pageToken = page.nextPageToken
        } while pageToken != nil
        return entries
    }

    /// A resumable upload (one session request, then the bytes), so any backup size works.
    public func upload(_ data: Data, name: String, properties: [String: String], target: CloudBackupTarget,
                       folderID: String) async throws -> String {
        var metadata: [String: Any] = ["name": name, "mimeType": Self.fileType, "appProperties": properties]
        let path: String, method: String
        switch target {
        case .create:
            metadata["parents"] = [folderID]
            (path, method) = ("files", "POST")
        case .update(let id):
            (path, method) = ("files/\(id)", "PATCH")
        }
        var start = try await authorized(URL(string: "\(path)?uploadType=resumable&fields=id", relativeTo: Self.uploadAPI)!)
        start.httpMethod = method
        start.setValue("application/json; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        start.setValue(Self.fileType, forHTTPHeaderField: "X-Upload-Content-Type")
        start.setValue(String(data.count), forHTTPHeaderField: "X-Upload-Content-Length")
        start.httpBody = try JSONSerialization.data(withJSONObject: metadata)
        let (_, session) = try await send(start)
        guard let location = session.value(forHTTPHeaderField: "Location").flatMap(URL.init(string:)) else {
            throw CloudBackupError.other
        }
        var put = URLRequest(url: location)
        put.httpMethod = "PUT"
        put.setValue(Self.fileType, forHTTPHeaderField: "Content-Type")
        put.httpBody = data
        struct Uploaded: Decodable { let id: String }
        let uploaded: Uploaded = try await json(put)
        return uploaded.id
    }

    public func download(id: String) async throws -> Data {
        try await send(get("files/\(id)", ["alt": "media"])).0
    }

    public func delete(id: String) async throws {
        var request = try await authorized(URL(string: "files/\(id)", relativeTo: Self.api)!)
        request.httpMethod = "DELETE"
        do { _ = try await send(request) } catch DriveFailure.notFound {}
    }

    // MARK: Requests

    struct FileList: Decodable {
        struct File: Decodable {
            let id: String
            let name: String?
            let appProperties: [String: String]?
        }
        let files: [File]
        let nextPageToken: String?
    }

    /// A 404 from Drive (a file or folder that is gone); everything else is a `CloudBackupError`.
    enum DriveFailure: Error { case notFound }

    private func get(_ path: String, _ query: [String: String]) async throws -> URLRequest {
        var components = URLComponents(url: URL(string: path, relativeTo: Self.api)!, resolvingAgainstBaseURL: true)!
        components.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        return try await authorized(components.url!)
    }

    private func authorized(_ url: URL) async throws -> URLRequest {
        var request = URLRequest(url: url.absoluteURL)
        request.setValue("Bearer \(try await auth.accessToken())", forHTTPHeaderField: "Authorization")
        return request
    }

    private func json<Value: Decodable>(_ request: URLRequest) async throws -> Value {
        let (data, _) = try await send(request)
        do { return try JSONDecoder().decode(Value.self, from: data) } catch { throw CloudBackupError.other }
    }

    /// Sends with the current token; on a 401 refreshes once and retries (the access token expired early).
    private func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        var (data, response) = try await http.send(request)
        if response.statusCode == 401 {
            var retry = request
            retry.setValue("Bearer \(try await auth.accessToken(forceRefresh: true))", forHTTPHeaderField: "Authorization")
            (data, response) = try await http.send(retry)
        }
        switch response.statusCode {
        case 200..<300: return (data, response)
        case 404: throw DriveFailure.notFound
        default: throw GoogleError.map(status: response.statusCode, data: data)
        }
    }
}
