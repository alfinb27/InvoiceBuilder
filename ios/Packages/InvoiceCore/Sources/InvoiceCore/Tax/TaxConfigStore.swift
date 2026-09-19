import Foundation

/// Every tax config the app knows, loaded from `spec/tax/*.json` (bundled by `make sync-spec`).
public struct TaxConfigStore: Sendable {
    /// Sorted by family, then `configVersion`.
    public let configs: [TaxConfig]

    public init(configs: [TaxConfig]) {
        self.configs = configs.sorted { ($0.family, $0.configVersion) < ($1.family, $1.configVersion) }
    }

    /// Loads every `*.json` file in `directory`.
    public init(directory: URL) throws {
        let files = try FileManager.default
            .contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
        let decoder = JSONDecoder()
        var configs: [TaxConfig] = []
        for file in files {
            do {
                configs.append(try decoder.decode(TaxConfig.self, from: Data(contentsOf: file)))
            } catch {
                throw SpecLoadingError(path: "tax/\(file.lastPathComponent)", reason: "\(error)")
            }
        }
        self.init(configs: configs)
    }

    /// The configs bundled in InvoiceCore.
    public static func bundled() throws -> TaxConfigStore {
        try TaxConfigStore(directory: SpecResources.url("tax"))
    }

    /// `IN@2025-09-22` → that exact config version.
    public func config(ref: String) -> TaxConfig? {
        configs.first { $0.ref == ref }
    }

    /// The newest version of a family in effect on `date` (the newest overall when `date` is nil, or when every
    /// version is newer than `date`).
    public func latest(family: String, on date: LocalDate? = nil) -> TaxConfig? {
        let versions = configs.filter { $0.family == family }
        guard let date else { return versions.last }
        return versions.last { $0.configVersion <= date } ?? versions.first
    }

    /// The config family a business in `countryCode` uses: `IN`, `GB`, or `GENERIC` for every other country
    /// (`spec/setup.md` §3).
    public static func family(forCountry countryCode: String) -> String {
        switch countryCode {
        case "IN", "GB": countryCode
        default: "GENERIC"
        }
    }
}
