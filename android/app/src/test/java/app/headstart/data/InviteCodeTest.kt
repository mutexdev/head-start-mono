package app.headstart.data

import com.google.common.truth.Truth.assertThat
import org.junit.Test

class InviteCodeTest {

    @Test fun `accepts a well formed code in any case with any spacing`() {
        val table = listOf(
            "K7M2QP",
            "k7m2qp",
            "k7 m2 qp",
            " K7M2QP ",
            "K7M2-QP",
        )
        for (raw in table) {
            assertThat(InviteCode.normalize(raw)).isEqualTo("K7M2QP")
        }
    }

    @Test fun `rejects the look-alike characters the alphabet excludes`() {
        // The alphabet has no I, O, 0 or 1, so those characters are stripped and the
        // remaining five characters fail the length check.
        val table = listOf("K7M2QI", "K7M2QO", "K7M2Q0", "K7M2Q1")
        for (raw in table) {
            assertThat(InviteCode.normalize(raw)).isNull()
        }
    }

    @Test fun `rejects wrong lengths`() {
        assertThat(InviteCode.normalize("K7M2Q")).isNull()
        assertThat(InviteCode.normalize("K7M2QPX")).isNull()
        assertThat(InviteCode.normalize("")).isNull()
    }

    @Test fun `extracts a code from a deep link`() {
        assertThat(InviteCode.fromDeepLink("headstart://pair/K7M2QP")).isEqualTo("K7M2QP")
        assertThat(InviteCode.fromDeepLink("headstart://pair/k7m2qp")).isEqualTo("K7M2QP")
        assertThat(InviteCode.fromDeepLink("https://headstart.app/pair/K7M2QP")).isEqualTo("K7M2QP")
        assertThat(InviteCode.fromDeepLink("headstart://pair/")).isNull()
        assertThat(InviteCode.fromDeepLink("headstart://other/K7M2QP")).isNull()
        assertThat(InviteCode.fromDeepLink(null)).isNull()
    }

    @Test fun `builds the share text and link`() {
        assertThat(InviteCode.link("K7M2QP")).isEqualTo("headstart://pair/K7M2QP")
        assertThat(InviteCode.shareText("K7M2QP"))
            .isEqualTo("Pair with me on Headstart. Code: K7M2QP — headstart://pair/K7M2QP")
    }
}
