package app.invoicebuilder.android

import android.content.Intent
import android.graphics.Bitmap
import android.os.Build
import android.os.ParcelFileDescriptor
import android.util.Log
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.semantics.getOrNull
import androidx.compose.ui.test.ExperimentalTestApi
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.SemanticsNodeInteraction
import androidx.compose.ui.test.hasContentDescription
import androidx.compose.ui.test.hasScrollToNodeAction
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.isRoot
import androidx.compose.ui.test.junit4.AndroidComposeTestRule
import androidx.compose.ui.test.junit4.accessibility.disableAccessibilityChecks
import androidx.compose.ui.test.junit4.accessibility.enableAccessibilityChecks
import androidx.compose.ui.test.junit4.createEmptyComposeRule
import androidx.compose.ui.test.onFirst
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.compose.ui.test.performScrollToNode
import androidx.compose.ui.test.performTextInput
import androidx.compose.ui.test.tryPerformAccessibilityChecks
import androidx.compose.ui.text.TextLayoutResult
import androidx.test.core.app.ActivityScenario
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.google.android.apps.common.testing.accessibility.framework.integrations.espresso.AccessibilityValidator
import org.junit.After
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File

/**
 * The Accessibility Test Framework's checks (missing labels, contrast, touch targets, …) on the main screens of a seeded
 * business, the builder and onboarding (iOS: `AccessibilityAuditTests`), at the default text size and at the largest one
 * Settings offers (200% from Android 14). Text cut off without an ellipsis or broken inside a word fails too; text
 * shortened with an ellipsis is logged (`adb logcat -s AccessibilityChecks`) for the manual TalkBack and font-size pass
 * (`docs/product/play-release.md` §5). Every screen is checked before a test fails, and each problem names the screen,
 * the element and the issue.
 */
@OptIn(ExperimentalTestApi::class)
@RunWith(AndroidJUnit4::class)
class AccessibilityChecksTests {
    @get:Rule val compose = createEmptyComposeRule()
    private var scenario: ActivityScenario<MainActivity>? = null
    /** In order, without the same problem twice (a sheet and its activity are checked from the same root). */
    private val problems = linkedSetOf<String>()
    /** Contrast is measured on a screenshot of the screen, as on iOS. */
    private val validator = AccessibilityValidator().setRunChecksFromRootView(true).setCaptureScreenshots(true)

    @After fun tearDown() {
        scenario?.close()
        setFontScale(1f)
    }

    @Test fun mainScreensPassTheChecks() = mainScreens(fontScale = 1f)
    @Test fun mainScreensPassTheChecksAtTheLargestTextSize() = mainScreens(largestFontScale)
    @Test fun builderPassesTheChecks() = builder(fontScale = 1f)
    @Test fun builderPassesTheChecksAtTheLargestTextSize() = builder(largestFontScale)
    @Test fun onboardingPassesTheChecks() = onboarding(fontScale = 1f)
    @Test fun onboardingPassesTheChecksAtTheLargestTextSize() = onboarding(largestFontScale)

    private fun mainScreens(fontScale: Float) {
        launch("IN", fontScale, fakeDrive = true) // the Backup page shows its Google Drive section
        compose.waitUntilExactlyOneExists(hasTestTag("homeNewInvoice"), 10_000)
        check("home")
        tap("tab-documents")
        check("invoices")
        tap("tab-clients")
        check("clients")
        tap("tab-items")
        check("items")
        tap("tab-settings")
        check("settings")
        tap("settings-backup")
        check("backup")
        tap("backup.drive")
        compose.waitUntilExactlyOneExists(hasTestTag("backup.drive.connect"), 5_000)
        check("backup-drive")
        tap("backup.drive.connect")
        compose.waitUntilExactlyOneExists(hasTestTag("backup.drive.backUpNow"), 10_000)
        check("backup-drive-connected")
        tap("editorCancel")
        compose.waitUntilExactlyOneExists(hasTestTag("backup.drive"), 5_000)
        goBack()
        tap("settings-sync")
        compose.waitUntilExactlyOneExists(hasTestTag("sync.drive"), 5_000)
        check("sync")
        tap("sync.drive")
        tap("sync.drive.confirm")
        compose.waitUntilExactlyOneExists(hasTestTag("sync.drive.now"), 10_000)
        check("sync-drive-on")
        assertNoProblems()
    }

    private fun builder(fontScale: Float) {
        launch("IN", fontScale)
        tap("homeNewInvoice")
        compose.waitUntilExactlyOneExists(hasTestTag("chooseClient"), 5_000)
        check("builder")
        tap("chooseClient")
        tap("pickClient-Rao Traders")
        tap("addItem") // a seeded business has saved items, so the sheet opens on them
        compose.waitUntilExactlyOneExists(hasTestTag("addItemTab-new"), 5_000)
        check("add-item-saved")
        tap("catalogItem-Website development")
        tap("catalogDone")
        // Something new, which takes its rate from the saved item's line.
        tap("addItem")
        tap("addItemTab-new")
        compose.waitUntilExactlyOneExists(hasTestTag("lineDescription"), 5_000)
        check("add-item-new")
        compose.onNodeWithTag("lineDescription").performTextInput("Hosting setup")
        compose.onNodeWithTag("linePrice").performTextInput("1000")
        tap("lineDone")
        check("builder-with-items")
        tap("reviewAndSend")
        compose.waitUntilExactlyOneExists(hasTestTag("review.send"), 10_000)
        Thread.sleep(2_500) // the page thumbnail renders in the background
        check("review-and-send")
        assertNoProblems()
    }

