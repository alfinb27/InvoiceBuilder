package app.invoicebuilder.core.data

import app.invoicebuilder.core.domain.dates.iso
import app.invoicebuilder.core.domain.dates.parseIsoDate
import app.invoicebuilder.core.domain.documents.BuyerSnapshot
import app.invoicebuilder.core.domain.documents.Document
import app.invoicebuilder.core.domain.documents.DocumentLifecycle
import app.invoicebuilder.core.domain.documents.DocumentTotals
import app.invoicebuilder.core.domain.documents.LineItem
import app.invoicebuilder.core.domain.documents.Payment
import app.invoicebuilder.core.domain.documents.PaymentMethod
import app.invoicebuilder.core.domain.documents.QuoteOutcome
import app.invoicebuilder.core.domain.documents.RateSnapshot
import app.invoicebuilder.core.domain.documents.SellerSnapshot
import app.invoicebuilder.core.domain.models.Address
import app.invoicebuilder.core.domain.models.Asset
import app.invoicebuilder.core.domain.models.AssetKind
import app.invoicebuilder.core.domain.models.BankDetails
import app.invoicebuilder.core.domain.models.Business
import app.invoicebuilder.core.domain.models.CatalogItem
import app.invoicebuilder.core.domain.models.Client
import app.invoicebuilder.core.domain.models.DevicePreferences
import app.invoicebuilder.core.domain.models.DeviceState
import app.invoicebuilder.core.domain.models.DocumentType
import app.invoicebuilder.core.domain.models.ExtraIDs
import app.invoicebuilder.core.domain.models.ItemKind
import app.invoicebuilder.core.domain.models.NumberingSeries
import app.invoicebuilder.core.domain.models.TemplateID
import app.invoicebuilder.core.domain.money.CurrencyCode
import app.invoicebuilder.core.domain.numbering.NumberingReset
import app.invoicebuilder.core.domain.support.SpecJson
import app.invoicebuilder.core.domain.tax.ComputedDocument
import app.invoicebuilder.core.domain.tax.ComputedTaxLine
import app.invoicebuilder.core.domain.tax.Discount
import app.invoicebuilder.core.domain.tax.TaxRate
import kotlinx.serialization.KSerializer
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.builtins.MapSerializer
import kotlinx.serialization.builtins.serializer
import java.time.LocalDate

// Entity ↔ domain mapping (iOS: the GRDB records' `init(_:)` and `business()`, `client()`, …). JSON columns hold the
// domain JSON form (`domain.schema.json`, camelCase keys), like on iOS.

internal object JsonColumn {
    fun <T> encode(serializer: KSerializer<T>, value: T?): String? = value?.let { SpecJson.encodeToString(serializer, it) }
    fun <T> decode(serializer: KSerializer<T>, text: String?): T? =
        if (text.isNullOrEmpty()) null else SpecJson.decodeFromString(serializer, text)
}

internal fun date(text: String): LocalDate = parseIsoDate(text) ?: throw IllegalStateException("unreadable date: $text")

private val taxRates = ListSerializer(TaxRate.serializer())
private val countersSerializer = MapSerializer(String.serializer(), Int.serializer())

internal fun Business.toEntity() = BusinessEntity(
    id = id, name = name, legalName = legalName, address = JsonColumn.encode(Address.serializer(), address), email = email,
    phone = phone, website = website, countryCode = countryCode, taxConfig = taxConfig, taxRegistration = taxRegistration,
    taxId = taxId, extraIds = JsonColumn.encode(ExtraIDs.serializer(), extraIds), homeCurrency = homeCurrency.rawValue,
    turnoverMinor = turnoverMinor, bank = JsonColumn.encode(BankDetails.serializer(), bank), upiVpa = upiVpa,
    paymentTermsDays = paymentTermsDays, defaultNotes = defaultNotes, defaultTerms = defaultTerms, templateId = templateId.rawValue,
    accentColor = accentColor, logoAssetId = logoAssetId, signatureAssetId = signatureAssetId,
    reminderDaysAfterDue = reminderDaysAfterDue, customRates = JsonColumn.encode(taxRates, customRates),
    createdAt = createdAt, updatedAt = updatedAt, deletedAt = deletedAt,
)

internal fun BusinessEntity.toDomain() = Business(
    id = id, createdAt = createdAt, updatedAt = updatedAt, deletedAt = deletedAt, name = name, legalName = legalName,
    address = JsonColumn.decode(Address.serializer(), address), email = email, phone = phone, website = website,
    countryCode = countryCode, taxConfig = taxConfig, taxRegistration = taxRegistration, taxId = taxId,
    extraIds = JsonColumn.decode(ExtraIDs.serializer(), extraIds), homeCurrency = CurrencyCode(homeCurrency),
    turnoverMinor = turnoverMinor, bank = JsonColumn.decode(BankDetails.serializer(), bank), upiVpa = upiVpa,
    paymentTermsDays = paymentTermsDays, defaultNotes = defaultNotes, defaultTerms = defaultTerms,
    templateId = TemplateID(templateId), accentColor = accentColor, logoAssetId = logoAssetId,
    signatureAssetId = signatureAssetId, reminderDaysAfterDue = reminderDaysAfterDue,
    customRates = JsonColumn.decode(taxRates, customRates),
)

