import Foundation
import GRDB
import InvoiceCore

// GRDB records: one per table, one property per column (snake_case columns ↔ camelCase properties). JSON columns
// hold the domain JSON form (`domain.schema.json`, camelCase keys) and are mapped explicitly, as Room's type
// converters will be on Android. Value lists are plain strings here; InvoiceCore's open enums wrap them.

protocol SnakeCaseRecord: Codable, FetchableRecord, PersistableRecord, Sendable {}

extension SnakeCaseRecord {
    static var databaseColumnDecodingStrategy: DatabaseColumnDecodingStrategy { .convertFromSnakeCase }
    static var databaseColumnEncodingStrategy: DatabaseColumnEncodingStrategy { .convertToSnakeCase }
}

enum DBColumns {
    static let id = Column("id")
    static let businessID = Column("business_id")
    static let deletedAt = Column("deleted_at")
    static let createdAt = Column("created_at")
    static let kind = Column("kind")
    static let sha256 = Column("sha256")
    static let rateID = Column("rate_id")
    static let logoAssetID = Column("logo_asset_id")
    static let signatureAssetID = Column("signature_asset_id")
    static let updatedAt = Column("updated_at")
    static let documentID = Column("document_id")
    static let position = Column("position")
    static let docType = Column("doc_type")
    static let lifecycle = Column("lifecycle")
    static let quoteOutcome = Column("quote_outcome")
    static let convertedFromID = Column("converted_from_id")
}

/// JSON text columns.
enum JSONColumn {
    static func encode<Value: Encodable>(_ value: Value?) throws -> String? {
        guard let value else { return nil }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return String(decoding: try encoder.encode(value), as: UTF8.self)
    }

    static func decode<Value: Decodable>(_ type: Value.Type, from text: String?) throws -> Value? {
        guard let text, !text.isEmpty else { return nil }
        return try JSONDecoder().decode(type, from: Data(text.utf8))
    }
}

struct BusinessRecord: SnakeCaseRecord, Equatable {
    static let databaseTableName = "business"

    var id: String
    var name: String
    var legalName: String?
    var address: String?
    var email: String?
    var phone: String?
    var website: String?
    var countryCode: String
    var taxConfig: String
    var taxRegistration: String
    var taxId: String?
    var extraIds: String?
    var homeCurrency: String
    var turnoverMinor: Int64?
    var bank: String?
    var upiVpa: String?
    var paymentTermsDays: Int
    var defaultNotes: String?
    var defaultTerms: String?
    var templateId: String
    var accentColor: String?
    var logoAssetId: String?
    var signatureAssetId: String?
    var reminderDaysAfterDue: Int?
    var customRates: String?
    var createdAt: Int64
    var updatedAt: Int64
    var deletedAt: Int64?

    init(_ business: Business) throws {
        id = business.id
        name = business.name
        legalName = business.legalName
        address = try JSONColumn.encode(business.address)
        email = business.email
        phone = business.phone
        website = business.website
        countryCode = business.countryCode
        taxConfig = business.taxConfig
        taxRegistration = business.taxRegistration
        taxId = business.taxId
        extraIds = try JSONColumn.encode(business.extraIds)
        homeCurrency = business.homeCurrency.rawValue
        turnoverMinor = business.turnoverMinor
        bank = try JSONColumn.encode(business.bank)
        upiVpa = business.upiVpa
        paymentTermsDays = business.paymentTermsDays
        defaultNotes = business.defaultNotes
        defaultTerms = business.defaultTerms
        templateId = business.templateId.rawValue
        accentColor = business.accentColor
        logoAssetId = business.logoAssetId
        signatureAssetId = business.signatureAssetId
        reminderDaysAfterDue = business.reminderDaysAfterDue
        customRates = try JSONColumn.encode(business.customRates)
        createdAt = business.createdAt
        updatedAt = business.updatedAt
        deletedAt = business.deletedAt
    }

    func business() throws -> Business {
        Business(
            id: id, createdAt: createdAt, updatedAt: updatedAt, deletedAt: deletedAt, name: name, legalName: legalName,
            address: try JSONColumn.decode(Address.self, from: address), email: email, phone: phone,
            website: website, countryCode: countryCode, taxConfig: taxConfig, taxRegistration: taxRegistration,
            taxId: taxId, extraIds: try JSONColumn.decode(ExtraIDs.self, from: extraIds),
            homeCurrency: CurrencyCode(rawValue: homeCurrency), turnoverMinor: turnoverMinor,
            bank: try JSONColumn.decode(BankDetails.self, from: bank), upiVpa: upiVpa,
            paymentTermsDays: paymentTermsDays, defaultNotes: defaultNotes, defaultTerms: defaultTerms,
            templateId: TemplateID(rawValue: templateId), accentColor: accentColor, logoAssetId: logoAssetId,
            signatureAssetId: signatureAssetId, reminderDaysAfterDue: reminderDaysAfterDue,
            customRates: try JSONColumn.decode([TaxRate].self, from: customRates)
        )
    }
}

struct ClientRecord: SnakeCaseRecord, Equatable {
    static let databaseTableName = "client"

    var id: String
    var businessId: String
    var name: String
    var contactName: String?
    var email: String?
    var phone: String?
    var billingAddress: String?
    var shippingAddress: String?
    var countryCode: String
    var regionCode: String?
    var taxId: String?
    var isBusiness: Bool
    var defaultCurrency: String?
    var notes: String?
    var archivedAt: Int64?
    var createdAt: Int64
    var updatedAt: Int64
    var deletedAt: Int64?

