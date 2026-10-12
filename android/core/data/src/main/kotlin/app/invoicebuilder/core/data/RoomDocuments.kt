package app.invoicebuilder.core.data

import androidx.room.withTransaction
import app.invoicebuilder.core.domain.dates.iso
import app.invoicebuilder.core.domain.decimal.Outcome
import app.invoicebuilder.core.domain.documents.BuyerSnapshot
import app.invoicebuilder.core.domain.documents.DashboardTotals
import app.invoicebuilder.core.domain.documents.Document
import app.invoicebuilder.core.domain.documents.DocumentLifecycle
import app.invoicebuilder.core.domain.documents.DocumentRules
import app.invoicebuilder.core.domain.documents.DocumentStatus
import app.invoicebuilder.core.domain.documents.DocumentSummary
import app.invoicebuilder.core.domain.documents.IssueProblem
import app.invoicebuilder.core.domain.documents.LineItem
import app.invoicebuilder.core.domain.documents.Payment
import app.invoicebuilder.core.domain.documents.PaymentMethod
import app.invoicebuilder.core.domain.documents.QuoteOutcome
import app.invoicebuilder.core.domain.documents.ReminderCandidate
import app.invoicebuilder.core.domain.models.Client
import app.invoicebuilder.core.domain.models.DocumentType
import app.invoicebuilder.core.domain.money.CurrencyCatalog
import app.invoicebuilder.core.domain.money.CurrencyCode
import app.invoicebuilder.core.domain.numbering.NumberAllocator
import app.invoicebuilder.core.domain.repositories.DocumentRepository
import app.invoicebuilder.core.domain.repositories.DocumentService
import app.invoicebuilder.core.domain.repositories.DocumentServiceError
import app.invoicebuilder.core.domain.repositories.PaymentRepository
import app.invoicebuilder.core.domain.repositories.PaymentService
import app.invoicebuilder.core.domain.repositories.PaymentServiceError
import app.invoicebuilder.core.domain.support.IDGenerator
import app.invoicebuilder.core.domain.support.TimeSource
import app.invoicebuilder.core.domain.support.trimmedOrNull
import app.invoicebuilder.core.domain.tax.TaxConfigStore
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.mapLatest
import java.time.LocalDate

/** A Flow of [read]: the current value, then a new one after every commit to [tables] (≈ GRDB `ValueObservation`). */
@OptIn(ExperimentalCoroutinesApi::class)
internal fun <T> AppDatabase.observe(vararg tables: String, read: suspend () -> T): Flow<T> =
    invalidationTracker.createFlow(*tables).mapLatest { read() }.distinctUntilChanged()

/** The free-tier counter (`spec/billing.md`): `app_state.issued_invoice_count` and the device mirror, never decreased. */
internal object FreeTierCounter {
    const val KEY = "issued_invoice_count"

    suspend fun increment(db: AppDatabase, now: Long) {
        db.appState().increment(KEY)
        db.devices().incrementMirror(now)
    }

    suspend fun count(db: AppDatabase): Int = db.appState().value(KEY)?.toIntOrNull() ?: 0
}

/** The live document [id] with its live lines, in position order. */
internal suspend fun AppDatabase.fetchDocument(id: String): Document? {
    val entity = documents().live(id) ?: return null
    return entity.toDomain(documents().liveLines(id).map { it.toDomain() })
}

/** Writes [lines] for a document: unchanged rows left alone, changed ones updated, new ones inserted, others tombstoned. */
internal suspend fun AppDatabase.replaceLines(lines: List<LineItem>, documentID: String, now: Long) {
    val stored = documents().allLinesOf(documentID).associateBy { it.id }
    for (line in lines) {
        val existing = stored[line.id]
        if (existing != null) {
            val record = line.toEntity(documentID, existing.createdAt, existing.updatedAt)
            if (record.copy(deletedAt = existing.deletedAt) == existing && existing.deletedAt == null) continue
            documents().updateLine(record.copy(updatedAt = now))
        } else {
            documents().insertLine(line.toEntity(documentID, now, now))
        }
    }
    val kept = lines.map { it.id }.toSet()
    for (record in stored.values) if (record.deletedAt == null && record.id !in kept) documents().tombstoneLine(record.id, now)
}

