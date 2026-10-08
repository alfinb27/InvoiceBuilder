package app.invoicebuilder.android

import android.Manifest
import android.content.Intent
import android.os.Build
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.result.contract.ActivityResultContracts
import androidx.activity.viewModels
import app.invoicebuilder.android.app.AppModel
import app.invoicebuilder.android.app.AppRoot
import app.invoicebuilder.core.designsystem.InvoiceTheme
import kotlinx.coroutines.launch

/**
 * The single activity (≈ the single-window scene). Compose draws everything inside it; the `AppModel` view model
 * keeps the app's state across the activity being recreated.
 */
class MainActivity : ComponentActivity() {
    private val model: AppModel by viewModels()

    /** Android 13+: the notification permission, asked the first time reminders matter (≈ `requestAuthorization`). */
    private val notificationPermission = registerForActivityResult(ActivityResultContracts.RequestPermission()) {
        (model.phase as? AppModel.Phase.Ready)?.session?.reconcileReminders()
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        enableEdgeToEdge()
        super.onCreate(savedInstanceState)
        model.launch(inMemory = intent.getBooleanExtra(EXTRA_IN_MEMORY, false), seed = intent.getStringExtra(EXTRA_SEED))
        if (savedInstanceState == null) handle(intent)
        setContent {
            InvoiceTheme {
                AppRoot(model, requestNotificationPermission = {
                    if (Build.VERSION.SDK_INT >= 33) notificationPermission.launch(Manifest.permission.POST_NOTIFICATIONS)
                })
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handle(intent)
    }

    override fun onResume() {
        super.onResume()
        // Play Billing: refresh on every resume, so a refund or a pending payment that cleared is noticed (`billing.md`).
        (model.phase as? AppModel.Phase.Ready)?.session?.let { session ->
            session.scope.launch { session.container.entitlements.restore() }
        }
    }

    /** A backup opened from another app, or a tapped reminder. */
    private fun handle(intent: Intent) {
        intent.getStringExtra(EXTRA_DOCUMENT_ID)?.let { model.openDocument(it) }
        if (intent.action == Intent.ACTION_VIEW) intent.data?.let { model.open(it) }
    }

    companion object {
        const val EXTRA_DOCUMENT_ID = "documentID"
        /** UI tests: an empty in-memory database (≈ `-inMemory`). */
        const val EXTRA_IN_MEMORY = "inMemory"
        /** UI tests: a seeded sample business, `IN` or `GB` (≈ `-seed IN`). */
        const val EXTRA_SEED = "seed"
    }
}
