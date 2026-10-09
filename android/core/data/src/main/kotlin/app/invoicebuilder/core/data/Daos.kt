package app.invoicebuilder.core.data

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.Query
import androidx.room.Update
import kotlinx.coroutines.flow.Flow

// DAOs (≈ GRDB requests on iOS). Every read filters tombstones (`deleted_at IS NULL`) unless named `…Any…`; writes
// never use a replacing INSERT for an existing id (it would cascade), so `save` is update-or-insert.

@Dao
interface BusinessDao {
    @Query("SELECT * FROM business WHERE id = :id AND deleted_at IS NULL") fun observe(id: String): Flow<BusinessEntity?>
    @Query("SELECT * FROM business WHERE id = :id AND deleted_at IS NULL") suspend fun live(id: String): BusinessEntity?
    @Query("SELECT * FROM business WHERE id = :id") suspend fun any(id: String): BusinessEntity?
    @Query("SELECT * FROM business WHERE deleted_at IS NULL ORDER BY created_at, id") suspend fun allLive(): List<BusinessEntity>
    @Query("SELECT * FROM business ORDER BY created_at, id") suspend fun all(): List<BusinessEntity>
    @Insert suspend fun insert(entity: BusinessEntity)
    @Update suspend fun update(entity: BusinessEntity)
    @Query("SELECT COUNT(*) FROM business WHERE deleted_at IS NULL AND (logo_asset_id = :assetID OR signature_asset_id = :assetID)")
    suspend fun countUsing(assetID: String): Int
}

@Dao
interface ClientDao {
    @Query("SELECT * FROM client WHERE business_id = :businessID AND deleted_at IS NULL") fun observeAll(businessID: String): Flow<List<ClientEntity>>
    @Query("SELECT * FROM client WHERE id = :id AND deleted_at IS NULL") fun observe(id: String): Flow<ClientEntity?>
    @Query("SELECT * FROM client WHERE id = :id AND deleted_at IS NULL") suspend fun live(id: String): ClientEntity?
    @Query("SELECT * FROM client WHERE id = :id") suspend fun any(id: String): ClientEntity?
    @Query("SELECT * FROM client ORDER BY created_at, id") suspend fun all(): List<ClientEntity>
    @Insert suspend fun insert(entity: ClientEntity)
    @Update suspend fun update(entity: ClientEntity)
    @Query("UPDATE client SET archived_at = :value, updated_at = :now WHERE id = :id AND deleted_at IS NULL") suspend fun setArchived(id: String, value: Long?, now: Long): Int
    @Query("UPDATE client SET deleted_at = :now, updated_at = :now WHERE id = :id AND deleted_at IS NULL") suspend fun tombstone(id: String, now: Long): Int
}

@Dao
interface CatalogDao {
    @Query("SELECT * FROM catalog_item WHERE business_id = :businessID AND deleted_at IS NULL") fun observeAll(businessID: String): Flow<List<CatalogItemEntity>>
    @Query("SELECT * FROM catalog_item WHERE id = :id AND deleted_at IS NULL") fun observe(id: String): Flow<CatalogItemEntity?>
    @Query("SELECT * FROM catalog_item WHERE id = :id AND deleted_at IS NULL") suspend fun live(id: String): CatalogItemEntity?
    @Query("SELECT * FROM catalog_item WHERE id = :id") suspend fun any(id: String): CatalogItemEntity?
    @Query("SELECT * FROM catalog_item ORDER BY created_at, id") suspend fun all(): List<CatalogItemEntity>
    @Insert suspend fun insert(entity: CatalogItemEntity)
    @Update suspend fun update(entity: CatalogItemEntity)
    @Query("UPDATE catalog_item SET archived_at = :value, updated_at = :now WHERE id = :id AND deleted_at IS NULL") suspend fun setArchived(id: String, value: Long?, now: Long): Int
    @Query("UPDATE catalog_item SET deleted_at = :now, updated_at = :now WHERE id = :id AND deleted_at IS NULL") suspend fun tombstone(id: String, now: Long): Int
    @Query("SELECT COUNT(*) FROM catalog_item WHERE business_id = :businessID AND rate_id = :rateID AND deleted_at IS NULL") suspend fun countUsingRate(businessID: String, rateID: String): Int
}

