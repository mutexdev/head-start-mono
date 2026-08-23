package app.headstart.ui.driver

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import app.headstart.data.Bands
import app.headstart.data.Eta
import app.headstart.data.Reply
import app.headstart.data.Trip
import app.headstart.data.TripAlerts
import app.headstart.data.clampExtraMin
import app.headstart.ui.components.BigEta
import app.headstart.ui.components.HsCard
import app.headstart.ui.components.HsScreen
import app.headstart.ui.components.SectionLabel
import app.headstart.ui.components.SmallAction
import app.headstart.ui.theme.HeadstartTheme
import app.headstart.ui.theme.Hs
import app.headstart.ui.theme.HsType
import java.time.ZoneId

/**
 * DriverTrip.dc.html.
 *
 * The three actions map onto three different callables, and the mapping matters:
 * "Late +5/+10/+15" is `setRunningLate(tripId, extraMin)` clamped to 1–60 (addendum §K) —
 * it is NOT a reply kind (addendum §B) — while "I'm here" is `endTrip(reason="arrived")`
 * and "Cancel" is `endTrip(reason="cancelled")`. Arrival is still the server's decision;
 * this button only tells it the driver says so.
 */
@Composable
fun DriverTripScreen(
    trip: Trip,
    partnerName: String,
    latestReply: Reply?,
    nowMs: Long,
    busy: Boolean,
    error: String?,
    onRunningLate: (Int) -> Unit,
    onCancel: () -> Unit,
    onArrived: () -> Unit,
    zone: ZoneId = ZoneId.systemDefault(),
) {
    val steps = ladderFor(trip, nowMs, zone)

    HsScreen {
        Spacer(Modifier.height(78.dp))

        Row(modifier = Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            Box(Modifier.size(9.dp).clip(CircleShape).background(Hs.Go))
            Spacer(Modifier.width(10.dp))
            Text("SHARING WITH ${partnerName.uppercase()}", style = HsType.StatusLabel, color = Hs.Go)
            Spacer(Modifier.weight(1f))
            Text("ends on arrival", style = HsType.Small, color = Hs.TextTertiary)
        }

        Spacer(Modifier.height(30.dp))
        BigEta(value = driverEtaMinutes(trip), unit = "min away")
        Spacer(Modifier.height(10.dp))
        Text(
            driverArrivalLine(trip, nowMs, zone),
            style = HsType.CardTitle.copy(fontWeight = FontWeight.Normal),
            color = Hs.TextSecondary,
        )

        Spacer(Modifier.height(30.dp))
        Box(Modifier.fillMaxWidth().height(1.dp).background(Hs.Line))
        Spacer(Modifier.height(24.dp))

        SectionLabel("What $partnerName has been told")
        Spacer(Modifier.height(16.dp))
        Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
            for (step in steps) {
                Row(modifier = Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                    when (step.state) {
                        StepState.DONE -> Icon(
                            Icons.Filled.CheckCircle,
                            contentDescription = null,
                            tint = Hs.Go,
                            modifier = Modifier.size(21.dp),
                        )
                        StepState.PENDING -> EmptyRing(Hs.Line)
                        StepState.PENDING_LEAD -> EmptyRing(Hs.HeadstartBorder)
                    }
                    Spacer(Modifier.width(13.dp))
                    Text(
                        buildAnnotatedString {
                            append(step.label)
                            if (step.detail != null) {
                                withStyle(SpanStyle(color = Hs.Headstart)) { append(" · ${step.detail}") }
                            }
                        },
                        style = HsType.BodyStrong.copy(fontWeight = FontWeight.Normal),
                        color = if (step.state == StepState.DONE) Hs.TextPrimary else Hs.TextSecondary,
                        modifier = Modifier.weight(1f),
                    )
                    Text(step.timing, style = HsType.TabularSmall, color = Hs.TextTertiary)
                }
            }
        }

        if (latestReply != null) {
            Spacer(Modifier.height(26.dp))
            HsCard {
                Row(
                    modifier = Modifier.padding(horizontal = 18.dp, vertical = 16.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Box(
                        modifier = Modifier.size(34.dp).clip(CircleShape).background(Hs.Raised),
                        contentAlignment = Alignment.Center,
                    ) {
                        Text(
                            partnerName.take(1).uppercase(),
                            style = HsType.SmallStrong,
                            color = Hs.TextSecondary,
                        )
                    }
                    Spacer(Modifier.width(13.dp))
                    Column {
                        Text(latestReply.displayText, style = HsType.SmallStrong, color = Hs.TextPrimary)
                        Spacer(Modifier.height(2.dp))
                        Text("$partnerName · just now", style = HsType.Caption, color = Hs.TextTertiary)
                    }
                }
            }
        }

        if (error != null) {
            Spacer(Modifier.height(16.dp))
            Text(error, style = HsType.Small, color = Hs.Delayed)
        }

        Spacer(Modifier.weight(1f))
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(9.dp),
        ) {
            SmallAction("Late +5", { onRunningLate(clampExtraMin(5)) }, Modifier.weight(1f))
            SmallAction("+10", { onRunningLate(clampExtraMin(10)) }, Modifier.weight(1f))
            SmallAction("+15", { onRunningLate(clampExtraMin(15)) }, Modifier.weight(1f))
            SmallAction("Cancel", onCancel, Modifier.weight(1f), contentColor = Hs.Delayed)
        }
        Spacer(Modifier.height(12.dp))
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .height(60.dp)
                .clip(RoundedCornerShape(15.dp))
                .background(Hs.Go)
                .clickable(enabled = !busy, onClick = onArrived),
            contentAlignment = Alignment.Center,
        ) {
            Text(
                if (busy) "…" else "I'm here",
                style = HsType.CardTitle.copy(fontWeight = FontWeight.Bold),
                color = Hs.InkOnGo,
            )
        }
        Spacer(Modifier.height(38.dp))
    }
}

