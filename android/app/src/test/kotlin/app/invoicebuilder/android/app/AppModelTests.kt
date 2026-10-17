package app.invoicebuilder.android.app

import android.net.Uri
import android.os.Looper
import androidx.lifecycle.SavedStateHandle
import androidx.test.core.app.ApplicationProvider
import org.junit.Assert.assertEquals
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import java.io.File

/** The app's start (iOS: `AppModelTests`). */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class AppModelTests {
    /** Runs the main thread's queue until [condition] holds: the model starts on the main thread, the database off it. */
    private fun until(condition: () -> Boolean) {
        val deadline = System.currentTimeMillis() + 10_000
        while (!condition()) {
            check(System.currentTimeMillis() < deadline) { "timed out" }
            shadowOf(Looper.getMainLooper()).idle()
            Thread.sleep(10)
        }
    }

    @Test
    fun aBackupOpenedWhileStartingOpensWithOnboarding() {
        // Every backup opened from another app arrives in a new activity, before its model has loaded (`spec/backup.md` §6).
        val model = AppModel(ApplicationProvider.getApplicationContext(), SavedStateHandle())
        model.launch(inMemory = true, seed = null)
        assertEquals(AppModel.Phase.Loading, model.phase)
        model.open(Uri.fromFile(File(System.getProperty("spec.root"), "samples/backup-v1-sample.invoicebackup.json")))
        until { (model.phase as? AppModel.Phase.Onboarding)?.model?.backup?.pendingRestore != null }
        val onboarding = model.phase as AppModel.Phase.Onboarding
        assertEquals("ios", onboarding.model.backup.pendingRestore?.file?.app?.platform)
    }
}
