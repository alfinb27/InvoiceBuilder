import Foundation
import InvoiceCore
import Synchronization
import Testing
@testable import InvoiceDrive

/// Google sign-in and Drive requests against a scripted server (`spec/backup.md` §7, ADR-0021).
@Suite("Google Drive")
struct GoogleDriveTests {
    static let config = GoogleOAuthConfig(clientID: "1234-abc.apps.googleusercontent.com")

    /// Answers each request from `handler` and records it.
    final class FakeHTTP: HTTPClient, @unchecked Sendable {
        struct Reply {
            var status = 200
            var headers: [String: String] = [:]
            var body = Data("{}".utf8)

            static func json(_ object: Any, status: Int = 200) -> Reply {
                Reply(status: status, body: try! JSONSerialization.data(withJSONObject: object))
            }
        }

        let requests = Mutex<[URLRequest]>([])
        let handler: @Sendable (URLRequest) throws -> Reply

        init(_ handler: @escaping @Sendable (URLRequest) throws -> Reply) {
            self.handler = handler
        }

        func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
            requests.withLock { $0.append(request) }
            let reply = try handler(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: reply.status, httpVersion: "HTTP/1.1",
                                           headerFields: reply.headers)!
            return (reply.body, response)
        }

        var sent: [URLRequest] { requests.withLock { $0 } }
    }

    final class MemoryStore: GoogleTokenStore, @unchecked Sendable {
        let tokens = Mutex<GoogleTokens?>(nil)
        init(_ initial: GoogleTokens? = nil) { tokens.withLock { $0 = initial } }
        func load() -> GoogleTokens? { tokens.withLock { $0 } }
        func save(_ value: GoogleTokens) { tokens.withLock { $0 = value } }
        func delete() { tokens.withLock { $0 = nil } }
    }

    /// Returns Google's redirect with the code and the state the request carried.
    final class FakeBrowser: WebAuthenticator, @unchecked Sendable {
        let seen = Mutex<URL?>(nil)
        var answer: (@Sendable (URL) -> URL)?

        func authenticate(url: URL, callbackScheme: String) async throws -> URL {
            seen.withLock { $0 = url }
            if let answer { return answer(url) }
            let state = URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!.first { $0.name == "state" }!.value!
            return URL(string: "\(callbackScheme):/oauth2redirect?state=\(state)&code=the-code")!
        }
    }

    static let now = Date(timeIntervalSince1970: 1_791_600_000)
    static let fresh = GoogleTokens(refreshToken: "refresh-1", accessToken: "access-1",
                                    expiresAt: now.timeIntervalSince1970 + 3600)

    func auth(_ http: FakeHTTP, store: MemoryStore = MemoryStore(fresh), browser: FakeBrowser = FakeBrowser())
        -> GoogleAuth {
        GoogleAuth(config: Self.config, http: http, store: store, authenticator: browser, now: { Self.now },
                   randomBytes: { Array(repeating: 7, count: $0) })
    }

    static func form(_ request: URLRequest) -> [String: String] {
        let text = String(decoding: request.httpBody ?? Data(), as: UTF8.self)
        return Dictionary(uniqueKeysWithValues: text.split(separator: "&").map { pair in
            let parts = pair.split(separator: "=", maxSplits: 1).map { String($0).removingPercentEncoding! }
            return (parts[0], parts.count > 1 ? parts[1] : "")
        })
    }

    // MARK: Sign-in

    @Test func signInUsesPKCEForTheOneScopeAndKeepsTheTokens() async throws {
        let http = FakeHTTP { request in
            #expect(request.url?.absoluteString == "https://oauth2.googleapis.com/token")
            return .json(["access_token": "access-new", "expires_in": 3599, "refresh_token": "refresh-new"])
        }
        let store = MemoryStore()
        let browser = FakeBrowser()
        try await auth(http, store: store, browser: browser).signIn()

        let page = try #require(browser.seen.withLock { $0 })
        let query = Dictionary(uniqueKeysWithValues: URLComponents(url: page, resolvingAgainstBaseURL: false)!
            .queryItems!.map { ($0.name, $0.value ?? "") })
        #expect(page.host == "accounts.google.com")
        #expect(query["scope"] == "https://www.googleapis.com/auth/drive.file")
        #expect(query["redirect_uri"] == "com.googleusercontent.apps.1234-abc:/oauth2redirect")
        #expect(query["code_challenge_method"] == "S256")
        let verifier = GoogleAuth.base64URL(Array(repeating: 7, count: 32))
        #expect(query["code_challenge"] == GoogleAuth.challenge(for: verifier))

        let exchange = Self.form(try #require(http.sent.first))
        #expect(exchange["grant_type"] == "authorization_code")
        #expect(exchange["code"] == "the-code")
        #expect(exchange["code_verifier"] == verifier)
        #expect(store.load()?.refreshToken == "refresh-new")
        #expect(store.load()?.expiresAt == Self.now.timeIntervalSince1970 + 3599)
    }

    @Test func aRedirectWithTheWrongStateIsRejected() async throws {
        let browser = FakeBrowser()
        browser.answer = { _ in URL(string: "com.googleusercontent.apps.1234-abc:/oauth2redirect?state=forged&code=x")! }
        let http = FakeHTTP { _ in .json([:]) }
        await #expect(throws: CloudBackupError.other) {
            try await auth(http, store: MemoryStore(), browser: browser).signIn()
        }
        #expect(http.sent.isEmpty)
    }

    @Test func anExpiredTokenIsRefreshed() async throws {
        let expired = GoogleTokens(refreshToken: "refresh-1", accessToken: "old", expiresAt: Self.now.timeIntervalSince1970 - 1)
        let store = MemoryStore(expired)
        let http = FakeHTTP { _ in .json(["access_token": "access-2", "expires_in": 3600]) }
        let token = try await auth(http, store: store).accessToken()
        #expect(token == "access-2")
        #expect(Self.form(http.sent[0])["grant_type"] == "refresh_token")
        #expect(store.load()?.refreshToken == "refresh-1") // Google keeps the refresh token
    }

    @Test func aRevokedGrantSignsOut() async throws {
        let expired = GoogleTokens(refreshToken: "refresh-1", accessToken: "old", expiresAt: 0)
        let store = MemoryStore(expired)
        let http = FakeHTTP { _ in .json(["error": "invalid_grant"], status: 400) }
        await #expect(throws: CloudBackupError.signedOut) { try await auth(http, store: store).accessToken() }
        #expect(store.load() == nil)
    }

    @Test func signingOutRevokesAndForgets() async throws {
        let store = MemoryStore(Self.fresh)
        let http = FakeHTTP { _ in .json([:]) }
        await auth(http, store: store).signOut()
        #expect(store.load() == nil)
        #expect(http.sent.first?.url?.absoluteString == "https://oauth2.googleapis.com/revoke")
        #expect(Self.form(http.sent[0])["token"] == "refresh-1")
    }

    // MARK: Drive

    func drive(_ http: FakeHTTP, store: MemoryStore = MemoryStore(fresh)) -> GoogleDriveDestination {
        GoogleDriveDestination(auth: auth(http, store: store), http: http)
    }

    @Test func theFolderIsReusedFoundOrCreated() async throws {
        // A known folder that still exists.
        var http = FakeHTTP { _ in .json(["id": "folder-1", "trashed": false]) }
        #expect(try await drive(http).folder(knownID: "folder-1") == "folder-1")

        // A trashed one: look for another, then create.
        http = FakeHTTP { request in
            switch (request.httpMethod ?? "GET", request.url!.path) {
            case ("GET", "/drive/v3/files/folder-1"): return .json(["id": "folder-1", "trashed": true])
            case ("GET", "/drive/v3/files"): return .json(["files": []])
            case ("POST", "/drive/v3/files"): return .json(["id": "folder-2"])
            default: Issue.record("unexpected \(request)"); return .json([:], status: 500)
            }
        }
        #expect(try await drive(http).folder(knownID: "folder-1") == "folder-2")
        let created = try JSONSerialization.jsonObject(with: http.sent[2].httpBody!) as! [String: Any]
        #expect(created["name"] as? String == "InvoiceBuilder backups")
        #expect(created["mimeType"] as? String == "application/vnd.google-apps.folder")
        #expect(http.sent.allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == "Bearer access-1" })
    }

    @Test func listingReadsEveryPageAndTheAppProperties() async throws {
        let http = FakeHTTP { request in
            var values: [String: String] = [:]
            for item in URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems! {
                values[item.name] = item.value
            }
            #expect(values["q"] == "'folder-1' in parents and trashed = false")
            if values["pageToken"] == "p2" {
                return .json(["files": [["id": "f2", "name": "manual.json"]]])
            }
            return .json(["nextPageToken": "p2", "files": [[
                "id": "f1", "name": "InvoiceBackup-2026-10-10.invoicebackup",
                "appProperties": ["ibDeviceId": "dev-1", "ibCreatedAt": "1791600000000", "ibPlatform": "android",
                                  "ibInvoices": "12", "ibClients": "4", "ibBusinesses": "Rao Traders"],
            ]]])
        }
        let entries = try await drive(http).list(folderID: "folder-1")
        #expect(entries.map(\.id) == ["f1", "f2"])
        #expect(entries[0].isTagged)
        #expect(entries[0].platform == "android")
        #expect(entries[0].invoiceCount == 12)
        #expect(entries[1].isTagged == false)
    }

    @Test func aNewBackupIsAResumableUploadIntoTheFolder() async throws {
        let http = FakeHTTP { request in
            if request.httpMethod == "POST" {
                return FakeHTTP.Reply(headers: ["Location": "https://upload.example/session-1"])
            }
            #expect(request.url?.absoluteString == "https://upload.example/session-1")
            return .json(["id": "file-9"])
        }
        let id = try await drive(http).upload(Data("{}".utf8), name: "InvoiceBackup-2026-10-10.invoicebackup",
                                              properties: ["ibDeviceId": "dev-1"], target: .create, folderID: "folder-1")
        #expect(id == "file-9")
        let start = http.sent[0]
        #expect(start.url?.absoluteString == "https://www.googleapis.com/upload/drive/v3/files?uploadType=resumable&fields=id")
        #expect(start.value(forHTTPHeaderField: "X-Upload-Content-Length") == "2")
        let metadata = try JSONSerialization.jsonObject(with: start.httpBody!) as! [String: Any]
        #expect(metadata["parents"] as? [String] == ["folder-1"])
        #expect((metadata["appProperties"] as? [String: String])?["ibDeviceId"] == "dev-1")
        #expect(http.sent[1].httpMethod == "PUT")
        #expect(http.sent[1].httpBody == Data("{}".utf8))
    }

    @Test func todaysFileIsUpdatedInPlace() async throws {
        let http = FakeHTTP { request in
            request.httpMethod == "PATCH" ? FakeHTTP.Reply(headers: ["Location": "https://upload.example/s"]) : .json(["id": "file-3"])
        }
        _ = try await drive(http).upload(Data(), name: "n", properties: [:], target: .update(id: "file-3"), folderID: "folder-1")
        #expect(http.sent[0].url?.path == "/upload/drive/v3/files/file-3")
        let metadata = try JSONSerialization.jsonObject(with: http.sent[0].httpBody!) as! [String: Any]
        #expect(metadata["parents"] == nil) // a PATCH can't set parents
    }

    @Test func a401RefreshesOnceAndRetries() async throws {
        let calls = Mutex(0)
        let http = FakeHTTP { request in
            if request.url?.host == "oauth2.googleapis.com" {
                return .json(["access_token": "access-2", "expires_in": 3600])
            }
            let attempt = calls.withLock { $0 += 1; return $0 }
            return attempt == 1 ? .json([:], status: 401) : .json(["id": "folder-1", "trashed": false])
        }
        #expect(try await drive(http).folder(knownID: "folder-1") == "folder-1")
        #expect(http.sent.last?.value(forHTTPHeaderField: "Authorization") == "Bearer access-2")
    }

    @Test func aFullDriveIsQuotaExceeded() async throws {
        let http = FakeHTTP { _ in
            .json(["error": ["code": 403, "errors": [["reason": "storageQuotaExceeded"]]]], status: 403)
        }
        await #expect(throws: CloudBackupError.quotaExceeded) {
            _ = try await drive(http).upload(Data(), name: "n", properties: [:], target: .create, folderID: "f")
        }
    }

    @Test func noConnectionIsNetworkUnavailable() {
        #expect(GoogleError.map(URLError(.notConnectedToInternet)) == .networkUnavailable)
        #expect(GoogleError.map(URLError(.timedOut)) == .networkUnavailable)
        #expect(GoogleError.map(URLError(.badServerResponse)) == .other)
    }

    @Test func theRedirectSchemeIsTheReversedClientID() {
        #expect(Self.config.redirectScheme == "com.googleusercontent.apps.1234-abc")
    }
}
