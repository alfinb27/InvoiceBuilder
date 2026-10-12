package app.invoicebuilder.android

import android.content.Intent
import android.graphics.Bitmap
import androidx.compose.ui.test.ExperimentalTestApi
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.junit4.createEmptyComposeRule
import androidx.compose.ui.test.onNodeWithTag
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
import java.io.File

/**
 * Walks the main screens and saves a screenshot of each to the app's external files folder (`screenshots/`), to
 * review layouts (iOS: `ScreenshotTour`). `adb pull /sdcard/Android/data/<app id>/files/screenshots` collects them
 * when the tests were run with `am instrument` (Gradle's connected run uninstalls the app, files and all).
 */
@OptIn(ExperimentalTestApi::class)
@RunWith(AndroidJUnit4::class)
class ScreenshotTour {
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
        val node = compose.onNodeWithTag(tag)
        runCatching { node.performScrollTo() }
        node.performClick()
    }

    private fun snapshot(name: String) {
        compose.waitForIdle()
        Thread.sleep(600) // animations settle
        val bitmap = InstrumentationRegistry.getInstrumentation().uiAutomation.takeScreenshot() ?: return
        val folder = File(InstrumentationRegistry.getInstrumentation().targetContext.getExternalFilesDir(null), "screenshots")
        folder.mkdirs()
        File(folder, "$name.png").outputStream().use { bitmap.compress(Bitmap.CompressFormat.PNG, 90, it) }
    }

    @Test fun tourOfOnboarding() {
        launch(seed = null)
        compose.waitUntilExactlyOneExists(hasTestTag("onboarding.start"), 10_000)
        snapshot("10-welcome")
        tap("onboarding.start")
        snapshot("11-where-you-work")
        tap("country-IN")
        snapshot("12-where-you-work-india")
        tap("onboarding.continue")
        snapshot("13-your-business")
    }

    @Test fun tourOfTheBuilder() {
        launch()
        compose.waitUntilExactlyOneExists(hasTestTag("homeNewInvoice"), 10_000)
        snapshot("01-home-first-run")
        tap("homeNewInvoice")
        snapshot("20-builder-empty")
        tap("chooseClient")
        tap("pickClient-Umesh Foods")
        tap("addItem")
        compose.waitUntilExactlyOneExists(hasTestTag("catalogItem-Tea leaves"), 10_000)
        tap("catalogItem-Tea leaves")
        snapshot("21-add-item-saved")
        tap("addItemTab-new")
        compose.onNodeWithTag("lineDescription").performTextInput("Delivery")
        compose.onNodeWithTag("linePrice").performTextInput("250")
        snapshot("22-add-item-new")
        tap("lineDone")
        snapshot("23-builder")
        tap("moreOptions")
        snapshot("24-more-options")
        tap("reviewAndSend")
        compose.waitUntilExactlyOneExists(hasTestTag("review.send"), 10_000)
        Thread.sleep(2_500) // the page thumbnail renders in the background
        snapshot("25-review-and-send")
    }
}
