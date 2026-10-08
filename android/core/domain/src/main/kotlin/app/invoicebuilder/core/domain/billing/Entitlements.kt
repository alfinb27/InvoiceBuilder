package app.invoicebuilder.core.domain.billing

/** The free tier and the unlock (`spec/billing.md`). iOS: `FreeTier`. */
object FreeTier {
    const val LIMIT = 15

    /** "Effective count" (`billing.md`, Free tier): the highest of every place the count is kept. */
    fun effectiveCount(local: Int, deviceMirror: Int, keystoreMirror: Int, issuedInDatabase: Int): Int =
        maxOf(local, deviceMirror, keystoreMirror, issuedInDatabase)

    fun remaining(count: Int): Int = maxOf(LIMIT - count, 0)
}

enum class EntitlementState { unknown, free, limitReached, purchasing, pending, unlocked;

    companion object { fun of(rawValue: String): EntitlementState? = entries.firstOrNull { it.name == rawValue } }
}

enum class EntitlementEvent {
    resolvedOwned, resolvedNotOwned, counted, purchaseStarted, purchasePending, purchased, purchaseCancelled,
    purchaseFailed, revoked;

    companion object { fun of(rawValue: String): EntitlementEvent? = entries.firstOrNull { it.name == rawValue } }
}

/** `billing.md`, Transitions. iOS: `EntitlementMachine`. */
object EntitlementMachine {
    fun next(state: EntitlementState, event: EntitlementEvent, count: Int): EntitlementState {
        val byCount = if (count >= FreeTier.LIMIT) EntitlementState.limitReached else EntitlementState.free
        return when {
            event == EntitlementEvent.resolvedOwned || event == EntitlementEvent.purchased -> EntitlementState.unlocked
            event == EntitlementEvent.resolvedNotOwned && state in setOf(
                EntitlementState.unknown, EntitlementState.unlocked, EntitlementState.free, EntitlementState.limitReached,
            ) -> byCount
            event == EntitlementEvent.counted && state in setOf(EntitlementState.free, EntitlementState.limitReached) -> byCount
            event == EntitlementEvent.purchaseStarted && state in setOf(EntitlementState.free, EntitlementState.limitReached) ->
                EntitlementState.purchasing
            event == EntitlementEvent.purchasePending && state == EntitlementState.purchasing -> EntitlementState.pending
            (event == EntitlementEvent.purchaseCancelled || event == EntitlementEvent.purchaseFailed) &&
                state in setOf(EntitlementState.purchasing, EntitlementState.pending) -> byCount
            event == EntitlementEvent.revoked && state == EntitlementState.unlocked -> byCount
            else -> state
        }
    }

    /** Issuing an invoice is allowed when unlocked or below the limit, in every state. */
    fun canIssueInvoice(state: EntitlementState, count: Int): Boolean = state == EntitlementState.unlocked || count < FreeTier.LIMIT
}

/** What the app shows about the unlock: the state, the effective count and the store's price. */
data class EntitlementStatus(val state: EntitlementState, val count: Int, val displayPrice: String? = null) {
    val canIssueInvoice: Boolean get() = EntitlementMachine.canIssueInvoice(state, count)
    val remaining: Int get() = FreeTier.remaining(count)
    val isUnlocked: Boolean get() = state == EntitlementState.unlocked
}
