package app.invoicebuilder.android.documents

import android.app.Application
import androidx.test.core.app.ApplicationProvider
import app.invoicebuilder.android.app.AppContainer
import app.invoicebuilder.android.app.DocumentRoute
import app.invoicebuilder.android.app.SampleData
import app.invoicebuilder.android.app.Session
import app.invoicebuilder.android.onboarding.OnboardingViewModel
import app.invoicebuilder.core.data.AppDatabase
import app.invoicebuilder.core.domain.models.Business
import app.invoicebuilder.core.domain.models.CatalogItem
import app.invoicebuilder.core.domain.models.DocumentType
import app.invoicebuilder.core.domain.money.CurrencyCode
import app.invoicebuilder.core.domain.setup.BusinessField
import app.invoicebuilder.core.domain.setup.FieldIssue
import app.invoicebuilder.core.domain.setup.FirstRunChecklist
import app.invoicebuilder.core.domain.setup.OnboardingStage
import app.invoicebuilder.core.domain.support.IDGenerator
import app.invoicebuilder.core.domain.support.TimeSource
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import java.time.LocalDate

/**
 * The guided builder of ADR-0020 on Android: the "Add an item" sheet (`spec/documents.md` §3.2), payment-term chips
 * (§3.3), Review & send (§6.1), the shared PDF's name (§8), Home's checklist and the onboarding stages
 * (`spec/setup.md` §3). iOS: `GuidedBuilderTests`, `OnboardingViewModelTests`.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class GuidedBuilderTests {
    private val today = LocalDate.of(2026, 9, 19)
    private val context: Application = ApplicationProvider.getApplicationContext()
    private val container = AppContainer.make(
        context, AppDatabase.inMemory(context), TimeSource.fixed(1_789_800_000_000, today), IDGenerator.sequential(),
    )
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Unconfined)

    private suspend fun session(): Session {
        val deviceID = container.deviceState.loadOrCreate("test").id
        val business = SampleData.seed(SampleData.Country.india, container, deviceID)
        return Session(container, business, deviceID, scope)
    }

    private suspend fun until(condition: () -> Boolean) = withTimeout(5_000) { while (!condition()) delay(10) }

    private suspend fun newInvoice(session: Session): DocumentViewModel {
        val model = DocumentViewModel(session, DocumentRoute.New(DocumentType.invoice, "doc-1"), autosaveDelayMs = 0)
        model.load()
        until { model.isLoaded }
        return model
    }

    private suspend fun item(session: Session, name: String): CatalogItem =
        container.catalog.observeItems(session.business.id).first().first { it.name == name }

    /** Something new: description, quantity, price and rate. */
    private fun addSomethingNew(model: DocumentViewModel, description: String, quantity: String = "1", price: String,
                                includesTax: Boolean = false, saveToItems: Boolean = false): Boolean {
        model.addLine()
        val editor = model.lineEditor!!
        model.updateLineDraft(editor.draft.copy(description = description, quantityText = quantity, priceText = price, rateId = "gst_18"))
        model.setLineIncludesTax(includesTax)
        model.setLineSaveToItems(saveToItems)
        return model.commitLineEditor()
    }

    @Test
    fun theFirstLinesSwitchSetsTheDocumentsBasisAndKeepsThePriceAsTyped() = runBlocking {
        val model = newInvoice(session())
        assertTrue(addSomethingNew(model, "Logo refresh", quantity = "2", price = "2500", includesTax = true))
        assertTrue(model.document.pricesIncludeTax)
        assertEquals(250_000L, model.document.lines[0].unitPriceMinor)
        assertEquals(500_000L, model.computed?.totals?.total) // 2 × ₹2,500 including 18%
    }

    @Test
    fun aLaterLineOnTheOtherBasisIsConverted() = runBlocking {
        val model = newInvoice(session())
        assertTrue(addSomethingNew(model, "Website design", price = "12000"))
        assertTrue(addSomethingNew(model, "Logo refresh", price = "2500", includesTax = true))
        assertFalse(model.document.pricesIncludeTax) // the document's basis stays
        assertEquals(211_864L, model.document.lines[1].unitPriceMinor) // 2500 × 100 / 118
    }

    @Test
    fun theLiveLineTotalIsTheEnginesForThatLine() = runBlocking {
        val model = newInvoice(session())
        model.addLine()
        model.updateLineDraft(model.lineEditor!!.draft.copy(quantityText = "2", priceText = "2500"))
        assertNull(model.lineEditorPreview) // no rate yet
        model.updateLineDraft(model.lineEditor!!.draft.copy(rateId = "gst_18"))
        assertEquals("2 × ₹2,500.00 + ₹900.00 GST", model.lineEditorPreview?.text)
        assertEquals("₹5,900.00", model.lineEditorPreview?.total)
        model.setLineIncludesTax(true)
        // Inside the price: CGST and SGST of 9% are rounded each (₹381.36), so ₹762.72 of the ₹5,000.
        assertEquals("2 × ₹2,500.00 incl. ₹762.72 GST", model.lineEditorPreview?.text)
        assertEquals("₹5,000.00", model.lineEditorPreview?.total)
    }

    @Test
    fun savingToMyItemsWritesTheItemAndLinksTheLine() = runBlocking {
        val session = session()
        val model = newInvoice(session)
        assertTrue(addSomethingNew(model, "Hosting setup", price = "1000", saveToItems = true))
        model.waitForItemSaves()
        val saved = item(session, "Hosting setup")
        assertEquals(100_000L, saved.unitPriceMinor)
        assertEquals("gst_18", saved.rateId)
        assertFalse(saved.priceIncludesTax)
        assertEquals(saved.id, model.document.lines[0].catalogItemId)
        model.flush()
        assertEquals(saved.id, container.documents.fetchDocument("doc-1")?.lines?.first()?.catalogItemId)
    }

    @Test
    fun somethingNewTakesTheRateOfASavedItemAddedMeanwhile() = runBlocking {
        val session = session()
        val model = newInvoice(session)
        model.addLine() // the sheet opens before any line exists: no rate yet
        assertEquals("", model.lineEditor?.draft?.rateId)
        model.addItem(item(session, "Tea leaves")) // GST 5%, from "My saved items"
        assertEquals("gst_5", model.lineEditor?.draft?.rateId)
    }

    @Test
    fun aForeignCurrencyLineIsNotOfferedForMyItems() = runBlocking {
        val model = newInvoice(session())
        model.setCurrency(CurrencyCode("USD"))
        model.addLine()
        assertFalse(model.canSaveLineToItems)
        assertFalse(model.lineEditor!!.saveToItems)
    }

    @Test
    fun howManyStepsByOneAndNeverBelowOne() = runBlocking {
        val model = newInvoice(session())
        model.addLine()
        model.stepLineQuantity(1)
        assertEquals("2", model.lineEditor?.draft?.quantityText)
        model.stepLineQuantity(-1)
        model.stepLineQuantity(-1)
        assertEquals("1", model.lineEditor?.draft?.quantityText)
        model.updateLineDraft(model.lineEditor!!.draft.copy(quantityText = "1.5"))
        model.stepLineQuantity(1)
        assertEquals("2.5", model.lineEditor?.draft?.quantityText)
    }

    @Test
    fun rateChipsComeFromTheSpec() = runBlocking {
        val model = newInvoice(session())
        model.addLine()
        assertEquals(listOf("gst_0", "gst_5", "gst_18", "gst_40"), model.lineRateChoices.chips.map { it.id })
        assertTrue(model.lineRateChoices.others.any { it.id == "gst_28" })
    }

    @Test
    fun paymentTermChipsSetTheDueDate() = runBlocking {
        val model = newInvoice(session())
        assertEquals(listOf(0, 7, 15, 30), model.termChoices) // the business's 15 days is one of them
        assertEquals(15, model.selectedTermDays)
        model.setTerm(7)
        assertEquals(model.document.issueDate.plusDays(7), model.document.dueDate)
        assertEquals(7, model.selectedTermDays)
        model.setDueDate(model.document.issueDate.plusDays(10))
        assertNull(model.selectedTermDays)
    }

    @Test
    fun reviewThenSendIssuesAndOpensTheChannel() = runBlocking {
        val session = session()
        val model = newInvoice(session)
        model.addItem(item(session, "Website development"))
        model.requestIssue()
        until { model.confirmingIssue }
        assertEquals("INV/26-27/0001", model.numberPreview)

        model.keepAsDraft()
        model.sendAfterReview()
        assertTrue(model.isDraft)
        assertNull(model.preview)

        model.requestIssue()
        until { model.confirmingIssue }
        model.send(SendChannel.email) // closes the review and sends
        assertFalse(model.confirmingIssue)
        until { model.preview != null }
        assertEquals("INV/26-27/0001", model.document.number)
        assertEquals(SendChannel.email, model.preview?.pendingChannel)
        assertNull(model.pendingSend)
    }

    @Test
    fun theSharedPDFIsNamedAfterTheNumber() = runBlocking {
        val model = newInvoice(session())
        assertEquals("Invoice draft.pdf", DocumentText.pdfFileName(model.document))
        assertEquals("Invoice INV-26-27-0001.pdf", DocumentText.pdfFileName(model.document.copy(number = "INV/26-27/0001")))
    }

    @Test
    fun homeShowsTheChecklistUntilTheFirstInvoiceIsSent() = runBlocking {
        val session = session()
        val businessID = session.business.id
        suspend fun checklist() = FirstRunChecklist.of(container.clients.observeClients(businessID).first().size,
            container.catalog.observeItems(businessID).first().size, container.documents.observeDocuments(businessID).first())
        assertTrue(checklist().isShown)
        assertEquals(3, checklist().doneCount)
        val model = newInvoice(session)
        model.addItem(item(session, "Website development"))
        model.requestIssue()
        until { model.confirmingIssue }
        model.confirmIssue()
        until { !model.isDraft }
        assertFalse(checklist().isShown)
    }

    // Onboarding (`spec/setup.md` §3)

    private fun onboarding(deviceID: String, finished: (Business) -> Unit = {}) =
        OnboardingViewModel(container, deviceID, scope, "test", onRestored = {}, onTryDemo = {}, onFinished = finished)

    @Test
    fun onboardingRunsWelcomeThenThreeStages() = runBlocking {
        val deviceID = container.deviceState.loadOrCreate("test").id
        var finished: Business? = null
        val model = onboarding(deviceID) { finished = it }
        assertTrue(model.showsWelcome)
        model.start()
        model.continueTapped()
        assertEquals(OnboardingStage.whereYouWork, model.stage)
        assertEquals(FieldIssue.Required, model.visibleIssue(BusinessField.Country))
        model.selectCountry("IN")
        assertEquals("IN", model.countryCard)
        model.continueTapped() // country and registration are one stage
        assertEquals(OnboardingStage.yourBusiness, model.stage)
        model.update(model.draft.copy(name = "Bharat Test Studio", taxId = "29AAGCB7383J1Z4"))
        model.update(model.draft.copy(address = model.draft.address.copy(line1 = "12 MG Road")))
        model.continueTapped()
        assertEquals(OnboardingStage.gettingPaid, model.stage)
        model.update(model.draft.copy(sortCode = "12", ifsc = "BAD"))
        model.skipAndFinish() // Skip for now keeps nothing typed on this stage
        until { finished != null }
        assertNull(finished?.bank)
    }

    @Test
    fun backFromTheFirstStageShowsTheWelcomeAndSomewhereElseClearsIndia() = runBlocking {
        val model = onboarding(container.deviceState.loadOrCreate("test").id)
        model.start()
        model.selectCountry("IN")
        model.pickOtherCountry()
        assertEquals("other", model.countryCard)
        assertNull(model.draft.countryCode)
        model.selectCountry("US")
        assertEquals("United States", model.countryName)
        model.back()
        assertTrue(model.showsWelcome)
        assertNotNull(model.draft.countryCode)
    }
}
