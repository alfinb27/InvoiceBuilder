package app.invoicebuilder.core.domain

import app.invoicebuilder.core.domain.billing.EntitlementEvent
import app.invoicebuilder.core.domain.billing.EntitlementMachine
import app.invoicebuilder.core.domain.billing.EntitlementState
import app.invoicebuilder.core.domain.billing.FreeTier
import app.invoicebuilder.core.domain.dates.MonthDay
import app.invoicebuilder.core.domain.dates.parseIsoDate
import app.invoicebuilder.core.domain.decimal.DecimalInput
import app.invoicebuilder.core.domain.decimal.DecimalString
import app.invoicebuilder.core.domain.decimal.MoneyInput
import app.invoicebuilder.core.domain.decimal.Outcome
import app.invoicebuilder.core.domain.documents.AmountInWords
import app.invoicebuilder.core.domain.documents.DocumentLifecycle
import app.invoicebuilder.core.domain.documents.DocumentStatus
import app.invoicebuilder.core.domain.documents.QuoteOutcome
import app.invoicebuilder.core.domain.documents.ReminderCandidate
import app.invoicebuilder.core.domain.documents.ReminderScheduler
import app.invoicebuilder.core.domain.documents.UPIPaymentLink
import app.invoicebuilder.core.domain.models.DocumentType
import app.invoicebuilder.core.domain.money.CurrencyCode
import app.invoicebuilder.core.domain.money.SpecFormatter
import app.invoicebuilder.core.domain.numbering.DuplicateNumbers
import app.invoicebuilder.core.domain.numbering.Numbering
import app.invoicebuilder.core.domain.numbering.NumberingReset
import app.invoicebuilder.core.domain.numbering.SeriesOwnership
import app.invoicebuilder.core.domain.reference.ReferenceData
import app.invoicebuilder.core.domain.support.SpecJson
import app.invoicebuilder.core.domain.tax.EngineBuyer
import app.invoicebuilder.core.domain.tax.EngineDraft
import app.invoicebuilder.core.domain.tax.EngineInput
import app.invoicebuilder.core.domain.tax.EngineSeller
import app.invoicebuilder.core.domain.tax.RoundingMode
import app.invoicebuilder.core.domain.tax.SpecMath
import app.invoicebuilder.core.domain.tax.TaxConfigStore
import app.invoicebuilder.core.domain.tax.TaxEngine
import app.invoicebuilder.core.domain.tax.TaxEngineError
import app.invoicebuilder.core.domain.tax.TaxIDValidator
import app.invoicebuilder.core.domain.validation.FieldRule
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.int
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.long
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.DynamicTest
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.TestFactory

/**
 * Runs every golden fixture kind that `:core:domain` implements (iOS: `FixtureTests.swift`). Kinds still waiting
 * for a runner are listed in [pendingKinds], so the fixture count stays an explicit parity metric
 * (`docs/parity.md`).
 */
class FixtureTests {
    companion object {
        val implementedKinds = mutableSetOf(
            "validation", "field", "input", "format", "numbering", "tax", "rounding", "distribute", "words", "status",
            "upi", "reminder", "series", "billing", "document", "pdf", "backup",
        )
        /** Kinds with no runner yet (none: every spec fixture kind runs on Android). */
        val pendingKinds = mutableSetOf<String>()

        val configs: TaxConfigStore by lazy { TaxConfigStore.bundled() }
        val reference: ReferenceData by lazy { ReferenceData.bundled() }
        val currencies get() = reference.currencies
        val formatter by lazy { SpecFormatter(currencies) }
    }

    private fun cases(kind: String, run: (FixtureCase) -> Unit): List<DynamicTest> =
        Fixtures.cases(kind).map { fixture -> DynamicTest.dynamicTest(fixture.id) { run(fixture) } }

    @Test
    fun everyKindIsImplementedOrExplicitlyPending() {
        val kinds = Fixtures.all.map { it.kind }.toSet()
        assertTrue(Fixtures.all.isNotEmpty(), "no fixtures found under ${Spec.root}")
        assertEquals(emptySet<String>(), kinds - implementedKinds - pendingKinds, "fixture kinds with no runner")
        for (kind in implementedKinds) assertTrue(Fixtures.cases(kind).isNotEmpty(), "no $kind fixtures")
    }

    @Test
    fun caseIDsAreUnique() {
        val ids = Fixtures.all.map { it.id }
        assertEquals(ids.size, ids.toSet().size)
    }

