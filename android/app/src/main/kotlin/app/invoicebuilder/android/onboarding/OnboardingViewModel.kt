package app.invoicebuilder.android.onboarding

import android.content.ContentResolver
import android.net.Uri
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import app.invoicebuilder.android.app.AppContainer
import app.invoicebuilder.android.app.SampleData
import app.invoicebuilder.android.backup.BackupViewModel
import app.invoicebuilder.android.common.ImageProcessing
import app.invoicebuilder.android.common.TaxIDFeedback
import app.invoicebuilder.core.designsystem.IssueMessages
import app.invoicebuilder.core.domain.models.Business
import app.invoicebuilder.core.domain.models.ImagePayload
import app.invoicebuilder.core.domain.money.Currency
import app.invoicebuilder.core.domain.reference.Country
import app.invoicebuilder.core.domain.setup.BusinessDraft
import app.invoicebuilder.core.domain.setup.BusinessField
import app.invoicebuilder.core.domain.setup.BusinessRules
import app.invoicebuilder.core.domain.setup.BusinessSetup
import app.invoicebuilder.core.domain.setup.FieldIssue
import app.invoicebuilder.core.domain.setup.OnboardingStep
import app.invoicebuilder.core.domain.tax.TaxConfig
import app.invoicebuilder.core.domain.tax.TaxConfigStore
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.launch

/**
 * Onboarding (`spec/setup.md` §3): five steps over one `BusinessDraft`. Nothing is written until Finish, which creates
 * the business, its images, its series and the active-business preference in one transaction. iOS: `OnboardingViewModel`.
 */
