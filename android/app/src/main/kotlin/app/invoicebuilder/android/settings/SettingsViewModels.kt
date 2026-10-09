package app.invoicebuilder.android.settings

import android.content.ContentResolver
import android.net.Uri
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import app.invoicebuilder.android.app.Session
import app.invoicebuilder.android.common.ImageProcessing
import app.invoicebuilder.android.common.TaxIDFeedback
import app.invoicebuilder.core.designsystem.IssueMessages
import app.invoicebuilder.core.domain.decimal.Outcome
import app.invoicebuilder.core.domain.models.AssetKind
import app.invoicebuilder.core.domain.models.Business
import app.invoicebuilder.core.domain.models.ImagePayload
import app.invoicebuilder.core.domain.models.NumberingSeries
import app.invoicebuilder.core.domain.numbering.NumberingReset
import app.invoicebuilder.core.domain.setup.BusinessDraft
import app.invoicebuilder.core.domain.setup.BusinessField
import app.invoicebuilder.core.domain.setup.BusinessRules
import app.invoicebuilder.core.domain.setup.CustomRateDraft
import app.invoicebuilder.core.domain.setup.CustomRateField
import app.invoicebuilder.core.domain.setup.CustomRates
import app.invoicebuilder.core.domain.setup.FieldIssue
import app.invoicebuilder.core.domain.setup.NumberingSeriesDraft
import app.invoicebuilder.core.domain.setup.NumberingSeriesField
import app.invoicebuilder.core.domain.setup.NumberingSeriesRules
import app.invoicebuilder.core.domain.tax.TaxRate
import kotlinx.coroutines.launch

/** Settings → Business profile and Defaults (`spec/setup.md` §4). iOS: `BusinessProfileViewModel`. */
class BusinessProfileViewModel(private val session: Session) {
    var draft by mutableStateOf(BusinessDraft.of(session.business, session.businessRules))
        private set
    var attemptedSave by mutableStateOf(false)
        private set
    var isSaving by mutableStateOf(false)
        private set
    var didSave by mutableStateOf(false)
        private set
    var errorMessage by mutableStateOf<String?>(null)

    val rules: BusinessRules get() = session.businessRules
    val business: Business get() = session.business
    val issues: Map<BusinessField, FieldIssue> get() = rules.issues(draft)

    /** Every edit goes through the rules' derivations (≈ `didSet { applyDerivations }`). */
    fun update(new: BusinessDraft) { draft = rules.applyDerivations(new) }

    fun visibleIssue(field: BusinessField): FieldIssue? = if (attemptedSave) issues[field] else null

    val taxIDFeedback: TaxIDFeedback?
        get() {
            val validation = rules.taxIDValidation(draft) ?: return null
            if (validation.valid) return TaxIDFeedback.Valid(validation.region?.let { rules.config.region(it)?.name })
            if (!attemptedSave && validation.normalized.length < 15) return null
            val error = validation.error ?: return null
            val name = rules.config.labels.taxIdName
            return TaxIDFeedback.Invalid(IssueMessages.text(FieldIssue.InvalidTaxID(error), name, name))
        }

    val hasChanges: Boolean get() = rules.updating(business, draft) != business

    fun save() {
        attemptedSave = true
        didSave = false
        if (issues.isNotEmpty()) return
        session.scope.launch {
            isSaving = true
            try {
                session.container.businesses.save(rules.updating(business, draft))
                attemptedSave = false
                didSave = true
                session.reconcileReminders() // the default may have changed (`spec/reminders.md` §3)
            } catch (error: Exception) {
                errorMessage = "Your changes couldn't be saved."
            } finally {
                isSaving = false
            }
        }
    }

    fun discardChanges() {
        draft = BusinessDraft.of(business, rules)
        attemptedSave = false
        didSave = false
    }
}

/** Settings → Logo and signature: saved immediately (`spec/setup.md` §9). iOS: `BusinessImagesViewModel`. */
class BusinessImagesViewModel(private val session: Session) {
    var logo by mutableStateOf<ByteArray?>(null)
        private set
    var signature by mutableStateOf<ByteArray?>(null)
        private set
    var isBusy by mutableStateOf(false)
        private set
    var errorMessage by mutableStateOf<String?>(null)

    suspend fun load() {
        logo = session.business.logoAssetId?.let { session.container.assets.fetchAsset(it)?.data }
        signature = session.business.signatureAssetId?.let { session.container.assets.fetchAsset(it)?.data }
    }

    fun setLogo(uri: Uri, resolver: ContentResolver) = update(AssetKind.logo) { ImageProcessing.logo(uri, resolver) }
    fun setSignature(payload: ImagePayload?) = update(AssetKind.signature) { payload }
    fun removeLogo() = update(AssetKind.logo) { null }

    private fun update(kind: AssetKind, makePayload: suspend () -> ImagePayload?) {
        session.scope.launch {
            isBusy = true
            try {
                val payload = makePayload()
                session.container.setup.setImage(payload, kind, session.business.id)
                if (kind == AssetKind.logo) logo = payload?.data else signature = payload?.data
            } catch (error: Exception) {
                errorMessage = "The image couldn't be saved. Try a PNG or JPEG."
            } finally {
                isBusy = false
            }
        }
    }
}