    private fun onboarding(fontScale: Float) {
        launch(seed = null, fontScale)
        compose.waitUntilExactlyOneExists(hasTestTag("onboarding.start"), 10_000)
        check("welcome")
        tap("onboarding.start")
        tap("country-IN")
        check("where-you-work")
        assertNoProblems()
    }

    private fun launch(seed: String?, fontScale: Float, fakeDrive: Boolean = false) {
        setFontScale(fontScale)
        val intent = Intent(ApplicationProvider.getApplicationContext(), MainActivity::class.java)
            .putExtra(MainActivity.EXTRA_IN_MEMORY, true).putExtra(MainActivity.EXTRA_FAKE_DRIVE, fakeDrive)
        seed?.let { intent.putExtra(MainActivity.EXTRA_SEED, it) }
        scenario = ActivityScenario.launch(intent)
    }

    /** The system setting, as Settings → Display → Font size changes it. */
    private fun setFontScale(scale: Float) {
        val output = InstrumentationRegistry.getInstrumentation().uiAutomation.executeShellCommand("settings put system font_scale $scale")
        ParcelFileDescriptor.AutoCloseInputStream(output).use { it.readBytes() }
        Thread.sleep(1_000) // the new configuration reaches the activity launched next
    }

    private fun tap(tag: String) {
        // A row of a lazy list that is off screen isn't composed yet: scroll the list to it first.
        if (compose.onAllNodes(hasTestTag(tag)).fetchSemanticsNodes().isEmpty()) {
            runCatching { compose.onAllNodes(hasScrollToNodeAction()).onFirst().performScrollToNode(hasTestTag(tag)) }
        }
        try {
            compose.waitUntilExactlyOneExists(hasTestTag(tag), 10_000)
        } catch (error: Throwable) {
            screenshot("missing-$tag")
            throw error
        }
        compose.onNodeWithTag(tag).performScrollToIfPossible().performClick()
    }

    /** Saved to the app's external files (`adb pull /sdcard/Android/data/<app id>/files/a11y`) to see what was on screen. */
    private fun screenshot(name: String) {
        val bitmap = InstrumentationRegistry.getInstrumentation().uiAutomation.takeScreenshot() ?: return
        val folder = File(InstrumentationRegistry.getInstrumentation().targetContext.getExternalFilesDir(null), "a11y").apply { mkdirs() }
        File(folder, "$name.png").outputStream().use { bitmap.compress(Bitmap.CompressFormat.PNG, 90, it) }
    }

    private fun SemanticsNodeInteraction.performScrollToIfPossible() = runCatching { performScrollTo() }.getOrDefault(this)

    /** The page's back arrow, once the screen has settled. */
    private fun goBack() {
        compose.waitForIdle()
        compose.onAllNodes(hasContentDescription("Back")).onFirst().performClick()
        compose.waitForIdle()
    }

    /** Runs the checks on every window of the screen (a sheet or a dialog is a window of its own) once it has settled. */
    private fun check(screen: String) {
        compose.waitForIdle()
        Thread.sleep(600) // a fading view measures as low contrast
        val rule = compose as AndroidComposeTestRule<*, *>
        rule.enableAccessibilityChecks(validator)
        try {
            val roots = compose.onAllNodes(isRoot())
            repeat(roots.fetchSemanticsNodes().size) { index ->
                runCatching { roots[index].tryPerformAccessibilityChecks() }.onFailure { problems += "$screen: ${it.message}" }
            }
        } finally {
            rule.disableAccessibilityChecks()
        }
        textProblems(screen)
    }

    /**
     * Text that doesn't fit its box: cut short (its last line ends before the text does) without an ellipsis, or broken
     * inside a word ("₹59,502.0" over "0", #49), is a problem; text shortened with an ellipsis is logged. Fields scroll,
     * so they are left out.
     */
    private fun textProblems(screen: String) {
        val text = SemanticsMatcher.keyIsDefined(SemanticsActions.GetTextLayoutResult) and
            SemanticsMatcher.keyNotDefined(SemanticsProperties.EditableText)
        val nodes = compose.onAllNodes(text, useUnmergedTree = true).fetchSemanticsNodes()
        compose.runOnIdle {
            for (node in nodes) {
                val layouts = mutableListOf<TextLayoutResult>()
                node.config.getOrNull(SemanticsActions.GetTextLayoutResult)?.action?.invoke(layouts)
                val layout = layouts.firstOrNull()?.takeIf { it.lineCount > 0 } ?: continue
                val words = layout.layoutInput.text.text
                val shortened = layout.getLineEnd(layout.lineCount - 1, visibleEnd = true) < words.trimEnd().length
                when {
                    shortened && (0 until layout.lineCount).any(layout::isLineEllipsized) ->
                        Log.i(TAG, "$screen: \"$words\" ends in an ellipsis")
                    shortened -> problems += "$screen: \"$words\" is cut off"
                    (0 until layout.lineCount - 1).any { breaksInsideAWord(words, layout.getLineEnd(it)) } ->
                        problems += "$screen: \"$words\" breaks inside a word"
                }
            }
        }
    }

    /** A line that ends between two letters or digits, not at a space or a hyphen. */
    private fun breaksInsideAWord(text: String, lineEnd: Int) =
        lineEnd in 1 until text.length && !text[lineEnd - 1].isWhitespace() && !text[lineEnd].isWhitespace() &&
            text[lineEnd - 1] !in "-/–—"

    private fun assertNoProblems() = assertTrue(problems.joinToString("\n"), problems.isEmpty())

    private companion object {
        const val TAG = "AccessibilityChecks"
        /** The largest font size Settings offers: 200% from Android 14 (scaled non-linearly), 130% before. */
        val largestFontScale = if (Build.VERSION.SDK_INT >= 34) 2f else 1.3f
    }
}
