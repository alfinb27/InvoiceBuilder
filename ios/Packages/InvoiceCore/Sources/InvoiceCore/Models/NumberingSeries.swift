/// A document number series (`domain.schema.json#/$defs/NumberingSeries`). Only the owner device advances it, so
/// devices working offline never issue the same number (ADR-0015).
public struct NumberingSeries: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var createdAt: Int64
    public var updatedAt: Int64
    public var deletedAt: Int64?

    public var businessId: String
    public var docType: DocumentType
    public var label: String
    public var pattern: String
    public var reset: NumberingReset
    public var ownerDeviceId: String
    /// Period key (`all`, `FY2026`, `CY2026`) → next sequence number.
    public var counters: [String: Int]

    public init(id: String, createdAt: Int64 = 0, updatedAt: Int64 = 0, deletedAt: Int64? = nil, businessId: String,
                docType: DocumentType, label: String, pattern: String, reset: NumberingReset, ownerDeviceId: String,
                counters: [String: Int] = [:]) {
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.businessId = businessId
        self.docType = docType
        self.label = label
        self.pattern = pattern
        self.reset = reset
        self.ownerDeviceId = ownerDeviceId
        self.counters = counters
    }

    /// The sequence the next document issued in `periodKey` gets.
    public func nextSequence(periodKey: String) -> Int {
        max(counters[periodKey] ?? 1, 1)
    }
}
