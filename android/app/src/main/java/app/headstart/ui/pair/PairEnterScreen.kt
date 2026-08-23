package app.headstart.ui.pair

import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.imePadding
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import app.headstart.data.InviteCode
import app.headstart.ui.components.BackBar
import app.headstart.ui.components.CodeInput
import app.headstart.ui.components.HsScreen
import app.headstart.ui.components.PrimaryButton
import app.headstart.ui.theme.HeadstartTheme
import app.headstart.ui.theme.Hs
import app.headstart.ui.theme.HsType

/**
 * `design/PairEnter.dc.html`, minus the artboard's QR-scanning row — QR pairing is M4, so
 * that row is not rendered and its copy appears nowhere in `app/src/main`.
 *
 * Stateless: it holds the six characters the keyboard is editing and nothing else.
 * `acceptPair` is the host's call (batch and7); [prefilledCode] is how a `headstart://pair/…`
 * deep link arrives here, already normalised by `InviteCode.fromDeepLink`.
 */
@Composable
fun PairEnterScreen(
    onBack: () -> Unit,
    onPair: (code: String) -> Unit,
    modifier: Modifier = Modifier,
    prefilledCode: String? = null,
    pairing: Boolean = false,
    errorMessage: String? = null,
) {
    var code by rememberSaveable { mutableStateOf(prefilledCode.orEmpty()) }
    val normalized = remember(code) { InviteCode.normalize(code) }

    HsScreen(modifier = modifier.imePadding()) {
        Spacer(Modifier.height(70.dp))
        BackBar(onBack = onBack)
        Spacer(Modifier.height(26.dp))

        Text("Enter their code", style = HsType.ScreenTitle, color = Hs.TextPrimary)
        Spacer(Modifier.height(12.dp))
        Text(
            "Six characters, from the invite they sent you.",
            style = HsType.Body,
            color = Hs.TextSecondary,
        )

        Spacer(Modifier.height(36.dp))
        CodeInput(
            value = code,
            onValueChange = { code = it },
            digitsOnly = false,
            boxHeight = 62.dp,
            gap = 8.dp,
        )

        if (errorMessage != null) {
            Spacer(Modifier.height(16.dp))
            Text(errorMessage, style = HsType.Small, color = Hs.Delayed)
        }

        Spacer(Modifier.weight(1f))
        PrimaryButton(
            text = if (pairing) "Pairing…" else "Pair",
            enabled = normalized != null && !pairing,
            onClick = { normalized?.let(onPair) },
        )
        Spacer(Modifier.height(38.dp))
    }
}

@Preview(name = "PairEnter — empty", widthDp = 390, heightDp = 844, backgroundColor = 0xFF15171B, showBackground = true)
@Composable
private fun PreviewPairEnterEmpty() {
    HeadstartTheme {
        PairEnterScreen(onBack = {}, onPair = {})
    }
}

@Preview(name = "PairEnter — filled", widthDp = 390, heightDp = 844, backgroundColor = 0xFF15171B, showBackground = true)
@Composable
private fun PreviewPairEnterFilled() {
    HeadstartTheme {
        PairEnterScreen(
            onBack = {},
            onPair = {},
            prefilledCode = "K7M2QP",
            errorMessage = "That code was not right. Check the six characters and try again.",
        )
    }
}
