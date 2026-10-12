package app.invoicebuilder.core.drive

import android.accounts.Account
import android.content.Context
import android.content.Intent
import android.content.IntentSender
import app.invoicebuilder.core.domain.backup.CloudBackupError
import app.invoicebuilder.core.domain.backup.CloudBackupException
import com.google.android.gms.auth.api.identity.AuthorizationRequest
import com.google.android.gms.auth.api.identity.AuthorizationResult
import com.google.android.gms.auth.api.identity.ClearTokenRequest
import com.google.android.gms.auth.api.identity.Identity
import com.google.android.gms.auth.api.identity.RevokeAccessRequest
import com.google.android.gms.common.api.ApiException
import com.google.android.gms.common.api.CommonStatusCodes
import com.google.android.gms.common.api.Scope
import kotlinx.coroutines.tasks.await

/** Shows Google's consent sheet: launches [sender] from the current Activity and returns its result (null = closed). */
fun interface ConsentLauncher {
    suspend fun launch(sender: IntentSender): Intent?
}

/**
 * Tokens for the one `drive.file` scope from Google Identity's `AuthorizationClient` (≈ iOS `GoogleAuth`, which runs
 * OAuth itself; on Android, Google Play services keeps the grant and refreshes tokens). Works from background work
 * once granted; asking for consent needs [consent], the visible Activity's launcher.
 */
class GoogleAuth(context: Context, private val consent: () -> ConsentLauncher?) : DriveAuth {
    companion object {
        const val SCOPE = "https://www.googleapis.com/auth/drive.file"
        private const val ACCOUNT = "account"
    }

    private val client = Identity.getAuthorizationClient(context)
    /** App-private and outside Auto Backup (`data_extraction_rules.xml` backs up only the database and snapshots). */
    private val prefs = context.getSharedPreferences("google-drive", Context.MODE_PRIVATE)
    private val request = AuthorizationRequest.builder().setRequestedScopes(listOf(Scope(SCOPE))).build()
    @Volatile private var cached: String? = null

    override suspend fun signIn() {
        var result = call { client.authorize(request).await() }
        if (result.hasResolution()) {
            val launcher = consent() ?: throw CloudBackupException(CloudBackupError.Other)
            val sender = result.pendingIntent?.intentSender ?: throw CloudBackupException(CloudBackupError.Other)
            val data = launcher.launch(sender) ?: throw CloudBackupException(CloudBackupError.Cancelled)
            result = call { client.getAuthorizationResultFromIntent(data) }
        }
        remember(result)
    }

    override suspend fun accessToken(forceRefresh: Boolean): String {
        if (!forceRefresh) cached?.let { return it }
        cached?.let { stale ->
            runCatching { client.clearToken(ClearTokenRequest.builder().setToken(stale).build()).await() }
            cached = null
        }
        val result = call { client.authorize(request).await() }
        if (result.hasResolution()) throw CloudBackupException(CloudBackupError.SignedOut) // consent was revoked
        return remember(result)
    }

    override suspend fun signOut() {
        val email = prefs.getString(ACCOUNT, null)
        cached = null
        prefs.edit().clear().apply()
        if (email != null) {
            runCatching {
                client.revokeAccess(RevokeAccessRequest.builder().setAccount(Account(email, "com.google"))
                    .setScopes(listOf(Scope(SCOPE))).build()).await()
            }
        }
    }

    private fun remember(result: AuthorizationResult): String {
        val token = result.accessToken ?: throw CloudBackupException(CloudBackupError.Other)
        cached = token
        @Suppress("DEPRECATION") // the account is only needed to revoke access later
        result.toGoogleSignInAccount()?.email?.let { prefs.edit().putString(ACCOUNT, it).apply() }
        return token
    }

    /** Play services failures as [CloudBackupError]s. */
    private suspend fun <T> call(block: suspend () -> T): T = try {
        block()
    } catch (error: ApiException) {
        throw CloudBackupException(when (error.statusCode) {
            CommonStatusCodes.NETWORK_ERROR, CommonStatusCodes.TIMEOUT -> CloudBackupError.NetworkUnavailable
            CommonStatusCodes.CANCELED -> CloudBackupError.Cancelled
            CommonStatusCodes.SIGN_IN_REQUIRED -> CloudBackupError.SignedOut
            else -> CloudBackupError.Other
        })
    }
}
