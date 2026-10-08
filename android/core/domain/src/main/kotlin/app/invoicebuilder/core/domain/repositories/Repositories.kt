package app.invoicebuilder.core.domain.repositories

import app.invoicebuilder.core.domain.backup.BackupFile
import app.invoicebuilder.core.domain.backup.BackupStatus
import app.invoicebuilder.core.domain.billing.EntitlementStatus
import app.invoicebuilder.core.domain.documents.DashboardTotals
import app.invoicebuilder.core.domain.documents.Document
import app.invoicebuilder.core.domain.documents.DocumentSummary
import app.invoicebuilder.core.domain.documents.IssueProblem
import app.invoicebuilder.core.domain.documents.Payment
import app.invoicebuilder.core.domain.documents.PaymentMethod
import app.invoicebuilder.core.domain.documents.ReminderCandidate
import app.invoicebuilder.core.domain.models.Asset
import app.invoicebuilder.core.domain.models.AssetKind
import app.invoicebuilder.core.domain.models.Business
import app.invoicebuilder.core.domain.models.CatalogItem
import app.invoicebuilder.core.domain.models.Client
import app.invoicebuilder.core.domain.models.DeviceState
import app.invoicebuilder.core.domain.models.DocumentType
import app.invoicebuilder.core.domain.models.ImagePayload
import app.invoicebuilder.core.domain.models.NumberingSeries
import app.invoicebuilder.core.domain.money.CurrencyCode
import app.invoicebuilder.core.domain.numbering.DuplicateNumbers
import kotlinx.coroutines.flow.Flow
import java.time.LocalDate

// Storage interfaces (iOS: `Repositories.swift`). `:core:data` implements them with Room; view-model tests use
// fakes. Every `observe…` Flow emits the current value first, then again after every committed change (≈ the
// Swift `AsyncThrowingStream`s). Reads never return tombstoned rows (`spec/setup.md` §1).

interface BusinessRepository {
    fun observeBusiness(id: String): Flow<Business?>
    suspend fun fetchBusiness(id: String): Business?
    /** Every live business, oldest first. */
    suspend fun fetchBusinesses(): List<Business>
    /** Inserts or updates; sets `updatedAt` (and `createdAt` on insert). Returns the stored value. */
    suspend fun save(business: Business): Business
}

interface ClientRepository {
    fun observeClients(businessID: String): Flow<List<Client>>
    fun observeClient(id: String): Flow<Client?>
    suspend fun fetchClient(id: String): Client?
    suspend fun save(client: Client): Client
    suspend fun setArchived(archived: Boolean, clientID: String)
    /** Writes a tombstone. */
    suspend fun delete(clientID: String)
}

interface CatalogRepository {
    fun observeItems(businessID: String): Flow<List<CatalogItem>>
    fun observeItem(id: String): Flow<CatalogItem?>
    suspend fun fetchItem(id: String): CatalogItem?
    suspend fun save(item: CatalogItem): CatalogItem
    suspend fun setArchived(archived: Boolean, itemID: String)
    suspend fun delete(itemID: String)
    /** Live items of the business that use [rateID] (a custom rate in use cannot be removed). */
    suspend fun countItems(businessID: String, rateID: String): Int
}

interface NumberingSeriesRepository {
    fun observeSeries(businessID: String): Flow<List<NumberingSeries>>
    suspend fun save(series: NumberingSeries): NumberingSeries
}

interface AssetRepository {
    suspend fun fetchAsset(id: String): Asset?
    fun observeAsset(id: String): Flow<Asset?>
}

interface DeviceStateRepository {
    /** This device's row, created on first use (`spec/setup.md` §2). */
    suspend fun loadOrCreate(deviceName: String): DeviceState
    suspend fun setActiveBusiness(id: String?)
}

/** Operations that write several tables in one transaction (ADR-0002's thin domain-service layer). */
interface BusinessSetupService {
    /** Onboarding's Finish: the business, its images, its numbering series and the active-business preference. */
    suspend fun createBusiness(business: Business, series: List<NumberingSeries>, logo: ImagePayload?, signature: ImagePayload?, deviceID: String): Business
    /** Replaces (or removes, with null) the logo or signature; an image no business uses any more is tombstoned. */
    suspend fun setImage(image: ImagePayload?, kind: AssetKind, businessID: String): Business
}