/** Documents and their lines (`spec/documents.md` §5). iOS: `GRDBDocumentRepository`. */
class RoomDocumentRepository(private val db: AppDatabase, private val time: TimeSource) : DocumentRepository {
    override fun observeDocuments(businessID: String): Flow<List<DocumentSummary>> =
        db.observe("document", "line_item", "payment") { summaries(businessID) }

    override fun observeDocument(id: String): Flow<Document?> = db.observe("document", "line_item") { db.fetchDocument(id) }

    override suspend fun fetchDocument(id: String): Document? = db.fetchDocument(id)

    override suspend fun saveDraft(document: Document): Document = db.withTransaction {
        if (document.lifecycle != DocumentLifecycle.draft) throw DocumentServiceError.NotADraft
        val now = time.now()
        val existing = db.documents().any(document.id)
        val stored = if (existing != null) {
            if (existing.lifecycle != DocumentLifecycle.draft.rawValue) throw DocumentServiceError.NotADraft
            // A draft deleted while its builder was open (§9) comes back when it is edited again.
            document.copy(updatedAt = now, createdAt = existing.createdAt, deletedAt = null).also { db.documents().update(it.toEntity()) }
        } else {
            document.copy(updatedAt = now, createdAt = now).also { db.documents().insert(it.toEntity()) }
        }
        db.replaceLines(stored.lines, stored.id, now)
        stored
    }

    override suspend fun highestIssuedSequence(seriesID: String, periodKey: String): Int? = db.documents().highestSequence(seriesID, periodKey)

    override suspend fun markSent(documentID: String, timestamp: Long?) {
        db.withTransaction {
            val entity = db.documents().live(documentID)
            if (entity == null || entity.lifecycle == DocumentLifecycle.draft.rawValue) throw DocumentServiceError.NotFound
            db.documents().update(entity.copy(sentAt = timestamp, updatedAt = time.now()))
        }
    }

    override fun observeDashboard(businessID: String, homeCurrency: CurrencyCode): Flow<DashboardTotals> =
        db.observe("document", "payment") { dashboard(businessID, homeCurrency, time.today()) }

    override suspend fun fetchReminderCandidates(businessID: String): List<ReminderCandidate> {
        val today = time.today()
        return db.documents().issuedInvoices(businessID, null).map { row ->
            val dueDate = row.due_date?.let(::date)
            val input = DocumentStatus.Input(DocumentType.invoice, DocumentLifecycle.issued, row.total_minor, row.paid_minor, dueDate, sentAt = row.sent_at, today = today)
            ReminderCandidate(row.id, dueDate, row.reminder_days_after_due_override, DocumentStatus.derive(input))
        }
    }

    suspend fun summaries(businessID: String): List<DocumentSummary> = db.documents().summaries(businessID).map { row ->
        val buyer = JsonColumn.decode(BuyerSnapshot.serializer(), row.buyer_snapshot)
        DocumentSummary(
            id = row.id, docType = DocumentType(row.doc_type), number = row.number, lifecycle = DocumentLifecycle(row.lifecycle),
            issueDate = date(row.issue_date), dueDate = row.due_date?.let(::date), validUntil = row.valid_until?.let(::date),
            sentAt = row.sent_at, quoteOutcome = row.quote_outcome?.let(::QuoteOutcome), clientId = row.client_id,
            buyerName = buyer?.name, currency = CurrencyCode(row.currency), totalMinor = row.total_minor, paidMinor = row.paid_minor,
            lineCount = row.line_count, updatedAt = row.updated_at,
        )
    }

    /** Outstanding, overdue and paid-this-month, home-currency issued invoices only (iOS: `dashboard`). */
    suspend fun dashboard(businessID: String, homeCurrency: CurrencyCode, today: LocalDate): DashboardTotals {
        var outstanding = 0L
        var overdue = 0L
        for (row in db.documents().issuedInvoices(businessID, homeCurrency.rawValue)) {
            val input = DocumentStatus.Input(DocumentType.invoice, DocumentLifecycle.issued, row.total_minor, row.paid_minor,
                row.due_date?.let(::date), sentAt = row.sent_at, today = today)
            val status = DocumentStatus.derive(input)
            val due = DocumentStatus.outstanding(input) ?: 0
            if (status != DocumentStatus.paid) outstanding += due
            if (status == DocumentStatus.overdue) overdue += due
        }
        val monthStart = today.withDayOfMonth(1)
        val paid = db.documents().paidBetween(businessID, homeCurrency.rawValue, monthStart.iso, monthStart.plusMonths(1).iso)
        return DashboardTotals(outstanding, overdue, paid)
    }
}

