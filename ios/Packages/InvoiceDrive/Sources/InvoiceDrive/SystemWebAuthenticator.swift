#if canImport(UIKit)
import AuthenticationServices
import InvoiceCore
import UIKit

/// Google's sign-in page in `ASWebAuthenticationSession`, which shares Safari's cookies (an account already signed in
/// to Google is offered) and catches the redirect without registering a URL scheme.
public struct SystemWebAuthenticator: WebAuthenticator {
    public init() {}

    public func authenticate(url: URL, callbackScheme: String) async throws -> URL {
        try await Self.run(url: url, callbackScheme: callbackScheme)
    }

    @MainActor
    private static func run(url: URL, callbackScheme: String) async throws -> URL {
        let holder = Holder()
        return try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: callbackScheme) { callback, error in
                if let callback {
                    continuation.resume(returning: callback)
                } else if let error = error as? ASWebAuthenticationSessionError, error.code == .canceledLogin {
                    continuation.resume(throwing: CloudBackupError.cancelled)
                } else {
                    continuation.resume(throwing: CloudBackupError.other)
                }
                Task { @MainActor in holder.session = nil } // the session and its anchor live until here
            }
            session.presentationContextProvider = holder
            session.prefersEphemeralWebBrowserSession = false
            holder.session = session
            if !session.start() {
                holder.session = nil
                continuation.resume(throwing: CloudBackupError.other)
            }
        }
    }

    /// Keeps the session alive while it shows, and anchors it to the active window.
    @MainActor
    private final class Holder: NSObject, ASWebAuthenticationPresentationContextProviding {
        var session: ASWebAuthenticationSession?

        nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
            MainActor.assumeIsolated {
                let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
                let active = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
                return active?.keyWindow ?? ASPresentationAnchor()
            }
        }
    }
}
#endif
