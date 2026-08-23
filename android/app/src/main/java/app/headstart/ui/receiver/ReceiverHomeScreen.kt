package app.headstart.ui.receiver

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
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.Notifications
import androidx.compose.material.icons.filled.Remove
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import app.headstart.Role
import app.headstart.data.Spot
import app.headstart.data.SpotLimits
import app.headstart.ui.components.HsCard
import app.headstart.ui.components.HsScreen
import app.headstart.ui.components.PrivacyNote
import app.headstart.ui.components.RoleSwitch
import app.headstart.ui.components.SectionLabel
import app.headstart.ui.theme.HeadstartTheme
import app.headstart.ui.theme.Hs
import app.headstart.ui.theme.HsType

/**
 * ReceiverHome.dc.html — the idle state. The headstart stepper writes straight through to
 * `upsertSpot` via [onLeadTimeChange], because the person waiting owns that number, and it
 * is clamped to the contract's 1–30 before it ever reaches the callable (addendum §K).
 *
 * [nextSchedule] is always null in M1: schedules are the M3 milestone. The "Coming up"
 * card is written here so M3 only has to supply the string.
 */
@Composable
fun ReceiverHomeScreen(
    partnerName: String,
    spot: Spot?,
    role: Role,
    nextSchedule: String?,
    arming: Boolean,
    armed: Boolean,
    error: String?,
    onRoleChange: (Role) -> Unit,
    onLeadTimeChange: (Int) -> Unit,
    onPingMe: () -> Unit,
    onSettings: () -> Unit,
    onManageSpots: () -> Unit,
) {
    HsScreen(modifier = Modifier.verticalScroll(rememberScrollState())) {
        Spacer(Modifier.height(78.dp))

        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.SpaceBetween,
        ) {
            Text("Nothing on the way", style = HsType.HomeTitle, color = Hs.TextPrimary)
            Box(
                modifier = Modifier
                    .size(44.dp)
                    .clip(CircleShape)
                    .background(Hs.Card)
                    .border(1.dp, Hs.Line, CircleShape)
                    .clickable(onClick = onSettings),
                contentAlignment = Alignment.Center,
            ) {
                Icon(
                    Icons.Filled.Settings,
                    contentDescription = "Settings",
                    tint = Hs.TextSecondary,
                    modifier = Modifier.size(21.dp),
                )
            }
        }

        Spacer(Modifier.height(10.dp))
        Text(
            "You'll get a notification the moment $partnerName starts driving.",
            style = HsType.Body,
            color = Hs.TextSecondary,
        )

        Spacer(Modifier.height(16.dp))
        RoleSwitch(role = role, onRoleChange = onRoleChange)

        Spacer(Modifier.height(20.dp))
        if (spot == null) {
            HsCard(radius = 20.dp, onClick = onManageSpots) {
                Column(Modifier.padding(22.dp)) {
                    Text("No pickup spot yet", style = HsType.CardTitle, color = Hs.TextPrimary)
                    Spacer(Modifier.height(6.dp))
                    Text(
                        "Add the place you wait, and set how long it takes you to get there.",
                        style = HsType.Body,
                        color = Hs.TextSecondary,
                    )
                }
            }
        } else {
            HsCard(radius = 20.dp) {
                Column(Modifier.padding(horizontal = 22.dp, vertical = 24.dp)) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Box(
                            modifier = Modifier
                                .size(44.dp)
                                .clip(RoundedCornerShape(12.dp))
                                .background(Hs.Raised),
                            contentAlignment = Alignment.Center,
                        ) {
                            Icon(
                                Icons.Filled.Home,
                                contentDescription = null,
                                tint = Hs.Go,
                                modifier = Modifier.size(22.dp),
                            )
                        }
                        Spacer(Modifier.width(14.dp))
                        Column(Modifier.weight(1f)) {
                            Text(spot.name, style = HsType.CardTitle, color = Hs.TextPrimary)
                            Spacer(Modifier.height(3.dp))
                            Text("your usual spot", style = HsType.Small, color = Hs.TextTertiary)
                        }
                    }

                    Spacer(Modifier.height(20.dp))
                    Box(Modifier.fillMaxWidth().height(1.dp).background(Hs.Line))
                    Spacer(Modifier.height(20.dp))

                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.SpaceBetween,
                    ) {
                        Column {
                            Text("Your headstart", style = HsType.BodyStrong, color = Hs.TextPrimary)
                            Spacer(Modifier.height(3.dp))
                            Text("desk to curb", style = HsType.Small, color = Hs.TextTertiary)
                        }
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            StepperButton(Icons.Filled.Remove, "One minute less") {
                                onLeadTimeChange(SpotLimits.clampLeadTimeMin(spot.leadTimeMin - 1))
                            }
                            Spacer(Modifier.width(14.dp))
                            Text(
                                buildAnnotatedString {
                                    append("${spot.leadTimeMin}")
                                    withStyle(
                                        SpanStyle(color = Hs.TextSecondary, fontWeight = FontWeight.Medium),
                                    ) {
                                        append(" min")
                                    }
                                },
                                style = HsType.NumberMedium,
                                color = Hs.Headstart,
                            )
                            Spacer(Modifier.width(14.dp))
                            StepperButton(Icons.Filled.Add, "One minute more") {
                                onLeadTimeChange(SpotLimits.clampLeadTimeMin(spot.leadTimeMin + 1))
                            }
                        }
                    }
                }
            }

            Spacer(Modifier.height(16.dp))
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .height(60.dp)
                    .clip(RoundedCornerShape(15.dp))
                    .background(Hs.Raised)
                    .border(1.dp, Hs.Line, RoundedCornerShape(15.dp))
                    .clickable(enabled = !arming && !armed, onClick = onPingMe),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.Center,
            ) {
                Icon(
                    Icons.Filled.Notifications,
                    contentDescription = null,
                    tint = Hs.Go,
                    modifier = Modifier.size(21.dp),
                )
                Spacer(Modifier.width(11.dp))
                Text(
                    when {
                        armed -> "$partnerName has been asked"
                        arming -> "Asking…"
                        else -> "Ping me when $partnerName leaves"
                    },
                    style = HsType.ButtonLabel,
                    color = Hs.TextPrimary,
                )
            }
        }

        if (error != null) {
            Spacer(Modifier.height(16.dp))
            Text(error, style = HsType.Small, color = Hs.Delayed)
        }

        if (nextSchedule != null) {
            Spacer(Modifier.height(28.dp))
            SectionLabel("Coming up")
            Spacer(Modifier.height(12.dp))
            HsCard(radius = 14.dp) {
                Column(Modifier.padding(horizontal = 18.dp, vertical = 16.dp)) {
                    Text(nextSchedule, style = HsType.SmallStrong, color = Hs.TextPrimary)
                    Spacer(Modifier.height(3.dp))
                    Text(
                        "$partnerName gets a reminder to start",
                        style = HsType.Caption,
                        color = Hs.TextTertiary,
                    )
                }
            }
        }

        Spacer(Modifier.height(30.dp))
        PrivacyNote("You can't see where $partnerName is right now", centered = true)
        Spacer(Modifier.height(44.dp))
    }
}