    // ENGINE.md §8
    @TestFactory
    fun validation() = cases("validation") { fixture ->
        val config = configs.config(fixture.string("config"))!!
        val format = config.taxIdFormats.first { it.id == fixture.string("format") }
        val result = TaxIDValidator.validate(fixture.string("value"), format, config.regions)
        expectFixture(fixture, obj("valid" to result.valid, "normalized" to result.normalized, "region" to result.region,
            "error" to result.error?.rawValue))
    }

    // setup.md §8
    @TestFactory
    fun field() = cases("field") { fixture ->
        val result = FieldRule.of(fixture.string("rule"))!!.validate(fixture.string("value"))
        expectFixture(fixture, obj("valid" to result.valid, "normalized" to result.normalized, "error" to result.error?.rawValue))
    }

    // setup.md §11
    @TestFactory
    fun input() = cases("input") { fixture ->
        val text = fixture.string("text")
        when (fixture.string("op")) {
            "money" -> {
                val exponent = currencies[CurrencyCode(fixture.string("currency"))]!!.minorUnits
                when (val result = MoneyInput.parse(text, exponent)) {
                    is Outcome.Success -> expectFixture(fixture, obj("minor" to result.value))
                    is Outcome.Failure -> expectFixture(fixture, obj("error" to result.error.rawValue))
                }
            }
            "decimal" -> when (val result = DecimalInput.parse(text)) {
                is Outcome.Success -> expectFixture(fixture, obj("value" to result.value))
                is Outcome.Failure -> expectFixture(fixture, obj("error" to result.error.rawValue))
            }
            else -> error("${fixture.id}: unknown op")
        }
    }

    // ENGINE.md §7.1–7.2
    @TestFactory
    fun format() = cases("format") { fixture ->
        val text = when (fixture.string("op")) {
            "money" -> formatter.money(fixture.long("minor"), CurrencyCode(fixture.string("currency")), CurrencyCode(fixture.string("homeCurrency")))
            "percent" -> SpecFormatter.percent(fixture.string("value"))
            "quantity" -> SpecFormatter.quantity(fixture.string("value"))
            else -> error("${fixture.id}: unknown op")
        }
        expectFixture(fixture, obj("text" to text))
    }

    // ENGINE.md §5
    @TestFactory
    fun numbering() = cases("numbering") { fixture ->
        val result = Numbering.format(
            pattern = fixture.string("pattern"), reset = NumberingReset(fixture.string("reset")),
            date = parseIsoDate(fixture.string("date"))!!, seq = fixture.long("seq").toInt(),
            fiscalYearStart = MonthDay.parse(fixture.string("fiscalYearStart"))!!,
            maxLength = fixture.input["maxLength"]?.jsonPrimitive?.int,
            allowedPattern = fixture.optionalString("allowedPattern"),
        )
        when (result) {
            is Outcome.Success -> expectFixture(fixture, obj("number" to result.value.number, "periodKey" to result.value.periodKey))
            is Outcome.Failure -> expectFixture(fixture, obj("error" to result.error.rawValue))
        }
    }

    // ENGINE.md §1–4
    @kotlinx.serialization.Serializable
    data class TaxCaseInput(val seller: EngineSeller, val buyer: EngineBuyer, val draft: EngineDraft)

    @TestFactory
    fun tax() = cases("tax") { fixture ->
        val config = configs.config(fixture.config!!) ?: error("${fixture.id}: unknown config ${fixture.config}")
        val input = SpecJson.decodeFromJsonElement(TaxCaseInput.serializer(), fixture.input)
        try {
            val result = TaxEngine.compute(EngineInput(config, input.seller, input.buyer, input.draft, currencies))
            expectFixture(fixture, SpecJson.encodeToJsonElement(app.invoicebuilder.core.domain.tax.ComputedDocument.serializer(), result))
        } catch (error: TaxEngineError) {
            expectFixture(fixture, obj("error" to error.code.rawValue, *listOfNotNull(error.line?.let { "line" to it }).toTypedArray()))
        }
    }

    // ENGINE.md §2.2–2.4
    @TestFactory
    fun rounding() = cases("rounding") { fixture ->
        val value = DecimalString.parse(fixture.string("value"))!!
        val mode = RoundingMode.of(fixture.string("mode"))!!
        expectFixture(fixture, obj("result" to SpecMath.round(value, mode)))
    }

    @TestFactory
    fun distribute() = cases("distribute") { fixture ->
        val total = fixture.long("total")
        val parts = when {
            fixture.input["exacts"] != null -> SpecMath.distribute(total, fixture.input["exacts"]!!.jsonArray.map { DecimalString.parse(it.jsonPrimitive.content)!! })
            fixture.input["weights"] != null -> SpecMath.allocateProportional(total, fixture.input["weights"]!!.jsonArray.map { it.jsonPrimitive.long })
            else -> error("${fixture.id}: needs exacts or weights")
        }
        expectFixture(fixture, obj("parts" to parts))
    }