internal fun Client.toEntity() = ClientEntity(
    id = id, businessId = businessId, name = name, contactName = contactName, email = email, phone = phone,
    billingAddress = JsonColumn.encode(Address.serializer(), billingAddress),
    shippingAddress = JsonColumn.encode(Address.serializer(), shippingAddress), countryCode = countryCode,
    regionCode = regionCode, taxId = taxId, isBusiness = isBusiness, defaultCurrency = defaultCurrency?.rawValue, notes = notes,
    archivedAt = archivedAt, createdAt = createdAt, updatedAt = updatedAt, deletedAt = deletedAt,
)

internal fun ClientEntity.toDomain() = Client(
    id = id, createdAt = createdAt, updatedAt = updatedAt, deletedAt = deletedAt, businessId = businessId, name = name,
    contactName = contactName, email = email, phone = phone, billingAddress = JsonColumn.decode(Address.serializer(), billingAddress),
    shippingAddress = JsonColumn.decode(Address.serializer(), shippingAddress), countryCode = countryCode, regionCode = regionCode,
    taxId = taxId, isBusiness = isBusiness, defaultCurrency = defaultCurrency?.let(::CurrencyCode), notes = notes, archivedAt = archivedAt,
)

internal fun CatalogItem.toEntity() = CatalogItemEntity(
    id = id, businessId = businessId, name = name, description = description, kind = kind.rawValue, unit = unit,
    unitPriceMinor = unitPriceMinor, currency = currency.rawValue, rateId = rateId, productCode = productCode,
    priceIncludesTax = priceIncludesTax, archivedAt = archivedAt, createdAt = createdAt, updatedAt = updatedAt, deletedAt = deletedAt,
)

internal fun CatalogItemEntity.toDomain() = CatalogItem(
    id = id, createdAt = createdAt, updatedAt = updatedAt, deletedAt = deletedAt, businessId = businessId, name = name,
    description = description, kind = ItemKind(kind), unit = unit, unitPriceMinor = unitPriceMinor, currency = CurrencyCode(currency),
    rateId = rateId, productCode = productCode, priceIncludesTax = priceIncludesTax, archivedAt = archivedAt,
)

internal fun NumberingSeries.toEntity() = NumberingSeriesEntity(
    id = id, businessId = businessId, docType = docType.rawValue, label = label, pattern = pattern, reset = reset.rawValue,
    ownerDeviceId = ownerDeviceId, counters = SpecJson.encodeToString(countersSerializer, counters),
    createdAt = createdAt, updatedAt = updatedAt, deletedAt = deletedAt,
)

internal fun NumberingSeriesEntity.toDomain() = NumberingSeries(
    id = id, createdAt = createdAt, updatedAt = updatedAt, deletedAt = deletedAt, businessId = businessId,
    docType = DocumentType(docType), label = label, pattern = pattern, reset = NumberingReset(reset), ownerDeviceId = ownerDeviceId,
    counters = JsonColumn.decode(countersSerializer, counters) ?: emptyMap(),
)

internal fun Asset.toEntity() = AssetEntity(
    id = id, businessId = businessId, kind = kind.rawValue, mime = mime, sha256 = sha256, data = data,
    createdAt = createdAt, updatedAt = updatedAt, deletedAt = deletedAt,
)

internal fun AssetEntity.toDomain() = Asset(
    id = id, createdAt = createdAt, updatedAt = updatedAt, deletedAt = deletedAt, businessId = businessId,
    kind = AssetKind(kind), mime = mime, sha256 = sha256, data = data,
)

internal fun DeviceState.toEntity() = DeviceStateEntity(
    id = id, deviceName = deviceName, freeCounterMirror = freeCounterMirror,
    preferences = SpecJson.encodeToString(DevicePreferences.serializer(), preferences), createdAt = createdAt, updatedAt = updatedAt,
)

internal fun DeviceStateEntity.toDomain() = DeviceState(
    id = id, deviceName = deviceName, freeCounterMirror = freeCounterMirror,
    preferences = JsonColumn.decode(DevicePreferences.serializer(), preferences) ?: DevicePreferences(), createdAt = createdAt, updatedAt = updatedAt,
)

internal fun Payment.toEntity() = PaymentEntity(
    id = id, businessId = businessId, documentId = documentId, amountMinor = amountMinor, date = date.iso, method = method.rawValue,
    reference = reference, note = note, createdAt = createdAt, updatedAt = updatedAt, deletedAt = deletedAt,
)

internal fun PaymentEntity.toDomain() = Payment(
    id = id, createdAt = createdAt, updatedAt = updatedAt, deletedAt = deletedAt, businessId = businessId, documentId = documentId,
    amountMinor = amountMinor, date = date(date), method = PaymentMethod(method), reference = reference, note = note,
)

