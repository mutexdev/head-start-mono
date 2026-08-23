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
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.DirectionsCar
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import app.headstart.Role
import app.headstart.data.Spot
import app.headstart.ui.components.HsCard
import app.headstart.ui.components.HsScreen
import app.headstart.ui.components.PrivacyNote
import app.headstart.ui.components.RoleSwitch
import app.headstart.ui.components.RowChevron
import app.headstart.ui.components.SectionLabel
import app.headstart.ui.theme.HeadstartTheme
import app.headstart.ui.theme.Hs
import app.headstart.ui.theme.HsType

/**
 * DriverHome.dc.html. Stateless: the nav host (Task 20) supplies the data and performs the
 * `startTrip` call behind [onStart].
 *
 * Every spot is startable in one tap. The first one — the spot the receiver armed, if they
 * armed one — gets the big green card; the rest are 56 dp "I'm coming" rows, which is the
 * contract's control height. Opening a spot for editing is the 44 dp chevron on the right,
 * a separate target, so a mis-tap starts a trip rather than losing one.
 */
@Composable
fun DriverHomeScreen(
    greeting: String,
    driverName: String,
    partnerName: String,
    spots: List<Spot>,
    /** Name of the spot the receiver armed, if they asked for a ping. */
    armedSpotName: String?,
    role: Role,
    starting: Boolean,
    error: String?,
    onRoleChange: (Role) -> Unit,
    onStart: (Spot) -> Unit,
    onOpenSpot: (Spot) -> Unit,
    onManageSpots: () -> Unit,
    onSettings: () -> Unit,
) {
    val primary = spots.firstOrNull { it.name == armedSpotName } ?: spots.firstOrNull()
    val others = spots.filter { it.id != primary?.id }

    HsScreen(modifier = Modifier.verticalScroll(rememberScrollState())) {
        Spacer(Modifier.height(78.dp))

        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.SpaceBetween,
        ) {
            Column(Modifier.weight(1f)) {
                Text(
                    greeting,
                    style = HsType.SmallStrong.copy(fontWeight = FontWeight.Normal),
                    color = Hs.TextTertiary,
                )
                Spacer(Modifier.height(4.dp))
                Text("Where to, $driverName?", style = HsType.HomeTitle, color = Hs.TextPrimary)
            }
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

        Spacer(Modifier.height(16.dp))
        RoleSwitch(role = role, onRoleChange = onRoleChange)

        if (armedSpotName != null) {
            Spacer(Modifier.height(20.dp))
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .clip(RoundedCornerShape(16.dp))
                    .background(Hs.HeadstartWash)
                    .border(1.dp, Hs.HeadstartBorder, RoundedCornerShape(16.dp))
                    .padding(horizontal = 18.dp, vertical = 16.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Box(Modifier.size(8.dp).clip(CircleShape).background(Hs.Headstart))
                Spacer(Modifier.width(14.dp))
                Text(
                    buildAnnotatedString {
                        append("$partnerName is waiting at ")
                        withStyle(SpanStyle(fontWeight = FontWeight.SemiBold)) { append(armedSpotName) }
                        append(" — they asked for a ping when you leave.")
                    },
                    style = HsType.SmallStrong.copy(fontWeight = FontWeight.Normal),
                    color = Hs.TextPrimary,
                )
            }
        }

        Spacer(Modifier.height(22.dp))

        if (primary == null) {
            HsCard(radius = 22.dp, onClick = onManageSpots) {
                Column(Modifier.padding(horizontal = 24.dp, vertical = 26.dp)) {
                    Text("Add a pickup spot", style = HsType.CardHeadline, color = Hs.TextPrimary)
                    Spacer(Modifier.height(6.dp))
                    Text(
                        "Headstart needs somewhere to drive to before it can tell $partnerName anything.",
                        style = HsType.Body,
                        color = Hs.TextSecondary,
                    )
                }
            }
        } else {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .clip(RoundedCornerShape(22.dp))
                    .background(Hs.Go)
                    .clickable(enabled = !starting) { onStart(primary) }
                    .padding(horizontal = 24.dp, vertical = 26.dp),
            ) {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    SectionLabel("Tap once — that's it", color = Hs.InkOnGo.copy(alpha = 0.62f))
                    Icon(
                        Icons.Filled.DirectionsCar,
                        contentDescription = null,
                        tint = Hs.InkOnGo.copy(alpha = 0.62f),
                        modifier = Modifier.size(26.dp),
                    )
                }
                Spacer(Modifier.height(22.dp))
                Text(
                    if (starting) "Starting…" else "I'm coming",
                    style = HsType.CardHeadline,
                    color = Hs.InkOnGo,
                )
                Spacer(Modifier.height(6.dp))
                Text(
                    "to ${primary.name} — $partnerName gets ${primary.leadTimeMin} min",
                    style = HsType.CardTitle.copy(fontWeight = FontWeight.Medium),
                    color = Hs.InkOnGo.copy(alpha = 0.72f),
                )
            }
        }

        if (error != null) {
            Spacer(Modifier.height(16.dp))
            Text(error, style = HsType.Small, color = Hs.Delayed)
        }

        if (others.isNotEmpty()) {
            Spacer(Modifier.height(24.dp))
            SectionLabel("Other spots")
            Spacer(Modifier.height(12.dp))
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                for (spot in others) {
                    OtherSpotRow(
                        spot = spot,
                        partnerName = partnerName,
                        enabled = !starting,
                        onStart = { onStart(spot) },
                        onOpen = { onOpenSpot(spot) },
                    )
                }
            }
        }

        Spacer(Modifier.height(28.dp))
        PrivacyNote("Nothing is shared until you tap", centered = true)
        Spacer(Modifier.height(44.dp))
    }
}

