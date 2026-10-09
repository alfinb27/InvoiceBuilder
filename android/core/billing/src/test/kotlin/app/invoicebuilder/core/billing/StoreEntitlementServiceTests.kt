package app.invoicebuilder.core.billing

import app.invoicebuilder.core.domain.billing.EntitlementState
import app.invoicebuilder.core.domain.billing.EntitlementStatus
import app.invoicebuilder.core.domain.billing.FreeTierCounts
import app.invoicebuilder.core.domain.repositories.FreeTierRepository
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

// iOS: `StoreEntitlementServiceTests.swift` — the same ten cases, plus two for a store that can't be reached (StoreKit
// always answers from its on-device cache; Play may not be connected).

/** [owned] null = the store can't be reached (Play not connected, an error response). */
class FakeStore(var owned: Boolean? = false, var outcome: PurchaseOutcome = PurchaseOutcome.purchased) : StoreClient {
    var price: String? = "₹299.00"
    var syncs = 0
    private val changes = MutableSharedFlow<OwnershipChange>(extraBufferCapacity = 4)

    /** A purchase change arriving from outside (a pending payment completing, a refund). */
    fun send(change: OwnershipChange) {
        owned = change == OwnershipChange.owned
        changes.tryEmit(change)
    }

    override suspend fun displayPrice(productID: String) = price
    override suspend fun owns(productID: String) = owned
    override suspend fun purchase(productID: String, activity: Any): PurchaseOutcome {
        if (outcome == PurchaseOutcome.purchased) owned = true
        return outcome
    }
    override fun updates(productID: String): Flow<OwnershipChange> = changes
    override suspend fun sync() { syncs++ }
}

class FakeCounts(var counts: FreeTierCounts) : FreeTierRepository {
    override suspend fun fetchCounts() = counts
}

class StoreEntitlementServiceTests {
    private fun counts(local: Int, mirror: Int = 0, database: Int? = null) = FakeCounts(FreeTierCounts(local, mirror, database ?: local))

    private fun TestScope.service(store: StoreClient, counts: FreeTierRepository, mirror: CounterMirror = MemoryCounterMirror()) =
        StoreEntitlementService("p", store, counts, mirror, backgroundScope)

    @Test fun productIDFollowsTheApplicationID() {
        assertEquals("app.invoicebuilder.invoices.unlimited_invoices", StoreEntitlementService.productID("app.invoicebuilder.invoices"))
    }

    @Test fun launchResolvesFromTheStoreAndShowsThePrice() = runTest(UnconfinedTestDispatcher()) {
        val service = service(FakeStore(owned = false), counts(4))
        service.start()
        assertEquals(EntitlementStatus(EntitlementState.free, 4, "₹299.00"), service.status.value)
        assertTrue(service.status.value.remaining == 11 && service.status.value.canIssueInvoice)

        val owned = service(FakeStore(owned = true), counts(40))
        owned.start()
        assertTrue(owned.status.value.state == EntitlementState.unlocked && owned.status.value.canIssueInvoice)
    }

    @Test fun theHighestCountWins() = runTest(UnconfinedTestDispatcher()) {
        // A reinstall emptied the database counter, but Block Store remembers 15.
        val service = service(FakeStore(), counts(0, database = 2), MemoryCounterMirror(15))
        service.start()
        assertEquals(EntitlementState.limitReached, service.status.value.state)
        assertFalse(service.status.value.canIssueInvoice)
    }

    @Test fun issuingTheFifteenthInvoiceReachesTheLimitAndRaisesTheMirror() = runTest(UnconfinedTestDispatcher()) {
        val counts = counts(14)
        val mirror = MemoryCounterMirror()
        val service = service(FakeStore(), counts, mirror)
        service.start()
        assertEquals(EntitlementState.free, service.status.value.state)
        counts.counts = FreeTierCounts(15, 15, 15)
        service.refreshCount()
        assertEquals(EntitlementState.limitReached, service.status.value.state)
        assertEquals(15, mirror.read())
    }

    @Test fun buyingAtTheLimitUnlocks() = runTest(UnconfinedTestDispatcher()) {
        val service = service(FakeStore(), counts(15))
        service.start()
        service.purchase(Any())
        assertTrue(service.status.value.state == EntitlementState.unlocked && service.status.value.canIssueInvoice)
    }

    @Test fun cancellingGoesBackToTheLimit() = runTest(UnconfinedTestDispatcher()) {
        val service = service(FakeStore(outcome = PurchaseOutcome.cancelled), counts(15))
        service.start()
        service.purchase(Any())
        assertEquals(EntitlementState.limitReached, service.status.value.state)
    }

    @Test fun aPendingPaymentWaitsUntilItCompletes() = runTest(UnconfinedTestDispatcher()) {
        val store = FakeStore(outcome = PurchaseOutcome.pending)
        val service = service(store, counts(15))
        service.start()
        service.purchase(Any())
        assertEquals(EntitlementState.pending, service.status.value.state)
        assertFalse(service.status.value.canIssueInvoice)
        store.send(OwnershipChange.owned) // the UPI payment cleared
        assertEquals(EntitlementState.unlocked, service.status.value.state)
    }

    @Test fun aRefundRevokes() = runTest(UnconfinedTestDispatcher()) {
        val store = FakeStore(owned = true)
        val service = service(store, counts(20))
        service.start()
        assertEquals(EntitlementState.unlocked, service.status.value.state)
        store.send(OwnershipChange.revoked)
        assertEquals(EntitlementState.limitReached, service.status.value.state)
    }

    @Test fun refreshUnlocksWhatWasBoughtElsewhere() = runTest(UnconfinedTestDispatcher()) {
        val store = FakeStore(owned = false)
        val service = service(store, counts(15))
        service.start()
        store.owned = true // bought on another device
        service.restore()
        assertTrue(store.syncs == 1 && service.status.value.state == EntitlementState.unlocked)
    }

    @Test fun buyingWhileUnlockedDoesNothing() = runTest(UnconfinedTestDispatcher()) {
        val service = service(FakeStore(owned = true, outcome = PurchaseOutcome.failed), counts(3))
        service.start()
        service.purchase(Any())
        assertEquals(EntitlementState.unlocked, service.status.value.state)
    }

    @Test fun aResumeThatCannotReachTheStoreKeepsTheUnlock() = runTest(UnconfinedTestDispatcher()) {
        val store = FakeStore(owned = true)
        val service = service(store, counts(40))
        service.start()
        assertEquals(EntitlementState.unlocked, service.status.value.state)

        store.owned = null // Play disconnected, or SERVICE_UNAVAILABLE
        assertFalse(service.restore()) // "Refresh purchases" says Play couldn't be reached
        assertEquals(EntitlementState.unlocked, service.status.value.state)
        assertTrue(service.status.value.canIssueInvoice)

        store.owned = false // a real answer without the product: refunded
        assertTrue(service.restore())
        assertEquals(EntitlementState.limitReached, service.status.value.state)
    }

    @Test fun aLaunchThatCannotReachTheStoreStaysUnknown() = runTest(UnconfinedTestDispatcher()) {
        val store = FakeStore(owned = null)
        val under = service(store, counts(4))
        under.start()
        assertEquals(EntitlementState.unknown, under.status.value.state)
        assertTrue(under.status.value.canIssueInvoice) // below the limit, an unanswered store never blocks

        val over = service(store, counts(20))
        over.start()
        assertEquals(EntitlementState.unknown, over.status.value.state)
        store.owned = true // Play answers on the next resume
        over.restore()
        assertEquals(EntitlementState.unlocked, over.status.value.state)
    }
}
