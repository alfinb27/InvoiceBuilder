package app.invoicebuilder.android.app

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import app.invoicebuilder.android.documents.PDFLibrary
import app.invoicebuilder.android.reminders.PostedReminders
import app.invoicebuilder.android.reminders.ReminderReconciler
import app.invoicebuilder.core.domain.billing.EntitlementState
import app.invoicebuilder.core.domain.billing.EntitlementStatus
import app.invoicebuilder.core.domain.documents.DocumentRules
import app.invoicebuilder.core.domain.models.Business
import app.invoicebuilder.core.domain.models.DocumentType
import app.invoicebuilder.core.domain.money.CurrencyCode
import app.invoicebuilder.core.domain.money.SpecFormatter
import app.invoicebuilder.core.domain.setup.BusinessRules
import app.invoicebuilder.core.domain.setup.CatalogItemRules
import app.invoicebuilder.core.domain.setup.ClientRules
import app.invoicebuilder.core.domain.setup.NumberingSeriesRules
import app.invoicebuilder.core.domain.support.SpecLoadingError
import app.invoicebuilder.core.domain.tax.TaxConfig
import app.invoicebuilder.core.domain.tax.TaxRate
import app.invoicebuilder.core.domain.tax.TaxRegistration
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.launch
import java.time.LocalDate

/**
 * The signed-in state: the active business, its tax config and the router (iOS: `Session`). Shared by every screen
 * through `LocalSession` (≈ `.environment(session)`).
 */
class Session(
    val container: AppContainer,
    business: Business,
    val deviceID: String,
    /** Where observation runs: the activity `ViewModel`'s scope, so it ends with the app model (≈ `.task`). */
    val scope: CoroutineScope,
    private val postedReminders: PostedReminders? = null,
) {
    var business by mutableStateOf(business)
        private set
    val config: TaxConfig
    val router = AppRouter()
    val formatter = SpecFormatter(container.reference.currencies)
    val pdfLibrary = PDFLibrary(container.taxConfigs, container.reference, container.assets, container.cacheDirectory)
    var entitlement by mutableStateOf(EntitlementStatus(EntitlementState.unknown, 0))
        internal set
    /** The sample business in an in-memory database; nothing is saved. */
    var isDemo by mutableStateOf(false)
        internal set
    /** Rebuilds the app from the database (set by `AppModel`); a restore calls it. */
    var reloadApp: suspend () -> Unit = {}
    /** Asks for the notification permission (set by `MainActivity`, which owns the permission launcher). */
    var requestNotificationPermission: () -> Unit = {}

    init {
        val today = container.time.today()
        config = container.taxConfigs.latest(business.taxConfig, today) ?: container.taxConfigs.latest("GENERIC", today)
            ?: throw SpecLoadingError("tax/${business.taxConfig}.json", "no config for this business")
    }

    /** Starts the long-running observations (iOS: the shell's `.task`s). */
    fun start() {
        scope.launch {
            container.businesses.observeBusiness(business.id).collect { latest -> if (latest != null) business = latest }
        }
        scope.launch { container.entitlements.status.collect { entitlement = it } }
        reconcileReminders()
    }

    /** Re-plans this business's reminders (`spec/reminders.md` §3). */
    fun reconcileReminders() {
        val posted = postedReminders ?: return
        ReminderReconciler(container, posted).reconcile()
    }

    /** The first time an invoice is issued, ask for notifications (Android 13+), so reminders can fire. */
    fun askForRemindersIfNeeded() {
        if (container.notifications.canRequestAuthorization()) requestNotificationPermission() else reconcileReminders()
    }

    // Screen models that must outlive the activity (an open editor's draft survives rotation and folding, as the
    // router does). Created on first use, released when the screen closes for good.

    private val retained = mutableMapOf<String, Any>()

    @Suppress("UNCHECKED_CAST")
    fun <T : Any> retained(key: String, make: () -> T): T = retained.getOrPut(key, make) as T

    fun release(key: String) { retained.remove(key) }

    // Rules for the active business

    val today: LocalDate get() = container.time.today()
    val businessRules get() = BusinessRules(config)
    val clientRules get() = ClientRules(config, business.countryCode)
    val catalogRules get() = CatalogItemRules(config, business, container.reference.currencies, container.reference.units, today)
    val numberingRules get() = NumberingSeriesRules(config, today, deviceID)
    val documentRules get() = DocumentRules(container.taxConfigs, business, container.reference.currencies, config)

    // Navigation

    fun startNewDocument(docType: DocumentType) {
        router.selectedTab = AppTab.documents
        router.documents.docType = docType
        router.documents.selection = DocumentRoute.New(docType, container.ids.make())
    }

    fun openDocument(id: String, docType: DocumentType) {
        router.selectedTab = AppTab.documents
        router.documents.docType = docType
        router.documents.open(id)
    }

    val registration: TaxRegistration? get() = config.registration(business.taxRegistration)
    val chargesTax: Boolean get() = registration?.chargesTax ?: false

    // Display helpers

    /** An amount: the symbol for the home currency, the ISO code for any other (`ENGINE.md` §7.1). */
    fun money(minor: Long, currency: CurrencyCode? = null): String =
        formatter.money(minor, currency ?: business.homeCurrency, business.homeCurrency)

    fun countryName(code: String): String = container.reference.country(code)?.name ?: code
    fun regionName(code: String?): String? = code?.let { config.region(it)?.name ?: it }
    fun rate(id: String): TaxRate? = config.rate(id, business.customRates)
    fun unitLabel(id: String): String = container.reference.unit(id)?.label ?: id

    companion object {
        fun make(container: AppContainer, business: Business, deviceID: String, scope: CoroutineScope, posted: PostedReminders?) =
            Session(container, business, deviceID, scope, posted)
    }
}
