import Foundation

/// Everything a PDF shows, already formatted (`spec/pdf/RENDERING.md` §1). The renderers draw this and nothing
/// else: no rounding, no label lookups and no locale formatting happen while drawing.
public struct PDFDocumentModel: Codable, Hashable, Sendable {
    public var title: String
    /// No number yet: every page carries `draftLabel` as a watermark.
    public var isDraft: Bool
    public var draftLabel: String?
    public var number: String?
    public var numberLabel: String
    public var meta: [Field]
    public var seller: Party
    public var buyer: Party?
    public var shipTo: Party?
    public var columns: [Column]
    /// One row per line, in column order.
    public var rows: [[String]]
    public var totals: [TotalRow]
    public var taxSummary: Table?
    public var amountInWords: String?
    public var homeTotals: String?
    public var reverseChargeNote: String?
    public var notes: [Note]
    public var payment: Payment
    public var signature: Signature
    public var footer: Footer

    public struct Field: Codable, Hashable, Sendable {
        public var label: String
        public var value: String

        public init(label: String, value: String) {
            self.label = label
            self.value = value
        }
    }

    public struct Party: Codable, Hashable, Sendable {
        public var heading: String?
        public var name: String
        public var lines: [String]
        public var fields: [Field]

        public init(heading: String? = nil, name: String, lines: [String] = [], fields: [Field] = []) {
            self.heading = heading
            self.name = name
            self.lines = lines
            self.fields = fields
        }
    }

    public struct Column: Codable, Hashable, Sendable {
        /// `index`, `description`, `productCode`, `quantity`, `unit`, `unitPrice`, `discount`, `taxable`,
        /// `tax:<component>` or `amount`.
        public var id: String
        public var label: String
        public var align: Align

        public init(id: String, label: String, align: Align) {
            self.id = id
            self.label = label
            self.align = align
        }
    }

    public enum Align: String, Codable, Hashable, Sendable {
        case leading, trailing
    }

    public struct Table: Codable, Hashable, Sendable {
        public var columns: [Column]
        public var rows: [[String]]

        public init(columns: [Column], rows: [[String]]) {
            self.columns = columns
            self.rows = rows
        }
    }

    public struct TotalRow: Codable, Hashable, Sendable {
        public var label: String
        public var value: String
        public var emphasis: Emphasis

        public init(label: String, value: String, emphasis: Emphasis = .normal) {
            self.label = label
            self.value = value
            self.emphasis = emphasis
        }
    }

    public enum Emphasis: String, Codable, Hashable, Sendable {
        case normal, strong
    }

    public struct Note: Codable, Hashable, Sendable {
        public var label: String?
        public var text: String
        /// `top` notes are printed above the items, `bottom` ones below the totals.
        public var placement: String

        public init(label: String? = nil, text: String, placement: String) {
            self.label = label
            self.text = text
            self.placement = placement
        }
    }

    public struct Payment: Codable, Hashable, Sendable {
        public var bank: [Field]
        public var upi: UPI?

        public init(bank: [Field] = [], upi: UPI? = nil) {
            self.bank = bank
            self.upi = upi
        }

        public struct UPI: Codable, Hashable, Sendable {
            public var id: String
            public var caption: String
            /// The `upi://pay` link the QR code encodes (`ENGINE.md` §9).
            public var payload: String

            public init(id: String, caption: String, payload: String) {
                self.id = id
                self.caption = caption
                self.payload = payload
            }
        }
    }

    public struct Signature: Codable, Hashable, Sendable {
        public var imageAssetId: String?
        public var forBusiness: String
        public var authorisedSignatory: String

        public init(imageAssetId: String? = nil, forBusiness: String, authorisedSignatory: String) {
            self.imageAssetId = imageAssetId
            self.forBusiness = forBusiness
            self.authorisedSignatory = authorisedSignatory
        }
    }

    public struct Footer: Codable, Hashable, Sendable {
        /// Still holds `{page}` and `{pages}`: the renderer knows the page count.
        public var pageLabel: String
        public var continued: String

        public init(pageLabel: String, continued: String) {
            self.pageLabel = pageLabel
            self.continued = continued
        }
    }

    public init(title: String, isDraft: Bool, draftLabel: String? = nil, number: String? = nil,
                numberLabel: String, meta: [Field] = [],
                seller: Party, buyer: Party? = nil, shipTo: Party? = nil, columns: [Column] = [],
                rows: [[String]] = [], totals: [TotalRow] = [], taxSummary: Table? = nil,
                amountInWords: String? = nil, homeTotals: String? = nil, reverseChargeNote: String? = nil,
                notes: [Note] = [], payment: Payment = Payment(), signature: Signature, footer: Footer) {
        self.title = title
        self.isDraft = isDraft
        self.draftLabel = draftLabel
        self.number = number
        self.numberLabel = numberLabel
        self.meta = meta
        self.seller = seller
        self.buyer = buyer
        self.shipTo = shipTo
        self.columns = columns
        self.rows = rows
        self.totals = totals
        self.taxSummary = taxSummary
        self.amountInWords = amountInWords
        self.homeTotals = homeTotals
        self.reverseChargeNote = reverseChargeNote
        self.notes = notes
        self.payment = payment
        self.signature = signature
        self.footer = footer
    }

    /// Notes printed above the items table.
    public var topNotes: [Note] { notes.filter { $0.placement == "top" } }
    /// Notes printed below the totals.
    public var bottomNotes: [Note] { notes.filter { $0.placement != "top" } }
}

/// The shared label strings (`spec/pdf/labels/en.json`), with `{placeholder}` substitution.
public struct PDFLabels: Decodable, Hashable, Sendable {
    public let locale: String
    public let labels: [String: String]

    public init(locale: String, labels: [String: String]) {
        self.locale = locale
        self.labels = labels
    }

    /// The label for `key`, with each `{name}` replaced. An unknown key returns the key itself, so a missing
    /// translation is visible rather than blank.
    public func text(_ key: String, _ arguments: [String: String] = [:]) -> String {
        var text = labels[key] ?? key
        for (name, value) in arguments {
            text = text.replacingOccurrences(of: "{\(name)}", with: value)
        }
        return text
    }

    /// The copy bundled in InvoiceCore (`make sync-spec`).
    public static func bundled(locale: String = "en") throws -> PDFLabels {
        try JSONDecoder().decode(PDFLabels.self, from: SpecResources.data("pdf/labels/\(locale).json"))
    }
}
