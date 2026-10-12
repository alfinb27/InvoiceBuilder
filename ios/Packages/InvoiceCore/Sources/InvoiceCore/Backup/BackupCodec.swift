import CryptoKit
import Foundation

/// Reads and writes `.invoicebackup` files (`spec/backup.md`). Pure: bytes in, a preview or an error out.
public enum BackupCodec {
    /// The file's bytes: UTF-8 JSON with sorted keys (§1).
    public static func encode(_ file: BackupFile) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(file)
    }

    /// §3: the checks in order; the first failure wins.
    public static func validate(_ bytes: Data, appSchemaVersion: Int) -> Result<BackupPreview, BackupError> {
        do {
            return .success(BackupPreview(file: try decodeChecked(bytes, appSchemaVersion: appSchemaVersion)))
        } catch let error as BackupError {
            return .failure(error)
        } catch {
            return .failure(BackupError(.invalidRecord, String(describing: error)))
        }
    }

    /// Lowercase hex SHA-256 (asset hashes, `spec/setup.md` §9).
    public static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    // MARK: Checks

    private static func decodeChecked(_ bytes: Data, appSchemaVersion: Int) throws -> BackupFile {
        // 1–4: the envelope, read loosely so a wrong file gets the right code rather than a decoding error.
        guard let object = (try? JSONSerialization.jsonObject(with: bytes)) as? [String: Any] else {
            throw BackupError(.notJSON)
        }
        guard object["format"] as? String == BackupFile.format else { throw BackupError(.notABackup, "format") }
        guard let formatVersion = integer(object["formatVersion"]), formatVersion >= 1 else {
            throw BackupError(.notABackup, "formatVersion")
        }
        guard formatVersion <= BackupFile.formatVersion else {
            throw BackupError(.newerFormat, "formatVersion \(formatVersion)")
        }
        guard let schemaVersion = integer(object["dbSchemaVersion"]), schemaVersion >= 1 else {
            throw BackupError(.invalidRecord, "dbSchemaVersion")
        }
        guard schemaVersion <= appSchemaVersion else {
            throw BackupError(.newerSchema, "dbSchemaVersion \(schemaVersion) > \(appSchemaVersion)")
        }

        // 5: every record decodes (unknown keys are ignored by Codable).
        let file: BackupFile
        do {
            file = try JSONDecoder().decode(BackupFile.self, from: bytes)
        } catch let DecodingError.keyNotFound(key, context) {
            throw BackupError(.invalidRecord, path(context.codingPath + [key]))
        } catch let DecodingError.typeMismatch(_, context), let DecodingError.valueNotFound(_, context),
                let DecodingError.dataCorrupted(context) {
            throw BackupError(.invalidRecord, path(context.codingPath))
        }
        let data = file.data

        // 6: counts
        if file.counts != data.counts {
            let pairs = zip(countList(file.counts), countList(data.counts))
            let name = pairs.first { $0.0.value != $0.1.value }?.0.name
            throw BackupError(.countMismatch, name)
        }

        // 7: unique ids
        try unique(data.businesses.map(\.id), "businesses")
        try unique(data.clients.map(\.id), "clients")
        try unique(data.catalogItems.map(\.id), "catalogItems")
        try unique(data.numberingSeries.map(\.id), "numberingSeries")
        try unique(data.documents.map(\.id), "documents")
        try unique(data.payments.map(\.id), "payments")
        try unique(data.assets.map(\.id), "assets")
        for document in data.documents { try unique(document.lines.map(\.id), "documents \(document.id) lines") }

        // 8: asset hashes
        for asset in data.assets where sha256Hex(asset.data) != asset.sha256.lowercased() {
            throw BackupError(.assetHashMismatch, asset.id)
        }

        // 9: references resolve inside the file
        let businesses = Set(data.businesses.map(\.id)), clients = Set(data.clients.map(\.id))
        let items = Set(data.catalogItems.map(\.id)), series = Set(data.numberingSeries.map(\.id))
        let documents = Set(data.documents.map(\.id)), assets = Set(data.assets.map(\.id))
        func check(_ id: String?, in ids: Set<String>, _ what: @autoclosure () -> String) throws {
            if let id, !ids.contains(id) { throw BackupError(.danglingReference, "\(what()) → \(id)") }
        }
        for business in data.businesses {
            try check(business.logoAssetId, in: assets, "business \(business.id) logoAssetId")
            try check(business.signatureAssetId, in: assets, "business \(business.id) signatureAssetId")
        }
        for client in data.clients { try check(client.businessId, in: businesses, "client \(client.id)") }
        for item in data.catalogItems { try check(item.businessId, in: businesses, "catalog item \(item.id)") }
        for row in data.numberingSeries { try check(row.businessId, in: businesses, "series \(row.id)") }
        for asset in data.assets { try check(asset.businessId, in: businesses, "asset \(asset.id)") }
        for document in data.documents {
            try check(document.businessId, in: businesses, "document \(document.id) businessId")
            try check(document.clientId, in: clients, "document \(document.id) clientId")
            try check(document.seriesId, in: series, "document \(document.id) seriesId")
            try check(document.convertedFromId, in: documents, "document \(document.id) convertedFromId")
            for line in document.lines {
                try check(line.catalogItemId, in: items, "line \(line.id) catalogItemId")
            }
        }
        for payment in data.payments {
            try check(payment.businessId, in: businesses, "payment \(payment.id) businessId")
            try check(payment.documentId, in: documents, "payment \(payment.id) documentId")
        }
        return file
    }

    private static func integer(_ value: Any?) -> Int? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        let double = number.doubleValue
        return double.rounded() == double ? number.intValue : nil
    }

    private static func unique(_ ids: [String], _ collection: String) throws {
        var seen = Set<String>()
        for id in ids where !seen.insert(id).inserted { throw BackupError(.duplicateID, "\(collection) \(id)") }
    }

    private static func countList(_ counts: BackupCounts) -> [(name: String, value: Int)] {
        [("businesses", counts.businesses), ("clients", counts.clients), ("catalogItems", counts.catalogItems),
         ("numberingSeries", counts.numberingSeries), ("documents", counts.documents), ("payments", counts.payments),
         ("assets", counts.assets)]
    }

    private static func path(_ keys: [any CodingKey]) -> String {
        keys.map { $0.intValue.map { "[\($0)]" } ?? ".\($0.stringValue)" }.joined()
    }
}
