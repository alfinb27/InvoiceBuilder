import Foundation

/// A template from `spec/pdf/layout/<id>.json` (`schema/pdf-layout.schema.json`): which blocks to draw, in order,
/// and the style tokens to draw them with. Both platforms decode this same file.
public struct PDFTemplate: Decodable, Hashable, Sendable, Identifiable {
    public let id: TemplateID
    public let label: String
    public let description: String?
    public let page: Page
    public let style: Style
    public let blocks: [Block]

    public struct Page: Decodable, Hashable, Sendable {
        public let margins: Margins
        public let footerHeight: Double

        public struct Margins: Decodable, Hashable, Sendable {
            public let top: Double
            public let right: Double
            public let bottom: Double
            public let left: Double
        }
    }

    public struct Style: Decodable, Hashable, Sendable {
        public let fontSizes: FontSizes
        public let lineHeight: Double
        public let colors: Colors
        public let accentUse: [AccentUse]
        public let rule: Rule
        public let table: Table
        public let blockSpacing: Double
        public let logo: Logo
        public let qrSize: Double?
        public let signatureHeight: Double?

        public struct FontSizes: Decodable, Hashable, Sendable {
            public let title: Double
            public let heading: Double
            public let body: Double
            public let small: Double
        }

        public struct Colors: Decodable, Hashable, Sendable {
            public let text: String
            public let muted: String
            public let rule: String
            public let onAccent: String
            public let tableHeaderFill: String?
            public let zebraFill: String?
        }

        public struct Rule: Decodable, Hashable, Sendable {
            public let width: Double
        }

        public struct Table: Decodable, Hashable, Sendable {
            public let headerWeight: Weight
            public let headerUppercase: Bool
            public let rowPadding: Padding
            public let rowRule: RowRule

            public struct Padding: Decodable, Hashable, Sendable {
                public let vertical: Double
                public let horizontal: Double
            }
        }

        public struct Logo: Decodable, Hashable, Sendable {
            public let maxWidth: Double
            public let maxHeight: Double
        }
    }

    public enum Weight: String, Decodable, Hashable, Sendable {
        case regular, semibold, bold
    }

    public enum RowRule: String, Decodable, Hashable, Sendable {
        case none, below, zebra
    }

    /// Where the accent colour is used; unknown values (a newer template) are ignored by an older app.
    public struct AccentUse: RawRepresentable, Decodable, Hashable, Sendable {
        public let rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }

        public static let title = AccentUse(rawValue: "title")
        public static let headerBand = AccentUse(rawValue: "headerBand")
        public static let tableHeaderFill = AccentUse(rawValue: "tableHeaderFill")
        public static let tableHeaderText = AccentUse(rawValue: "tableHeaderText")
        public static let rules = AccentUse(rawValue: "rules")
        public static let totalRow = AccentUse(rawValue: "totalRow")
    }

    public struct Block: Decodable, Hashable, Sendable {
        public let id: Kind
        public let variant: Variant

        public struct Kind: RawRepresentable, Decodable, Hashable, Sendable {
            public let rawValue: String
            public init(rawValue: String) { self.rawValue = rawValue }

            public static let header = Kind(rawValue: "header")
            public static let parties = Kind(rawValue: "parties")
            public static let items = Kind(rawValue: "items")
            public static let totals = Kind(rawValue: "totals")
            public static let payment = Kind(rawValue: "payment")
            public static let notes = Kind(rawValue: "notes")
            public static let signature = Kind(rawValue: "signature")
        }

        public struct Variant: RawRepresentable, Decodable, Hashable, Sendable {
            public let rawValue: String
            public init(rawValue: String) { self.rawValue = rawValue }

            public static let logoLeft = Variant(rawValue: "logoLeft")
            public static let logoRight = Variant(rawValue: "logoRight")
            public static let band = Variant(rawValue: "band")
            public static let plain = Variant(rawValue: "plain")
            public static let twoColumns = Variant(rawValue: "twoColumns")
            public static let stacked = Variant(rawValue: "stacked")
            public static let ruled = Variant(rawValue: "ruled")
            public static let zebra = Variant(rawValue: "zebra")
            public static let compact = Variant(rawValue: "compact")
            public static let right = Variant(rawValue: "right")
            public static let left = Variant(rawValue: "left")
        }
    }

    public func uses(_ accent: AccentUse) -> Bool { style.accentUse.contains(accent) }

    public func block(_ kind: Block.Kind) -> Block? { blocks.first { $0.id == kind } }
}

/// The templates bundled in InvoiceCore (`spec/pdf/layout`, copied by `make sync-spec`).
public struct PDFTemplateStore: Sendable {
    public let templates: [PDFTemplate]

    public init(templates: [PDFTemplate]) {
        self.templates = templates
    }

    public init(directory: URL) throws {
        let files = try FileManager.default
            .contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        let decoder = JSONDecoder()
        var templates: [PDFTemplate] = []
        for file in files {
            do {
                templates.append(try decoder.decode(PDFTemplate.self, from: Data(contentsOf: file)))
            } catch {
                throw SpecLoadingError(path: "pdf/layout/\(file.lastPathComponent)", reason: "\(error)")
            }
        }
        self.init(templates: templates)
    }

    public static func bundled() throws -> PDFTemplateStore {
        try PDFTemplateStore(directory: SpecResources.url("pdf/layout"))
    }

    /// The template a document asks for, falling back to the first one so a value from a newer app version still
    /// renders.
    public func template(_ id: TemplateID) -> PDFTemplate? {
        templates.first { $0.id == id } ?? templates.first
    }

    /// For the template switcher, in file order.
    public var all: [PDFTemplate] { templates }
}
