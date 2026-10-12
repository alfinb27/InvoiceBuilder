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
 * Automatic backup to Google Drive (`spec/backup.md` §7) with the in-memory Drive (`fakeDrive` extra): connect, back
 * up now, restore from the list; and Welcome's "Restore from Google Drive". iOS: `DriveBackupSmokeTests`.
 */
@OptIn(ExperimentalTestApi::class)
@RunWith(AndroidJUnit4::class)
class DriveBackupSmokeTests {
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
    fun backUpToGoogleDriveThenRestoreFromIt() {
        launch("IN")
        tap("tab-settings")
        tap("settings-backup")
        waitForText("Off")
        tap("backup.drive")
        tap("backup.drive.connect")
        waitForText("you@example.com")
        waitForText("Last backup to Google Drive: today")
        tap("backup.drive.backUpNow")
        compose.onNodeWithTag("backup.drive.status").assertExists()
        tap("editorCancel")
        waitForText("Last backup: today") // §7.5: it counts as a backup
        tap("backup.drive.restore")
        tap("driveBackup-0")
        compose.waitUntilExactlyOneExists(hasTestTag("backup.confirmRestore"), 10_000)
    }

    @Test
    fun welcomeOffersRestoreFromGoogleDrive() {
        launch(null)
        tap("onboarding.usedBefore")
        tap("onboarding.restoreDrive")
        waitForText("No backups in Google Drive yet")
    }
}
