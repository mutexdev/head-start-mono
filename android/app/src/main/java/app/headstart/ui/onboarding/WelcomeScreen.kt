package app.headstart.ui.onboarding

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.headstart.ui.components.HsScreen
import app.headstart.ui.components.PrimaryButton
import app.headstart.ui.components.SecondaryButton
import app.headstart.ui.theme.HeadstartTheme
import app.headstart.ui.theme.Hs
import app.headstart.ui.theme.HsType

/**
 * `design/Welcome.dc.html`.
 *
 * Stateless: data in, lambdas out. The nav graph and `AppViewModel` (batch and7) own every
 * decision this screen can trigger — nothing here touches a repository, a ViewModel or a Flow.
 */
@Composable
fun WelcomeScreen(
    onGetStarted: () -> Unit,
    onHaveInviteCode: () -> Unit,
    modifier: Modifier = Modifier,
) {
    HsScreen(modifier = modifier) {
        Spacer(Modifier.height(78.dp))

        Row(verticalAlignment = Alignment.CenterVertically) {
            Box(
                modifier = Modifier.size(30.dp).clip(CircleShape).background(Hs.Go.copy(alpha = 0.18f)),
                contentAlignment = Alignment.Center,
            ) {
                Box(Modifier.size(11.dp).clip(CircleShape).background(Hs.Go))
            }
            Spacer(Modifier.width(11.dp))
            Text(
                "Headstart",
                style = HsType.CardTitle.copy(
                    fontSize = 21.sp,
                    fontWeight = FontWeight.Bold,
                    letterSpacing = (-0.6).sp,
                ),
                color = Hs.TextPrimary,
            )
        }

        Spacer(Modifier.height(52.dp))
        Text("Know exactly\nwhen to walk out.", style = HsType.Hero, color = Hs.TextPrimary)
        Spacer(Modifier.height(18.dp))
        Text(
            "Your ride tells you when to leave the building — down to the minute you asked for.",
            style = HsType.Body,
            color = Hs.TextSecondary,
        )

        Spacer(Modifier.height(44.dp))
        LadderRow(
            dotColor = Hs.Go,
            title = "Mostafi started driving",
            subtitle = "ETA 22 min to Office",
            showConnector = true,
        )
        LadderRow(
            dotColor = Hs.Go,
            title = "10 minutes away",
            subtitle = "wrap up what you're doing",
            showConnector = true,
        )
        LadderRow(
            dotColor = Hs.Headstart,
            title = "Start walking now",
            subtitle = "the 3 minutes you asked for",
            showConnector = true,
            emphasise = true,
        )
        LadderRow(
            dotColor = Hs.Line,
            title = "Arrived — tracking stops",
            subtitle = null,
            showConnector = false,
            dim = true,
        )

        Spacer(Modifier.weight(1f))
        PrimaryButton("Get started", onClick = onGetStarted)
        Spacer(Modifier.height(12.dp))
        SecondaryButton("I have an invite code", onClick = onHaveInviteCode)
        Spacer(Modifier.height(38.dp))
    }
}

@Composable
private fun LadderRow(
    dotColor: Color,
    title: String,
    subtitle: String?,
    showConnector: Boolean,
    emphasise: Boolean = false,
    dim: Boolean = false,
) {
    Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.Start) {
        Column(
            modifier = Modifier.width(14.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Spacer(Modifier.height(if (emphasise) 3.dp else 5.dp))
            Box(
                Modifier
                    .size(if (emphasise) 15.dp else 11.dp)
                    .clip(CircleShape)
                    .background(dotColor),
            )
            if (showConnector) {
                Box(Modifier.width(2.dp).height(46.dp).background(Hs.Line))
            }
        }
        Spacer(Modifier.width(16.dp))
        Column {
            Text(
                title,
                style = if (emphasise) HsType.CardTitle else HsType.BodyStrong,
                color = when {
                    emphasise -> Hs.Headstart
                    dim -> Hs.TextTertiary
                    else -> Hs.TextPrimary
                },
            )
            if (subtitle != null) {
                Spacer(Modifier.height(3.dp))
                Text(
                    subtitle,
                    style = HsType.Small,
                    color = if (emphasise) Hs.TextSecondary else Hs.TextTertiary,
                )
            }
            Spacer(Modifier.height(22.dp))
        }
    }
}

@Preview(name = "Welcome", widthDp = 390, heightDp = 844, backgroundColor = 0xFF15171B, showBackground = true)
@Composable
private fun PreviewWelcome() {
    HeadstartTheme {
        WelcomeScreen(onGetStarted = {}, onHaveInviteCode = {})
    }
}
