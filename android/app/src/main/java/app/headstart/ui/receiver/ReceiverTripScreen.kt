package app.headstart.ui.receiver

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.DirectionsCar
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import app.headstart.core.arrivalClock
import app.headstart.core.clockAt
import app.headstart.core.formatCountdown
import app.headstart.data.Bands
import app.headstart.data.Eta
import app.headstart.data.ReceiverView
import app.headstart.data.Trip
import app.headstart.data.TripAlerts
import app.headstart.ui.components.HsCard
import app.headstart.ui.components.HsChip
import app.headstart.ui.components.HsTextField
import app.headstart.ui.components.SectionLabel
import app.headstart.ui.components.StylizedMapPanel
import app.headstart.ui.theme.HeadstartTheme
import app.headstart.ui.theme.Hs
import app.headstart.ui.theme.HsType
import java.time.ZoneId
import kotlinx.coroutines.delay

/**
 * ReceiverTrip.dc.html.
 *
 * PRIVACY IS STRUCTURAL HERE (addendum §H). Everything on this screen comes from
 * `trip.receiverView`, which carries an ETA and a 0–100 progress figure and nothing else —
 * `app.headstart.data.ReceiverView` has no position field for this file to read even by
 * mistake, and `tripFrom` never decodes the driver's last position from any part of the
 * trip document. Fuzzy mode is a server decision; the client has nothing to leak.
 *
 * The addendum enforces that with a grep for the driver-position field name over this
 * directory, which must return nothing — so the name itself is deliberately not written
 * anywhere in `ui/receiver/`, comments included.
 *
 * The four quick replies are exactly the contract's `sendReply` kinds:
 * `fiveMore`, `takeYourTime`, `atSpot`, `custom`. "Running late" is deliberately absent —
 * that is the driver's `setRunningLate` callable, not a reply (addendum §B).
 */
@Composable
fun ReceiverTripScreen(
    trip: Trip,
    partnerName: String,
    sending: Boolean,
    error: String?,
    onReply: (kind: String, text: String?) -> Unit,
    nowMs: Long = System.currentTimeMillis(),
    zone: ZoneId = ZoneId.systemDefault(),
) {
    val view = trip.receiverView
    val etaSeconds = view?.etaSeconds ?: trip.eta?.seconds ?: 0
    val progress = clampProgressPct(view?.progressPct ?: 0)

    // The server refreshes receiverView every few seconds; between updates we tick locally,
    // never past what the server last said — headstartSecondsLeft clamps at zero.
    var elapsed by remember(view?.etaSeconds) { mutableIntStateOf(0) }
    LaunchedEffect(view?.etaSeconds) {
        elapsed = 0
        while (true) {
            delay(1_000)
            elapsed += 1
        }
    }
    val secondsLeft = headstartSecondsLeft(etaSeconds, trip.leadTimeMin, elapsed)
    val walkOut = isWalkOutNow(secondsLeft)
    var composing by remember { mutableStateOf(false) }

    Column(modifier = Modifier.fillMaxSize().background(Hs.Base)) {
        Box {
            StylizedMapPanel(
                height = 300.dp,
                showRadius = false,
                // A dot on a fixed diagonal at the server's own progress figure. It is not
                // a location: there is no location on this screen to draw.
                driverProgress = progress / 100f,
            )
            Row(
                modifier = Modifier
                    .padding(start = 26.dp, top = 70.dp)
                    .height(36.dp)
                    .clip(RoundedCornerShape(18.dp))
                    .background(Hs.Base.copy(alpha = 0.86f))
                    .border(1.dp, Hs.Line, RoundedCornerShape(18.dp))
                    .padding(horizontal = 14.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Box(Modifier.size(7.dp).clip(CircleShape).background(Hs.Go))
                Spacer(Modifier.width(9.dp))
                Text("$partnerName is driving", style = HsType.Caption, color = Hs.TextPrimary)
            }
        }

        Column(Modifier.padding(horizontal = 26.dp).weight(1f)) {
            Spacer(Modifier.height(20.dp))
            SectionLabel(if (walkOut) "Walk out now" else "Your headstart", color = Hs.Headstart)
            Spacer(Modifier.height(8.dp))
            Row(verticalAlignment = Alignment.Bottom) {
                Text(
                    if (walkOut) "Go" else formatCountdown(secondsLeft),
                    style = HsType.CountdownBig,
                    color = if (walkOut) Hs.Headstart else Hs.TextPrimary,
                    modifier = Modifier.alignByBaseline(),
                )
                Spacer(Modifier.width(11.dp))
                Text(
                    if (walkOut) "start walking" else "until you walk out",
                    style = HsType.CardTitle,
                    color = Hs.TextSecondary,
                    modifier = Modifier.alignByBaseline(),
                )
            }

            Spacer(Modifier.height(18.dp))
            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .height(8.dp)
                    .clip(RoundedCornerShape(4.dp))
                    .background(Hs.Raised),
            ) {
                Box(
                    modifier = Modifier
                        .fillMaxWidth(progress / 100f)
                        .height(8.dp)
                        .clip(RoundedCornerShape(4.dp))
                        .background(Hs.Go),
                )
            }
            Spacer(Modifier.height(10.dp))
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
            ) {
                Text(
                    trip.startedAtMs?.let { "Started ${clockAt(it, zone)}" } ?: "Started",
                    style = HsType.Caption,
                    color = Hs.TextTertiary,
                )
                Text(
                    "Arrives ${arrivalClock(nowMs + elapsed * 1_000L, etaSeconds - elapsed, zone)}",
                    style = HsType.TabularSmall,
                    color = Hs.TextSecondary,
                )
            }

            Spacer(Modifier.height(22.dp))
            HsCard {
                Row(
                    modifier = Modifier.padding(horizontal = 20.dp, vertical = 18.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Box(
                        modifier = Modifier
                            .size(42.dp)
                            .clip(RoundedCornerShape(12.dp))
                            .background(Hs.Raised),
                        contentAlignment = Alignment.Center,
                    ) {
                        Icon(
                            Icons.Filled.DirectionsCar,
                            contentDescription = null,
                            tint = Hs.TextSecondary,
                            modifier = Modifier.size(21.dp),
                        )
                    }
                    Spacer(Modifier.width(15.dp))
                    Column {
                        Text(
                            receiverStatusLine(etaSeconds - elapsed),
                            style = HsType.BodyStrong,
                            color = Hs.TextPrimary,
                        )
                        Spacer(Modifier.height(3.dp))
                        Text(
                            if (trip.eta?.approximate == true) {
                                "ETA is approximate"
                            } else {
                                "on the way to ${trip.spotName}"
                            },
                            style = HsType.Small,
                            color = Hs.TextTertiary,
                        )
                    }
                }
            }

            if (error != null) {
                Spacer(Modifier.height(16.dp))
                Text(error, style = HsType.Small, color = Hs.Delayed)
            }

            Spacer(Modifier.weight(1f))
            SectionLabel("Quick reply")
            Spacer(Modifier.height(12.dp))
            Row(horizontalArrangement = Arrangement.spacedBy(9.dp)) {
                HsChip("5 more min", onClick = { onReply("fiveMore", null) }, enabled = !sending)
                HsChip("Take your time", onClick = { onReply("takeYourTime", null) }, enabled = !sending)
            }
            Spacer(Modifier.height(9.dp))
            Row(horizontalArrangement = Arrangement.spacedBy(9.dp)) {
                HsChip("I'm at ${trip.spotName}", onClick = { onReply("atSpot", null) }, enabled = !sending)
                HsChip("Something else…", onClick = { composing = true }, enabled = !sending)
            }
            Spacer(Modifier.height(38.dp))
        }
    }

    if (composing) {
        CustomReplyDialog(
            onDismiss = { composing = false },
            onSend = { text ->
                composing = false
                onReply("custom", text)
            },
        )
    }
}