    init(_ client: Client) throws {
        id = client.id
        businessId = client.businessId
        name = client.name
        contactName = client.contactName
        email = client.email
        phone = client.phone
        billingAddress = try JSONColumn.encode(client.billingAddress)
        shippingAddress = try JSONColumn.encode(client.shippingAddress)
        countryCode = client.countryCode
        regionCode = client.regionCode
        taxId = client.taxId
        isBusiness = client.isBusiness
        defaultCurrency = client.defaultCurrency?.rawValue
        notes = client.notes
        archivedAt = client.archivedAt
        createdAt = client.createdAt
        updatedAt = client.updatedAt
        deletedAt = client.deletedAt
    }

    func client() throws -> Client {
        Client(
            id: id, createdAt: createdAt, updatedAt: updatedAt, deletedAt: deletedAt, businessId: businessId,
            name: name, contactName: contactName, email: email, phone: phone,
            billingAddress: try JSONColumn.decode(Address.self, from: billingAddress),
            shippingAddress: try JSONColumn.decode(Address.self, from: shippingAddress), countryCode: countryCode,
            regionCode: regionCode, taxId: taxId, isBusiness: isBusiness,
            defaultCurrency: defaultCurrency.map(CurrencyCode.init(rawValue:)), notes: notes, archivedAt: archivedAt
        )
    }
}

struct CatalogItemRecord: SnakeCaseRecord, Equatable {
    static let databaseTableName = "catalog_item"

    var id: String
    var businessId: String
    var name: String
    var description: String?
    var kind: String
    var unit: String
    var unitPriceMinor: Int64
    var currency: String
    var rateId: String
    var productCode: String?
    var priceIncludesTax: Bool
    var archivedAt: Int64?
    var createdAt: Int64
    var updatedAt: Int64
    var deletedAt: Int64?

    init(_ item: CatalogItem) {
        id = item.id
        businessId = item.businessId
        name = item.name
        description = item.description
        kind = item.kind.rawValue
        unit = item.unit
        unitPriceMinor = item.unitPriceMinor
        currency = item.currency.rawValue
        rateId = item.rateId
        productCode = item.productCode
        priceIncludesTax = item.priceIncludesTax
        archivedAt = item.archivedAt
        createdAt = item.createdAt
        updatedAt = item.updatedAt
        deletedAt = item.deletedAt
    }

    func item() -> CatalogItem {
        CatalogItem(
            id: id, createdAt: createdAt, updatedAt: updatedAt, deletedAt: deletedAt, businessId: businessId,
            name: name, description: description, kind: ItemKind(rawValue: kind), unit: unit,
            unitPriceMinor: unitPriceMinor, currency: CurrencyCode(rawValue: currency), rateId: rateId,
            productCode: productCode, priceIncludesTax: priceIncludesTax, archivedAt: archivedAt
        )
    }
}

struct NumberingSeriesRecord: SnakeCaseRecord, Equatable {
    static let databaseTableName = "numbering_series"

    var id: String
    var businessId: String
    var docType: String
    var label: String
    var pattern: String
    var reset: String
    var ownerDeviceId: String
    var counters: String
    var createdAt: Int64
    var updatedAt: Int64
    var deletedAt: Int64?

    init(_ series: NumberingSeries) throws {
        id = series.id
        businessId = series.businessId
        docType = series.docType.rawValue
        label = series.label
        pattern = series.pattern
        reset = series.reset.rawValue
        ownerDeviceId = series.ownerDeviceId
        counters = try JSONColumn.encode(series.counters) ?? "{}"
        createdAt = series.createdAt
        updatedAt = series.updatedAt
        deletedAt = series.deletedAt
    }

    func series() throws -> NumberingSeries {
        NumberingSeries(
            id: id, createdAt: createdAt, updatedAt: updatedAt, deletedAt: deletedAt, businessId: businessId,
            docType: DocumentType(rawValue: docType), label: label, pattern: pattern,
            reset: NumberingReset(rawValue: reset), ownerDeviceId: ownerDeviceId,
            counters: try JSONColumn.decode([String: Int].self, from: counters) ?? [:]
        )
    }
}

struct AssetRecord: SnakeCaseRecord, Equatable {
    static let databaseTableName = "asset"

    var id: String
    var businessId: String
    var kind: String
    var mime: String
    var sha256: String
    var data: Data
    var createdAt: Int64
    var updatedAt: Int64
    var deletedAt: Int64?

    init(_ asset: Asset) {
        id = asset.id
        businessId = asset.businessId
        kind = asset.kind.rawValue
        mime = asset.mime
        sha256 = asset.sha256
        data = asset.data
        createdAt = asset.createdAt
        updatedAt = asset.updatedAt
        deletedAt = asset.deletedAt
    }

    func asset() -> Asset {
        Asset(id: id, createdAt: createdAt, updatedAt: updatedAt, deletedAt: deletedAt, businessId: businessId,
              kind: AssetKind(rawValue: kind), mime: mime, sha256: sha256, data: data)
    }
}

/// Local only: never synced, never backed up.
struct DeviceStateRecord: SnakeCaseRecord, Equatable {
    static let databaseTableName = "device_state"

    var id: String
    var deviceName: String
    var freeCounterMirror: Int64
    var preferences: String
    var createdAt: Int64
    var updatedAt: Int64

    init(_ state: DeviceState) throws {
        id = state.id
        deviceName = state.deviceName
        freeCounterMirror = state.freeCounterMirror
        preferences = try JSONColumn.encode(state.preferences) ?? "{}"
        createdAt = state.createdAt
        updatedAt = state.updatedAt
    }

    func deviceState() throws -> DeviceState {
        DeviceState(
            id: id, deviceName: deviceName, freeCounterMirror: freeCounterMirror,
            preferences: try JSONColumn.decode(DevicePreferences.self, from: preferences) ?? DevicePreferences(),
            createdAt: createdAt, updatedAt: updatedAt
        )
    }
}
