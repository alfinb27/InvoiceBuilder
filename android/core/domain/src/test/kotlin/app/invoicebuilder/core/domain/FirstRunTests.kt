package app.invoicebuilder.core.domain

import app.invoicebuilder.core.domain.documents.DocumentLifecycle
import app.invoicebuilder.core.domain.documents.DocumentRules
import app.invoicebuilder.core.domain.documents.DocumentSummary
import app.invoicebuilder.core.domain.documents.LineItem
import app.invoicebuilder.core.domain.documents.OneOffLine
import app.invoicebuilder.core.domain.documents.RateChips
import app.invoicebuilder.core.domain.models.Address
import app.invoicebuilder.core.domain.models.Business
import app.invoicebuilder.core.domain.models.DocumentType
import app.invoicebuilder.core.domain.models.ItemKind
import app.invoicebuilder.core.domain.money.CurrencyCode
import app.invoicebuilder.core.domain.setup.CustomRateDraft
import app.invoicebuilder.core.domain.setup.FirstRunChecklist
import app.invoicebuilder.core.domain.setup.OnboardingStage
import app.invoicebuilder.core.domain.setup.OnboardingStep
import app.invoicebuilder.core.domain.tax.RoundingMode
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import java.time.LocalDate

/** `spec/documents.md` §3.2 and `spec/setup.md` §3, §3.2 (ADR-0020). iOS: `FirstRunTests.swift`. */
class FirstRunTests {
    private val configs = FixtureTests.configs
    private val india = configs.latest("IN")!!
    private val uk = configs.latest("GB")!!
    private val generic = configs.latest("GENERIC")!!
    private val today: LocalDate = LocalDate.parse("2026-09-19")
    private val chips = RateChips.bundled()
    private val business = Business(
        id = "b-in", name = "Bharat Web Studio", address = Address(line1 = "12 MG Road", city = "Bengaluru", regionCode = "29",
            postalCode = "560001", countryCode = "IN"),
        countryCode = "IN", taxConfig = "IN", taxRegistration = "regular", taxId = "29AAGCB7383J1Z4",
        homeCurrency = CurrencyCode.INR,
    )
    private val rules = DocumentRules(configs, business, FixtureTests.currencies)

    // Rate chips

    @Test fun indiaShowsTheFourCommonRatesAndTheRestUnderOtherRates() {
        val choices = chips.choices(india, null, today)
        assertEquals(listOf("gst_0", "gst_5", "gst_18", "gst_40"), choices.chips.map { it.id })
        assertEquals(listOf("gst_0_1", "gst_0_25", "gst_1_5", "gst_3", "gst_28", "exempt", "nil"), choices.others.map { it.id })
        assertTrue(choices.hint!!.startsWith("Most services are 18%"))
    }

    @Test fun aChipRateNotYetInForceIsLeftOut() {
        val choices = chips.choices(india, null, LocalDate.parse("2025-09-21"))
        assertEquals(listOf("gst_0", "gst_5", "gst_18"), choices.chips.map { it.id })
        assertTrue(choices.others.any { it.id == "gst_12" })
    }

    @Test fun theUKShowsStandardReducedAndZero() {
        val choices = chips.choices(uk, null, today)
        assertEquals(listOf("standard", "reduced", "zero"), choices.chips.map { it.id })
        assertEquals(listOf("exempt", "outsideScope"), choices.others.map { it.id })
    }

    @Test fun elsewhereTheBusinessesOwnRatesAreTheChips() {
        val rates = (1..5).map { CustomRateDraft(name = "Tax $it", percent = "$it").makeRate("r$it", today) }
        val choices = chips.choices(generic, rates, today)
        assertEquals(listOf("r1", "r2", "r3", "r4"), choices.chips.map { it.id })
        assertEquals(listOf("r5"), choices.others.map { it.id })
        assertNull(choices.hint)
    }

    // One-off lines

    private fun price(typed: Long, includesTax: Boolean, documentInclusive: Boolean, chargesTax: Boolean = true): Long {
        val document = rules.newDocument(DocumentType.invoice, "d1", today, now = 1).copy(pricesIncludeTax = documentInclusive)
        return OneOffLine.unitPrice(typed, includesTax, india.rate("gst_18", null), document, chargesTax, FixtureTests.currencies,
            RoundingMode.halfAwayFromZero)
    }

    @Test fun aPriceOnTheDocumentsBasisIsKeptAsTyped() {
        assertEquals(250_000L, price(250_000, includesTax = false, documentInclusive = false))
        assertEquals(250_000L, price(250_000, includesTax = true, documentInclusive = true))
        assertEquals(250_000L, price(250_000, includesTax = true, documentInclusive = false, chargesTax = false))
    }

