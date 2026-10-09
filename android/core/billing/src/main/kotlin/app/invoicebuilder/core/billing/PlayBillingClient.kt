package app.invoicebuilder.core.billing

import android.app.Activity
import android.content.Context
import com.android.billingclient.api.AcknowledgePurchaseParams
import com.android.billingclient.api.BillingClient
import com.android.billingclient.api.BillingClientStateListener
import com.android.billingclient.api.BillingFlowParams
import com.android.billingclient.api.BillingResult
import com.android.billingclient.api.PendingPurchasesParams
import com.android.billingclient.api.ProductDetails
import com.android.billingclient.api.Purchase
import com.android.billingclient.api.PurchasesUpdatedListener
import com.android.billingclient.api.QueryProductDetailsParams
import com.android.billingclient.api.QueryPurchasesParams
import com.android.billingclient.api.acknowledgePurchase
import com.android.billingclient.api.queryProductDetails
import com.android.billingclient.api.queryPurchasesAsync
import com.google.android.gms.auth.blockstore.Blockstore
import com.google.android.gms.auth.blockstore.RetrieveBytesRequest
import com.google.android.gms.auth.blockstore.StoreBytesData
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.mapNotNull
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.tasks.await
import kotlin.coroutines.resume
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withTimeoutOrNull

/**
 * Play Billing (`spec/billing.md`, Platform rules — Android). iOS: `StoreKitClient`.
 *
 * Unlike StoreKit's async sequences, Play Billing is a callback API on a service connection: the client connects
 * lazily (and reconnects automatically), purchase results arrive on one `PurchasesUpdatedListener`, and every
 * `PURCHASED` purchase must be acknowledged within 3 days or Google refunds it.
 */
class PlayBillingClient(context: Context) : StoreClient {
    private val purchaseResults = MutableSharedFlow<Pair<BillingResult, List<Purchase>?>>(extraBufferCapacity = 8)
    /** The purchase call waiting for its result; while it is set, results go to it instead of [updates]. */
    @Volatile private var pendingPurchase: CompletableDeferred<Pair<BillingResult, List<Purchase>?>>? = null
    private val connection = Mutex()

    private companion object {
        const val CONNECT_TIMEOUT_MS = 5_000L
    }

    private val listener = PurchasesUpdatedListener { result, purchases ->
        val waiting = pendingPurchase
        if (waiting != null) waiting.complete(result to purchases) else purchaseResults.tryEmit(result to purchases)
    }

    private val client: BillingClient = BillingClient.newBuilder(context.applicationContext)
        .setListener(listener)
        .enablePendingPurchases(PendingPurchasesParams.newBuilder().enableOneTimeProducts().build())
        .enableAutoServiceReconnection()
        .build()

    /** At most [CONNECT_TIMEOUT_MS]: with Play missing or offline, auto-reconnection retries for a long time. */
    private suspend fun connected(): Boolean = connection.withLock {
        if (client.isReady) return true
        withTimeoutOrNull(CONNECT_TIMEOUT_MS) { connect() } ?: false
    }

    private suspend fun connect(): Boolean =
        suspendCancellableCoroutine { continuation ->
            client.startConnection(object : BillingClientStateListener {
                override fun onBillingSetupFinished(result: BillingResult) {
                    if (continuation.isActive) continuation.resume(result.responseCode == BillingClient.BillingResponseCode.OK)
                }
                override fun onBillingServiceDisconnected() {}
            })
        }

    private suspend fun details(productID: String): ProductDetails? {
        if (!connected()) return null
        val params = QueryProductDetailsParams.newBuilder().setProductList(listOf(
            QueryProductDetailsParams.Product.newBuilder().setProductId(productID).setProductType(BillingClient.ProductType.INAPP).build(),
        )).build()
        return client.queryProductDetails(params).productDetailsList?.firstOrNull()
    }

    override suspend fun displayPrice(productID: String): String? = details(productID)?.oneTimePurchaseOfferDetails?.formattedPrice