/** Settings → Invoice numbering (`spec/setup.md` §6). iOS: `NumberingSettingsViewModel`. */
class NumberingSettingsViewModel(private val session: Session) {
    var editing by mutableStateOf<NumberingSeries?>(null)
        private set
    var draft by mutableStateOf<NumberingSeriesDraft?>(null)
    /** Period key → the highest sequence already issued from the series being edited. */
    private var highestIssued by mutableStateOf(emptyMap<String, Int>())
    var attemptedSave by mutableStateOf(false)
        private set
    var errorMessage by mutableStateOf<String?>(null)

    val rules: NumberingSeriesRules get() = session.numberingRules

    fun nextNumber(series: NumberingSeries): String = (rules.nextNumber(series) as? Outcome.Success)?.value?.number ?: "—"

    fun edit(series: NumberingSeries) {
        if (!rules.isEditable(series)) return
        editing = series
        draft = NumberingSeriesDraft.of(series, rules.periodKey(series.reset))
        highestIssued = emptyMap()
        attemptedSave = false
        session.scope.launch {
            val highest = mutableMapOf<String, Int>()
            for (reset in NumberingReset.known) {
                val key = rules.periodKey(reset)
                session.container.documents.highestIssuedSequence(series.id, key)?.let { highest[key] = it }
            }
            if (editing?.id == series.id) highestIssued = highest
        }
    }

    fun cancelEditing() {
        editing = null
        draft = null
    }

    val draftIssues: Map<NumberingSeriesField, FieldIssue>
        get() {
            val draft = draft ?: return emptyMap()
            return rules.issues(draft, highestIssued[rules.periodKey(draft.reset)])
        }

    /** Issues show as soon as the pattern changes, so the preview and its problem appear together. */
    fun visibleIssue(field: NumberingSeriesField): FieldIssue? {
        val issue = draftIssues[field] ?: return null
        return if (attemptedSave || field == NumberingSeriesField.Pattern) issue else null
    }

    val preview: String? get() = draft?.let { (rules.preview(it) as? Outcome.Success)?.value?.number }

    suspend fun saveEditing(): Boolean {
        attemptedSave = true
        val series = editing ?: return false
        val draft = draft ?: return false
        if (draftIssues.isNotEmpty()) return false
        return try {
            session.container.numberingSeries.save(rules.updating(series, draft))
            cancelEditing()
            true
        } catch (error: Exception) {
            errorMessage = "The numbering couldn't be saved."
            false
        }
    }
}

/** Settings → Tax rates, for GENERIC businesses (`spec/setup.md` §7). iOS: `TaxRatesViewModel`. */
class TaxRatesViewModel(private val session: Session) {
    /** The rate being edited (null id = a new rate). */
    var editingID by mutableStateOf<String?>(null)
        private set
    var draft by mutableStateOf<CustomRateDraft?>(null)
    var attemptedSave by mutableStateOf(false)
        private set
    var errorMessage by mutableStateOf<String?>(null)

    val rates: List<TaxRate> get() = session.business.customRates ?: emptyList()

    fun startNew() {
        editingID = null
        draft = CustomRateDraft(name = rates.firstOrNull()?.components?.firstOrNull()?.label ?: "Tax")
        attemptedSave = false
    }

    fun edit(rate: TaxRate) {
        editingID = rate.id
        draft = CustomRateDraft.of(rate)
        attemptedSave = false
    }

    fun cancelEditing() {
        draft = null
        editingID = null
    }

    val draftIssues: Map<CustomRateField, FieldIssue> get() = draft?.issues ?: emptyMap()
    fun visibleIssue(field: CustomRateField): FieldIssue? = if (attemptedSave) draftIssues[field] else null

    suspend fun saveEditing(): Boolean {
        attemptedSave = true
        val draft = draft ?: return false
        if (draftIssues.isNotEmpty()) return false
        val container = session.container
        val id = editingID ?: CustomRates.rateID(container.ids.make(), rates)
        val updated = rates.toMutableList()
        var rate = draft.makeRate(id, container.time.today())
        val index = updated.indexOfFirst { it.id == id }
        if (index >= 0) {
            rate = rate.copy(effectiveFrom = updated[index].effectiveFrom)
            updated[index] = rate
        } else {
            updated.add(maxOf(0, updated.size - if (updated.lastOrNull()?.id == CustomRates.noTax.id) 1 else 0), rate)
        }
        return store(updated)
    }

    /** A rate used by a live catalogue item cannot be removed. */
    fun remove(rate: TaxRate) {
        session.scope.launch {
            try {
                val users = session.container.catalog.countItems(session.business.id, rate.id)
                if (users > 0) {
                    errorMessage = "$users item${if (users == 1) " uses" else "s use"} this rate. Change ${if (users == 1) "it" else "them"} first."
                    return@launch
                }
                store(rates.filter { it.id != rate.id })
            } catch (error: Exception) {
                errorMessage = "The rate couldn't be removed."
            }
        }
    }

    private suspend fun store(rates: List<TaxRate>): Boolean = try {
        session.container.businesses.save(session.business.copy(customRates = rates))
        cancelEditing()
        true
    } catch (error: Exception) {
        errorMessage = "The rates couldn't be saved."
        false
    }
}

val NumberingReset.label: String
    get() = when (this) {
        NumberingReset.fiscalYear -> "Every financial year"
        NumberingReset.calendarYear -> "Every calendar year"
        NumberingReset.never -> "Never"
        else -> rawValue
    }
