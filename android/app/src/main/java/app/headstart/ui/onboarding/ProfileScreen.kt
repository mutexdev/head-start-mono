package app.headstart.ui.onboarding

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.LocationOn
import androidx.compose.material.icons.filled.Notifications
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import app.headstart.ui.components.BackBar
import app.headstart.ui.components.HsCard
import app.headstart.ui.components.HsScreen
import app.headstart.ui.components.HsTextField
import app.headstart.ui.components.PrimaryButton
import app.headstart.ui.theme.HeadstartTheme
import app.headstart.ui.theme.Hs
import app.headstart.ui.theme.HsType

/** Longest display name we let a user type; the alert copy has to fit it. */
private const val MAX_DISPLAY_NAME = 24

/**
 * `design/Profile.dc.html`.
 *
 * The two permissions are primed here in the app's own words *before* the OS prompt appears.
 * The actual `requestPermissions` call is wired by batch and7 and handed in as
 * [onAllowAndContinue] — this file asks for nothing itself.
 *
 * The location copy ("Never in the background otherwise") is the artboard's exact wording and
 * is load-bearing: it is the promise that lets Headstart ship without
 * `ACCESS_BACKGROUND_LOCATION`. Do not soften it.
 */
@Composable
fun ProfileScreen(
    onBack: () -> Unit,
    onAllowAndContinue: (displayName: String) -> Unit,
    modifier: Modifier = Modifier,
    initialName: String = "",
    saving: Boolean = false,
    errorMessage: String? = null,
) {
    var name by rememberSaveable { mutableStateOf(initialName) }

    HsScreen(modifier = modifier.imePadding()) {
        Spacer(Modifier.height(70.dp))
        BackBar(onBack = onBack)
        Spacer(Modifier.height(24.dp))

        Text("Two last things", style = HsType.ScreenTitle, color = Hs.TextPrimary)
        Spacer(Modifier.height(12.dp))
        Text(
            "Your name shows up in every alert the other person gets.",
            style = HsType.Body,
            color = Hs.TextSecondary,
        )

        Spacer(Modifier.height(28.dp))
        HsTextField(
            value = name,
            onValueChange = { name = it.take(MAX_DISPLAY_NAME) },
            placeholder = "Your name",
            autoFocus = true,
        )

        Spacer(Modifier.height(32.dp))
        HsCard {
            Column(Modifier.padding(20.dp)) {
                PermissionRow(
                    icon = Icons.Filled.LocationOn,
                    tint = Hs.Go,
                    title = "Location, only during a trip",
                    body = "Starts when you tap \"I'm coming\", stops the second you arrive. " +
                        "Never in the background otherwise.",
                )
                Spacer(Modifier.height(14.dp))
                Box(Modifier.fillMaxWidth().height(1.dp).background(Hs.Line))
                Spacer(Modifier.height(14.dp))
                PermissionRow(
                    icon = Icons.Filled.Notifications,
                    tint = Hs.Headstart,
                    title = "Notifications",
                    body = "Without these the walk-out alert can't reach you — it's the whole point.",
                )
            }
        }

        if (errorMessage != null) {
            Spacer(Modifier.height(14.dp))
            Text(errorMessage, style = HsType.Small, color = Hs.Delayed)
        }

        Spacer(Modifier.weight(1f))
        PrimaryButton(
            text = if (saving) "Saving…" else "Allow and continue",
            enabled = name.trim().length >= 2 && !saving,
            onClick = { onAllowAndContinue(name.trim()) },
        )
        Spacer(Modifier.height(38.dp))
    }
}

@Composable
private fun PermissionRow(icon: ImageVector, tint: Color, title: String, body: String) {
    Row(verticalAlignment = Alignment.Top) {
        Box(
            modifier = Modifier.size(38.dp).clip(RoundedCornerShape(11.dp)).background(Hs.Raised),
            contentAlignment = Alignment.Center,
        ) {
            Icon(icon, contentDescription = null, tint = tint, modifier = Modifier.size(20.dp))
        }
        Spacer(Modifier.width(14.dp))
        Column {
            Text(title, style = HsType.BodyStrong, color = Hs.TextPrimary)
            Spacer(Modifier.height(4.dp))
            Text(body, style = HsType.Small, color = Hs.TextSecondary)
        }
    }
}

@Preview(name = "Profile — empty", widthDp = 390, heightDp = 844, backgroundColor = 0xFF15171B, showBackground = true)
@Composable
private fun PreviewProfileEmpty() {
    HeadstartTheme {
        ProfileScreen(onBack = {}, onAllowAndContinue = {})
    }
}

@Preview(name = "Profile — filled", widthDp = 390, heightDp = 844, backgroundColor = 0xFF15171B, showBackground = true)
@Composable
private fun PreviewProfileFilled() {
    HeadstartTheme {
        ProfileScreen(onBack = {}, onAllowAndContinue = {}, initialName = "Mostafi")
    }
}
