package app.headstart.ui.onboarding

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import app.headstart.BuildConfig
import app.headstart.core.HeadstartConfig
import app.headstart.core.formatCountdown
import app.headstart.data.PhoneNumber
import app.headstart.ui.components.BackBar
import app.headstart.ui.components.CodeInput
import app.headstart.ui.components.HsScreen
import app.headstart.ui.components.PrimaryButton
import app.headstart.ui.theme.HeadstartTheme
import app.headstart.ui.theme.Hs
import app.headstart.ui.theme.HsType
import app.headstart.ui.theme.TABULAR

/**
 * Where a reviewer running against the Firebase Auth emulator reads the SMS code that was
 * never sent. Shown only in a debug build that is actually pointed at the emulator suite —
 * see the addendum's "Phone sign-in without SMS".
 */
private const val EMULATOR_PROJECT_ID = "fin-e8358"

/**
 * `design/Verify.dc.html`.
 *
 * Stateless: it holds the six digits the keyboard is editing and nothing else. The resend
 * countdown is ticked by the host and handed in as [resendInSeconds], so this file runs no
 * effect, collects no Flow and touches no repository.
 *
 * @param resendInSeconds seconds until "Resend code" becomes tappable; 0 means tappable now.
 *   The host restarts it at 24 each time a new verification id arrives.
 */
@Composable
fun VerifyScreen(
    dialCode: String,
    national: String,
    onBack: () -> Unit,
    onChangeNumber: () -> Unit,
    onResend: () -> Unit,
    onVerify: (code: String) -> Unit,
    modifier: Modifier = Modifier,
    resendInSeconds: Int = 0,
    verifying: Boolean = false,
    errorMessage: String? = null,
) {
    var code by rememberSaveable { mutableStateOf("") }
    val canVerify = remember(code) { PhoneNumber.isValidSmsCode(code) }

    HsScreen(modifier = modifier.imePadding()) {
        Spacer(Modifier.height(70.dp))
        BackBar(onBack = onBack)
        Spacer(Modifier.height(28.dp))

        Text("Enter the code", style = HsType.ScreenTitle, color = Hs.TextPrimary)
        Spacer(Modifier.height(12.dp))
        Text(
            "Sent to ${PhoneNumber.display(dialCode, national)}.",
            style = HsType.Body,
            color = Hs.TextSecondary,
        )
        Text(
            "Change number",
            style = HsType.Body,
            color = Hs.Go,
            modifier = Modifier
                .height(44.dp)
                .clickable(onClick = onChangeNumber),
        )

        Spacer(Modifier.height(32.dp))
        CodeInput(value = code, onValueChange = { code = it }, digitsOnly = true)

        Spacer(Modifier.height(20.dp))
        Text(
            if (resendInSeconds > 0) "Resend in ${formatCountdown(resendInSeconds)}" else "Resend code",
            style = HsType.Small.copy(fontFeatureSettings = TABULAR),
            color = if (resendInSeconds > 0) Hs.TextTertiary else Hs.Go,
            textAlign = TextAlign.Center,
            modifier = Modifier
                .fillMaxWidth()
                .height(44.dp)
                .clickable(enabled = resendInSeconds == 0, onClick = onResend),
        )

        if (BuildConfig.DEBUG && HeadstartConfig.useLocalEmulators) {
            Spacer(Modifier.height(10.dp))
            EmulatorCodeHint()
        }

        if (errorMessage != null) {
            Spacer(Modifier.height(14.dp))
            Text(errorMessage, style = HsType.Small, color = Hs.Delayed)
        }

        Spacer(Modifier.weight(1f))
        PrimaryButton(
            text = if (verifying) "Verifying…" else "Verify",
            enabled = canVerify && !verifying,
            onClick = { onVerify(code) },
        )
        Spacer(Modifier.height(38.dp))
    }
}

/**
 * Debug-only. Release builds never render this: [BuildConfig.DEBUG] is false and
 * [HeadstartConfig.useLocalEmulators] is gated on it as well.
 */
@Composable
private fun EmulatorCodeHint() {
    val shape = RoundedCornerShape(12.dp)
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clip(shape)
            .background(Hs.Card)
            .border(1.dp, Hs.Line, shape)
            .padding(horizontal = 14.dp, vertical = 12.dp),
    ) {
        Text("DEBUG · AUTH EMULATOR", style = HsType.SectionLabel, color = Hs.Headstart)
        Spacer(Modifier.height(6.dp))
        Text(
            "No SMS is sent. Read the code on the host with:",
            style = HsType.Caption,
            color = Hs.TextSecondary,
        )
        Spacer(Modifier.height(4.dp))
        Text(
            "curl http://127.0.0.1:${HeadstartConfig.AUTH_PORT}" +
                "/emulator/v1/projects/$EMULATOR_PROJECT_ID/verificationCodes",
            style = HsType.Caption.copy(fontFeatureSettings = TABULAR),
            color = Hs.TextPrimary,
        )
    }
}

@Preview(name = "Verify", widthDp = 390, heightDp = 844, backgroundColor = 0xFF15171B, showBackground = true)
@Composable
private fun PreviewVerify() {
    HeadstartTheme {
        VerifyScreen(
            dialCode = "+880",
            national = "1712345678",
            onBack = {},
            onChangeNumber = {},
            onResend = {},
            onVerify = {},
            resendInSeconds = 24,
        )
    }
}

@Preview(name = "Verify — resend ready, error", widthDp = 390, heightDp = 844, backgroundColor = 0xFF15171B, showBackground = true)
@Composable
private fun PreviewVerifyError() {
    HeadstartTheme {
        VerifyScreen(
            dialCode = "+880",
            national = "1712345678",
            onBack = {},
            onChangeNumber = {},
            onResend = {},
            onVerify = {},
            resendInSeconds = 0,
            errorMessage = "That code was not right. Check the six digits and try again.",
        )
    }
}

@Preview(name = "Verify — box (embedded)", widthDp = 390, heightDp = 200, backgroundColor = 0xFF15171B, showBackground = true)
@Composable
private fun PreviewEmulatorHint() {
    HeadstartTheme {
        Box(Modifier.background(Hs.Base).padding(26.dp)) { EmulatorCodeHint() }
    }
}