/** `IssueDocument`, duplicate, convert, delete, void, quote outcomes (`spec/documents.md` §6–12). iOS: `GRDBDocumentService`. */
class RoomDocumentService(
    private val db: AppDatabase,
    private val time: TimeSource,
    private val ids: IDGenerator,
    private val configs: TaxConfigStore,
    private val currencies: CurrencyCatalog,
) : DocumentService {
    private class Context(val document: Document, val client: Client?, val rules: DocumentRules)

    private suspend fun load(documentID: String): Context {
        val document = db.fetchDocument(documentID) ?: throw DocumentServiceError.NotFound
        val business = db.businesses().live(document.businessId)?.toDomain() ?: throw RecordNotFound("business", document.businessId)
        val client = document.clientId?.let { db.clients().live(it)?.toDomain() }
        return Context(document, client, DocumentRules(configs, business, currencies))
    }

    override suspend fun issue(documentID: String, deviceID: String): Document = db.withTransaction {
        val now = time.now()
        val context = load(documentID)
        val document = context.document
        if (!document.isDraft) throw DocumentServiceError.NotADraft
        val rules = context.rules
        val config = rules.config(document)
        val seller = rules.sellerSnapshot(config)
        val buyer = rules.buyerSnapshot(document, context.client)
        val result = rules.compute(document, seller, buyer)
        val problems = rules.issueProblems(document, result).toMutableList()
        val series = db.series().liveOf(document.businessId).map { it.toDomain() }
        var allocation: NumberAllocator.Allocation? = null
        val owned = NumberAllocator.series(document.docType, deviceID, series)
        if (owned == null) {
            problems += IssueProblem.NoSeries
        } else {
            when (val allocated = NumberAllocator.allocate(owned, document.issueDate, config)) {
                is Outcome.Success -> allocation = allocated.value
                is Outcome.Failure -> problems += IssueProblem.Numbering(allocated.error)
            }
        }
        val computed = (result as? Outcome.Success)?.value
        if (problems.isNotEmpty() || allocation == null || computed == null) throw DocumentServiceError.Blocked(problems)

        val issued = rules.issued(document, seller, buyer, computed, allocation).copy(updatedAt = now)
        db.documents().update(issued.toEntity())
        db.replaceLines(issued.lines, issued.id, now)
        db.series().update(allocation.series.copy(updatedAt = now).toEntity())
        for (taxLine in computed.taxLines) db.documents().insertTaxLine(taxLineEntity(ids.make(), issued.id, taxLine, now))
        if (issued.docType == DocumentType.invoice) FreeTierCounter.increment(db, now)
        issued
    }

    override suspend fun duplicate(documentID: String): Document = db.withTransaction {
        val now = time.now()
        val context = load(documentID)
        val copy = context.rules.duplicate(context.document, ids.make(), time.today(), now, ids.make)
        insertDraft(context.rules.preparedDraft(copy, context.client), now)
    }

    override suspend fun convertQuote(documentID: String): Document = db.withTransaction {
        val now = time.now()
        val context = load(documentID)
        if (!context.rules.canConvert(context.document)) throw DocumentServiceError.NotConvertible
        val invoice = context.rules.convertedInvoice(context.document, ids.make(), time.today(), now, ids.make)
        val quote = db.documents().live(documentID)!!
        db.documents().update(quote.copy(quoteOutcome = QuoteOutcome.converted.rawValue, updatedAt = now))
        insertDraft(context.rules.preparedDraft(invoice, context.client), now)
    }

    override suspend fun deleteDraft(documentID: String) = db.withTransaction {
        val now = time.now()
        val record = db.documents().live(documentID) ?: throw DocumentServiceError.NotFound
        if (record.lifecycle != DocumentLifecycle.draft.rawValue) throw DocumentServiceError.NotADraft
        db.documents().update(record.copy(deletedAt = now, updatedAt = now))
        // A converted quote whose invoice draft is gone can be converted again.
        val quoteID = record.convertedFromId
        if (quoteID != null && db.documents().liveConversions(quoteID) == 0) {
            db.documents().live(quoteID)?.takeIf { it.quoteOutcome == QuoteOutcome.converted.rawValue }?.let {
                db.documents().update(it.copy(quoteOutcome = null, updatedAt = now))
            }
        }
    }

    override suspend fun voidDocument(documentID: String, reason: String): Document {
        val trimmed = reason.trimmedOrNull ?: throw DocumentServiceError.VoidReasonRequired
        return db.withTransaction {
            val now = time.now()
            val record = db.documents().live(documentID) ?: throw DocumentServiceError.NotFound
            if (record.lifecycle != DocumentLifecycle.issued.rawValue) throw DocumentServiceError.NotVoidable
            db.documents().update(record.copy(lifecycle = DocumentLifecycle.void.rawValue, voidedAt = now, voidReason = trimmed, updatedAt = now))
            db.fetchDocument(documentID) ?: throw DocumentServiceError.NotFound
        }
    }

    override suspend fun acceptQuote(documentID: String): Document = setQuoteOutcome(QuoteOutcome.accepted, documentID)
    override suspend fun declineQuote(documentID: String): Document = setQuoteOutcome(QuoteOutcome.declined, documentID)

    /** §12: valid from no outcome or the other one; never from `converted`, and expiry does not block it. */
    private suspend fun setQuoteOutcome(outcome: QuoteOutcome, documentID: String): Document = db.withTransaction {
        val record = db.documents().live(documentID) ?: throw DocumentServiceError.NotFound
        if (record.docType != DocumentType.quote.rawValue || record.lifecycle != DocumentLifecycle.issued.rawValue) throw DocumentServiceError.NotALiveQuote
        if (record.quoteOutcome == QuoteOutcome.converted.rawValue) throw DocumentServiceError.AlreadyConverted
        db.documents().update(record.copy(quoteOutcome = outcome.rawValue, updatedAt = time.now()))
        db.fetchDocument(documentID) ?: throw DocumentServiceError.NotFound
    }

    private suspend fun insertDraft(draft: Document, now: Long): Document {
        val stored = draft.copy(createdAt = now, updatedAt = now)
        db.documents().insert(stored.toEntity())
        db.replaceLines(stored.lines, stored.id, now)
        return stored
    }
}

