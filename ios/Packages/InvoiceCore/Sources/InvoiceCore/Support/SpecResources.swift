import Foundation

/// The runtime copy of `spec/` bundled into InvoiceCore by `make sync-spec`. Never edit the copy by hand;
/// `make check-sync` fails when it drifts from `spec/`.
public enum SpecResources {
    /// Root of the bundled `spec` folder.
    public static var root: URL {
        guard let url = Bundle.module.url(forResource: "spec", withExtension: nil) else {
            preconditionFailure("InvoiceCore is missing its bundled spec folder; run `make sync-spec`.")
        }
        return url
    }

    /// A file inside the bundled spec, e.g. `tax/IN.json`.
    public static func url(_ relativePath: String) -> URL {
        root.appending(path: relativePath)
    }

    public static func data(_ relativePath: String) throws -> Data {
        try Data(contentsOf: url(relativePath))
    }
}

/// A spec file that is missing or does not match its schema.
public struct SpecLoadingError: Error, CustomStringConvertible, Sendable {
    public let path: String
    public let reason: String

    public init(path: String, reason: String) {
        self.path = path
        self.reason = reason
    }

    public var description: String { "\(path): \(reason)" }
}
