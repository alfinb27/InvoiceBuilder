package app.invoicebuilder.core.billing

import app.invoicebuilder.core.domain.billing.EntitlementEvent
import app.invoicebuilder.core.domain.billing.EntitlementMachine
import app.invoicebuilder.core.domain.billing.EntitlementState
import app.invoicebuilder.core.domain.billing.EntitlementStatus
import app.invoicebuilder.core.domain.billing.FreeTier
import app.invoicebuilder.core.domain.billing.FreeTierCounts
import app.invoicebuilder.core.domain.repositories.EntitlementService
import app.invoicebuilder.core.domain.repositories.FreeTierRepository
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.emptyFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

/** What the entitlement service needs from the store; `PlayBillingClient` implements it. iOS: `StoreClient`. */
interface StoreClient {
    /** The localised price, or null when the store cannot be reached or the product is missing. */
    suspend fun displayPrice(productID: String): String?
    /** Whether a `PURCHASED` purchase of the product is in the store's current list (absent ⇒ refunded). */
    suspend fun owns(productID: String): Boolean
    /** [activity] is the `Activity` the purchase sheet is shown over (≈ the window scene StoreKit uses). */
    suspend fun purchase(productID: String, activity: Any): PurchaseOutcome
    /** Purchase changes arriving outside a purchase call (pending payments completing, refunds seen on resume). */
    fun updates(productID: String): Flow<OwnershipChange>
    /** "Refresh purchases" (≈ `AppStore.sync()`). */
    suspend fun sync()
}

enum class PurchaseOutcome { purchased, pending, cancelled, failed }

enum class OwnershipChange { owned, revoked }

/** The free-tier counter mirrored outside the database (Android: Block Store), best effort. iOS: `CounterMirror`. */
interface CounterMirror {
    suspend fun read(): Int
    /** Raises the stored value to [count]; never lowers it. */
    suspend fun raise(count: Int)
}

/** `spec/billing.md`: the state machine driven by the store, with the effective count from every source. */
class StoreEntitlementService(
    val productID: String,
    private val store: StoreClient,
    private val counts: FreeTierRepository,
    private val mirror: CounterMirror,
    private val scope: CoroutineScope,
) : EntitlementService {
    private val state = MutableStateFlow(EntitlementStatus(EntitlementState.unknown, 0))
    override val status: StateFlow<EntitlementStatus> = state.asStateFlow()
    private var listener: Job? = null

    override suspend fun start() {
        val count = effectiveCount()
        state.update { it.copy(count = count) }
        startListening()
        apply(if (store.owns(productID)) EntitlementEvent.resolvedOwned else EntitlementEvent.resolvedNotOwned, count)
        store.displayPrice(productID)?.let { price -> state.update { it.copy(displayPrice = price) } }
    }

    override suspend fun refreshCount() {
        val count = effectiveCount()
        mirror.raise(count)
        apply(EntitlementEvent.counted, count)
    }

    override suspend fun purchase(activity: Any) {
        val count = effectiveCount()
        apply(EntitlementEvent.purchaseStarted, count)
        if (state.value.state != EntitlementState.purchasing) return
        apply(
            when (store.purchase(productID, activity)) {
                PurchaseOutcome.purchased -> EntitlementEvent.purchased
                PurchaseOutcome.pending -> EntitlementEvent.purchasePending
                PurchaseOutcome.cancelled -> EntitlementEvent.purchaseCancelled
                PurchaseOutcome.failed -> EntitlementEvent.purchaseFailed
            },
            count,
        )
    }

    override suspend fun restore() {
        val count = effectiveCount()
        runCatching { store.sync() }
        apply(if (store.owns(productID)) EntitlementEvent.resolvedOwned else EntitlementEvent.resolvedNotOwned, count)
    }

    private suspend fun effectiveCount(): Int {
        val stored = runCatching { counts.fetchCounts() }.getOrElse { FreeTierCounts(0, 0, 0) }
        val mirrored = runCatching { mirror.read() }.getOrDefault(0)
        return FreeTier.effectiveCount(stored.local, stored.deviceMirror, mirrored, stored.issuedInDatabase)
    }

    private fun startListening() {
        listener?.cancel()
        listener = scope.launch {
            store.updates(productID).collect { change ->
                apply(if (change == OwnershipChange.owned) EntitlementEvent.purchased else EntitlementEvent.revoked, effectiveCount())
            }
        }
    }

    private fun apply(event: EntitlementEvent, count: Int) {
        state.update { it.copy(state = EntitlementMachine.next(it.state, event, count), count = count) }
    }

    companion object {
        /** `<application id>.unlimited_invoices` (`billing.md`, Product). */
        fun productID(applicationID: String): String = "$applicationID.unlimited_invoices"
    }
}

/** No store (emulators without Play, tests): nothing is owned, nothing can be bought, no price. */
class UnavailableStoreClient : StoreClient {
    override suspend fun displayPrice(productID: String): String? = null
    override suspend fun owns(productID: String): Boolean = false
    override suspend fun purchase(productID: String, activity: Any): PurchaseOutcome = PurchaseOutcome.failed
    override fun updates(productID: String): Flow<OwnershipChange> = emptyFlow()
    override suspend fun sync() {}
}

/** A mirror that lives as long as the process (tests, in-memory launches). */
class MemoryCounterMirror(initial: Int = 0) : CounterMirror {
    @Volatile private var value = initial
    override suspend fun read(): Int = value
    @Synchronized private fun set(count: Int) { value = maxOf(value, count) }
    override suspend fun raise(count: Int) = set(count)
}
