package app.headstart.data

import com.google.common.truth.Truth.assertThat
import org.junit.Test

/**
 * Regression test for a bug the two-device integration drive found: after unpairing,
 * "Invite someone" re-displayed the OLD, revoked code instead of minting a fresh one.
 * The predicate matched `!isActive`, which is true for "revoked" as well as "pending".
 * acceptPair only queries pending pairs, so that code could never be accepted —
 * the user was handed a silently dead invite.
 */
class PendingInviteTest {
    private fun pair(id: String, status: String, createdBy: String, code: String) = PairInfo(
        id = id, members = listOf("me"), status = status,
        inviteCode = code, createdBy = createdBy, createdAtMs = null,
    )

    @Test fun `a revoked pair I created is NOT offered as an invite`() {
        val pairs = listOf(pair("p1", "revoked", "me", "JCC4AW"))
        assertThat(PairRepository.pickPendingInvite(pairs, "me")).isNull()
    }

    @Test fun `a pending pair I created is offered`() {
        val pairs = listOf(pair("p1", "pending", "me", "K7M2QP"))
        assertThat(PairRepository.pickPendingInvite(pairs, "me")?.inviteCode).isEqualTo("K7M2QP")
    }

    @Test fun `after unpairing and re-inviting, the FRESH code wins over the revoked one`() {
        val pairs = listOf(
            pair("old", "revoked", "me", "JCC4AW"),
            pair("new", "pending", "me", "ZQ8T4N"),
        )
        assertThat(PairRepository.pickPendingInvite(pairs, "me")?.inviteCode).isEqualTo("ZQ8T4N")
    }

    @Test fun `a pending pair someone else created is not my invite`() {
        val pairs = listOf(pair("p1", "pending", "them", "K7M2QP"))
        assertThat(PairRepository.pickPendingInvite(pairs, "me")).isNull()
    }

    @Test fun `an active pair is never offered as a pending invite`() {
        val pairs = listOf(pair("p1", "active", "me", "K7M2QP"))
        assertThat(PairRepository.pickPendingInvite(pairs, "me")).isNull()
    }
}
