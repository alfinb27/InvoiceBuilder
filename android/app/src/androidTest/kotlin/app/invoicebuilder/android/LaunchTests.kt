package app.invoicebuilder.android

import android.app.Activity
import android.content.Context
import android.content.Intent
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.runner.lifecycle.ActivityLifecycleMonitorRegistry
import androidx.test.runner.lifecycle.Stage
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Test
import org.junit.runner.RunWith

/**
 * How the app is opened (#55). A reminder or a backup file starts it with an intent of its own; tapping the app icon
 * afterwards must come back to that copy, not stack another on top. Each copy loads all the data again, and on a 48 MB
 * phone fifty of them ran out of memory.
 */
@RunWith(AndroidJUnit4::class)
class LaunchTests {
    private val context: Context = ApplicationProvider.getApplicationContext()
    private val instrumentation = InstrumentationRegistry.getInstrumentation()

    @After fun tearDown() = instrumentation.runOnMainSync { liveCopies().forEach(Activity::finish) }

    private fun liveCopies(): List<MainActivity> =
        listOf(Stage.PRE_ON_CREATE, Stage.CREATED, Stage.STARTED, Stage.RESUMED, Stage.PAUSED, Stage.STOPPED, Stage.RESTARTED)
            .flatMap { ActivityLifecycleMonitorRegistry.getInstance().getActivitiesInStage(it) }.filterIsInstance<MainActivity>()

    private fun copies(): Int {
        var count = 0
        instrumentation.runOnMainSync { count = liveCopies().size }
        return count
    }

    @Test fun theAppIconReturnsToTheCopyAReminderOpened() {
        // As Reminders.kt opens it.
        context.startActivity(Intent(context, MainActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
            .putExtra(MainActivity.EXTRA_IN_MEMORY, true).putExtra(MainActivity.EXTRA_DOCUMENT_ID, "no-such-invoice"))
        val deadline = System.currentTimeMillis() + 10_000
        while (copies() == 0 && System.currentTimeMillis() < deadline) Thread.sleep(100)
        // As the launcher opens it.
        repeat(3) {
            context.startActivity(Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER).setClass(context, MainActivity::class.java)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_RESET_TASK_IF_NEEDED))
            instrumentation.waitForIdleSync()
        }
        Thread.sleep(1_000)
        assertEquals(1, copies())
    }
}