@Dao
interface NumberingSeriesDao {
    @Query("SELECT * FROM numbering_series WHERE business_id = :businessID AND deleted_at IS NULL ORDER BY doc_type, created_at, id")
    fun observeAll(businessID: String): Flow<List<NumberingSeriesEntity>>
    @Query("SELECT * FROM numbering_series WHERE business_id = :businessID AND deleted_at IS NULL ORDER BY created_at, id")
    suspend fun liveOf(businessID: String): List<NumberingSeriesEntity>
    @Query("SELECT * FROM numbering_series WHERE id = :id AND deleted_at IS NULL") suspend fun live(id: String): NumberingSeriesEntity?
    @Query("SELECT * FROM numbering_series WHERE id = :id") suspend fun any(id: String): NumberingSeriesEntity?
    @Query("SELECT * FROM numbering_series WHERE deleted_at IS NULL ORDER BY created_at, id") suspend fun allLive(): List<NumberingSeriesEntity>
    @Query("SELECT * FROM numbering_series ORDER BY created_at, id") suspend fun all(): List<NumberingSeriesEntity>
    @Insert suspend fun insert(entity: NumberingSeriesEntity)
    @Update suspend fun update(entity: NumberingSeriesEntity)
}

@Dao
interface AssetDao {
    @Query("SELECT * FROM asset WHERE id = :id AND deleted_at IS NULL") suspend fun live(id: String): AssetEntity?
    @Query("SELECT * FROM asset WHERE id = :id AND deleted_at IS NULL") fun observe(id: String): Flow<AssetEntity?>
    @Query("SELECT * FROM asset WHERE id = :id") suspend fun any(id: String): AssetEntity?
    @Query("SELECT * FROM asset ORDER BY created_at, id") suspend fun all(): List<AssetEntity>
    @Query("SELECT * FROM asset WHERE business_id = :businessID AND kind = :kind AND sha256 = :sha256 AND deleted_at IS NULL LIMIT 1")
    suspend fun matching(businessID: String, kind: String, sha256: String): AssetEntity?
    @Insert suspend fun insert(entity: AssetEntity)
    @Update suspend fun update(entity: AssetEntity)
    @Query("UPDATE asset SET deleted_at = :now, updated_at = :now WHERE id = :id AND deleted_at IS NULL") suspend fun tombstone(id: String, now: Long): Int
}

@Dao
interface DeviceStateDao {
    /** This device's row: the earliest one if there are several (`spec/setup.md` §2). */
    @Query("SELECT * FROM device_state ORDER BY created_at, id LIMIT 1") suspend fun current(): DeviceStateEntity?
    @Insert suspend fun insert(entity: DeviceStateEntity)
    @Update suspend fun update(entity: DeviceStateEntity)
    @Query("UPDATE device_state SET free_counter_mirror = free_counter_mirror + 1, updated_at = :now WHERE id = (SELECT id FROM device_state ORDER BY created_at, id LIMIT 1)")
    suspend fun incrementMirror(now: Long)
    /** A database copied from another device takes a new id (ADR-0019); nothing references this local row. */
    @Query("UPDATE device_state SET id = :newID, updated_at = :now WHERE id = :oldID") suspend fun changeID(oldID: String, newID: String, now: Long)
}

@Dao
interface AppStateDao {
    @Query("SELECT value FROM app_state WHERE `key` = :key") suspend fun value(key: String): String?
    @Query("SELECT value FROM app_state WHERE `key` = :key") fun observe(key: String): Flow<String?>
    @Query("INSERT INTO app_state (`key`, value) VALUES (:key, :value) ON CONFLICT(`key`) DO UPDATE SET value = excluded.value")
    suspend fun set(key: String, value: String)
    @Query("INSERT INTO app_state (`key`, value) VALUES (:key, '1') ON CONFLICT(`key`) DO UPDATE SET value = CAST(CAST(value AS INTEGER) + 1 AS TEXT)")
    suspend fun increment(key: String)
}

/** One documents-list row (iOS: `GRDBDocumentRepository.summaries`). */
data class SummaryRow(
    val id: String, val doc_type: String, val number: String?, val lifecycle: String, val issue_date: String, val due_date: String?,
    val valid_until: String?, val sent_at: Long?, val quote_outcome: String?, val client_id: String?, val buyer_snapshot: String?,
    val currency: String, val total_minor: Long, val updated_at: Long, val line_count: Int, val paid_minor: Long,
)

/** A reminder candidate or dashboard row: status inputs plus the paid sum. */
data class StatusRow(
    val id: String, val due_date: String?, val total_minor: Long, val sent_at: Long?, val reminder_days_after_due_override: Int?,
    val paid_minor: Long,
)

@Dao
interface DocumentDao {
    @Query("SELECT * FROM document WHERE id = :id AND deleted_at IS NULL") suspend fun live(id: String): DocumentEntity?
    @Query("SELECT * FROM document WHERE id = :id") suspend fun any(id: String): DocumentEntity?
    @Query("SELECT * FROM document ORDER BY created_at, id") suspend fun all(): List<DocumentEntity>
    @Insert suspend fun insert(entity: DocumentEntity)
    @Update suspend fun update(entity: DocumentEntity)

