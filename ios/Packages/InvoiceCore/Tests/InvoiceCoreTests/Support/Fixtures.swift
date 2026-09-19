import Foundation
import Testing

/// The repository's `spec/` folder, found from this file's location: tests read the fixtures straight from the spec
/// (ADR-0009), so a fixture change is picked up without a sync step.
enum Spec {
    static let root: URL = {
        var url = URL(fileURLWithPath: #filePath)
        // Support → InvoiceCoreTests → Tests → InvoiceCore → Packages → ios → repository root
        for _ in 0..<7 { url.deleteLastPathComponent() }
        return url.appending(path: "spec")
    }()
}

/// One golden fixture case (`spec/fixtures/README.md`). The test name is the case id.
struct FixtureCase: Sendable, CustomTestStringConvertible {
    let id: String
    let kind: String
    let input: JSONValue
    let expected: JSONValue

    var testDescription: String { id }

    /// `input[key]` as a string; fails the test when missing.
    func string(_ key: String) throws -> String {
        try #require(input[key]?.stringValue, "\(id): input.\(key) is missing")
    }
}

enum Fixtures {
    struct File: Decodable {
        let kind: String
        let cases: [JSONValue]
    }

    /// Every case in `spec/fixtures/**/*.json`, in file-name order.
    static let all: [FixtureCase] = {
        let folder = Spec.root.appending(path: "fixtures")
        guard let enumerator = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: nil) else {
            return []
        }
        let files = enumerator.compactMap { $0 as? URL }.filter { $0.pathExtension == "json" }
            .sorted { $0.path < $1.path }
        return files.flatMap { url -> [FixtureCase] in
            guard let data = try? Data(contentsOf: url), let file = try? JSONDecoder().decode(File.self, from: data)
            else { return [FixtureCase(id: "unreadable: \(url.lastPathComponent)", kind: "?", input: .null, expected: .null)] }
            return file.cases.map { raw in
                FixtureCase(id: raw["id"]?.stringValue ?? "?", kind: file.kind, input: raw["input"] ?? .null,
                            expected: raw["expected"] ?? .null)
            }
        }
    }()

    static func cases(kind: String) -> [FixtureCase] {
        all.filter { $0.kind == kind }
    }
}

/// A parsed JSON value with the fixture comparison rules (`spec/fixtures/README.md`).
indirect enum JSONValue: Decodable, Sendable, Equatable, CustomStringConvertible {
    case null
    case bool(Bool)
    case int(Int64)
    case double(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int64.self) {
            self = .int(value)
        } else if let value = try? container.decode(Double.self) {
            self = .double(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: JSONValue].self))
        }
    }

    subscript(key: String) -> JSONValue? {
        if case .object(let fields) = self { fields[key] } else { nil }
    }

    var stringValue: String? {
        if case .string(let value) = self { value } else { nil }
    }

    var intValue: Int64? {
        if case .int(let value) = self { value } else { nil }
    }

    var description: String {
        switch self {
        case .null: "null"
        case .bool(let value): String(value)
        case .int(let value): String(value)
        case .double(let value): String(value)
        case .string(let value): "\"\(value)\""
        case .array(let values): "[" + values.map(\.description).joined(separator: ", ") + "]"
        case .object(let fields):
            "{" + fields.keys.sorted().map { "\($0): \(fields[$0]!)" }.joined(separator: ", ") + "}"
        }
    }

    /// Subset match: every expected key must be present and equal (extra actual keys allowed), arrays compare
    /// element by element with equal lengths, and an expected `null` means null or absent.
    static func mismatches(expected: JSONValue, actual: JSONValue?, path: String = "") -> [String] {
        switch (expected, actual) {
        case (.null, nil), (.null, .null?):
            return []
        case (.object(let fields), .object(let actualFields)?):
            return fields.keys.sorted().flatMap { key in
                mismatches(expected: fields[key]!, actual: actualFields[key], path: path + "." + key)
            }
        case (.array(let items), .array(let actualItems)?):
            guard items.count == actualItems.count else {
                return ["\(path): expected \(items.count) items, got \(actualItems.count)"]
            }
            return zip(items, actualItems).enumerated().flatMap { index, pair in
                mismatches(expected: pair.0, actual: pair.1, path: "\(path)[\(index)]")
            }
        default:
            return expected == actual ? [] : ["\(path.isEmpty ? "value" : path): expected \(expected), got \(actual?.description ?? "nothing")"]
        }
    }
}

/// Builds `JSONValue`s from results.
extension JSONValue {
    static func optional(_ value: String?) -> JSONValue { value.map(JSONValue.string) ?? .null }
}

/// Fails the current test with every difference between `actual` and the fixture's `expected`.
func expectFixture(_ fixture: FixtureCase, _ actual: JSONValue, sourceLocation: SourceLocation = #_sourceLocation) {
    let problems = JSONValue.mismatches(expected: fixture.expected, actual: actual)
    #expect(problems.isEmpty, "\(fixture.id): \(problems.joined(separator: "; "))", sourceLocation: sourceLocation)
}
