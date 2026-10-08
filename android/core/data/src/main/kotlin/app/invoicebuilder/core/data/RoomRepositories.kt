package app.invoicebuilder.core.data

import androidx.room.withTransaction
import app.invoicebuilder.core.domain.backup.BackupCodec
import app.invoicebuilder.core.domain.models.Asset
import app.invoicebuilder.core.domain.models.AssetKind
import app.invoicebuilder.core.domain.models.Business
import app.invoicebuilder.core.domain.models.CatalogItem
import app.invoicebuilder.core.domain.models.Client
import app.invoicebuilder.core.domain.models.DeviceState
import app.invoicebuilder.core.domain.models.ImagePayload
import app.invoicebuilder.core.domain.models.NumberingSeries
import app.invoicebuilder.core.domain.repositories.AssetRepository
import app.invoicebuilder.core.domain.repositories.BusinessRepository
import app.invoicebuilder.core.domain.repositories.BusinessSetupService
import app.invoicebuilder.core.domain.repositories.CatalogRepository
import app.invoicebuilder.core.domain.repositories.ClientRepository
import app.invoicebuilder.core.domain.repositories.DeviceStateRepository
import app.invoicebuilder.core.domain.repositories.NumberingSeriesRepository
import app.invoicebuilder.core.domain.support.IDGenerator
import app.invoicebuilder.core.domain.support.TimeSource
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.map

// Room implementations of `:core:domain`'s repository interfaces (iOS: `GRDBRepositories.swift`). Reads never
// return tombstoned rows; deletes write a tombstone (`spec/setup.md` §1). `save` inserts or updates by id, keeps the
// stored `created_at` and stamps `updated_at`.

/** A row that the caller expected to exist is missing (or tombstoned). iOS: `RecordNotFound`. */
class RecordNotFound(val table: String, val id: String) : Exception("$table $id not found")

class RoomBusinessRepository(private val db: AppDatabase, private val time: TimeSource) : BusinessRepository {
    override fun observeBusiness(id: String): Flow<Business?> = db.businesses().observe(id).map { it?.toDomain() }.distinctUntilChanged()
    override suspend fun fetchBusiness(id: String): Business? = db.businesses().live(id)?.toDomain()
    override suspend fun fetchBusinesses(): List<Business> = db.businesses().allLive().map { it.toDomain() }

    override suspend fun save(business: Business): Business = db.withTransaction {
        val now = time.now()
        val existing = db.businesses().any(business.id)
        val stored = business.copy(updatedAt = now, createdAt = existing?.createdAt ?: now)
        if (existing != null) db.businesses().update(stored.toEntity()) else db.businesses().insert(stored.toEntity())
        stored
    }
}

class RoomClientRepository(private val db: AppDatabase, private val time: TimeSource) : ClientRepository {
    override fun observeClients(businessID: String): Flow<List<Client>> =
        db.clients().observeAll(businessID).map { rows -> rows.map { it.toDomain() } }.distinctUntilChanged()
    override fun observeClient(id: String): Flow<Client?> = db.clients().observe(id).map { it?.toDomain() }.distinctUntilChanged()
    override suspend fun fetchClient(id: String): Client? = db.clients().live(id)?.toDomain()

    override suspend fun save(client: Client): Client = db.withTransaction {
        val now = time.now()
        val existing = db.clients().any(client.id)
        val stored = client.copy(updatedAt = now, createdAt = existing?.createdAt ?: now)
        if (existing != null) db.clients().update(stored.toEntity()) else db.clients().insert(stored.toEntity())
        stored
    }

    override suspend fun setArchived(archived: Boolean, clientID: String) {
        val now = time.now()
        if (db.clients().setArchived(clientID, if (archived) now else null, now) == 0) throw RecordNotFound("client", clientID)
    }

    override suspend fun delete(clientID: String) {
        if (db.clients().tombstone(clientID, time.now()) == 0) throw RecordNotFound("client", clientID)
    }
}

class RoomCatalogRepository(private val db: AppDatabase, private val time: TimeSource) : CatalogRepository {
    override fun observeItems(businessID: String): Flow<List<CatalogItem>> =
        db.catalog().observeAll(businessID).map { rows -> rows.map { it.toDomain() } }.distinctUntilChanged()
    override fun observeItem(id: String): Flow<CatalogItem?> = db.catalog().observe(id).map { it?.toDomain() }.distinctUntilChanged()
    override suspend fun fetchItem(id: String): CatalogItem? = db.catalog().live(id)?.toDomain()

    override suspend fun save(item: CatalogItem): CatalogItem = db.withTransaction {
        val now = time.now()
        val existing = db.catalog().any(item.id)
        val stored = item.copy(updatedAt = now, createdAt = existing?.createdAt ?: now)
        if (existing != null) db.catalog().update(stored.toEntity()) else db.catalog().insert(stored.toEntity())
        stored
    }

    override suspend fun setArchived(archived: Boolean, itemID: String) {
        val now = time.now()
        if (db.catalog().setArchived(itemID, if (archived) now else null, now) == 0) throw RecordNotFound("catalog_item", itemID)
    }

    override suspend fun delete(itemID: String) {
        if (db.catalog().tombstone(itemID, time.now()) == 0) throw RecordNotFound("catalog_item", itemID)
    }

