package app.invoicebuilder.android

import android.content.Intent
import androidx.compose.ui.test.ExperimentalTestApi
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.createEmptyComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.test.core.app.ActivityScenario
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.After
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Live sync through Google Drive (`spec/drive-sync.md`) with the in-memory Drive (`fakeDrive` extra): Settings → Sync,
 * and Welcome's "Sync with Google Drive". iOS: `DriveSyncSmokeTests`.
 */
@OptIn(ExperimentalTestApi::class)
@RunWith(AndroidJUnit4::class)
class DriveSyncSmokeTests {
    @get:Rule val compose = createEmptyComposeRule()
    private var scenario: ActivityScenario<MainActivity>? = null

    private fun launch(seed: String?) {
        val intent = Intent(ApplicationProvider.getApplicationContext(), MainActivity::class.java)
            .putExtra(MainActivity.EXTRA_IN_MEMORY, true).putExtra(MainActivity.EXTRA_FAKE_DRIVE, true)
        seed?.let { intent.putExtra(MainActivity.EXTRA_SEED, it) }
        scenario = ActivityScenario.launch(intent)
    }

    @After fun tearDown() { scenario?.close() }

    private fun tap(tag: String) {
        compose.waitUntilExactlyOneExists(hasTestTag(tag), 10_000)
        compose.onNodeWithTag(tag).let { runCatching { it.performScrollTo() }.getOrDefault(it) }.performClick()
    }

    private fun waitForText(text: String) = compose.waitUntilAtLeastOneExists(hasText(text, substring = true), 10_000)

    @Test
    fun turnOnGoogleDriveSyncThenSyncNow() {
        launch("IN")
        tap("tab-settings")
        tap("settings-sync")
        waitForText("Keep this phone in step")
        tap("sync.drive")
        tap("sync.drive.confirm")
        waitForText("Up to date")
        tap("sync.drive.now")
        waitForText("Up to date")
        tap("sync.drive")
        waitForText("Keep this phone in step")
    }

    @Test
    fun welcomeOffersSyncWithGoogleDrive() {
        launch(null)
        tap("onboarding.usedBefore")
        tap("onboarding.syncDrive")
        // An empty Drive: nothing arrives, so the Welcome screen stays.
        compose.waitUntilExactlyOneExists(hasTestTag("onboarding.usedBefore"), 10_000)
    }
}
