package app.invoicebuilder.android

import android.app.Application
import app.invoicebuilder.android.app.AppContainer

/**
 * The process-wide object (≈ the `@main App` struct): owns the live `AppContainer`, built on first use so a UI-test
 * launch that asks for an in-memory database never opens the real one. WorkManager's reminder job reaches it too.
 */
class InvoiceApplication : Application() {
    @Volatile private var live: AppContainer? = null

    val container: AppContainer
        get() = live ?: synchronized(this) { live ?: AppContainer.live(this).also { live = it } }

    /** The live container if something already built it (the in-memory test launches never do). */
    val containerIfCreated: AppContainer? get() = live
}
