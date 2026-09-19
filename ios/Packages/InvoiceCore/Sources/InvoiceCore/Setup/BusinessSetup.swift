import Foundation

/// Pure parts of creating a business and choosing the active one (`spec/setup.md` §2–3, §6).
public enum BusinessSetup {
    /// One series per document type from the config's patterns, owned by this device.
    public static func defaultSeries(businessID: String, config: TaxConfig, ownerDeviceID: String, now: Int64,
                                     newID: () -> String) -> [NumberingSeries] {
        [(DocumentType.invoice, "Invoices"), (DocumentType.quote, "Quotes")].map { docType, label in
            NumberingSeries(id: newID(), createdAt: now, updatedAt: now, businessId: businessID, docType: docType,
                            label: label, pattern: config.numberingPattern(for: docType),
                            reset: config.numbering.reset, ownerDeviceId: ownerDeviceID)
        }
    }

    /// `preferences.activeBusinessId` when it names a live business; otherwise the earliest-created live business
    /// (ties: lowest id); nil → onboarding.
    public static func activeBusiness(preferences: DevicePreferences, businesses: [Business]) -> Business? {
        let live = businesses.filter { $0.deletedAt == nil }
        if let id = preferences.activeBusinessId, let chosen = live.first(where: { $0.id == id }) {
            return chosen
        }
        return live.min { ($0.createdAt, $0.id) < ($1.createdAt, $1.id) }
    }
}

/// List and picker search (`spec/setup.md` §5, §10): case-insensitive substring match, sorted by name then id.
public enum SetupSearch {
    public static func clients(_ clients: [Client], matching query: String) -> [Client] {
        filter(clients, query: query, name: \.name) { client in
            [client.name, client.contactName, client.email, client.phone, client.taxId]
        }
    }

    public static func items(_ items: [CatalogItem], matching query: String) -> [CatalogItem] {
        filter(items, query: query, name: \.name) { item in [item.name, item.description, item.productCode] }
    }

    private static func filter<T: Identifiable>(_ rows: [T], query: String, name: KeyPath<T, String>,
                                                 fields: (T) -> [String?]) -> [T] where T.ID == String {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let matches = needle.isEmpty ? rows : rows.filter { row in
            fields(row).contains { $0?.range(of: needle, options: .caseInsensitive) != nil }
        }
        return matches.sorted { lhs, rhs in
            switch lhs[keyPath: name].localizedStandardCompare(rhs[keyPath: name]) {
            case .orderedAscending: true
            case .orderedDescending: false
            case .orderedSame: lhs.id < rhs.id
            }
        }
    }
}
