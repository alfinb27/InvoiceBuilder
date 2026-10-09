package app.invoicebuilder.android.reminders

import android.Manifest
import androidx.core.content.edit
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import androidx.work.CoroutineWorker
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import app.invoicebuilder.android.InvoiceApplication
import app.invoicebuilder.android.MainActivity
import app.invoicebuilder.android.R
import app.invoicebuilder.android.app.AppContainer
import app.invoicebuilder.core.domain.documents.Document
import app.invoicebuilder.core.domain.documents.ReminderScheduler
import app.invoicebuilder.core.domain.documents.UPIPaymentLink
import app.invoicebuilder.core.domain.money.SpecFormatter
import app.invoicebuilder.core.domain.models.Business
import app.invoicebuilder.core.domain.money.CurrencyCode
import app.invoicebuilder.core.domain.setup.BusinessSetup
import java.time.LocalDate
import java.util.concurrent.TimeUnit

/**
 * Local notifications for overdue invoices (`spec/reminders.md` §3, ADR-0013). iOS schedules up to 50 calendar
 * notifications ahead; Android runs one daily WorkManager job (≈ a background task the OS schedules) that posts the
 * reminders due today. Abstracted so tests and the demo never touch the system.
 */
interface NotificationScheduling {
    /** Notifications may be shown (Android 13+: `POST_NOTIFICATIONS` granted; older: not blocked in Settings). */
    fun isAuthorized(): Boolean
    /** True when asking would show the system prompt (Android 13+, not granted yet). */
    fun canRequestAuthorization(): Boolean
    fun startDailyCheck()
    fun stopDailyCheck()
    fun post(documentID: String, title: String, body: String)
}

class SystemNotificationScheduler(private val context: Context) : NotificationScheduling {
    override fun isAuthorized(): Boolean {
        if (Build.VERSION.SDK_INT >= 33 &&
            ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) return false
        return NotificationManagerCompat.from(context).areNotificationsEnabled()
    }

    override fun canRequestAuthorization(): Boolean = Build.VERSION.SDK_INT >= 33 &&
        ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED

    override fun startDailyCheck() {
        val request = PeriodicWorkRequestBuilder<ReminderWorker>(1, TimeUnit.DAYS).build()
        WorkManager.getInstance(context).enqueueUniquePeriodicWork(WORK_NAME, ExistingPeriodicWorkPolicy.KEEP, request)
    }

    override fun stopDailyCheck() {
        WorkManager.getInstance(context).cancelUniqueWork(WORK_NAME)
    }

