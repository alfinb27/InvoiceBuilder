import Foundation

/// An image kept in the database (logo or signature), so sync and backups carry it (`spec/setup.md` §9).
public struct Asset: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var createdAt: Int64
    public var updatedAt: Int64
    public var deletedAt: Int64?

    public var businessId: String
    public var kind: AssetKind
    /// `image/png` or `image/jpeg`.
    public var mime: String
    /// Lowercase hex SHA-256 of `data`.
    public var sha256: String
    public var data: Data

    enum CodingKeys: String, CodingKey {
        case id, createdAt, updatedAt, deletedAt, businessId, kind, mime, sha256
        case data = "dataBase64" // backups carry the bytes as base64
    }

    public init(id: String, createdAt: Int64 = 0, updatedAt: Int64 = 0, deletedAt: Int64? = nil, businessId: String,
                kind: AssetKind, mime: String, sha256: String, data: Data) {
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.businessId = businessId
        self.kind = kind
        self.mime = mime
        self.sha256 = sha256
        self.data = data
    }
}

/// Logo or signature. An open set.
public struct AssetKind: RawRepresentable, Codable, Hashable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    public static let logo = AssetKind(rawValue: "logo")
    public static let signature = AssetKind(rawValue: "signature")
}

/// Processed image bytes waiting to be stored as an `Asset`.
public struct ImagePayload: Hashable, Sendable {
    public var mime: String
    public var data: Data

    public init(mime: String, data: Data) {
        self.mime = mime
        self.data = data
    }

    public static let png = "image/png"
    public static let jpeg = "image/jpeg"
}
