import Foundation
import InvoiceCore

/// One HTTP exchange. `URLSessionHTTPClient` in the app; tests script the responses.
public protocol HTTPClient: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

public struct URLSessionHTTPClient: HTTPClient {
    let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw CloudBackupError.other }
            return (data, http)
        } catch let error as URLError {
            throw GoogleError.map(error)
        }
    }
}

/// Google's error bodies mapped to `CloudBackupError` (`spec/backup.md` §7.5).
enum GoogleError {
    struct Body: Decodable {
        struct Detail: Decodable {
            let code: Int?
            let errors: [Reason]?
        }
        struct Reason: Decodable {
            let reason: String?
        }
        /// Drive: an object; OAuth: a string such as "invalid_grant".
        let error: Detail?
        let oauthError: String?

        enum CodingKeys: String, CodingKey { case error }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            error = try? container.decode(Detail.self, forKey: .error)
            oauthError = try? container.decode(String.self, forKey: .error)
        }
    }

    static func map(_ error: URLError) -> CloudBackupError {
        switch error.code {
        case .notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotFindHost, .cannotConnectToHost,
             .dnsLookupFailed, .dataNotAllowed, .internationalRoamingOff:
            return .networkUnavailable
        case .cancelled:
            return .cancelled
        default:
            return .other
        }
    }

    /// A non-2xx Drive response.
    static func map(status: Int, data: Data) -> CloudBackupError {
        let body = try? JSONDecoder().decode(Body.self, from: data)
        let reasons = Set(body?.error?.errors?.compactMap(\.reason) ?? [])
        if body?.oauthError == "invalid_grant" || status == 401 { return .signedOut }
        if reasons.contains("storageQuotaExceeded") || reasons.contains("quotaExceeded") { return .quotaExceeded }
        return .other
    }
}