/** Payments recorded against invoices (`spec/documents.md` §10). iOS: `GRDBPaymentRepository`. */
class RoomPaymentRepository(private val db: AppDatabase, private val time: TimeSource) : PaymentRepository {
    override fun observePayments(documentID: String): Flow<List<Payment>> =
        db.observe("payment") { db.payments().liveOf(documentID).map { it.toDomain() } }
    override suspend fun fetchPayments(documentID: String): List<Payment> = db.payments().liveOf(documentID).map { it.toDomain() }
    override suspend fun softDelete(paymentID: String) {
        if (db.payments().tombstone(paymentID, time.now()) == 0) throw RecordNotFound("payment", paymentID)
    }
}

/** `recordPayment` (`spec/documents.md` §10): a live, issued invoice, then one payment row. iOS: `GRDBPaymentService`. */
class RoomPaymentService(private val db: AppDatabase, private val time: TimeSource, private val ids: IDGenerator) : PaymentService {
    override suspend fun recordPayment(documentID: String, amountMinor: Long, date: LocalDate, method: PaymentMethod, reference: String?, note: String?): Payment =
        db.withTransaction {
            val document = db.documents().live(documentID) ?: throw PaymentServiceError.DocumentNotFound
            if (document.docType != DocumentType.invoice.rawValue || document.lifecycle != DocumentLifecycle.issued.rawValue) throw PaymentServiceError.NotPayable
            val now = time.now()
            val payment = Payment(ids.make(), now, now, null, document.businessId, documentID, amountMinor, date, method, reference?.trimmedOrNull, note?.trimmedOrNull)
            db.payments().insert(payment.toEntity())
            payment
        }
}
