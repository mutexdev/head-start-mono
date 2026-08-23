package app.headstart.ui.pair

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Share
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import app.headstart.data.InviteCode
import app.headstart.ui.components.BackBar
import app.headstart.ui.components.HsCard
import app.headstart.ui.components.HsScreen
import app.headstart.ui.components.PrimaryButton
import app.headstart.ui.components.SecondaryButton
import app.headstart.ui.theme.HeadstartTheme
import app.headstart.ui.theme.Hs
import app.headstart.ui.theme.HsType

/**
 * `design/PairInvite.dc.html`, minus the QR square.
 *
 * QR pairing is M4: generating a scannable code needs an encoder dependency and reading one
 * needs CameraX plus ML Kit — three libraries and a camera permission for something a
 * six-character code and a share link already cover. The artboard's "scan the square" clause
 * is dropped from the subtitle for the same reason.
 *
 * Stateless: the host (batch and7) calls `createPair` and feeds the result in as [code], and
 * owns the share sheet and the clipboard. Addendum §N: the code leads, the link follows, and
 * the scheme is `headstart` everywhere.
 *
 * @param code the six-character invite code, or null while `createPair` is still in flight.
 * @param onShare receives the finished share text so the host can hand it to `ACTION_SEND`.
 * @param onCopy receives the bare code for the clipboard.
 */
@Composable
fun PairInviteScreen(
    code: String?,
    onBack: () -> Unit,
    onShare: (shareText: String) -> Unit,
    onCopy: (code: String) -> Unit,
    modifier: Modifier = Modifier,
    copied: Boolean = false,
    errorMessage: String? = null,
) {
    HsScreen(modifier = modifier) {
        Spacer(Modifier.height(70.dp))
        BackBar(onBack = onBack)
        Spacer(Modifier.height(20.dp))

        Text("Your invite", style = HsType.ScreenTitle, color = Hs.TextPrimary)
        Spacer(Modifier.height(10.dp))
        Text(
            "They enter this code or tap your link.",
            style = HsType.Body,
            color = Hs.TextSecondary,
        )

        Spacer(Modifier.height(28.dp))
        HsCard(radius = 18.dp) {
            Column(
                modifier = Modifier.fillMaxWidth().padding(26.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
            ) {
                when {
                    errorMessage != null -> Text(
                        errorMessage,
                        style = HsType.Body,
                        color = Hs.Delayed,
                        textAlign = TextAlign.Center,
                    )

                    code == null -> CircularProgressIndicator(color = Hs.Go)

                    else -> {
                        Text(code, style = HsType.Code, color = Hs.TextPrimary)
                        Spacer(Modifier.height(20.dp))
                        LinkPill(InviteCode.link(code))
                    }
                }
                Spacer(Modifier.height(22.dp))
                Text("Expires in 24 hours", style = HsType.Small, color = Hs.TextTertiary)
            }
        }

        Spacer(Modifier.weight(1f))
        PrimaryButton(
            text = "Share link",
            enabled = code != null,
            leadingIcon = Icons.Filled.Share,
            onClick = { code?.let { onShare(InviteCode.shareText(it)) } },
        )
        Spacer(Modifier.height(12.dp))
        SecondaryButton(
            text = if (copied) "Copied" else "Copy code",
            enabled = code != null,
            onClick = { code?.let(onCopy) },
        )
        Spacer(Modifier.height(38.dp))
    }
}

/** The `headstart://pair/{code}` link, shown but deliberately secondary to the code itself. */
@Composable
private fun LinkPill(link: String) {
    val shape = RoundedCornerShape(11.dp)
    Box(
        modifier = Modifier
            .clip(shape)
            .background(Hs.Raised)
            .border(1.dp, Hs.Line, shape)
            .padding(horizontal = 14.dp, vertical = 9.dp),
        contentAlignment = Alignment.Center,
    ) {
        Text(link, style = HsType.Caption, color = Hs.TextSecondary, textAlign = TextAlign.Center)
    }
}

@Preview(name = "PairInvite", widthDp = 390, heightDp = 844, backgroundColor = 0xFF15171B, showBackground = true)
@Composable
private fun PreviewPairInvite() {
    HeadstartTheme {
        PairInviteScreen(code = "K7M2QP", onBack = {}, onShare = {}, onCopy = {})
    }
}

@Preview(name = "PairInvite — loading", widthDp = 390, heightDp = 844, backgroundColor = 0xFF15171B, showBackground = true)
@Composable
private fun PreviewPairInviteLoading() {
    HeadstartTheme {
        PairInviteScreen(code = null, onBack = {}, onShare = {}, onCopy = {})
    }
}

@Preview(name = "PairInvite — error", widthDp = 390, heightDp = 844, backgroundColor = 0xFF15171B, showBackground = true)
@Composable
private fun PreviewPairInviteError() {
    HeadstartTheme {
        PairInviteScreen(
            code = null,
            onBack = {},
            onShare = {},
            onCopy = {},
            errorMessage = "You are already paired with someone. Unpair first, then invite.",
        )
    }
}