    // ENGINE.md §7.3
    @TestFactory
    fun words() = cases("words") { fixture ->
        expectFixture(fixture, obj("text" to AmountInWords.text(fixture.long("minor"), CurrencyCode(fixture.string("currency")), currencies)))
    }

    // ENGINE.md §6
    @TestFactory
    fun status() = cases("status") { fixture ->
        val input = DocumentStatus.Input(
            docType = DocumentType(fixture.string("docType")), lifecycle = DocumentLifecycle(fixture.string("lifecycle")),
            total = fixture.long("total"), paid = fixture.long("paid"),
            dueDate = fixture.optionalString("dueDate")?.let(::parseIsoDate),
            validUntil = fixture.optionalString("validUntil")?.let(::parseIsoDate),
            sentAt = fixture.input["sentAt"]?.jsonPrimitive?.contentOrNull?.toLongOrNull(),
            outcome = fixture.optionalString("outcome")?.let(::QuoteOutcome),
            today = parseIsoDate(fixture.string("today"))!!,
        )
        val fields = mutableListOf<Pair<String, Any?>>("status" to DocumentStatus.derive(input).rawValue)
        DocumentStatus.outstanding(input)?.let { fields += "outstanding" to it }
        expectFixture(fixture, obj(*fields.toTypedArray()))
    }

    // ENGINE.md §9
    @TestFactory
    fun upi() = cases("upi") { fixture ->
        val url = UPIPaymentLink.url(fixture.string("vpa"), fixture.string("payeeName"), fixture.long("amountMinor"), fixture.string("invoiceNumber"))
        expectFixture(fixture, obj("url" to url))
    }

    // reminders.md §3
    @TestFactory
    fun reminder() = cases("reminder") { fixture ->
        val candidates = fixture.input["candidates"]!!.jsonArray.map { element ->
            val candidate = element.jsonObject
            ReminderCandidate(
                documentId = candidate["documentId"]!!.jsonPrimitive.content,
                dueDate = candidate["dueDate"]?.jsonPrimitive?.contentOrNull?.let(::parseIsoDate),
                overrideDays = candidate["overrideDays"]?.jsonPrimitive?.contentOrNull?.toInt(),
                status = DocumentStatus.of(candidate["status"]!!.jsonPrimitive.content)!!,
            )
        }
        val scheduled = ReminderScheduler.plan(
            businessDefaultDays = fixture.input["businessDefaultDays"]?.jsonPrimitive?.contentOrNull?.toInt(),
            cap = fixture.long("cap").toInt(), candidates = candidates,
        )
        expectFixture(fixture, obj("scheduled" to scheduled.map { mapOf("documentId" to it.documentId, "remindOn" to it.remindOn.toString()) }))
    }

    // sync.md §3–4
    @TestFactory
    fun series() = cases("series") { fixture ->
        when (fixture.string("op")) {
            "deviceSeries" -> when (val result = SeriesOwnership.deviceSeriesPattern(
                fixture.string("pattern"), DocumentType(fixture.string("docType")),
                fixture.input["existingPatterns"]?.jsonArray?.map { it.jsonPrimitive.content } ?: emptyList(),
            )) {
                is Outcome.Success -> expectFixture(fixture, obj("pattern" to result.value.pattern, "label" to result.value.label))
                is Outcome.Failure -> expectFixture(fixture, obj("error" to result.error.rawValue))
            }
            "takeOver" -> {
                fun counts(key: String): Map<String, Int> =
                    (fixture.input[key] as? JsonObject)?.mapValues { it.value.jsonPrimitive.int } ?: emptyMap()
                expectFixture(fixture, obj("counters" to SeriesOwnership.takeOverCounters(counts("counters"), counts("highest"))))
            }
            "duplicates" -> {
                val rows = fixture.input["documents"]!!.jsonArray.map { element ->
                    val row = element.jsonObject
                    DuplicateNumbers.Row(
                        row["id"]!!.jsonPrimitive.content, DocumentType(row["docType"]!!.jsonPrimitive.content),
                        DocumentLifecycle(row["lifecycle"]!!.jsonPrimitive.content), row["number"]?.jsonPrimitive?.contentOrNull,
                    )
                }
                expectFixture(fixture, obj("groups" to DuplicateNumbers.find(rows).map {
                    mapOf("docType" to it.docType.rawValue, "number" to it.number, "ids" to it.ids)
                }))
            }
            else -> error("${fixture.id}: unknown op")
        }
    }