@Composable
private fun EmptyRing(color: Color) {
    Box(
        modifier = Modifier
            .size(21.dp)
            .clip(CircleShape)
            .background(Hs.Base)
            .border(2.dp, color, CircleShape),
    )
}

private const val PREVIEW_NOW = 1_700_000_000_000L

internal fun previewTrip(
    etaSec: Int? = 1080,
    alerts: TripAlerts = TripAlerts(started = true),
) = Trip(
    id = "t_demo",
    pairId = "p1",
    driverUid = "uidA",
    receiverUid = "uidB",
    spotId = "s1",
    spotName = "Sara's office",
    spotLat = 23.79,
    spotLng = 90.41,
    spotRadiusM = 100,
    leadTimeMin = 3,
    state = "driving",
    startedAtMs = PREVIEW_NOW - 240_000,
    eta = etaSec?.let { Eta(it, PREVIEW_NOW, false) },
    bands = Bands(6600.0, 3850.0, 2750.0),
    phaseHint = "far",
    receiverView = null,
    alerts = alerts,
    routePolyline = null,
)

@Preview(name = "DriverTrip", widthDp = 390, heightDp = 844, backgroundColor = 0xFF15171B, showBackground = true)
@Composable
private fun PreviewDriverTrip() {
    HeadstartTheme {
        DriverTripScreen(
            trip = previewTrip(),
            partnerName = "Sara",
            latestReply = Reply("r1", "uidB", "fiveMore", null, PREVIEW_NOW),
            nowMs = PREVIEW_NOW,
            busy = false,
            error = null,
            onRunningLate = {},
            onCancel = {},
            onArrived = {},
        )
    }
}

@Preview(name = "DriverTrip — nearly there", widthDp = 390, heightDp = 844, backgroundColor = 0xFF15171B, showBackground = true)
@Composable
private fun PreviewDriverTripLate() {
    HeadstartTheme {
        DriverTripScreen(
            trip = previewTrip(
                etaSec = 150,
                alerts = TripAlerts(started = true, tenMin = true, leadTime = true),
            ),
            partnerName = "Sara",
            latestReply = null,
            nowMs = PREVIEW_NOW,
            busy = false,
            error = null,
            onRunningLate = {},
            onCancel = {},
            onArrived = {},
        )
    }
}