    override fun post(documentID: String, title: String, body: String) {
        if (!isAuthorized()) return
        val manager = context.getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(
            NotificationChannel(CHANNEL, context.getString(R.string.reminder_channel), NotificationManager.IMPORTANCE_DEFAULT)
                .apply { description = context.getString(R.string.reminder_channel_description) },
        )
        // Tapping opens the invoice (≈ the notification's `userInfo["documentID"]` on iOS).
        val open = Intent(context, MainActivity::class.java).apply {
            putExtra(MainActivity.EXTRA_DOCUMENT_ID, documentID)
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val pending = PendingIntent.getActivity(context, documentID.hashCode(), open, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        val notification = NotificationCompat.Builder(context, CHANNEL)
            .setSmallIcon(R.drawable.ic_launcher_foreground)
            .setContentTitle(title)
            .setContentText(body)
            .setContentIntent(pending)
            .setAutoCancel(true)
            .build()
        // Checked here, next to the call, so Lint (and a reader) can see the permission guard.
        if (Build.VERSION.SDK_INT >= 33 &&
            ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) return
        runCatching { NotificationManagerCompat.from(context).notify("reminder-$documentID", 0, notification) }
    }

    companion object {
        const val WORK_NAME = "invoiceReminders"
        const val CHANNEL = "invoiceReminder"
    }
}

/** Never touches the OS: tests, previews and the demo business. */
class NoOpNotificationScheduler : NotificationScheduling {
    override fun isAuthorized() = false
    override fun canRequestAuthorization() = false
    override fun startDailyCheck() {}
    override fun stopDailyCheck() {}
    override fun post(documentID: String, title: String, body: String) {}
}

/** Keeps the daily check in step with the permission, and posts the reminders due. iOS: `ReminderReconciler`. */
class ReminderReconciler(private val container: AppContainer, private val posted: PostedReminders) {
    /** Safe to call repeatedly: launch, after issuing, after payments, after a void, after the default changes. */
    fun reconcile() {
        if (container.notifications.isAuthorized()) container.notifications.startDailyCheck() else container.notifications.stopDailyCheck()
    }

    /**
     * The daily job: every reminder dated today or earlier that has not been shown yet, from the date of the last
     * completed run (never more than [CATCH_UP_DAYS] back), so a day the OS skipped is still covered but turning
     * reminders on doesn't post a backlog (`spec/reminders.md` §3).
     */
    suspend fun postDue(today: LocalDate = container.time.today()) {
        val device = container.deviceState.loadOrCreate(Build.MODEL)
        val business = BusinessSetup.activeBusiness(device.preferences, container.businesses.fetchBusinesses()) ?: return
        val candidates = container.documents.fetchReminderCandidates(business.id)
        val earliest = today.minusDays(CATCH_UP_DAYS)
        val from = posted.lastRun?.let { if (it.isBefore(earliest)) earliest else minOf(it, today) } ?: today
        val planned = ReminderScheduler.plan(business.reminderDaysAfterDue, CAP, candidates, from)
        val formatter = SpecFormatter(container.reference.currencies)
        for (reminder in planned) {
            if (reminder.remindOn.isAfter(today)) continue
            val key = "${reminder.documentId}@${reminder.remindOn}"
            if (posted.contains(key)) continue
            val document = container.documents.fetchDocument(reminder.documentId) ?: continue
            val paid = container.payments.fetchPayments(document.id).sumOf { it.amountMinor }
            container.notifications.post(document.id, "Payment reminder", body(document, paid, formatter))
            posted.add(key)
        }
        posted.lastRun = today
    }

    companion object {
        const val CAP = 50
        const val CATCH_UP_DAYS = 7L

        /** "INV/26-27/0001: ₹6,800.00 from Rao Traders is due." — the outstanding amount, not the total. */
        fun body(document: Document, paidMinor: Long, formatter: SpecFormatter): String {
            val amount = formatter.money(maxOf(document.totals.totalMinor - paidMinor, 0), document.currency, document.currency)
            val who = document.buyerSnapshot?.name?.let { " from $it" } ?: ""
            return "${document.number ?: ""}: $amount$who is due."
        }
    }
}

/**
 * Which reminders were already shown, so the daily job posts each once (≈ iOS's one-shot calendar triggers), and the
 * date of its last completed run.
 */
class PostedReminders(context: Context) {
    private val prefs = context.getSharedPreferences("posted_reminders", Context.MODE_PRIVATE)
    fun contains(key: String) = prefs.getBoolean(key, false)
    fun add(key: String) = prefs.edit { putBoolean(key, true) }

    var lastRun: LocalDate?
        get() = prefs.getString(LAST_RUN, null)?.let { runCatching { LocalDate.parse(it) }.getOrNull() }
        set(value) = prefs.edit { if (value == null) remove(LAST_RUN) else putString(LAST_RUN, value.toString()) }

    private companion object {
        const val LAST_RUN = "lastRun"
    }
}

class ReminderWorker(context: Context, params: WorkerParameters) : CoroutineWorker(context, params) {
    override suspend fun doWork(): Result {
        val app = applicationContext as InvoiceApplication
        runCatching { ReminderReconciler(app.container, PostedReminders(applicationContext)).postDue() }
        return Result.success()
    }
}

/**
 * "Send reminder"'s message (`spec/reminders.md` §4), shared as text. The seller's name and UPI ID come from the issued
 * document's `sellerSnapshot`, as on its PDF, not from the current business. iOS: `ReminderMessage`.
 */
object ReminderMessage {
    fun text(document: Document, paidMinor: Long, business: Business, money: (Long, CurrencyCode) -> String, dueText: String?): String {
        val outstanding = maxOf(document.totals.totalMinor - paidMinor, 0)
        val name = document.buyerSnapshot?.let { it.contactName ?: it.name }
        val greeting = if (name != null) "Hi $name," else "Hi there,"
        // Every issued document has a seller snapshot; the business is only a fallback for one that somehow lacks it.
        val seller = document.sellerSnapshot
        val sellerName = seller?.name ?: business.name
        var text = "$greeting this is a reminder that invoice ${document.number ?: ""} for ${money(outstanding, document.currency)} " +
            "from $sellerName was due on ${dueText ?: "the due date"}."
        val vpa = (if (seller != null) seller.upiVpa else business.upiVpa)?.trim()?.takeIf { it.isNotEmpty() }
        if (document.currency == CurrencyCode.INR && outstanding > 0 && vpa != null) {
            text += " Pay via UPI: " + UPIPaymentLink.url(vpa, sellerName, outstanding, document.number ?: "")
        }
        return "$text Thank you!"
    }
}
