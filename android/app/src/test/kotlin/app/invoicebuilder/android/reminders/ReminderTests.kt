package app.invoicebuilder.android.reminders

import android.app.Application
import androidx.test.core.app.ApplicationProvider
import app.invoicebuilder.android.app.AppContainer
import app.invoicebuilder.android.app.SampleData
import app.invoicebuilder.core.data.AppDatabase
import app.invoicebuilder.core.domain.documents.Document
import app.invoicebuilder.core.domain.documents.DocumentRules
import app.invoicebuilder.core.domain.documents.PaymentMethod
import app.invoicebuilder.core.domain.models.Business
import app.invoicebuilder.core.domain.models.DocumentType
import app.invoicebuilder.core.domain.money.SpecFormatter
import app.invoicebuilder.core.domain.support.IDGenerator
import app.invoicebuilder.core.domain.support.TimeSource
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import java.time.LocalDate

/** Records what the daily job would post, without touching the system's notifications. */
private class RecordingNotifications : NotificationScheduling {
    val posted = mutableListOf<Pair<String, String>>()
    override fun isAuthorized() = true
    override fun canRequestAuthorization() = false
    override fun startDailyCheck() {}
    override fun stopDailyCheck() {}
    override fun post(documentID: String, title: String, body: String) { posted += documentID to body }
}

/** The daily reminder job (`spec/reminders.md` §3) on an in-memory database. iOS: `ReminderReconcilerTests`. */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class ReminderTests {
    private val today = LocalDate.of(2026, 10, 9)
    private val context: Application = ApplicationProvider.getApplicationContext()
    private val notifications = RecordingNotifications()
    private val container = AppContainer.make(
        context, AppDatabase.inMemory(context), TimeSource.fixed(1_791_500_000_000, today), IDGenerator.sequential(), notifications,
    )
    private val posted = PostedReminders(context)

    /** A sample Indian business that reminds 3 days after the due date. */
    private suspend fun business(): Pair<Business, String> {
        val deviceID = container.deviceState.loadOrCreate("test").id
        val seeded = SampleData.seed(SampleData.Country.india, container, deviceID)
        return container.businesses.save(seeded.copy(reminderDaysAfterDue = 3)) to deviceID
    }

    /** Issues an invoice for the first client, due [daysFromToday] from today (negative = overdue). */
    private suspend fun issuedInvoice(business: Business, deviceID: String, daysFromToday: Long): Document {
        val rules = DocumentRules(container.taxConfigs, business, container.reference.currencies)
        val client = container.clients.observeClients(business.id).first().minBy { it.name }
        val item = container.catalog.observeItems(business.id).first().minBy { it.name }
        var document = rules.newDocument(DocumentType.invoice, container.ids.make(), today.minusDays(30), client, container.time.now())
        document = document.copy(lines = listOf(rules.line(item, document, container.ids.make()).first), dueDate = today.plusDays(daysFromToday))
        val saved = container.documents.saveDraft(rules.preparedDraft(document, client))
        return container.documentService.issue(saved.id, deviceID)
    }

    @Test
    fun firstRunPostsTodaysRemindersButNoBacklog() = runTest {
        val (business, deviceID) = business()
        issuedInvoice(business, deviceID, -10) // reminder a week ago: before the first run, never posted
        val dueToday = issuedInvoice(business, deviceID, -3) // reminder today

        ReminderReconciler(container, posted).postDue(today)
        assertEquals(listOf(dueToday.id), notifications.posted.map { it.first })
        assertEquals(today, posted.lastRun)
    }

    @Test
    fun aSkippedDayIsCaughtUpAndNothingIsPostedTwice() = runTest {
        val (business, deviceID) = business()
        posted.lastRun = today.minusDays(2) // the OS didn't run the job yesterday
        val yesterday = issuedInvoice(business, deviceID, -4) // reminder yesterday
        issuedInvoice(business, deviceID, -20) // reminder 17 days ago: before the last run

        val job = ReminderReconciler(container, posted)
        job.postDue(today)
        job.postDue(today) // a second run the same day
        assertEquals(listOf(yesterday.id), notifications.posted.map { it.first })
    }

    @Test
    fun catchUpNeverReachesBackMoreThanAWeek() = runTest {
        val (business, deviceID) = business()
        posted.lastRun = today.minusDays(60) // a phone that was off for two months
        issuedInvoice(business, deviceID, -30) // reminder 27 days ago
        val recent = issuedInvoice(business, deviceID, -8) // reminder 5 days ago

        ReminderReconciler(container, posted).postDue(today)
        assertEquals(listOf(recent.id), notifications.posted.map { it.first })
    }

    @Test
    fun notificationShowsTheOutstandingAmount() = runTest {
        val (business, deviceID) = business()
        val invoice = issuedInvoice(business, deviceID, -3)
        val half = invoice.totals.totalMinor / 2
        container.paymentService.recordPayment(invoice.id, half, today, PaymentMethod.cash, null, null)

        ReminderReconciler(container, posted).postDue(today)
        val body = notifications.posted.single().second
        val formatter = SpecFormatter(container.reference.currencies)
        assertTrue(body, body.contains(formatter.money(invoice.totals.totalMinor - half, invoice.currency, invoice.currency)))
        assertFalse(body, body.contains(formatter.money(invoice.totals.totalMinor, invoice.currency, invoice.currency)))
    }

    @Test
    fun sendReminderNamesTheSellerAsIssued() = runTest {
        val (business, deviceID) = business()
        val invoice = issuedInvoice(business, deviceID, -3)
        val asIssued = invoice.copy(sellerSnapshot = invoice.sellerSnapshot!!.copy(name = "Name When Issued"))

        val text = ReminderMessage.text(asIssued, 0, business, { minor, currency -> "$minor $currency" }, null)
        assertTrue(text, text.contains("from Name When Issued was due"))
        assertFalse(text, text.contains(business.name))
    }
}
