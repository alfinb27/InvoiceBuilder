/// Storage interfaces. InvoiceData implements them with GRDB; view-model tests use fakes. Every `observe…` stream
/// emits the current value first, then again after every committed change, until the consumer stops iterating.
/// Reads and streams never return tombstoned rows (`spec/setup.md` §1).

public protocol BusinessRepository: Sendable {
    func observeBusiness(id: String) -> AsyncThrowingStream<Business?, any Error>
    func fetchBusiness(id: String) async throws -> Business?
    /// Every live business, oldest first.
    func fetchBusinesses() async throws -> [Business]
    /// Inserts or updates; sets `updatedAt` (and `createdAt` on insert). Returns the stored value.
    @discardableResult func save(_ business: Business) async throws -> Business
}

public protocol ClientRepository: Sendable {
    /// Live clients of a business, archived included, in no particular order (`SetupSearch` sorts).
    func observeClients(businessID: String) -> AsyncThrowingStream<[Client], any Error>
    func observeClient(id: String) -> AsyncThrowingStream<Client?, any Error>
    func fetchClient(id: String) async throws -> Client?
    @discardableResult func save(_ client: Client) async throws -> Client
    func setArchived(_ archived: Bool, clientID: String) async throws
    /// Writes a tombstone.
    func delete(clientID: String) async throws
}

public protocol CatalogRepository: Sendable {
    func observeItems(businessID: String) -> AsyncThrowingStream<[CatalogItem], any Error>
    func observeItem(id: String) -> AsyncThrowingStream<CatalogItem?, any Error>
    func fetchItem(id: String) async throws -> CatalogItem?
    @discardableResult func save(_ item: CatalogItem) async throws -> CatalogItem
    func setArchived(_ archived: Bool, itemID: String) async throws
    func delete(itemID: String) async throws
    /// Live items of the business that use `rateID` (a custom rate in use cannot be removed).
    func countItems(businessID: String, usingRate rateID: String) async throws -> Int
}

public protocol NumberingSeriesRepository: Sendable {
    func observeSeries(businessID: String) -> AsyncThrowingStream<[NumberingSeries], any Error>
    @discardableResult func save(_ series: NumberingSeries) async throws -> NumberingSeries
}

public protocol AssetRepository: Sendable {
    func fetchAsset(id: String) async throws -> Asset?
    func observeAsset(id: String) -> AsyncThrowingStream<Asset?, any Error>
}

public protocol DeviceStateRepository: Sendable {
    /// This device's row, created on first use (`spec/setup.md` §2).
    func loadOrCreate(deviceName: String) async throws -> DeviceState
    func setActiveBusiness(id: String?) async throws
    /// `preferences.syncEnabled` (`spec/sync.md` §2).
    func setSyncEnabled(_ enabled: Bool) async throws
}

/// Operations that write several tables in one transaction (ADR-0002's thin domain-service layer).
public protocol BusinessSetupService: Sendable {
    /// Onboarding's Finish: the business, its images, its numbering series and the active-business preference,
    /// all or nothing (`spec/setup.md` §3).
    func createBusiness(_ business: Business, series: [NumberingSeries], logo: ImagePayload?,
                        signature: ImagePayload?, deviceID: String) async throws -> Business

    /// Replaces (or removes, with nil) the business logo or signature; an old image no business uses any more is
    /// tombstoned (`spec/setup.md` §9).
    func setImage(_ image: ImagePayload?, kind: AssetKind, businessID: String) async throws -> Business
}

public protocol DocumentRepository: Sendable {
    /// Live documents of a business, drafts included, newest issue date first (then most recently edited).
    func observeDocuments(businessID: String) -> AsyncThrowingStream<[DocumentSummary], any Error>
    /// A live document with its live lines in position order; nil once it is gone.
    func observeDocument(id: String) -> AsyncThrowingStream<Document?, any Error>
    func fetchDocument(id: String) async throws -> Document?
    /// Writes a draft as given (`spec/documents.md` §5): the row, its lines (update by id, insert new ones) and a
    /// tombstone for each stored line no longer in it. Only drafts; stamps `updatedAt` (and `createdAt` on insert).
    @discardableResult func saveDraft(_ document: Document) async throws -> Document
    /// The highest `sequence` issued from `seriesID` in `periodKey`, or nil.
    func highestIssuedSequence(seriesID: String, periodKey: String) async throws -> Int?
    /// Records that an issued document was sent (`spec/documents.md` §8); nil clears it again.
    func markSent(documentID: String, at timestamp: Int64?) async throws
    /// Home dashboard totals (`docs/plan.md` Phase 4); home-currency invoices only, see `DashboardTotals`.
    func observeDashboard(businessID: String, homeCurrency: CurrencyCode) -> AsyncThrowingStream<DashboardTotals, any Error>
    /// Live, issued invoices as reminder candidates (`spec/reminders.md` §2), status already derived.
    func fetchReminderCandidates(businessID: String) async throws -> [ReminderCandidate]
}

