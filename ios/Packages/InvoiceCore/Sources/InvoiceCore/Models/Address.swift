/// A postal address (`domain.schema.json#/$defs/address`), stored as JSON on businesses and clients.
public struct Address: Codable, Hashable, Sendable {
    public var line1: String
    public var line2: String?
    public var city: String?
    public var regionCode: String?
    public var postalCode: String?
    public var countryCode: String

    public init(line1: String, line2: String? = nil, city: String? = nil, regionCode: String? = nil,
                postalCode: String? = nil, countryCode: String) {
        self.line1 = line1
        self.line2 = line2
        self.city = city
        self.regionCode = regionCode
        self.postalCode = postalCode
        self.countryCode = countryCode
    }

    /// One line for lists and document snapshots: `12 MG Road, Bengaluru 560001`.
    public var singleLine: String {
        let cityLine = [city, postalCode].compactMap { $0?.trimmedOrNil }.joined(separator: " ")
        return [line1.trimmedOrNil, line2?.trimmedOrNil, cityLine.trimmedOrNil].compactMap { $0 }
            .joined(separator: ", ")
    }
}

/// Document types. An open set (`CLAUDE.md` rule 5): a value written by a newer app version is kept, not rejected.
public struct DocumentType: RawRepresentable, Codable, Hashable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    public static let invoice = DocumentType(rawValue: "invoice")
    public static let quote = DocumentType(rawValue: "quote")
    public static let known: [DocumentType] = [.invoice, .quote]
}

/// PDF template ids. An open set.
public struct TemplateID: RawRepresentable, Codable, Hashable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    public static let classic = TemplateID(rawValue: "classic")
    public static let modern = TemplateID(rawValue: "modern")
    public static let minimal = TemplateID(rawValue: "minimal")
    public static let compact = TemplateID(rawValue: "compact")
    public static let known: [TemplateID] = [.classic, .modern, .minimal, .compact]
}