    @Query("SELECT * FROM line_item WHERE document_id = :documentID AND deleted_at IS NULL ORDER BY position, id")
    suspend fun liveLines(documentID: String): List<LineItemEntity>
    @Query("SELECT * FROM line_item WHERE document_id = :documentID") suspend fun allLinesOf(documentID: String): List<LineItemEntity>
    @Query("SELECT * FROM line_item WHERE deleted_at IS NULL ORDER BY position, id") suspend fun allLiveLines(): List<LineItemEntity>
    @Query("SELECT * FROM line_item WHERE id = :id") suspend fun anyLine(id: String): LineItemEntity?
    @Insert suspend fun insertLine(entity: LineItemEntity)
    @Update suspend fun updateLine(entity: LineItemEntity)
    @Query("UPDATE line_item SET deleted_at = :now, updated_at = :now WHERE id = :id AND deleted_at IS NULL") suspend fun tombstoneLine(id: String, now: Long)

    @Insert suspend fun insertTaxLine(entity: TaxLineEntity)

    @Query(
        """
        SELECT d.id, d.doc_type, d.number, d.lifecycle, d.issue_date, d.due_date, d.valid_until, d.sent_at,
               d.quote_outcome, d.client_id, d.buyer_snapshot, d.currency, d.total_minor, d.updated_at,
               (SELECT COUNT(*) FROM line_item l WHERE l.document_id = d.id AND l.deleted_at IS NULL) AS line_count,
               (SELECT COALESCE(SUM(p.amount_minor), 0) FROM payment p WHERE p.document_id = d.id AND p.deleted_at IS NULL) AS paid_minor
        FROM document d WHERE d.business_id = :businessID AND d.deleted_at IS NULL
        ORDER BY d.issue_date DESC, d.updated_at DESC, d.id
        """,
    )
    suspend fun summaries(businessID: String): List<SummaryRow>

    @Query(
        """
        SELECT d.id, d.due_date, d.total_minor, d.sent_at, d.reminder_days_after_due_override,
               (SELECT COALESCE(SUM(p.amount_minor), 0) FROM payment p WHERE p.document_id = d.id AND p.deleted_at IS NULL) AS paid_minor
        FROM document d
        WHERE d.business_id = :businessID AND d.deleted_at IS NULL AND d.doc_type = 'invoice' AND d.lifecycle = 'issued'
              AND (:currency IS NULL OR d.currency = :currency)
        """,
    )
    suspend fun issuedInvoices(businessID: String, currency: String?): List<StatusRow>

    @Query(
        """
        SELECT COALESCE(SUM(p.amount_minor), 0) FROM payment p JOIN document d ON d.id = p.document_id
        WHERE d.business_id = :businessID AND d.deleted_at IS NULL AND d.currency = :currency
              AND p.deleted_at IS NULL AND p.date >= :from AND p.date < :until
        """,
    )
    suspend fun paidBetween(businessID: String, currency: String, from: String, until: String): Long

    @Query("SELECT MAX(sequence) FROM document WHERE series_id = :seriesID AND period_key = :periodKey AND lifecycle <> 'draft' AND deleted_at IS NULL")
    suspend fun highestSequence(seriesID: String, periodKey: String): Int?

    @Query("SELECT COUNT(*) FROM document WHERE converted_from_id = :quoteID AND deleted_at IS NULL") suspend fun liveConversions(quoteID: String): Int

    @Query("SELECT EXISTS (SELECT 1 FROM document WHERE lifecycle <> 'draft' AND deleted_at IS NULL)") fun observeHasIssued(): Flow<Boolean>

    @Query("SELECT COUNT(*) FROM document WHERE doc_type = 'invoice' AND lifecycle <> 'draft'") suspend fun everIssuedInvoices(): Int

    @Query(
        """
        SELECT COUNT(*) FROM document WHERE deleted_at IS NULL AND lifecycle <> 'draft' AND
        (json_extract(seller_snapshot, '$.logoAssetId') = :assetID OR json_extract(seller_snapshot, '$.signatureAssetId') = :assetID)
        """,
    )
    suspend fun issuedUsingAsset(assetID: String): Int
}

@Dao
interface PaymentDao {
    @Query("SELECT * FROM payment WHERE document_id = :documentID AND deleted_at IS NULL ORDER BY date DESC, created_at DESC")
    fun observeOf(documentID: String): Flow<List<PaymentEntity>>
    @Query("SELECT * FROM payment WHERE document_id = :documentID AND deleted_at IS NULL ORDER BY date DESC, created_at DESC")
    suspend fun liveOf(documentID: String): List<PaymentEntity>
    @Query("SELECT * FROM payment WHERE id = :id") suspend fun any(id: String): PaymentEntity?
    @Query("SELECT * FROM payment ORDER BY created_at, id") suspend fun all(): List<PaymentEntity>
    @Insert suspend fun insert(entity: PaymentEntity)
    @Update suspend fun update(entity: PaymentEntity)
    @Query("UPDATE payment SET deleted_at = :now, updated_at = :now WHERE id = :id AND deleted_at IS NULL") suspend fun tombstone(id: String, now: Long): Int
}
