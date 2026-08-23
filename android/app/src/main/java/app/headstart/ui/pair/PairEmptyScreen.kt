package app.headstart.ui.pair

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Dialpad
import androidx.compose.material.icons.filled.People
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import app.headstart.ui.components.HsCard
import app.headstart.ui.components.HsScreen
import app.headstart.ui.components.PrivacyNote
import app.headstart.ui.components.RowChevron
import app.headstart.ui.theme.HeadstartTheme
import app.headstart.ui.theme.Hs
import app.headstart.ui.theme.HsType

/**
 * `design/PairEmpty.dc.html`, minus QR.
 *
 * QR pairing is M4 (spec §11), so the artboard's "Send a code, link or QR" subtitle reads
 * "Send a code or a link" here — the screen must not promise a capability M1 does not ship.
 * Stateless: two lambdas, no state at all.
 */
@Composable
fun PairEmptyScreen(
    onInvite: () -> Unit,
    onEnterCode: () -> Unit,
    modifier: Modifier = Modifier,
) {
    HsScreen(modifier = modifier) {
        Spacer(Modifier.height(78.dp))
        Spacer(Modifier.height(64.dp))

        Box(
            modifier = Modifier
                .size(78.dp)
                .clip(RoundedCornerShape(22.dp))
                .background(Hs.Card),
            contentAlignment = Alignment.Center,
        ) {
            Icon(
                Icons.Filled.People,
                contentDescription = null,
                tint = Hs.Go,
                modifier = Modifier.size(38.dp),
            )
        }

        Spacer(Modifier.height(26.dp))
        Text("Pair with one person", style = HsType.ScreenTitle, color = Hs.TextPrimary)
        Spacer(Modifier.height(12.dp))
        Text(
            "Headstart works between two people at a time. Either of you can be the one driving.",
            style = HsType.Body,
            color = Hs.TextSecondary,
        )

        Spacer(Modifier.height(38.dp))
        ChoiceRow(
            icon = Icons.Filled.Add,
            iconBackground = Hs.Go,
            iconTint = Hs.InkOnGo,
            title = "Invite someone",
            subtitle = "Send a code or a link",
            onClick = onInvite,
        )
        Spacer(Modifier.height(12.dp))
        ChoiceRow(
            icon = Icons.Filled.Dialpad,
            iconBackground = Hs.Raised,
            iconTint = Hs.TextSecondary,
            title = "Enter a code",
            subtitle = "Someone already invited you",
            onClick = onEnterCode,
        )

        Spacer(Modifier.weight(1f))
        PrivacyNote("Either of you can unpair at any moment, from either phone.")
        Spacer(Modifier.height(44.dp))
    }
}

@Composable
private fun ChoiceRow(
    icon: ImageVector,
    iconBackground: Color,
    iconTint: Color,
    title: String,
    subtitle: String,
    onClick: () -> Unit,
) {
    HsCard(onClick = onClick) {
        Row(
            modifier = Modifier.padding(20.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Box(
                modifier = Modifier
                    .size(44.dp)
                    .clip(RoundedCornerShape(12.dp))
                    .background(iconBackground),
                contentAlignment = Alignment.Center,
            ) {
                Icon(icon, contentDescription = null, tint = iconTint, modifier = Modifier.size(22.dp))
            }
            Spacer(Modifier.width(16.dp))
            Column(Modifier.weight(1f)) {
                Text(title, style = HsType.ListTitle, color = Hs.TextPrimary)
                Spacer(Modifier.height(3.dp))
                Text(subtitle, style = HsType.Small, color = Hs.TextSecondary)
            }
            RowChevron()
        }
    }
}

@Preview(name = "PairEmpty", widthDp = 390, heightDp = 844, backgroundColor = 0xFF15171B, showBackground = true)
@Composable
private fun PreviewPairEmpty() {
    HeadstartTheme {
        PairEmptyScreen(onInvite = {}, onEnterCode = {})
    }
}
