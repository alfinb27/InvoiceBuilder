package app.invoicebuilder.core.data

import android.content.Context
import androidx.room.withTransaction
import androidx.test.core.app.ApplicationProvider
import app.invoicebuilder.core.domain.documents.DocumentLifecycle
import app.invoicebuilder.core.domain.documents.Payment
import app.invoicebuilder.core.domain.documents.PaymentMethod
import app.invoicebuilder.core.domain.models.DocumentType
import app.invoicebuilder.core.domain.money.CurrencyCode
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import java.time.LocalDate
import kotlin.system.measureTimeMillis

/**
 * Phase 6: a business with 1,000 issued invoices (three lines and a payment on every second one) keeps the list and
 * the dashboard fast. Ceilings are loose so a slow CI runner passes; the measured times are printed. iOS:
 * `PerformanceTests`.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class PerformanceTests {
    private val context: Context = ApplicationProvider.getApplicationContext()

    @Test fun theListAndDashboardStayFastWithAThousandInvoices() = runTest {
        val store = DataTests.TestStore(context)
        try {
            val (business, _) = store.setUp()
            store.draft(business, "template", DocumentType.invoice, store.line("t1", 100_000), store.line("t2", 250_000), store.line("t3", 12_000))
            val template = store.documents.fetchDocument("template")!!
            store.db.withTransaction {
                for (index in 1..1_000) {
                    val id = "doc-%05d".format(index)
                    val issueDate = LocalDate.of(2026, 4, 1).plusDays((index % 180).toLong())
                    val document = template.copy(
                        id = id, lifecycle = DocumentLifecycle.issued, number = "INV/26-27/%04d".format(index), issueDate = issueDate,
                        dueDate = issueDate.plusDays(30), createdAt = index.toLong(), updatedAt = index.toLong(),
                        lines = template.lines.mapIndexed { offset, line -> line.copy(id = "$id-l$offset") },
                    )
                    store.db.documents().insert(document.toEntity())
                    for (line in document.lines) store.db.documents().insertLine(line.toEntity(id, 1, 1))
                    if (index % 2 == 0) {
                        store.db.payments().insert(Payment(id = "pay-$index", businessId = business.id, documentId = id,
                            amountMinor = 50_000, date = issueDate, method = PaymentMethod.upi).toEntity())
                    }
                }
            }

            val listMs = measureTimeMillis { assertEquals(1_001, store.documents.summaries(business.id).size) } // + the template draft
            val dashboardMs = measureTimeMillis { store.documents.dashboard(business.id, CurrencyCode.INR, LocalDate.of(2026, 9, 19)) }
            // Home's checklist used to load the list above (and every client and item) to answer three yes/no questions.
            var checklist: ChecklistRow? = null
            val checklistMs = measureTimeMillis { checklist = store.db.documents().firstRunChecklist(business.id) }
            assertEquals(ChecklistRow(has_client = true, has_item = false, has_issued_invoice = true), checklist)
            println("1,000 invoices: list $listMs ms, dashboard $dashboardMs ms, checklist $checklistMs ms")
            assertTrue("list took $listMs ms", listMs < 1_000)
            assertTrue("dashboard took $dashboardMs ms", dashboardMs < 1_000)
            assertTrue("checklist took $checklistMs ms", checklistMs < 100)
        } finally {
            store.db.close()
        }
    }
}