/// Document operations that write several rows in one transaction (`spec/documents.md` §6–9, §11–12).
public protocol DocumentService: Sendable {
    /// `IssueDocument`: blocking problems, number, frozen snapshots, stored results and the free-tier counter.
    func issue(documentID: String, deviceID: String) async throws -> Document
    /// A new saved draft copying the document.
    func duplicate(documentID: String) async throws -> Document
    /// A new saved invoice draft from an issued quote, which becomes `converted`.
    func convertQuote(documentID: String) async throws -> Document
    /// Tombstones a draft (and releases the quote it was converted from).
    func deleteDraft(documentID: String) async throws
    /// Terminal: a live issued document becomes `void` (`spec/documents.md` §11). `reason` is trimmed and required.
    func voidDocument(documentID: String, reason: String) async throws -> Document
    /// The buyer accepted an issued quote (`spec/documents.md` §12); valid even after `validUntil` has passed.
    func acceptQuote(documentID: String) async throws -> Document
    /// The buyer declined an issued quote (`spec/documents.md` §12); valid even after `validUntil` has passed.
    func declineQuote(documentID: String) async throws -> Document
}

public enum DocumentServiceError: Error, Equatable, Sendable {
    case notFound
    /// `not_a_draft`: only drafts can be issued, edited or deleted.
    case notADraft
    /// `not_convertible`: only an issued quote that is not converted yet.
    case notConvertible
    /// Issuing is blocked; nothing was written.
    case blocked([IssueProblem])
    /// `not_voidable`: only a live issued document.
    case notVoidable
    /// Void needs a non-empty reason.
    case voidReasonRequired
    /// `already_converted`: a converted quote cannot be reopened.
    case alreadyConverted
    /// `not_a_live_quote`: only an issued quote can be accepted or declined.
    case notALiveQuote
}

public protocol PaymentRepository: Sendable {
    /// Live payments of a document, most recent date first.
    func observePayments(documentID: String) -> AsyncThrowingStream<[Payment], any Error>
    func fetchPayments(documentID: String) async throws -> [Payment]
    /// Writes a tombstone (correcting a payment is delete-and-re-add, `spec/documents.md` §10).
    func softDelete(paymentID: String) async throws
}

/// Records a payment after checking the document (`spec/documents.md` §10), one write.
public protocol PaymentService: Sendable {
    @discardableResult
    func recordPayment(documentID: String, amountMinor: Int64, date: LocalDate, method: PaymentMethod,
                       reference: String?, note: String?) async throws -> Payment
}

public enum PaymentServiceError: Error, Equatable, Sendable {
    case documentNotFound
    /// `not_payable`: only a live, issued invoice.
    case notPayable
}

/// Portable backups (`spec/backup.md`): export, restore ("replace all") and the "last backup" state.
public protocol BackupService: Sendable {
    /// The highest migration this app applies (`BackupCodec.validate`'s `appSchemaVersion`).
    var schemaVersion: Int { get }
    /// §1–2: every synced row, tombstones included, from one consistent read, sorted.
    func makeBackup(app: BackupFile.AppInfo) async throws -> BackupFile
    /// §4 steps 3–4: writes the safety snapshot, then replaces all data in one transaction (taking over series for
    /// `deviceID` where needed). Validate first; a thrown error means nothing changed.
    func restore(_ file: BackupFile, deviceID: String) async throws
    /// §4 step 3 on its own: a snapshot of the current data before something replaces it (a restore, or erasing
    /// this device's data to sync with another iCloud account).
    func writeSafetySnapshot() async throws
    /// §2: the user saved or shared an export.
    func recordBackup(at timestamp: Int64) async throws
    func observeStatus() -> AsyncThrowingStream<BackupStatus, any Error>
}

/// Numbering on several devices (`spec/sync.md` §3–4), each write one transaction.
public protocol NumberingService: Sendable {
    /// §3.1: a new series of `docType` owned by `deviceID`, with the next free device letter.
    func createDeviceSeries(businessID: String, docType: DocumentType, deviceID: String) async throws
        -> NumberingSeries
    /// §3.2: `deviceID` becomes the owner; counters continue after every number issued from the series.
    func takeOver(seriesID: String, deviceID: String) async throws -> NumberingSeries
    /// §4: issued or void documents of the business that share a number.
    func observeDuplicateNumbers(businessID: String) -> AsyncThrowingStream<[DuplicateNumbers.Group], any Error>
}

public enum NumberingServiceError: Error, Equatable, Sendable {
    case businessNotFound
    case seriesNotFound
    case noDeviceLetter
}