/** 56 dp — the contract's height for a primary control — and the whole row starts the trip. */
@Composable
private fun OtherSpotRow(
    spot: Spot,
    partnerName: String,
    enabled: Boolean,
    onStart: () -> Unit,
    onOpen: () -> Unit,
) {
    val shape = RoundedCornerShape(14.dp)
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .heightIn(min = 56.dp)
            .clip(shape)
            .background(Hs.Card)
            .border(1.dp, Hs.Line, shape)
            .clickable(enabled = enabled, onClick = onStart)
            .padding(start = 18.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(Modifier.weight(1f).padding(vertical = 8.dp)) {
            Text("I'm coming → ${spot.name}", style = HsType.BodyStrong, color = Hs.TextPrimary)
            Spacer(Modifier.height(2.dp))
            Text(
                "$partnerName gets ${spot.leadTimeMin} min",
                style = HsType.Caption,
                color = Hs.TextTertiary,
            )
        }
        Box(
            modifier = Modifier
                .size(44.dp)
                .clip(CircleShape)
                .clickable(onClick = onOpen),
            contentAlignment = Alignment.Center,
        ) {
            RowChevron()
        }
        Spacer(Modifier.width(4.dp))
    }
}

@Preview(name = "DriverHome", widthDp = 390, heightDp = 844, backgroundColor = 0xFF15171B, showBackground = true)
@Composable
private fun PreviewDriverHome() {
    HeadstartTheme {
        DriverHomeScreen(
            greeting = "Tuesday evening",
            driverName = "Mostafi",
            partnerName = "Sara",
            spots = listOf(
                Spot("s1", "p1", "Sara's office", 23.79, 90.41, 100, 3, "uidA"),
                Spot("s2", "p1", "The gym", 23.80, 90.42, 150, 5, "uidA"),
                Spot("s3", "p1", "Her mum's", 23.81, 90.43, 100, 8, "uidA"),
            ),
            armedSpotName = "Sara's office",
            role = Role.DRIVING,
            starting = false,
            error = null,
            onRoleChange = {},
            onStart = {},
            onOpenSpot = {},
            onManageSpots = {},
            onSettings = {},
        )
    }
}

@Preview(name = "DriverHome — no spots", widthDp = 390, heightDp = 844, backgroundColor = 0xFF15171B, showBackground = true)
@Composable
private fun PreviewDriverHomeEmpty() {
    HeadstartTheme {
        DriverHomeScreen(
            greeting = "Monday morning",
            driverName = "Mostafi",
            partnerName = "Sara",
            spots = emptyList(),
            armedSpotName = null,
            role = Role.DRIVING,
            starting = false,
            error = null,
            onRoleChange = {},
            onStart = {},
            onOpenSpot = {},
            onManageSpots = {},
            onSettings = {},
        )
    }
}