    override suspend fun countItems(businessID: String, rateID: String): Int = db.catalog().countUsingRate(businessID, rateID)
}

class RoomNumberingSeriesRepository(private val db: AppDatabase, private val time: TimeSource) : NumberingSeriesRepository {
    override fun observeSeries(businessID: String): Flow<List<NumberingSeries>> =
        db.series().observeAll(businessID).map { rows -> rows.map { it.toDomain() } }.distinctUntilChanged()

    override suspend fun save(series: NumberingSeries): NumberingSeries = db.withTransaction {
        val now = time.now()
        val existing = db.series().any(series.id)
        val stored = series.copy(updatedAt = now, createdAt = existing?.createdAt ?: now)
        if (existing != null) db.series().update(stored.toEntity()) else db.series().insert(stored.toEntity())
        stored
    }
}

class RoomAssetRepository(private val db: AppDatabase) : AssetRepository {
    override suspend fun fetchAsset(id: String): Asset? = db.assets().live(id)?.toDomain()
    override fun observeAsset(id: String): Flow<Asset?> = db.assets().observe(id).map { it?.toDomain() }
}

class RoomDeviceStateRepository(private val db: AppDatabase, private val time: TimeSource, private val ids: IDGenerator) : DeviceStateRepository {
    override suspend fun loadOrCreate(deviceName: String): DeviceState = db.withTransaction {
        db.devices().current()?.toDomain() ?: DeviceState(ids.make(), deviceName, createdAt = time.now(), updatedAt = time.now())
            .also { db.devices().insert(it.toEntity()) }
    }

    override suspend fun setActiveBusiness(id: String?) = db.withTransaction { setActiveBusiness(db, id, time.now()) }

    companion object {
        suspend fun setActiveBusiness(db: AppDatabase, businessID: String?, now: Long) {
            val current = db.devices().current()?.toDomain() ?: throw RecordNotFound("device_state", "this device")
            db.devices().update(current.copy(preferences = current.preferences.copy(activeBusinessId = businessID), updatedAt = now).toEntity())
        }
    }
}

/** Multi-table setup operations, each in one write transaction (all or nothing). iOS: `GRDBBusinessSetupService`. */
class RoomBusinessSetupService(private val db: AppDatabase, private val time: TimeSource, private val ids: IDGenerator) : BusinessSetupService {
    override suspend fun createBusiness(
        business: Business, series: List<NumberingSeries>, logo: ImagePayload?, signature: ImagePayload?, deviceID: String,
    ): Business = db.withTransaction {
        val now = time.now()
        var stored = business.copy(createdAt = now, updatedAt = now, logoAssetId = null, signatureAssetId = null)
        db.businesses().insert(stored.toEntity()) // assets reference the business, so it goes first
        stored = stored.copy(
            logoAssetId = logo?.let { AssetStore.store(db, it, AssetKind.logo, stored.id, now, ids).id },
            signatureAssetId = signature?.let { AssetStore.store(db, it, AssetKind.signature, stored.id, now, ids).id },
        )
        if (stored.logoAssetId != null || stored.signatureAssetId != null) db.businesses().update(stored.toEntity())
        for (entry in series) db.series().insert(entry.copy(createdAt = now, updatedAt = now).toEntity())
        RoomDeviceStateRepository.setActiveBusiness(db, stored.id, now)
        stored
    }

    override suspend fun setImage(image: ImagePayload?, kind: AssetKind, businessID: String): Business = db.withTransaction {
        val now = time.now()
        var business = db.businesses().live(businessID)?.toDomain() ?: throw RecordNotFound("business", businessID)
        val previous = if (kind == AssetKind.logo) business.logoAssetId else business.signatureAssetId
        val newID = image?.let { AssetStore.store(db, it, kind, businessID, now, ids).id }
        business = if (kind == AssetKind.logo) business.copy(logoAssetId = newID) else business.copy(signatureAssetId = newID)
        business = business.copy(updatedAt = now)
        db.businesses().update(business.toEntity())
        if (previous != null && previous != newID) AssetStore.releaseIfUnused(db, previous, now)
        business
    }
}

/** Asset rows (`spec/setup.md` §9). iOS: `AssetStore`. */
internal object AssetStore {
    /** Stores the bytes, or returns the live asset of the same business and kind with the same SHA-256. */
    suspend fun store(db: AppDatabase, image: ImagePayload, kind: AssetKind, businessID: String, now: Long, ids: IDGenerator): Asset {
        val digest = BackupCodec.sha256Hex(image.data)
        db.assets().matching(businessID, kind.rawValue, digest)?.let { return it.toDomain() }
        val asset = Asset(ids.make(), now, now, null, businessID, kind, image.mime, digest, image.data)
        db.assets().insert(asset.toEntity())
        return asset
    }

    /** Tombstones the asset when no live business and no issued document's seller snapshot points at it any more. */
    suspend fun releaseIfUnused(db: AppDatabase, assetID: String, now: Long) {
        if (db.businesses().countUsing(assetID) == 0 && db.documents().issuedUsingAsset(assetID) == 0) db.assets().tombstone(assetID, now)
    }
}
