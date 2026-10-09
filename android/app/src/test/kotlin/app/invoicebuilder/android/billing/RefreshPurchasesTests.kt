package app.invoicebuilder.android.billing

import android.app.Application
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.hasTestTag
import androidx.test.core.app.ApplicationProvider
import app.invoicebuilder.android.app.AppContainer
import app.invoicebuilder.android.app.SampleData
import app.invoicebuilder.android.app.Session
import app.invoicebuilder.core.billing.OwnershipChange
import app.invoicebuilder.core.billing.PurchaseOutcome
import app.invoicebuilder.core.billing.StoreClient
import app.invoicebuilder.core.data.AppDatabase
import app.invoicebuilder.core.designsystem.InvoiceTheme
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.emptyFlow
import kotlinx.coroutines.runBlocking
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode
import java.util.concurrent.atomic.AtomicInteger

/** A store that answers [owned], or can't be asked at all when it is null (Play not connected). */
private class TestStore(private val owned: Boolean?) : StoreClient {
    val asked = AtomicInteger(0)
    override suspend fun displayPrice(productID: String): String? = null
    override suspend fun owns(productID: String): Boolean? = owned.also { asked.incrementAndGet() }
    override suspend fun purchase(productID: String, activity: Any) = PurchaseOutcome.failed
    override fun updates(productID: String): Flow<OwnershipChange> = emptyFlow()
    override suspend fun sync() {}
}

/** "Refresh purchases" says when Google Play couldn't be reached (`spec/billing.md`, Android). */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class RefreshPurchasesTests {
    @get:Rule val compose = createComposeRule()
    private val context: Application = ApplicationProvider.getApplicationContext()

    private fun session(store: StoreClient): Session = runBlocking {
        val container = AppContainer.make(context, AppDatabase.inMemory(context), store = store)
        val deviceID = container.deviceState.loadOrCreate("test").id
        val business = SampleData.seed(SampleData.Country.india, container, deviceID)
        Session(container, business, deviceID, CoroutineScope(SupervisorJob() + Dispatchers.Unconfined))
    }

    private fun waitForText(text: String) =
        compose.waitUntil(5_000) { compose.onAllNodes(hasText(text)).fetchSemanticsNodes().isNotEmpty() }

    @Test
    fun settingsSaysWhenPlayCannotBeReached() {
        val session = session(TestStore(owned = null))
        compose.setContent { InvoiceTheme { UnlockPage(session) } }
        compose.onNodeWithTag("unlock.refresh").performClick()
        waitForText(BillingText.refreshFailed)
        compose.onNodeWithText("Purchases not refreshed").assertExists()
    }

    @Test
    fun settingsSaysNothingWhenPlayAnswers() {
        val store = TestStore(owned = false)
        val session = session(store)
        compose.setContent { InvoiceTheme { UnlockPage(session) } }
        compose.onNodeWithTag("unlock.refresh").performClick()
        compose.waitUntil(5_000) { store.asked.get() > 0 }
        compose.waitForIdle()
        compose.onNodeWithText(BillingText.refreshFailed).assertDoesNotExist()
    }

    @Test
    fun thePaywallSaysWhenPlayCannotBeReached() {
        val session = session(TestStore(owned = null))
        compose.setContent { InvoiceTheme { PaywallDialog(session) {} } }
        compose.onNodeWithTag("paywall.restore").performScrollTo().performClick() // below the fold on a small screen
        compose.waitUntil(5_000) { compose.onAllNodes(hasTestTag("paywall.refreshFailed")).fetchSemanticsNodes().isNotEmpty() }
        compose.onNodeWithText(BillingText.refreshFailed).assertExists()
    }
}