interface DocumentRepository {
    /** Live documents of a business, drafts included, newest issue date first (then most recently edited). */
    fun observeDocuments(businessID: String): Flow<List<DocumentSummary>>
    /** A live document with its live lines in position order; null once it is gone. */
    fun observeDocument(id: String): Flow<Document?>
    suspend fun fetchDocument(id: String): Document?
    /** Writes a draft as given (`spec/documents.md` §5). Only drafts; stamps `updatedAt` (and `createdAt` on insert). */
    suspend fun saveDraft(document: Document): Document
    /** The highest `sequence` issued from [seriesID] in [periodKey], or null. */
    suspend fun highestIssuedSequence(seriesID: String, periodKey: String): Int?
    /** Records that an issued document was sent (`spec/documents.md` §8); null clears it again. */
    suspend fun markSent(documentID: String, timestamp: Long?)
    /** Home dashboard totals; home-currency invoices only. */
    fun observeDashboard(businessID: String, homeCurrency: CurrencyCode): Flow<DashboardTotals>
    /** Live, issued invoices as reminder candidates (`spec/reminders.md` §2), status already derived. */
    suspend fun fetchReminderCandidates(businessID: String): List<ReminderCandidate>
}

/** Document operations that write several rows in one transaction (`spec/documents.md` §6–9, §11–12). */
interface DocumentService {
    suspend fun issue(documentID: String, deviceID: String): Document
    suspend fun duplicate(documentID: String): Document
    suspend fun convertQuote(documentID: String): Document
    suspend fun deleteDraft(documentID: String)
    suspend fun voidDocument(documentID: String, reason: String): Document
    suspend fun acceptQuote(documentID: String): Document
    suspend fun declineQuote(documentID: String): Document
}

/** iOS: `DocumentServiceError`. */
sealed class DocumentServiceError : Exception() {
    data object NotFound : DocumentServiceError()
    /** `not_a_draft`: only drafts can be issued, edited or deleted. */
    data object NotADraft : DocumentServiceError()
    /** `not_convertible`: only an issued quote that is not converted yet. */
    data object NotConvertible : DocumentServiceError()
    /** Issuing is blocked; nothing was written. */
    data class Blocked(val problems: List<IssueProblem>) : DocumentServiceError()
    data object NotVoidable : DocumentServiceError()
    data object VoidReasonRequired : DocumentServiceError()
    data object AlreadyConverted : DocumentServiceError()
    data object NotALiveQuote : DocumentServiceError()
}

interface PaymentRepository {
    fun observePayments(documentID: String): Flow<List<Payment>>
    suspend fun fetchPayments(documentID: String): List<Payment>
    /** Writes a tombstone (correcting a payment is delete-and-re-add, `spec/documents.md` §10). */
    suspend fun softDelete(paymentID: String)
}

/** Records a payment after checking the document (`spec/documents.md` §10), one write. */
interface PaymentService {
    suspend fun recordPayment(documentID: String, amountMinor: Long, date: LocalDate, method: PaymentMethod, reference: String?, note: String?): Payment
}

sealed class PaymentServiceError : Exception() {
    data object DocumentNotFound : PaymentServiceError()
    /** `not_payable`: only a live, issued invoice. */
    data object NotPayable : PaymentServiceError()
}

/** Portable backups (`spec/backup.md`). */
interface BackupService {
    val schemaVersion: Int
    suspend fun makeBackup(app: BackupFile.AppInfo): BackupFile
    suspend fun writeSafetySnapshot()
    suspend fun restore(file: BackupFile, deviceID: String)
    suspend fun recordBackup(timestamp: Long)
    fun observeStatus(): Flow<BackupStatus>
}

/** Numbering on several devices (`spec/sync.md` §3–4). */
interface NumberingService {
    suspend fun createDeviceSeries(businessID: String, docType: DocumentType, deviceID: String): NumberingSeries
    suspend fun takeOver(seriesID: String, deviceID: String): NumberingSeries
    fun observeDuplicateNumbers(businessID: String): Flow<List<DuplicateNumbers.Group>>
}

/** The free-tier counts the database keeps (`spec/billing.md`, Free tier). */
interface FreeTierRepository {
    suspend fun fetchCounts(): app.invoicebuilder.core.domain.billing.FreeTierCounts
}

/** The unlock and the free-tier count; `:core:billing` implements it with Play Billing. */
interface EntitlementService {
    val status: kotlinx.coroutines.flow.StateFlow<EntitlementStatus>
    suspend fun start()
    suspend fun refreshCount()
    suspend fun purchase(activity: Any)
    suspend fun restore()
}