    @Test fun aPriceOnTheOtherBasisIsConvertedWithOneRounding() {
        // ₹2,500 including 18% → 2500 × 100 / 118 = 2118.644… → ₹2,118.64
        assertEquals(211_864L, price(250_000, includesTax = true, documentInclusive = false))
        // ₹2,118.64 before tax → 2118.64 × 118 / 100 = 2499.9952 → ₹2,500.00
        assertEquals(250_000L, price(211_864, includesTax = false, documentInclusive = true))
    }

    @Test fun theSwitchSetsTheDocumentsBasisOnlyWithoutOtherLines() {
        var document = rules.newDocument(DocumentType.invoice, "d1", today, now = 1)
        assertTrue(OneOffLine.setsDocumentBasis(document, null))
        document = document.copy(lines = listOf(LineItem(id = "l1", description = "Design", unitPriceMinor = 100, rateId = "gst_18")))
        assertTrue(OneOffLine.setsDocumentBasis(document, "l1"))
        assertFalse(OneOffLine.setsDocumentBasis(document, null))
        document = document.copy(lines = document.lines + LineItem(id = "l2", description = "Logo", unitPriceMinor = 100, rateId = "gst_18"))
        assertFalse(OneOffLine.setsDocumentBasis(document, "l1"))
    }

    @Test fun savingToMyItemsKeepsTheTypedPriceAndItsBasis() {
        val line = LineItem(id = "l1", description = "Logo refresh", productCode = "998391", quantity = "2", unitPriceMinor = 211_864,
            rateId = "gst_18")
        val item = OneOffLine.catalogItem(line, 250_000, includesTax = true, chargesTax = true, businessID = "b-in",
            currency = CurrencyCode.INR, id = "i1", now = 7)
        assertEquals("Logo refresh", item.name)
        assertEquals(ItemKind.service, item.kind)
        assertEquals(ItemKind.service.defaultUnit, item.unit)
        assertEquals(250_000L, item.unitPriceMinor)
        assertTrue(item.priceIncludesTax)
        assertEquals("gst_18", item.rateId)
        assertEquals("998391", item.productCode)
        assertEquals(7L, item.createdAt)
        val untaxed = OneOffLine.catalogItem(line, 250_000, includesTax = true, chargesTax = false, businessID = "b-in",
            currency = CurrencyCode.INR, id = "i2", now = 7)
        assertFalse(untaxed.priceIncludesTax)
    }

    // First-run checklist

    private fun summary(type: DocumentType, lifecycle: DocumentLifecycle) = DocumentSummary(
        id = java.util.UUID.randomUUID().toString(), docType = type, number = null, lifecycle = lifecycle, issueDate = today,
        dueDate = null, validUntil = null, sentAt = null, quoteOutcome = null, clientId = null, buyerName = null,
        currency = CurrencyCode.INR, totalMinor = 0, lineCount = 1, updatedAt = 0,
    )

    @Test fun aNewBusinessHasOneOfFourDone() {
        val checklist = FirstRunChecklist.of(0, 0, emptyList())
        assertEquals(1, checklist.doneCount)
        assertTrue(checklist.isShown)
        assertTrue(checklist.isDone(FirstRunChecklist.Item.setUpBusiness))
        assertFalse(checklist.isDone(FirstRunChecklist.Item.addClient))
    }

    @Test fun draftsAndQuotesDoNotCountAsSendingTheFirstInvoice() {
        val checklist = FirstRunChecklist.of(2, 1, listOf(summary(DocumentType.invoice, DocumentLifecycle.draft),
            summary(DocumentType.quote, DocumentLifecycle.issued)))
        assertEquals(3, checklist.doneCount)
        assertTrue(checklist.isShown)
    }

    @Test fun anIssuedOrVoidInvoiceEndsTheChecklist() {
        assertFalse(FirstRunChecklist.of(0, 0, listOf(summary(DocumentType.invoice, DocumentLifecycle.issued))).isShown)
        val voided = FirstRunChecklist.of(0, 0, listOf(summary(DocumentType.invoice, DocumentLifecycle.void)))
        assertFalse(voided.isShown)
        assertTrue(voided.isDone(FirstRunChecklist.Item.sendInvoice))
    }

    // Onboarding stages

    @Test fun theFiveStepsAreShownAsThreeStages() {
        assertEquals(listOf(OnboardingStep.country, OnboardingStep.registration), OnboardingStage.whereYouWork.steps)
        assertEquals(OnboardingStage.gettingPaid, OnboardingStage.of(OnboardingStep.images))
        assertTrue(OnboardingStage.gettingPaid.isOptional && !OnboardingStage.yourBusiness.isOptional)
    }
}