    // documents.md §2, §3.1
    @kotlinx.serialization.Serializable
    data class DefaultsInput(val config: String, val docType: DocumentType, val today: app.invoicebuilder.core.domain.dates.IsoDate,
                             val business: BusinessFields, val client: ClientFields? = null) {
        @kotlinx.serialization.Serializable
        data class BusinessFields(val countryCode: String, val homeCurrency: CurrencyCode, val paymentTermsDays: Int, val lutReference: String? = null)
        @kotlinx.serialization.Serializable
        data class ClientFields(val countryCode: String, val isBusiness: Boolean, val defaultCurrency: CurrencyCode? = null)
    }

    @kotlinx.serialization.Serializable
    data class LinePriceInput(val config: String, val registration: String, val homeCurrency: CurrencyCode,
                              val customRates: List<app.invoicebuilder.core.domain.tax.TaxRate>? = null, val item: ItemFields, val document: DocumentFields) {
        @kotlinx.serialization.Serializable
        data class ItemFields(val unitPriceMinor: Long, val currency: CurrencyCode, val priceIncludesTax: Boolean, val rateId: String)
        @kotlinx.serialization.Serializable
        data class DocumentFields(val currency: CurrencyCode, val exchangeRate: String? = null, val pricesIncludeTax: Boolean)
    }

    @TestFactory
    fun document() = cases("document") { fixture ->
        when (fixture.string("op")) {
            "defaults" -> {
                val input = SpecJson.decodeFromJsonElement(DefaultsInput.serializer(), fixture.input)
                val config = configs.config(input.config)!!
                val business = app.invoicebuilder.core.domain.models.Business(
                    id = "b", name = "Business", countryCode = input.business.countryCode, taxConfig = config.family,
                    taxRegistration = config.registrations[0].id,
                    extraIds = input.business.lutReference?.let { app.invoicebuilder.core.domain.models.ExtraIDs(lutReference = it) },
                    homeCurrency = input.business.homeCurrency, paymentTermsDays = input.business.paymentTermsDays,
                )
                val client = input.client?.let {
                    app.invoicebuilder.core.domain.models.Client(id = "c", businessId = "b", name = "Client", countryCode = it.countryCode,
                        isBusiness = it.isBusiness, defaultCurrency = it.defaultCurrency)
                }
                val rules = app.invoicebuilder.core.domain.documents.DocumentRules(configs, business, currencies)
                val document = rules.newDocument(input.docType, "d", input.today, client, 0)
                expectFixture(fixture, obj(
                    "issueDate" to document.issueDate.toString(), "dueDate" to document.dueDate?.toString(),
                    "validUntil" to document.validUntil?.toString(), "currency" to document.currency.rawValue,
                    "supplyType" to document.supplyType, "roundOff" to document.roundOff,
                ))
            }
            "linePrice" -> {
                val input = SpecJson.decodeFromJsonElement(LinePriceInput.serializer(), fixture.input)
                val config = configs.config(input.config)!!
                val item = app.invoicebuilder.core.domain.models.CatalogItem(id = "i", businessId = "b", name = "Item", unit = "NOS",
                    unitPriceMinor = input.item.unitPriceMinor, currency = input.item.currency, rateId = input.item.rateId,
                    priceIncludesTax = input.item.priceIncludesTax)
                val result = app.invoicebuilder.core.domain.documents.LinePricing.unitPrice(
                    item, config.rate(input.item.rateId, input.customRates), config.registration(input.registration)!!.chargesTax,
                    input.homeCurrency, input.document.currency, input.document.exchangeRate, input.document.pricesIncludeTax,
                    currencies, config.rounding.amountMode,
                )
                when (result) {
                    is Outcome.Success -> expectFixture(fixture, obj("unitPriceMinor" to result.value))
                    is Outcome.Failure -> expectFixture(fixture, obj("error" to result.error.rawValue))
                }
            }
            else -> error("${fixture.id}: unknown op")
        }
    }

    // pdf/RENDERING.md §1
    @kotlinx.serialization.Serializable
    data class PDFCaseInput(val template: String, val document: app.invoicebuilder.core.domain.documents.Document)

