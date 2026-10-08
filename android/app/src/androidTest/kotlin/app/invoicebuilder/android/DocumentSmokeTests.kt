package app.invoicebuilder.android

import android.content.Intent
import androidx.compose.ui.test.ExperimentalTestApi
import androidx.compose.ui.test.assertTextContains
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.createEmptyComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.compose.ui.test.performTextInput
import androidx.test.core.app.ActivityScenario
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.After
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * End-to-end smoke flows (iOS: `DocumentSmokeTests`): build an invoice from a client, a catalogue item and a one-off
 * line, then issue it. Runs on a seeded in-memory database (the `seed` extra ≈ `-seed IN`), so the real one is
 * never touched. Expected totals come from the spec fixtures' arithmetic, not from the app.
 */
@OptIn(ExperimentalTestApi::class)
@RunWith(AndroidJUnit4::class)
class DocumentSmokeTests {
    @get:Rule val compose = createEmptyComposeRule()
    private var scenario: ActivityScenario<MainActivity>? = null

    private fun launch(seed: String? = "IN") {
        val intent = Intent(ApplicationProvider.getApplicationContext(), MainActivity::class.java)
            .putExtra(MainActivity.EXTRA_IN_MEMORY, true)
        seed?.let { intent.putExtra(MainActivity.EXTRA_SEED, it) }
        scenario = ActivityScenario.launch(intent)
    }

    @After fun tearDown() { scenario?.close() }

    private fun tap(tag: String) {
        compose.waitUntilExactlyOneExists(hasTestTag(tag), 10_000)
        compose.onNodeWithTag(tag).performScrollToIfPossible().performClick()
    }

    private fun androidx.compose.ui.test.SemanticsNodeInteraction.performScrollToIfPossible() =
        runCatching { performScrollTo() }.getOrDefault(this)

    private fun startInvoiceWithClientAndItem() {
        tap("homeNewInvoice")
        tap("chooseClient")
        tap("pickClient-Rao Traders")
        tap("addFromItems")
        tap("catalogItem-Website development")
        tap("catalogDone")
    }

    @Test fun buildAndIssueAnInvoice() {
        launch()
        startInvoiceWithClientAndItem()

        // A one-off line
        tap("addLine")
        compose.waitUntilExactlyOneExists(hasTestTag("lineDescription"), 5_000)
        compose.onNodeWithTag("lineDescription").performTextInput("Hosting setup")
        compose.onNodeWithTag("linePrice").performTextInput("1000")
        tap("lineDone")

        // Totals: (5000 + 1000) × 1.18 = ₹7,080.00, from the engine
        compose.waitUntilExactlyOneExists(hasTestTag("totalAmount"), 5_000)
        compose.onNodeWithTag("totalAmount").performScrollTo().assertTextContains("₹7,080.00")

        // Issue
        tap("issueButton")
        tap("confirmIssue")
        compose.waitUntilAtLeastOneExists(hasText("INV/26-27/0001"), 10_000)
        compose.onNodeWithTag("issuedTotal").assertTextContains("₹7,080.00")
    }

    @Test fun issueShowsWhatIsMissing() {
        launch()
        tap("homeNewInvoice")
        tap("issueButton")
        compose.waitUntilAtLeastOneExists(hasText("Add at least one line.", substring = true), 5_000)
    }

    /** The PDF preview of a draft, the template switcher and the share button (`spec/pdf/RENDERING.md`). */
    @Test fun previewAnInvoiceAndSwitchTemplate() {
        launch()
        startInvoiceWithClientAndItem()
        tap("previewButton")
        compose.waitUntilExactlyOneExists(hasTestTag("sharePDF"), 20_000)
        tap("template-classic")
        compose.waitUntilExactlyOneExists(hasTestTag("sharePDF"), 20_000)
        tap("previewDone")
        tap("issueButton")
        tap("confirmIssue")
        compose.waitUntilAtLeastOneExists(hasText("INV/26-27/0001"), 10_000)
    }

    /** Onboarding from an empty database: India, regular GST, the business details, then Finish. */
    @Test fun onboardAnIndianBusiness() {
        launch(seed = null)
        tap("suggested-IN")
        tap("onboarding.continue")
        tap("registration-regular")
        tap("onboarding.continue")
        compose.waitUntilExactlyOneExists(hasTestTag("businessName"), 5_000)
        compose.onNodeWithTag("businessName").performTextInput("Test Traders")
        compose.onNodeWithTag("businessTaxId").performTextInput("29AAGCB7383J1Z4")
        compose.onNodeWithTag("businessAddress1").performScrollTo().performTextInput("1 Main Road")
        tap("onboarding.continue")
        tap("onboarding.continue")
        tap("onboarding.finish")
        compose.waitUntilAtLeastOneExists(hasText("Test Traders"), 10_000)
        compose.onNodeWithText("Get ready to invoice").assertExists()
    }
}
