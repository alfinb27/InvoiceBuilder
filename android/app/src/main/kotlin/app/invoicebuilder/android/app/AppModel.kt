package app.invoicebuilder.android.app

import android.app.Application
import android.net.Uri
import android.os.Build
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.viewModelScope
import app.invoicebuilder.android.InvoiceApplication
import app.invoicebuilder.android.backup.appVersion
import app.invoicebuilder.android.onboarding.OnboardingViewModel
import app.invoicebuilder.android.reminders.PostedReminders
import app.invoicebuilder.core.domain.models.Business
import app.invoicebuilder.core.domain.setup.BusinessSetup
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch

/**
 * The app's top-level state: loading, then onboarding (no business yet) or the main shell. iOS: `AppModel`.
 *
 * An `AndroidViewModel` survives configuration changes (rotation, folding, dark mode), so the session and its router
 * outlive the `Activity` that is recreated around them (≈ an `@State` model owned by the `App` struct).
 */
class AppModel(application: Application, private val savedState: SavedStateHandle) : AndroidViewModel(application) {
    sealed interface Phase {
        data object Loading : Phase
        data class Onboarding(val model: OnboardingViewModel) : Phase
        data class Ready(val session: Session) : Phase
        data class Failed(val message: String) : Phase
    }

    var phase by mutableStateOf<Phase>(Phase.Loading)
        private set

    private val app get() = getApplication<InvoiceApplication>()
    private var container: AppContainer? = null
    private var seed: SampleData.Country? = null
    private var sessionScope = newScope()

    private fun newScope() = kotlinx.coroutines.CoroutineScope(viewModelScope.coroutineContext + kotlinx.coroutines.SupervisorJob())

    /**
     * Picks the container for this launch: the on-disk database, or an in-memory one for UI tests
     * (`inMemory` / `seed IN` intent extras ≈ the iOS `-inMemory` / `-seed IN` launch arguments).
     */
    fun launch(inMemory: Boolean, seed: String?) {
        if (container != null) return
        this.seed = SampleData.Country.of(seed)
        container = runCatching {
            if (inMemory || this.seed != null) AppContainer.inMemory(app) else app.container
        }.getOrElse {
            phase = Phase.Failed(it.toString())
            return
        }
        start()
    }

    /** Loads this device and the active business (`spec/setup.md` §2). */
    fun start() {
        val container = container ?: return
        viewModelScope.launch {
            try {
                var device = container.deviceState.loadOrCreate(Build.MODEL)
                val seed = seed
                if (seed != null && container.businesses.fetchBusinesses().isEmpty()) {
                    SampleData.seed(seed, container, device.id)
                    device = container.deviceState.loadOrCreate(Build.MODEL)
                }
                // Never wait for the store at launch: offline, or with Play unreachable, the billing connection retries
                // for many seconds. Until it answers the state is `unknown`, which still lets anyone under the free
                // limit issue (`spec/billing.md`).
                container.scope.launch { container.entitlements.start() }
                val businesses = container.businesses.fetchBusinesses()
                val business = BusinessSetup.activeBusiness(device.preferences, businesses)
                phase = if (business != null) {
                    Phase.Ready(makeSession(container, business, device.id))
                } else {
                    val deviceID = device.id
                    Phase.Onboarding(OnboardingViewModel(
                        container, deviceID, sessionScope, appVersion(app),
                        onRestored = { reload() },
                        onTryDemo = { startDemo(it) },
                        onFinished = { finishOnboarding(container, it, deviceID) },
                    ))
                }
            } catch (error: Exception) {
                phase = Phase.Failed(error.toString())
            }
        }
    }

    /** Onboarding's "Try it with a sample business": a seeded business in an in-memory database. */
    suspend fun startDemo(country: SampleData.Country) {
        try {
            val demo = AppContainer.inMemory(app)
            val device = demo.deviceState.loadOrCreate(Build.MODEL)
            val business = SampleData.seed(country, demo, device.id)
            SampleData.addDemoDocuments(business, demo, device.id)
            demo.scope.launch { demo.entitlements.start() }
            val session = Session(demo, business, device.id, sessionScope, null)
            session.isDemo = true
            session.reloadApp = { reload() }
            session.start()
            phase = Phase.Ready(session)
        } catch (error: Exception) {
            phase = Phase.Failed(error.toString())
        }
    }

    /** A `.invoicebackup` opened from another app (`spec/backup.md` §6). */
    fun open(uri: Uri) {
        when (val phase = phase) {
            is Phase.Onboarding -> phase.model.backup.open(uri, app.contentResolver)
            is Phase.Ready -> {
                phase.session.router.selectedTab = AppTab.settings
                phase.session.router.settings.restore(uri)
            }
            else -> {}
        }
    }

    /** A reminder notification was tapped. */
    fun openDocument(id: String) {
        (phase as? Phase.Ready)?.session?.let { session ->
            viewModelScope.launch {
                val document = session.container.documents.fetchDocument(id) ?: return@launch
                session.openDocument(id, document.docType)
            }
        }
    }

    /** Starts again from the database, as at launch (after a restore, or leaving the demo). */
    suspend fun reload() {
        sessionScope.cancel()
        sessionScope = newScope()
        phase = Phase.Loading
        seed = null
        start()
    }

    private fun finishOnboarding(container: AppContainer, business: Business, deviceID: String) {
        phase = try {
            Phase.Ready(makeSession(container, business, deviceID))
        } catch (error: Exception) {
            Phase.Failed(error.toString())
        }
    }

    private fun makeSession(container: AppContainer, business: Business, deviceID: String): Session {
        val posted = if (container === app.containerIfCreated) PostedReminders(app) else null
        return Session(container, business, deviceID, sessionScope, posted).also {
            it.reloadApp = { reload() }
            it.start()
            RouterState.restore(it.router, savedState)
            RouterState.save(it.router, savedState, sessionScope)
        }
    }
}