internal fun Document.toEntity() = DocumentEntity(
    id = id, businessId = businessId, docType = docType.rawValue, number = number, seriesId = seriesId, periodKey = periodKey,
    lifecycle = lifecycle.rawValue, issueDate = issueDate.iso, supplyDate = supplyDate?.iso, dueDate = dueDate?.iso,
    validUntil = validUntil?.iso, sentAt = sentAt, voidedAt = voidedAt, voidReason = voidReason, quoteOutcome = quoteOutcome?.rawValue,
    convertedFromId = convertedFromId, currency = currency.rawValue, exchangeRate = exchangeRate, supplyType = supplyType,
    placeOfSupply = placeOfSupply, reverseCharge = reverseCharge, pricesIncludeTax = pricesIncludeTax, roundOff = roundOff,
    clientId = clientId, sellerSnapshot = JsonColumn.encode(SellerSnapshot.serializer(), sellerSnapshot),
    buyerSnapshot = JsonColumn.encode(BuyerSnapshot.serializer(), buyerSnapshot), discount = JsonColumn.encode(Discount.serializer(), discount),
    shippingMinor = shippingMinor, notes = notes, terms = terms, templateId = templateId.rawValue, taxConfigRef = taxConfigRef,
    revision = revision, subtotalMinor = totals.subtotalMinor, discountMinor = totals.discountMinor, taxableMinor = totals.taxableMinor,
    taxMinor = totals.taxMinor, taxNotChargedMinor = totals.taxNotChargedMinor, roundOffMinor = totals.roundOffMinor,
    totalMinor = totals.totalMinor, computed = JsonColumn.encode(ComputedDocument.serializer(), computed),
    createdAt = createdAt, updatedAt = updatedAt, deletedAt = deletedAt, sequence = sequence,
    reminderDaysAfterDueOverride = reminderDaysAfterDueOverride,
)

internal fun DocumentEntity.toDomain(lines: List<LineItem>) = Document(
    id = id, createdAt = createdAt, updatedAt = updatedAt, deletedAt = deletedAt, businessId = businessId,
    docType = DocumentType(docType), number = number, seriesId = seriesId, periodKey = periodKey, sequence = sequence,
    lifecycle = DocumentLifecycle(lifecycle), issueDate = date(issueDate), supplyDate = supplyDate?.let(::date),
    dueDate = dueDate?.let(::date), reminderDaysAfterDueOverride = reminderDaysAfterDueOverride, validUntil = validUntil?.let(::date),
    sentAt = sentAt, voidedAt = voidedAt, voidReason = voidReason, quoteOutcome = quoteOutcome?.let(::QuoteOutcome),
    convertedFromId = convertedFromId, currency = CurrencyCode(currency), exchangeRate = exchangeRate, supplyType = supplyType,
    placeOfSupply = placeOfSupply, reverseCharge = reverseCharge, pricesIncludeTax = pricesIncludeTax, roundOff = roundOff,
    clientId = clientId, sellerSnapshot = JsonColumn.decode(SellerSnapshot.serializer(), sellerSnapshot),
    buyerSnapshot = JsonColumn.decode(BuyerSnapshot.serializer(), buyerSnapshot), discount = JsonColumn.decode(Discount.serializer(), discount),
    shippingMinor = shippingMinor, notes = notes, terms = terms, templateId = TemplateID(templateId), taxConfigRef = taxConfigRef,
    revision = revision, lines = lines,
    totals = DocumentTotals(subtotalMinor, discountMinor, shippingMinor, taxableMinor, taxMinor, taxNotChargedMinor, roundOffMinor, totalMinor),
    computed = JsonColumn.decode(ComputedDocument.serializer(), computed),
)

internal fun LineItem.toEntity(documentID: String, createdAt: Long, updatedAt: Long) = LineItemEntity(
    id = id, documentId = documentID, position = position, catalogItemId = catalogItemId, description = description,
    productCode = productCode, unit = unit, quantity = quantity, unitPriceMinor = unitPriceMinor,
    discount = JsonColumn.encode(Discount.serializer(), discount), rateId = rateId,
    rateSnapshot = JsonColumn.encode(RateSnapshot.serializer(), rateSnapshot), amountMinor = amountMinor,
    taxableMinor = taxableMinor, taxMinor = taxMinor, totalMinor = totalMinor, createdAt = createdAt, updatedAt = updatedAt, deletedAt = null,
)

internal fun LineItemEntity.toDomain() = LineItem(
    id = id, position = position, catalogItemId = catalogItemId, description = description, productCode = productCode, unit = unit,
    quantity = quantity, unitPriceMinor = unitPriceMinor, discount = JsonColumn.decode(Discount.serializer(), discount), rateId = rateId,
    rateSnapshot = JsonColumn.decode(RateSnapshot.serializer(), rateSnapshot), amountMinor = amountMinor, taxableMinor = taxableMinor,
    taxMinor = taxMinor, totalMinor = totalMinor,
)

internal fun taxLineEntity(id: String, documentID: String, taxLine: ComputedTaxLine, now: Long) = TaxLineEntity(
    id = id, documentId = documentID, lineId = null, component = taxLine.component, rate = taxLine.rate, category = taxLine.category.rawValue,
    taxableMinor = taxLine.taxable, taxMinor = taxLine.tax, charged = taxLine.charged, createdAt = now, updatedAt = now, deletedAt = null,
)
