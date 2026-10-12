package app.invoicebuilder.android

import android.accessibilityservice.AccessibilityService
import android.content.Intent
import androidx.compose.ui.test.ExperimentalTestApi
import androidx.compose.ui.test.assert
import androidx.compose.ui.test.assertTextContains
import androidx.compose.ui.test.hasContentDescription
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
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.After
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * End-to-end smoke flows (iOS: `DocumentSmokeTests`): build an invoice from a client, a saved item and something new,
 * then review and send it. Runs on a seeded in-memory database (the `seed` extra ≈ `-seed IN`), so the real one is
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

    /** Closes whatever another app or the system put on top (the share sheet, a mail app, the print dialog). */
    private fun pressSystemBack() {
        InstrumentationRegistry.getInstrumentation().uiAutomation.performGlobalAction(AccessibilityService.GLOBAL_ACTION_BACK)
        Thread.sleep(1_000)
    }

    private fun startInvoiceWithClientAndItem() {
        tap("homeNewInvoice")
        tap("chooseClient")
        tap("pickClient-Rao Traders")
        tap("addItem") // a seeded business has saved items, so the sheet opens on them
        tap("catalogItem-Website development")
        tap("catalogDone")
    }

    /** Review & send, then Send on WhatsApp: the document is issued and the share opens over its preview. */
    private fun reviewAndSend() {
        tap("reviewAndSend")
        tap("review.send")
        Thread.sleep(4_000) // issued, the PDF rendered and the chooser (or WhatsApp) opened over the preview
        pressSystemBack()
        compose.waitForIdle()
        if (compose.onAllNodes(hasTestTag("markSent")).fetchSemanticsNodes().isNotEmpty()) tap("markSent")
        if (compose.onAllNodes(hasTestTag("previewDone")).fetchSemanticsNodes().isNotEmpty()) tap("previewDone")
    }

    @Test fun buildAndSendAnInvoice() {
        launch()
        startInvoiceWithClientAndItem()

        // Something new, on the sheet's second tab
        tap("addItem")
        tap("addItemTab-new")
        compose.waitUntilExactlyOneExists(hasTestTag("lineDescription"), 5_000)
        compose.onNodeWithTag("lineDescription").performTextInput("Hosting setup")
        compose.onNodeWithTag("linePrice").performTextInput("1000")
        // The rate carries over from the saved item (GST 18%); the line's total is the engine's.
        compose.waitUntilExactlyOneExists(hasTestTag("lineTotal"), 5_000)
        compose.onNodeWithTag("lineTotal").assert(hasContentDescription("₹1,180.00", substring = true))
        tap("lineDone")

        // Totals: (5000 + 1000) × 1.18 = ₹7,080.00, from the engine
        compose.waitUntilExactlyOneExists(hasTestTag("totals"), 5_000) // one merged node for TalkBack
        compose.onNodeWithTag("totals").assertTextContains("₹7,080.00", substring = true)

        // Review & send: the number it will get, then send it.
        tap("reviewAndSend")
        compose.waitUntilAtLeastOneExists(hasText("INV/26-27/0001", substring = true), 10_000)
        tap("review.keepDraft")
        reviewAndSend()
        compose.waitUntilAtLeastOneExists(hasText("INV/26-27/0001"), 10_000)
        compose.onNodeWithTag("issuedTotal").assertTextContains("₹7,080.00")
    }

    @Test fun sendShowsWhatIsMissing() {
        launch()
        tap("homeNewInvoice")
        tap("reviewAndSend")
        compose.waitUntilAtLeastOneExists(hasText("Add at least one item.", substring = true), 5_000)
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
        reviewAndSend()
        compose.waitUntilAtLeastOneExists(hasText("INV/26-27/0001"), 10_000)
    }

    /** The Welcome screen, then the three stages from an empty database: India, the business details, Finish. */
    @Test fun onboardAnIndianBusiness() {
        launch(seed = null)
        tap("onboarding.start")
        tap("country-IN")
        tap("registration.regular")
        tap("onboarding.continue")
        compose.waitUntilExactlyOneExists(hasTestTag("businessName"), 5_000)
        compose.onNodeWithTag("businessName").performTextInput("Test Traders")
        compose.onNodeWithTag("businessTaxId").performTextInput("29AAGCB7383J1Z4")
        compose.onNodeWithTag("businessAddress1").performScrollTo().performTextInput("1 Main Road")
        tap("onboarding.continue")
        tap("onboarding.finish")
        compose.waitUntilAtLeastOneExists(hasText("Test Traders"), 10_000)
        compose.onNodeWithTag("home.checklist").assertExists()
    }
}
