import CryptoKit
import Foundation
import InvoiceCore
import Security

/// The app's Google OAuth client (Info.plist `GoogleDriveClientID`, ADR-0021).
public struct GoogleOAuthConfig: Sendable {
    /// `1234-abc.apps.googleusercontent.com`.
    public var clientID: String
    /// The only scope the app asks for (`spec/backup.md` §7.1).
    public static let scope = "https://www.googleapis.com/auth/drive.file"

    public init(clientID: String) {
        self.clientID = clientID
    }

    /// The reversed client ID (`com.googleusercontent.apps.1234-abc`), Google's redirect scheme for iOS clients.
    public var redirectScheme: String {
        clientID.split(separator: ".").reversed().joined(separator: ".")
    }

    public var redirectURI: String { "\(redirectScheme):/oauth2redirect" }
}

/// Shows Google's sign-in page and returns the redirect URL (`SystemWebAuthenticator` in the app).
public protocol WebAuthenticator: Sendable {
    func authenticate(url: URL, callbackScheme: String) async throws -> URL
}

/// The tokens kept on this device only (never in the database or a backup).
public struct GoogleTokens: Codable, Hashable, Sendable {
    public var refreshToken: String
    public var accessToken: String
    /// Seconds since 1970.
    public var expiresAt: TimeInterval

    public init(refreshToken: String, accessToken: String, expiresAt: TimeInterval) {
        self.refreshToken = refreshToken
        self.accessToken = accessToken
        self.expiresAt = expiresAt
    }
}

public protocol GoogleTokenStore: Sendable {
    func load() -> GoogleTokens?
    func save(_ tokens: GoogleTokens)
    func delete()
}

/// The Keychain, this device only, readable after the first unlock (background backups run with the screen locked).
public struct KeychainTokenStore: GoogleTokenStore {
    let service: String
    let account = "google-drive"

    public init(service: String = "app.invoicebuilder.drive") {
        self.service = service
    }

    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    public func load() -> GoogleTokens? {
        var lookup = query
        lookup[kSecReturnData as String] = true
        lookup[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(lookup as CFDictionary, &item) == errSecSuccess, let data = item as? Data else {
            return nil
        }
        return try? JSONDecoder().decode(GoogleTokens.self, from: data)
    }

    public func save(_ tokens: GoogleTokens) {
        guard let data = try? JSONEncoder().encode(tokens) else { return }
        SecItemDelete(query as CFDictionary)
        var item = query
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(item as CFDictionary, nil)
    }

    public func delete() {
        SecItemDelete(query as CFDictionary)
    }
}

/// OAuth 2.0 for native apps (RFC 8252) with PKCE (RFC 7636) against Google, for the one Drive scope.
public actor GoogleAuth {
    static let authorizeURL = URL(string: "https://accounts.google.com/o/oauth2/v2/auth")!
    static let tokenURL = URL(string: "https://oauth2.googleapis.com/token")!
    static let revokeURL = URL(string: "https://oauth2.googleapis.com/revoke")!

    let config: GoogleOAuthConfig
    let http: any HTTPClient
    let store: any GoogleTokenStore
    let authenticator: any WebAuthenticator
    let now: @Sendable () -> Date
    let randomBytes: @Sendable (Int) -> [UInt8]

    public init(config: GoogleOAuthConfig, http: any HTTPClient, store: any GoogleTokenStore,
                authenticator: any WebAuthenticator, now: @escaping @Sendable () -> Date = Date.init,
                randomBytes: @escaping @Sendable (Int) -> [UInt8] = GoogleAuth.secureRandom) {
        self.config = config
        self.http = http
        self.store = store
        self.authenticator = authenticator
        self.now = now
        self.randomBytes = randomBytes
    }

    public var isSignedIn: Bool { store.load() != nil }

    /// Shows Google's consent page and keeps the tokens. Throws `.cancelled` when the user closes it.
    public func signIn() async throws {
        let verifier = Self.base64URL(randomBytes(32))
        let state = Self.base64URL(randomBytes(16))
        var components = URLComponents(url: Self.authorizeURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: config.clientID),
            URLQueryItem(name: "redirect_uri", value: config.redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: GoogleOAuthConfig.scope),
            URLQueryItem(name: "code_challenge", value: Self.challenge(for: verifier)),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state),
        ]
        let callback = try await authenticator.authenticate(url: components.url!, callbackScheme: config.redirectScheme)
        let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
        guard items.first(where: { $0.name == "state" })?.value == state,
              let code = items.first(where: { $0.name == "code" })?.value
        else {
            throw items.contains(where: { $0.name == "error" && $0.value == "access_denied" })
                ? CloudBackupError.cancelled : CloudBackupError.other
        }
        let response = try await tokenRequest([
            "code": code, "client_id": config.clientID, "redirect_uri": config.redirectURI,
            "grant_type": "authorization_code", "code_verifier": verifier,
        ])
        guard let refresh = response.refreshToken else { throw CloudBackupError.other }
        store.save(GoogleTokens(refreshToken: refresh, accessToken: response.accessToken,
                                expiresAt: now().timeIntervalSince1970 + response.expiresIn))
    }

    /// A valid access token, refreshed when it has (nearly) expired. `forceRefresh` after a 401.
    public func accessToken(forceRefresh: Bool = false) async throws -> String {
        guard var tokens = store.load() else { throw CloudBackupError.signedOut }
        if !forceRefresh, tokens.expiresAt - 60 > now().timeIntervalSince1970 { return tokens.accessToken }
        do {
            let response = try await tokenRequest([
                "refresh_token": tokens.refreshToken, "client_id": config.clientID, "grant_type": "refresh_token",
            ])
            tokens.accessToken = response.accessToken
            tokens.expiresAt = now().timeIntervalSince1970 + response.expiresIn
            store.save(tokens)
            return tokens.accessToken
        } catch CloudBackupError.signedOut {
            store.delete() // the grant is gone: the user reconnects
            throw CloudBackupError.signedOut
        }
    }

    /// Revokes the grant (best effort) and forgets the tokens.
    public func signOut() async {
        guard let tokens = store.load() else { return }
        store.delete()
        var request = URLRequest(url: Self.revokeURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.form(["token": tokens.refreshToken])
        _ = try? await http.send(request)
    }

    // MARK: Helpers

    struct TokenResponse: Decodable {
        let accessToken: String
        let expiresIn: TimeInterval
        let refreshToken: String?

        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token", expiresIn = "expires_in", refreshToken = "refresh_token"
        }
    }

    private func tokenRequest(_ fields: [String: String]) async throws -> TokenResponse {
        var request = URLRequest(url: Self.tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.form(fields)
        let (data, response) = try await http.send(request)
        guard (200..<300).contains(response.statusCode) else {
            // A refused refresh (400 invalid_grant) maps to signedOut: access was revoked or expired.
            throw GoogleError.map(status: response.statusCode, data: data)
        }
        do { return try JSONDecoder().decode(TokenResponse.self, from: data) } catch { throw CloudBackupError.other }
    }

    static func form(_ fields: [String: String]) -> Data {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return fields.sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: allowed) ?? $0.value)" }
            .joined(separator: "&").data(using: .utf8)!
    }

    static func challenge(for verifier: String) -> String {
        base64URL(Array(SHA256.hash(data: Data(verifier.utf8))))
    }

    static func base64URL(_ bytes: [UInt8]) -> String {
        Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    public static let secureRandom: @Sendable (Int) -> [UInt8] = { count in
        var bytes = [UInt8](repeating: 0, count: count)
        _ = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
        return bytes
    }
}
