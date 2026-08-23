package app.headstart.ui.onboarding

import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.width
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import app.headstart.data.PhoneNumber
import app.headstart.ui.components.BackBar
import app.headstart.ui.components.HsScreen
import app.headstart.ui.components.HsTextField
import app.headstart.ui.components.PrimaryButton
import app.headstart.ui.components.PrivacyNote
import app.headstart.ui.theme.HeadstartTheme
import app.headstart.ui.theme.Hs
import app.headstart.ui.theme.HsType
import app.headstart.ui.theme.TABULAR

/**
 * `design/Phone.dc.html`.
 *
 * The artboard shows a flag beside the dial code. A country picker is not in M1 — the dial
 * code is an editable field prefilled `+880`, which is honest about what it is.
 *
 * Stateless in the sense that matters here: it holds only the two text fields the keyboard is
 * editing and nothing else. Sending the code, the resulting error and every navigation
 * decision belong to `AppViewModel` (batch and7), which owns the `Activity` that
 * `PhoneAuthProvider.verifyPhoneNumber` needs. This file imports no repository, no Firebase
 * type and no ViewModel.
 *
 * @param sending true while the host is calling `AuthRepository.sendCode`.
 * @param errorMessage a finished sentence from `HeadstartError.userMessage`, or null.
 * @param onSendCode receives the dialable E.164 number plus the raw parts, so the host can
 *   render "Sent to +880 1712345678" on the next screen without re-parsing.
 */
@Composable
fun PhoneScreen(
    onBack: () -> Unit,
    onSendCode: (e164: String, dialCode: String, national: String) -> Unit,
    modifier: Modifier = Modifier,
    initialDialCode: String = "+880",
    initialNational: String = "",
    sending: Boolean = false,
    errorMessage: String? = null,
) {
    var dialCode by rememberSaveable { mutableStateOf(initialDialCode) }
    var national by rememberSaveable { mutableStateOf(initialNational) }

    val e164 = remember(dialCode, national) { PhoneNumber.toE164(dialCode, national) }

    HsScreen(modifier = modifier.imePadding()) {
        Spacer(Modifier.height(70.dp))
        BackBar(onBack = onBack)
        Spacer(Modifier.height(28.dp))

        Text("What's your number?", style = HsType.ScreenTitle, color = Hs.TextPrimary)
        Spacer(Modifier.height(12.dp))
        Text(
            "We'll text you a six-digit code. No password to remember, no email.",
            style = HsType.Body,
            color = Hs.TextSecondary,
        )

        Spacer(Modifier.height(36.dp))
        Row {
            HsTextField(
                value = dialCode,
                onValueChange = { dialCode = it.take(5) },
                modifier = Modifier.width(104.dp),
                textStyle = HsType.CardTitle.copy(fontFeatureSettings = TABULAR),
                keyboardType = KeyboardType.Phone,
                imeAction = ImeAction.Next,
            )
            Spacer(Modifier.width(10.dp))
            HsTextField(
                value = national,
                onValueChange = { raw -> national = raw.filter { it.isDigit() || it == ' ' } },
                modifier = Modifier.weight(1f),
                placeholder = "1712 345678",
                textStyle = HsType.CardTitle.copy(fontFeatureSettings = TABULAR),
                keyboardType = KeyboardType.Phone,
                imeAction = ImeAction.Done,
                autoFocus = true,
            )
        }

        Spacer(Modifier.height(20.dp))
        PrivacyNote("Your number is only ever shown to the one person you pair with.")

        if (errorMessage != null) {
            Spacer(Modifier.height(14.dp))
            Text(errorMessage, style = HsType.Small, color = Hs.Delayed)
        }

        Spacer(Modifier.weight(1f))
        PrimaryButton(
            text = if (sending) "Sending…" else "Send code",
            enabled = e164 != null && !sending,
            onClick = { e164?.let { number -> onSendCode(number, dialCode, national) } },
        )
        Spacer(Modifier.height(38.dp))
    }
}

@Preview(name = "Phone — empty", widthDp = 390, heightDp = 844, backgroundColor = 0xFF15171B, showBackground = true)
@Composable
private fun PreviewPhoneEmpty() {
    HeadstartTheme {
        PhoneScreen(onBack = {}, onSendCode = { _, _, _ -> })
    }
}

@Preview(name = "Phone — error", widthDp = 390, heightDp = 844, backgroundColor = 0xFF15171B, showBackground = true)
@Composable
private fun PreviewPhoneError() {
    HeadstartTheme {
        PhoneScreen(
            onBack = {},
            onSendCode = { _, _, _ -> },
            initialNational = "1712345678",
            errorMessage = "We could not reach Headstart. Check your connection and try again.",
        )
    }
}
