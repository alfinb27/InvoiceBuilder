import Foundation

/// A file in the Drive sync folder (`spec/drive-sync.md` §3), from its `appProperties`. `kind` is nil on a file the
/// app didn't tag.
public struct DriveSyncEntry: Hashable, Sendable, Identifiable {
    public enum Kind: String, Sendable { case changes, snapshot }

    public var id: String
    public var kind: Kind?
    public var deviceID: String?
    /// Change files only.
    public var seq: Int?
    public var createdAt: Int64?

    public init(id: String, kind: Kind?, deviceID: String?, seq: Int? = nil, createdAt: Int64? = nil) {
        self.id = id
        self.kind = kind
        self.deviceID = deviceID
        self.seq = seq
        self.createdAt = createdAt
    }

    public init(id: String, properties: [String: String]) {
        self.init(id: id, kind: properties[Key.kind].flatMap(Kind.init(rawValue:)), deviceID: properties[Key.deviceID],
                  seq: properties[Key.seq].flatMap { Int($0) }, createdAt: properties[Key.createdAt].flatMap { Int64($0) })
    }

    public enum Key {
        public static let kind = "ibKind", deviceID = "ibDeviceId", seq = "ibSeq", createdAt = "ibCreatedAt"
    }
}

/// The pure rules of live sync through Google Drive (`spec/drive-sync.md`; fixtures kind `drivesync`).
public enum DriveSync {
    /// §8: own change files older than this, and covered by the snapshot, may go.
    public static let pruneAge: Int64 = 30 * 24 * 60 * 60 * 1000
    /// §8: a snapshot is written once a device has more change files than this.
    public static let snapshotAfter = 200

    // MARK: §5 merge

    /// §5: the incoming record replaces the local one. Records are backup-encoded JSON objects (as from
    /// `JSONSerialization`); `collection` is the backup key (`documents` compares `lifecycle` first).
    public static func wins(local: [String: Any]?, incoming: [String: Any], collection: String) -> Bool {
        guard let local else { return true }
        if collection == "documents" {
            let (l, i) = (lifecycleRank(local["lifecycle"]), lifecycleRank(incoming["lifecycle"]))
            if l != i { return i > l }
        }
        let (lu, iu) = (int(local["updatedAt"]) ?? 0, int(incoming["updatedAt"]) ?? 0)
        if lu != iu { return iu > lu }
        let (ld, id) = (isSet(local["deletedAt"]), isSet(incoming["deletedAt"]))
        if ld != id { return id }
        return Array(canonicalText(local).utf8).lexicographicallyPrecedes(Array(canonicalText(incoming).utf8))
    }

    /// §5 for a typed record: encodes both with the backup encoding first.
    public static func wins<T: Encodable>(local: T?, incoming: T, collection: String) throws -> Bool {
        try wins(local: local.map(object), incoming: object(incoming), collection: collection)
    }

    /// The backup JSON of one record as an object.
    public static func object<T: Encodable>(_ record: T) throws -> [String: Any] {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try JSONSerialization.jsonObject(with: encoder.encode(record)) as? [String: Any] ?? [:]
    }

    /// §5 step 4: sorted keys, nulls left out, no whitespace, minimal escaping.
    public static func canonicalText(_ value: Any) -> String {
        var out = ""
        write(value, into: &out)
        return out
    }

    private static func write(_ value: Any, into out: inout String) {
        switch value {
        case let object as [String: Any]:
            out += "{"
            let keys = object.keys.filter { !(object[$0] is NSNull) }
                .sorted { Array($0.utf8).lexicographicallyPrecedes(Array($1.utf8)) }
            for (index, key) in keys.enumerated() {
                if index > 0 { out += "," }
                writeString(key, into: &out)
                out += ":"
                write(object[key]!, into: &out)
            }
            out += "}"
        case let array as [Any]:
            out += "["
            for (index, element) in array.enumerated() {
                if index > 0 { out += "," }
                write(element, into: &out)
            }
            out += "]"
        case let string as String:
            writeString(string, into: &out)
        case let number as NSNumber:
            if CFGetTypeID(number) == CFBooleanGetTypeID() { out += number.boolValue ? "true" : "false" }
            else { out += number.stringValue }
        case is NSNull:
            out += "null"
        default:
            out += "\(value)"
        }
    }

    private static func writeString(_ string: String, into out: inout String) {
        out += "\""
        for scalar in string.unicodeScalars {
            switch scalar {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case _ where scalar.value < 0x20: out += String(format: "\\u%04x", scalar.value)
            default: out.unicodeScalars.append(scalar)
            }
        }
        out += "\""
    }

    private static func lifecycleRank(_ value: Any?) -> Int {
        switch value as? String {
        case "issued": 1
        case "void": 2
        default: 0
        }
    }

    private static func int(_ value: Any?) -> Int64? { (value as? NSNumber)?.int64Value }
    private static func isSet(_ value: Any?) -> Bool { value != nil && !(value is NSNull) }

    // MARK: §6 pull

    /// §6: the files a pull reads, in order — one catch-up snapshot alone, or the next change files.
    public static func toRead(entries: [DriveSyncEntry], seen: [String: Int], thisDevice: String) -> [String] {
        let others = entries.filter { $0.kind != nil && $0.deviceID != nil && $0.deviceID != thisDevice }
        let devices = Set(others.compactMap(\.deviceID)).sorted()
        var changes: [String: [Int: String]] = [:]
        var snapshots: [String: String] = [:]
        for entry in others {
            let device = entry.deviceID!
            switch entry.kind {
            case .changes: if let seq = entry.seq { changes[device, default: [:]][seq] = entry.id }
            case .snapshot: snapshots[device] = entry.id
            case nil: break
            }
        }
        for device in devices {
            let next = (seen[device] ?? 0) + 1
            let files = changes[device] ?? [:]
            let behind = files.isEmpty ? (seen[device] == nil) : (files[next] == nil && files.keys.contains { $0 > next })
            if behind, let snapshot = snapshots[device] { return [snapshot] }
        }
        var ids: [String] = []
        for device in devices {
            var seq = (seen[device] ?? 0) + 1
            while let id = changes[device]?[seq] {
                ids.append(id)
                seq += 1
            }
        }
        return ids
    }

    // MARK: §8 compaction

    /// §8: this device's change files its snapshot covers and that are more than 30 days old.
    public static func filesToDelete(entries: [DriveSyncEntry], thisDevice: String, snapshotCovers: Int?,
                                     now: Int64) -> [String] {
        guard let snapshotCovers else { return [] }
        return entries.filter {
            $0.kind == .changes && $0.deviceID == thisDevice && ($0.seq ?? .max) <= snapshotCovers
                && ($0.createdAt.map { now - $0 > pruneAge } ?? false)
        }.sorted { ($0.seq ?? 0) < ($1.seq ?? 0) }.map(\.id)
    }
}
