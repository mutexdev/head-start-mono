package app.headstart.ui.driver

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ErrorOutline
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import app.headstart.ui.components.DestructiveButton
import app.headstart.ui.components.PrimaryButton
import app.headstart.ui.theme.HeadstartTheme
import app.headstart.ui.theme.Hs
import app.headstart.ui.theme.HsType

/**
 * DriverNudge.dc.html.
 *
 * Raised by `NudgeBus.showDidYouLeave`, which `push/Notifications.deliver` sets when a
 * `didYouLeave` push lands — the one kind that has a screen as well as a notification. The
 * host collects that flow and calls `NudgeBus.clear()` from [onDismiss]; this file holds
 * no state of its own so it can be previewed and re-shown freely.
 *
 * There is no "tell them" action here on purpose: the receiver has not been told anything
 * is wrong, and the last line says so.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun DriverNudgeSheet(
    partnerName: String,
    onDismiss: () -> Unit,
    onOnMyWay: () -> Unit,
    onCancelTrip: () -> Unit,
) {
    val state = rememberModalBottomSheetState(skipPartiallyExpanded = true)

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = state,
        containerColor = Hs.Card,
        contentColor = Hs.TextPrimary,
        shape = RoundedCornerShape(topStart = 26.dp, topEnd = 26.dp),
        scrimColor = Hs.Base.copy(alpha = 0.72f),
    ) {
        Column(Modifier.padding(start = 26.dp, end = 26.dp, bottom = 40.dp)) {
            Box(
                modifier = Modifier
                    .size(52.dp)
                    .clip(RoundedCornerShape(15.dp))
                    .background(Hs.HeadstartWashStrong),
                contentAlignment = Alignment.Center,
            ) {
                Icon(
                    Icons.Filled.ErrorOutline,
                    contentDescription = null,
                    tint = Hs.Headstart,
                    modifier = Modifier.size(26.dp),
                )
            }

            Spacer(Modifier.height(22.dp))
            Text("Did you actually leave?", style = HsType.SheetTitle, color = Hs.TextPrimary)
            Spacer(Modifier.height(11.dp))
            Text(
                "You tapped \"I'm coming\" three minutes ago but haven't moved. " +
                    "$partnerName is counting on this being real.",
                style = HsType.Body,
                color = Hs.TextSecondary,
            )

            Spacer(Modifier.height(22.dp))
            PrimaryButton("I'm on my way now", onClick = onOnMyWay)
            Spacer(Modifier.height(11.dp))
            DestructiveButton("Cancel the trip", onClick = onCancelTrip, filled = true)

            Spacer(Modifier.height(22.dp))
            Text(
                "$partnerName hasn't been told anything is wrong.",
                style = HsType.Caption,
                color = Hs.TextTertiary,
                textAlign = TextAlign.Center,
                modifier = Modifier.fillMaxWidth(),
            )
        }
    }
}

@Preview(name = "DriverNudge", widthDp = 390, heightDp = 844, backgroundColor = 0xFF15171B, showBackground = true)
@Composable
private fun PreviewDriverNudge() {
    HeadstartTheme {
        DriverNudgeSheet(
            partnerName = "Sara",
            onDismiss = {},
            onOnMyWay = {},
            onCancelTrip = {},
        )
    }
}
