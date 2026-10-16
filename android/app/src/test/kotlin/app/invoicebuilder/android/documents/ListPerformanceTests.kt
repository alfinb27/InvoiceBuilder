package app.invoicebuilder.android.documents

import app.invoicebuilder.android.app.DocumentDateFilter
import app.invoicebuilder.android.app.InvoiceStatusFilter
import app.invoicebuilder.core.domain.documents.DocumentLifecycle
import app.invoicebuilder.core.domain.documents.DocumentSummary
import app.invoicebuilder.core.domain.models.DocumentType
import app.invoicebuilder.core.domain.money.CurrencyCode
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.LocalDate
import kotlin.system.measureNanoTime

/** iOS: `ListPerformanceTests`. */
class ListPerformanceTests {
    /** Phase 6: searching 1,000 invoices returns in under 100 ms (the list filters in memory). */
    @Test fun searchingAThousandInvoicesIsFast() {
        val today = LocalDate.of(2026, 9, 19)
        val rows = (1..1_000).map { index ->
            val age = (index % 300).toLong()
            val client = index % 40
            DocumentSummary(
                id = "d$index", docType = DocumentType.invoice, number = "INV/26-27/%04d".format(index),
                lifecycle = DocumentLifecycle.issued, issueDate = today.minusDays(age), dueDate = today.plusDays(30 - age),
                validUntil = null, sentAt = null, quoteOutcome = null, clientId = "c$client", buyerName = "Client $client",
                currency = CurrencyCode.INR, totalMinor = index * 1_000L, paidMinor = if (index % 3 == 0) 1_000 else 0,
                lineCount = 3, updatedAt = index.toLong(),
            )
        }
        var found = 0
        val elapsedMs = measureNanoTime {
            for (query in listOf("Client 7", "0420", "inv/26", "zzz")) {
                found += visibleDocuments(rows, DocumentType.invoice, query, InvoiceStatusFilter.unpaid, DocumentDateFilter.last3Months, today).second.size
            }
        } / 1_000_000
        assertTrue(found > 0)
        assertTrue("four searches took $elapsedMs ms", elapsedMs < 100)
    }
}
