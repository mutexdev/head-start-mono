package app.headstart.data

import android.app.Activity
import app.headstart.core.Callables
import app.headstart.core.HeadstartError
import com.google.firebase.FirebaseException
import com.google.firebase.FirebaseTooManyRequestsException
import com.google.firebase.auth.FirebaseAuth
import com.google.firebase.auth.FirebaseAuthInvalidCredentialsException
import com.google.firebase.auth.PhoneAuthCredential
import com.google.firebase.auth.PhoneAuthOptions
import com.google.firebase.auth.PhoneAuthProvider
import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.callbackFlow
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.tasks.await
import java.util.concurrent.TimeUnit
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException

sealed interface SendCodeResult {
    /** The SMS is on its way; hold this id until the user types the six digits. */
    data class CodeSent(val verificationId: String) : SendCodeResult

    /** Google Play auto-read the SMS (or this is a Firebase test number) — just sign in. */
    data class AutoRetrieved(val credential: PhoneAuthCredential) : SendCodeResult
}

/**
 * Firebase phone OTP. `verifyPhoneNumber` needs an Activity because it may put up a
 * reCAPTCHA web view when Play Integrity is unavailable.
 *
 * Against the Auth emulator no SMS is sent and no app verification runs at all
 * (`HeadstartConfig` calls `setAppVerificationDisabledForTesting(true)`); the reviewer
 * reads the code from the host with
 * `curl http://127.0.0.1:9099/emulator/v1/projects/fin-e8358/verificationCodes`.
 * That fetch is deliberately NOT built into the app.
 */
class AuthRepository(
    private val auth: FirebaseAuth,
    private val callables: Callables,
) {
    val uid: String? get() = auth.currentUser?.uid

    private var resendToken: PhoneAuthProvider.ForceResendingToken? = null

    /** Emits the current uid, then again on every sign-in/sign-out. */
    fun uidFlow(): Flow<String?> = callbackFlow {
        val listener = FirebaseAuth.AuthStateListener { trySend(it.currentUser?.uid) }
        auth.addAuthStateListener(listener)
        awaitClose { auth.removeAuthStateListener(listener) }
    }

    suspend fun sendCode(
        activity: Activity,
        e164: String,
        resend: Boolean = false,
    ): SendCodeResult = suspendCancellableCoroutine { cont ->
        val callbacks = object : PhoneAuthProvider.OnVerificationStateChangedCallbacks() {
            override fun onVerificationCompleted(credential: PhoneAuthCredential) {
                if (cont.isActive) cont.resume(SendCodeResult.AutoRetrieved(credential))
            }

            override fun onVerificationFailed(e: FirebaseException) {
                if (cont.isActive) cont.resumeWithException(mapAuthError(e))
            }

            override fun onCodeSent(
                verificationId: String,
                token: PhoneAuthProvider.ForceResendingToken,
            ) {
                resendToken = token
                if (cont.isActive) cont.resume(SendCodeResult.CodeSent(verificationId))
            }
        }

        val builder = PhoneAuthOptions.newBuilder(auth)
            .setPhoneNumber(e164)
            .setTimeout(60L, TimeUnit.SECONDS)
            .setActivity(activity)
            .setCallbacks(callbacks)
        if (resend) resendToken?.let { builder.setForceResendingToken(it) }
        PhoneAuthProvider.verifyPhoneNumber(builder.build())
    }

    suspend fun verify(verificationId: String, smsCode: String): String {
        if (!PhoneNumber.isValidSmsCode(smsCode)) throw HeadstartError.InvalidSmsCode
        return signIn(PhoneAuthProvider.getCredential(verificationId, smsCode))
    }

    suspend fun signIn(credential: PhoneAuthCredential): String = try {
        val result = auth.signInWithCredential(credential).await()
        result.user?.uid ?: throw HeadstartError.Unauthenticated
    } catch (t: Throwable) {
        throw mapAuthError(t)
    }

    /**
     * `registerPushToken` also carries the display name, which is how the server learns
     * what to put in "{driver} started driving" and what to write into
     * `pairs/{pairId}.memberNames`. Called after sign-in, after the name is set, and on
     * every FCM token refresh.
     */
    suspend fun registerPushToken(
        token: String,
        platform: String = "android",
        displayName: String? = null,
    ) {
        val payload = mutableMapOf<String, Any?>("token" to token, "platform" to platform)
        if (!displayName.isNullOrBlank()) payload["displayName"] = displayName
        callables.call("registerPushToken", payload)
    }

    fun signOut() = auth.signOut()

    private fun mapAuthError(t: Throwable): HeadstartError = when {
        t is HeadstartError -> t
        t is FirebaseAuthInvalidCredentialsException &&
            t.message?.contains("phone number", ignoreCase = true) == true -> HeadstartError.InvalidPhone
        t is FirebaseAuthInvalidCredentialsException -> HeadstartError.InvalidSmsCode
        t is FirebaseTooManyRequestsException -> HeadstartError.SmsQuotaExceeded
        t.message?.contains("expired", ignoreCase = true) == true -> HeadstartError.SessionExpired
        else -> HeadstartError.Unknown(t.message ?: "auth-failed")
    }
}