@Composable
private fun StepperButton(
    icon: ImageVector,
    description: String,
    onClick: () -> Unit,
) {
    Box(
        modifier = Modifier
            .size(44.dp)
            .clip(CircleShape)
            .background(Hs.Raised)
            .border(1.dp, Hs.Line, CircleShape)
            .clickable(onClick = onClick),
        contentAlignment = Alignment.Center,
    ) {
        Icon(icon, contentDescription = description, tint = Hs.TextSecondary, modifier = Modifier.size(18.dp))
    }
}

@Preview(name = "ReceiverHome", widthDp = 390, heightDp = 844, backgroundColor = 0xFF15171B, showBackground = true)
@Composable
private fun PreviewReceiverHome() {
    HeadstartTheme {
        ReceiverHomeScreen(
            partnerName = "Mostafi",
            spot = Spot("s1", "p1", "The lobby", 23.79, 90.41, 100, 3, "uidB"),
            role = Role.WAITING,
            nextSchedule = null,
            arming = false,
            armed = false,
            error = null,
            onRoleChange = {},
            onLeadTimeChange = {},
            onPingMe = {},
            onSettings = {},
            onManageSpots = {},
        )
    }
}

@Preview(name = "ReceiverHome — armed", widthDp = 390, heightDp = 844, backgroundColor = 0xFF15171B, showBackground = true)
@Composable
private fun PreviewReceiverHomeArmed() {
    HeadstartTheme {
        ReceiverHomeScreen(
            partnerName = "Mostafi",
            spot = Spot("s1", "p1", "The lobby", 23.79, 90.41, 100, 5, "uidB"),
            role = Role.WAITING,
            nextSchedule = "Tomorrow, 6:15 pm",
            arming = false,
            armed = true,
            error = null,
            onRoleChange = {},
            onLeadTimeChange = {},
            onPingMe = {},
            onSettings = {},
            onManageSpots = {},
        )
    }
}
