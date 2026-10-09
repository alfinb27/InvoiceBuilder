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
import app.invoicebuilder.core.domain.setup.OnboardingStage
import app.invoicebuilder.core.domain.setup.OnboardingStep
import app.invoicebuilder.core.domain.tax.TaxConfig
import app.invoicebuilder.core.domain.tax.TaxConfigStore
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.launch

/**
 * Onboarding (`spec/setup.md` §3): a Welcome screen, then five steps over one `BusinessDraft` shown as three stages.
 * Nothing is written until Finish, which creates the business, its images, its series and the active-business
 * preference in one transaction. iOS: `OnboardingViewModel`.
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
    var showsWelcome by mutableStateOf(true)
        private set
    var stage by mutableStateOf(OnboardingStage.whereYouWork)
    var draft by mutableStateOf(BusinessDraft())
        private set
    /** Steps whose stage had Continue (or Finish) pressed: their missing-field problems are now shown. */
    var attempted by mutableStateOf(emptySet<OnboardingStep>())
        private set
    /** "Somewhere else" was chosen: the country search and home currency show. */
    var picksOtherCountry by mutableStateOf(false)
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

    // Stages

    val stageNumber get() = stage.ordinal + 1
    val stageCount get() = OnboardingStage.entries.size
    val isLastStage get() = stage == OnboardingStage.entries.last()

    fun title(stage: OnboardingStage): String = when (stage) {
        OnboardingStage.whereYouWork -> "Where you work"
        OnboardingStage.yourBusiness -> "Your business"
        OnboardingStage.gettingPaid -> "Getting paid"
    }

    fun issues(step: OnboardingStep): Map<BusinessField, FieldIssue> {
        val rules = rules ?: return if (step == OnboardingStep.country) mapOf(BusinessField.Country to FieldIssue.Required) else emptyMap()
        return rules.issues(draft, setOf(step))
    }

    fun issues(stage: OnboardingStage): Map<BusinessField, FieldIssue> =
        stage.steps.fold(emptyMap()) { all, step -> issues(step) + all }

    /** The problem under a field: every problem once Continue was pressed on its stage, none before. */
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

    /** A stage can be opened from the side list once every stage before it is complete. */
    fun canVisit(stage: OnboardingStage): Boolean = OnboardingStage.entries.filter { it < stage }.all { issues(it).isEmpty() }

    fun go(to: OnboardingStage) { if (canVisit(to)) stage = to }

    /** "Let's get started" on the Welcome screen. */
    fun start() { showsWelcome = false }

    fun continueTapped() {
        attempted = attempted + stage.steps
        if (issues(stage).isNotEmpty()) return
        OnboardingStage.entries.getOrNull(stage.ordinal + 1)?.let { stage = it }
    }

    /** Back: the previous stage; from the first one, the Welcome screen. Answers are kept. */
    fun back() {
        val previous = OnboardingStage.entries.getOrNull(stage.ordinal - 1)
        if (previous != null) stage = previous else showsWelcome = true
    }

    // Country step

    fun selectCountry(code: String) {
        update(draft.copy(countryCode = code))
        picksOtherCountry = code !in listOf("IN", "GB")
    }

    /** "Somewhere else": clears India or the UK and shows the country search. */
    fun pickOtherCountry() {
        picksOtherCountry = true
        if (draft.countryCode in listOf("IN", "GB")) update(draft.copy(countryCode = null))
    }

    /** The country card that is selected: "IN", "GB", "other" or none. */
    val countryCard: String?
        get() {
            val code = draft.countryCode
            if (code == "IN" || code == "GB") return code
            return if (picksOtherCountry || code != null) "other" else null
        }

    val countryName: String? get() = draft.countryCode?.let { container.reference.country(it)?.name }

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

    /** "Skip for now": finish without anything typed on the Getting paid stage. */
    fun skipAndFinish() {
        draft = draft.clearGettingPaid()
        logo = null
        signature = null
        finish()
    }

    fun finish() {
        val rules = rules ?: return
        for (stage in OnboardingStage.entries) {
            if (issues(stage).isNotEmpty()) {
                attempted = attempted + stage.steps
                this.stage = stage
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
