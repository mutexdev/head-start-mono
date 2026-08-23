package app.headstart.data

import app.headstart.core.Callables
import app.headstart.core.HeadstartError
import app.headstart.core.snapshotFlow
import app.headstart.core.str
import com.google.firebase.firestore.FirebaseFirestore
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map

/** The 6-character alphabet from CLIENT_CONTRACT.md — no I, O, 0 or 1. */
object InviteCode {
    const val ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
    private const val LENGTH = 6

    /** Upper-cases, strips anything that is not in the alphabet, and checks the length. */
    fun normalize(raw: String?): String? {
        val cleaned = raw.orEmpty().uppercase().filter { it in ALPHABET }
        return if (cleaned.length == LENGTH) cleaned else null
    }

    /** Addendum §N: the deep-link scheme is `headstart` everywhere. The pre-rename scheme appears nowhere. */
    fun link(code: String): String = "headstart://pair/$code"

    /** The bare code leads, so manual entry always works even where the link cannot open. */
    fun shareText(code: String): String =
        "Pair with me on Headstart. Code: $code — ${link(code)}"

    /** Pulls a code out of `headstart://pair/{code}` or `https://.../pair/{code}`. */
    fun fromDeepLink(uri: String?): String? {
        val text = uri ?: return null
        val marker = "/pair/"
        val at = text.indexOf(marker)
        if (at < 0) return null
        return normalize(text.substring(at + marker.length).substringBefore('?').substringBefore('/'))
    }
}

data class CreatedPair(val pairId: String, val inviteCode: String)

class PairRepository(
    private val db: FirebaseFirestore,
    private val callables: Callables,
) {
    /**
     * All pairs this user belongs to. Queried by `array-contains` alone and filtered in
     * Kotlin: adding `status == active` to the query needs the composite index the backend
     * declares (addendum §M), and this way the client works whether or not it exists yet.
     * A user is only ever in a handful of pair documents.
     */
    fun pairsFor(uid: String): Flow<List<PairInfo>> =
        db.collection("pairs")
            .whereArrayContains("members", uid)
            .snapshotFlow()
            .map { snap -> snap.documents.mapNotNull { pairFrom(it.id, it.data) } }

    fun activePair(uid: String): Flow<PairInfo?> =
        pairsFor(uid).map { list -> list.firstOrNull { it.isActive } }

    /** The invite this user created and nobody has accepted yet — drives PairInvite. */
    fun pendingInvite(uid: String): Flow<PairInfo?> =
        pairsFor(uid).map { list -> list.firstOrNull { !it.isActive && it.createdBy == uid } }

    /** One pair document, live. `memberNames` lands here when the other side signs in. */
    fun pair(pairId: String): Flow<PairInfo?> =
        db.collection("pairs").document(pairId).snapshotFlow()
            .map { snap -> snap?.let { pairFrom(it.id, it.data) } }

    suspend fun createPair(): CreatedPair {
        val res = callables.call("createPair")
        val pairId = res.str("pairId") ?: throw HeadstartError.Unknown("createPair-no-id")
        val code = res.str("inviteCode") ?: throw HeadstartError.Unknown("createPair-no-code")
        return CreatedPair(pairId, code)
    }

    suspend fun acceptPair(rawCode: String): String {
        val code = InviteCode.normalize(rawCode) ?: throw HeadstartError.BadCode
        val res = callables.call("acceptPair", mapOf("code" to code))
        return res.str("pairId") ?: throw HeadstartError.Unknown("acceptPair-no-id")
    }

    suspend fun revokePair(pairId: String) {
        callables.call("revokePair", mapOf("pairId" to pairId))
    }
}