class OnboardingViewModel(
    val container: AppContainer,
    val deviceID: String,
    private val scope: CoroutineScope,
    appVersion: String,
    onRestored: suspend () -> Unit,
    private val onTryDemo: suspend (SampleData.Country) -> Unit,
    private val onFinished: (Business) -> Unit,
) {
    var step by mutableStateOf(OnboardingStep.country)
        private set
    var draft by mutableStateOf(BusinessDraft())
        private set
    /** Steps where Continue was pressed: their missing-field problems are now shown. */
    var attempted by mutableStateOf(emptySet<OnboardingStep>())
        private set
    var countrySearch by mutableStateOf("")
    var logo by mutableStateOf<ImagePayload?>(null)
        private set
    var signature by mutableStateOf<ImagePayload?>(null)
    var isProcessingImage by mutableStateOf(false)
        private set
    var isFinishing by mutableStateOf(false)
        private set
    var errorMessage by mutableStateOf<String?>(null)

    /** "Restore from a backup" instead of setting up (`spec/backup.md` §4). */
    val backup = BackupViewModel(container, deviceID, scope, appVersion, onRestored)

    /** IN → `IN.json`, GB → `GB.json`, anything else → `GENERIC.json`. */
    val config: TaxConfig?
        get() = draft.countryCode?.let { container.taxConfigs.latest(TaxConfigStore.family(it), container.time.today()) }

    val rules: BusinessRules? get() = config?.let(::BusinessRules)

    /** Every edit goes through here, so the rules' derivations run (≈ `didSet { applyDerivations }`). */
    fun update(new: BusinessDraft) {
        var next = new
        if (next.countryCode != draft.countryCode) {
            // A new country means a new config: start its registration and currency afresh.
            val config = next.countryCode?.let { container.taxConfigs.latest(TaxConfigStore.family(it), container.time.today()) }
            next = next.copy(taxRegistration = config?.registrations?.firstOrNull()?.id, homeCurrency = config?.currency,
                regionCode = null, turnoverTier = 0)
        }
        val rules = next.countryCode?.let { container.taxConfigs.latest(TaxConfigStore.family(it), container.time.today()) }?.let(::BusinessRules)
        draft = rules?.applyDerivations(next) ?: next
    }

    // Steps

    val stepNumber get() = step.ordinal + 1
    val stepCount get() = OnboardingStep.entries.size
    val isLastStep get() = step == OnboardingStep.entries.last()

    fun title(step: OnboardingStep): String = if (step == OnboardingStep.bank && rules?.isIndia != true) "Bank details" else step.title

    fun issues(step: OnboardingStep): Map<BusinessField, FieldIssue> {
        val rules = rules ?: return if (step == OnboardingStep.country) mapOf(BusinessField.Country to FieldIssue.Required) else emptyMap()
        return rules.issues(draft, setOf(step))
    }

    /** The problem under a field: every problem once Continue was pressed on its step, none before. */
    fun visibleIssue(field: BusinessField): FieldIssue? {
        val step = field.step ?: return null
        if (step !in attempted) return null
        return issues(step)[field]
    }

    /** Live GSTIN / VAT number feedback while typing. */
    val taxIDFeedback: TaxIDFeedback?
        get() {
            val rules = rules ?: return null
            val validation = rules.taxIDValidation(draft) ?: return null
            if (validation.valid) return TaxIDFeedback.Valid(validation.region?.let { rules.config.region(it)?.name })
            if (OnboardingStep.business !in attempted && validation.normalized.length < 15) return null
            val error = validation.error ?: return null
            return TaxIDFeedback.Invalid(IssueMessages.text(FieldIssue.InvalidTaxID(error), "", rules.config.labels.taxIdName))
        }

    fun canVisit(step: OnboardingStep): Boolean = OnboardingStep.entries.filter { it < step }.all { issues(it).isEmpty() }

    fun go(to: OnboardingStep) { if (canVisit(to)) step = to }

    fun continueTapped() {
        attempted = attempted + step
        if (issues(step).isNotEmpty()) return
        OnboardingStep.entries.getOrNull(step.ordinal + 1)?.let { step = it }
    }

    fun back() { OnboardingStep.entries.getOrNull(step.ordinal - 1)?.let { step = it } }

    // Country step

    fun selectCountry(code: String) = update(draft.copy(countryCode = code))

    val suggestedCountries: List<Country> get() = listOf("IN", "GB").mapNotNull(container.reference::country)

    val countries: List<Country>
        get() {
            val query = countrySearch.trim()
            val all = container.reference.countriesByName
            if (query.isEmpty()) return all
            return all.filter { it.name.contains(query, ignoreCase = true) || it.code.equals(query, ignoreCase = true) }
        }

    val currencies: List<Currency> get() = container.reference.currencies.all.sortedBy { it.name.lowercase() }

    fun tryDemo(country: SampleData.Country) { scope.launch { onTryDemo(country) } }

    // Images

    fun setLogo(uri: Uri, resolver: ContentResolver) {
        scope.launch {
            isProcessingImage = true
            try {
                logo = ImageProcessing.logo(uri, resolver)
            } catch (error: Exception) {
                errorMessage = "That image couldn't be used. Try a PNG or JPEG."
            } finally {
                isProcessingImage = false
            }
        }
    }

    fun removeLogo() { logo = null }

    // Finish

    fun finish() {
        val rules = rules ?: return
        for (step in OnboardingStep.entries) {
            if (issues(step).isNotEmpty()) {
                attempted = attempted + step
                this.step = step
                return
            }
        }
        scope.launch {
            isFinishing = true
            errorMessage = null
            try {
                val now = container.time.now()
                val business = rules.makeBusiness(draft, container.ids.make(), now, container.time.today(), container.ids.make)
                val series = BusinessSetup.defaultSeries(business.id, rules.config, deviceID, now, container.ids.make)
                onFinished(container.setup.createBusiness(business, series, logo, signature, deviceID))
            } catch (error: Exception) {
                errorMessage = "Your business couldn't be saved. Please try again."
            } finally {
                isFinishing = false
            }
        }
    }
}

val OnboardingStep.title: String
    get() = when (this) {
        OnboardingStep.country -> "Country"
        OnboardingStep.registration -> "Tax registration"
        OnboardingStep.business -> "Your business"
        OnboardingStep.bank -> "Bank and UPI"
        OnboardingStep.images -> "Logo and signature"
    }