    /**
     * Play's purchase list (it answers from the Play Store's on-device cache when offline). Null when Play can't be
     * reached or answers with an error: that is not "not owned", so the caller keeps the state it has (`billing.md`).
     */
    override suspend fun owns(productID: String): Boolean? {
        if (!connected()) return null
        val result = client.queryPurchasesAsync(QueryPurchasesParams.newBuilder().setProductType(BillingClient.ProductType.INAPP).build())
        if (result.billingResult.responseCode != BillingClient.BillingResponseCode.OK) return null
        val purchased = result.purchasesList.filter { productID in it.products && it.purchaseState == Purchase.PurchaseState.PURCHASED }
        purchased.forEach { acknowledge(it) } // the startup sweep: anything a crash left unacknowledged
        return purchased.isNotEmpty()
    }

    override suspend fun purchase(productID: String, activity: Any): PurchaseOutcome {
        val product = details(productID) ?: return PurchaseOutcome.failed
        val host = activity as? Activity ?: return PurchaseOutcome.failed
        val params = BillingFlowParams.newBuilder().setProductDetailsParamsList(listOf(
            BillingFlowParams.ProductDetailsParams.newBuilder().setProductDetails(product).build(),
        )).build()
        val waiting = CompletableDeferred<Pair<BillingResult, List<Purchase>?>>()
        pendingPurchase = waiting
        val launch = client.launchBillingFlow(host, params)
        if (launch.responseCode != BillingClient.BillingResponseCode.OK) {
            pendingPurchase = null
            return if (launch.responseCode == BillingClient.BillingResponseCode.ITEM_ALREADY_OWNED) PurchaseOutcome.purchased else PurchaseOutcome.failed
        }
        val (result, purchases) = try { waiting.await() } finally { pendingPurchase = null }
        return when (result.responseCode) {
            BillingClient.BillingResponseCode.OK -> {
                val purchase = purchases?.firstOrNull { productID in it.products }
                when (purchase?.purchaseState) {
                    Purchase.PurchaseState.PURCHASED -> { acknowledge(purchase); PurchaseOutcome.purchased }
                    Purchase.PurchaseState.PENDING -> PurchaseOutcome.pending
                    else -> PurchaseOutcome.failed
                }
            }
            BillingClient.BillingResponseCode.USER_CANCELED -> PurchaseOutcome.cancelled
            BillingClient.BillingResponseCode.ITEM_ALREADY_OWNED -> PurchaseOutcome.purchased
            else -> PurchaseOutcome.failed
        }
    }

    /** Pending payments that complete later (UPI, cash) arrive on the same listener once no purchase call waits. */
    override fun updates(productID: String): Flow<OwnershipChange> = purchaseResults.mapNotNull { (result, purchases) ->
        if (result.responseCode != BillingClient.BillingResponseCode.OK) return@mapNotNull null
        val purchase = purchases?.firstOrNull { productID in it.products } ?: return@mapNotNull null
        if (purchase.purchaseState == Purchase.PurchaseState.PURCHASED) {
            acknowledge(purchase)
            OwnershipChange.owned
        } else null
    }

    /** Play has no separate refresh (≈ `AppStore.sync()`): every [owns] queries the purchase list again. */
    override suspend fun sync() {}

    private suspend fun acknowledge(purchase: Purchase) {
        if (purchase.isAcknowledged || !connected()) return
        client.acknowledgePurchase(AcknowledgePurchaseParams.newBuilder().setPurchaseToken(purchase.purchaseToken).build())
    }
}

/**
 * The free-tier counter in Block Store (≈ the iOS Keychain item): survives a reinstall on the same device and, with
 * end-to-end-encrypted cloud backup, a new phone restored from it. Best effort: any failure reads as 0.
 */
class BlockStoreCounterMirror(context: Context) : CounterMirror {
    private val client = Blockstore.getClient(context.applicationContext)

    override suspend fun read(): Int = runCatching {
        val request = RetrieveBytesRequest.Builder().setKeys(listOf(KEY)).build()
        client.retrieveBytes(request).await().blockstoreDataMap[KEY]?.bytes?.decodeToString()?.toIntOrNull() ?: 0
    }.getOrDefault(0)

    override suspend fun raise(count: Int) {
        if (count <= read()) return
        runCatching {
            client.storeBytes(StoreBytesData.Builder().setKey(KEY).setBytes(count.toString().encodeToByteArray()).setShouldBackupToCloud(true).build()).await()
        }
    }

    private companion object {
        const val KEY = "invoicebuilder.freeCounter"
    }
}