    @TestFactory
    fun pdf() = cases("pdf") { fixture ->
        val input = SpecJson.decodeFromJsonElement(PDFCaseInput.serializer(), fixture.input)
        val document = input.document
        val config = configs.config(document.taxConfigRef)!!
        val seller = document.sellerSnapshot!!
        val computed = TaxEngine.compute(app.invoicebuilder.core.domain.documents.engineInput(
            document, seller.engineSeller, document.buyerSnapshot?.engineBuyer ?: EngineBuyer(), config, currencies))
        val model = app.invoicebuilder.core.domain.pdf.PDFModelBuilder.build(document, computed, config,
            app.invoicebuilder.core.domain.pdf.PDFLabels.bundled(), reference)
        expectFixture(fixture, SpecJson.encodeToJsonElement(app.invoicebuilder.core.domain.pdf.PDFDocumentModel.serializer(), model))
    }

    // backup.md §3
    @TestFactory
    fun backup() = cases("backup") { fixture ->
        val bytes = fixture.optionalString("raw")?.toByteArray() ?: run {
            var root: JsonElement = kotlinx.serialization.json.Json.parseToJsonElement(java.io.File(Spec.root, fixture.string("base")).readText())
            for (pointer in fixture.input["remove"]?.jsonArray ?: emptyList()) root = JsonPointer.remove(pointer.jsonPrimitive.content, root)
            for ((pointer, value) in (fixture.input["set"] as? JsonObject) ?: JsonObject(emptyMap())) root = JsonPointer.set(pointer, value, root)
            root.toString().toByteArray()
        }
        when (val result = app.invoicebuilder.core.domain.backup.BackupCodec.validate(bytes, fixture.long("appSchemaVersion").toInt())) {
            is Outcome.Success -> {
                val live = result.value.live
                expectFixture(fixture, obj("live" to mapOf("businesses" to live.businesses, "clients" to live.clients,
                    "catalogItems" to live.catalogItems, "numberingSeries" to live.numberingSeries, "documents" to live.documents,
                    "payments" to live.payments, "assets" to live.assets)))
            }
            is Outcome.Failure -> expectFixture(fixture, obj("error" to result.error.code.rawValue))
        }
    }

    @Test
    fun bundledFileListsMatchTheSpec() {
        fun names(folder: String) = java.io.File(Spec.root, folder).listFiles()!!.map { it.name }.filter { it.endsWith(".json") }.sorted()
        assertEquals(names("tax"), TaxConfigStore.bundledFiles.sorted())
        assertEquals(names("pdf/layout"), app.invoicebuilder.core.domain.pdf.PDFTemplateStore.bundledFiles.sorted())
        assertEquals(4, app.invoicebuilder.core.domain.pdf.PDFTemplateStore.bundled().all.size)
    }

    // billing.md, Transitions
    @TestFactory
    fun billing() = cases("billing") { fixture ->
        val count = fixture.long("count").toInt()
        val next = EntitlementMachine.next(EntitlementState.of(fixture.string("state"))!!, EntitlementEvent.of(fixture.string("event"))!!, count)
        expectFixture(fixture, obj("state" to next.name, "canIssueInvoice" to EntitlementMachine.canIssueInvoice(next, count),
            "remaining" to FreeTier.remaining(count)))
    }
}

@Suppress("unused")
private fun JsonElement.text(): String = jsonPrimitive.content

/** RFC 6901 pointers over JSON elements, for patching backup fixtures. */
object JsonPointer {
    fun set(pointer: String, value: JsonElement, root: JsonElement): JsonElement = update(parts(pointer), root) { value }
    fun remove(pointer: String, root: JsonElement): JsonElement = update(parts(pointer), root) { null }

    private fun parts(pointer: String) = pointer.split("/").drop(1).map { it.replace("~1", "/").replace("~0", "~") }

    private fun update(path: List<String>, node: JsonElement, change: (JsonElement?) -> JsonElement?): JsonElement {
        val key = path.firstOrNull() ?: return change(node) ?: kotlinx.serialization.json.JsonNull
        val rest = path.drop(1)
        if (node is kotlinx.serialization.json.JsonArray) {
            val index = key.toInt()
            val items = node.toMutableList()
            if (rest.isEmpty()) {
                val value = change(items[index])
                if (value == null) items.removeAt(index) else items[index] = value
            } else {
                items[index] = update(rest, items[index], change)
            }
            return kotlinx.serialization.json.JsonArray(items)
        }
        val fields = (node as? JsonObject)?.toMutableMap() ?: mutableMapOf()
        if (rest.isEmpty()) {
            val value = change(fields[key])
            if (value == null) fields.remove(key) else fields[key] = value
        } else {
            fields[key] = update(rest, fields[key] ?: JsonObject(emptyMap()), change)
        }
        return JsonObject(fields)
    }
}