/**
 * The fourth contract reply kind. `sendReply` returns `bad-reply` for empty custom text
 * (addendum §O), so Send stays disabled until there is something to send.
 */
@Composable
private fun CustomReplyDialog(onDismiss: () -> Unit, onSend: (String) -> Unit) {
    var text by remember { mutableStateOf("") }
    val trimmed = text.trim()
    AlertDialog(
        onDismissRequest = onDismiss,
        containerColor = Hs.Card,
        titleContentColor = Hs.TextPrimary,
        textContentColor = Hs.TextSecondary,
        title = { Text("Send a message", style = HsType.CardTitle) },
        text = {
            HsTextField(
                value = text,
                onValueChange = { text = it.take(120) },
                placeholder = "Anything you want them to know",
            )
        },
        confirmButton = {
            TextButton(
                onClick = { onSend(trimmed) },
                enabled = trimmed.isNotEmpty(),
            ) {
                Text("Send", color = if (trimmed.isEmpty()) Hs.TextTertiary else Hs.Go)
            }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) { Text("Cancel", color = Hs.TextSecondary) }
        },
    )
}

private const val PREVIEW_NOW = 1_700_000_000_000L

@Preview(name = "ReceiverTrip", widthDp = 390, heightDp = 844, backgroundColor = 0xFF15171B, showBackground = true)
@Composable
private fun PreviewReceiverTrip() {
    HeadstartTheme {
        ReceiverTripScreen(
            trip = Trip(
                id = "t_demo",
                pairId = "p1",
                driverUid = "uidA",
                receiverUid = "uidB",
                spotId = "s1",
                spotName = "the lobby",
                spotLat = 23.79,
                spotLng = 90.41,
                spotRadiusM = 100,
                leadTimeMin = 3,
                state = "driving",
                startedAtMs = PREVIEW_NOW - 300_000,
                eta = Eta(620, PREVIEW_NOW, false),
                bands = Bands(6600.0, 3850.0, 2750.0),
                phaseHint = "far",
                receiverView = ReceiverView(etaSeconds = 620, progressPct = 53),
                alerts = TripAlerts(started = true),
                routePolyline = null,
            ),
            partnerName = "Mostafi",
            sending = false,
            error = null,
            onReply = { _, _ -> },
            nowMs = PREVIEW_NOW,
        )
    }
}
