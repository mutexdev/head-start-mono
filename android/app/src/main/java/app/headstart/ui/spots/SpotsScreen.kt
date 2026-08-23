package app.headstart.ui.spots

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Place
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
import app.headstart.data.Spot
import app.headstart.ui.components.BackBar
import app.headstart.ui.components.HsCard
import app.headstart.ui.components.HsScreen
import app.headstart.ui.components.PrivacyNote
import app.headstart.ui.components.RowChevron
import app.headstart.ui.theme.HeadstartTheme
import app.headstart.ui.theme.Hs
import app.headstart.ui.theme.HsType
import app.headstart.ui.theme.TABULAR

/**
 * `design/Spots.dc.html`.
 *
 * Stateless: the list arrives already sorted from `SpotRepository.spots(pairId)`, which the
 * host collects. [partnerName] must come from `pairInfo.partnerName(myUid)` — never from the
 * other person's user document, and never from a fallback string built here.
 *
 * @param onBack null by default because the artboard has no back control (Spots is a tab-level
 *   destination); pass one to get a 44 dp chevron above the title.
 */
@Composable
fun SpotsScreen(
    spots: List<Spot>,
    partnerName: String,
    onAdd: () -> Unit,
    onOpen: (Spot) -> Unit,
    modifier: Modifier = Modifier,
    onBack: (() -> Unit)? = null,
) {
    HsScreen(modifier = modifier) {
        if (onBack != null) {
            Spacer(Modifier.height(34.dp))
            BackBar(onBack = onBack)
        } else {
            Spacer(Modifier.height(78.dp))
        }

        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.SpaceBetween,
        ) {
            Text("Pickup spots", style = HsType.ScreenTitle, color = Hs.TextPrimary)
            Box(
                modifier = Modifier
                    .size(44.dp)
                    .clip(RoundedCornerShape(14.dp))
                    .background(Hs.Card)
                    .clickable(onClick = onAdd),
                contentAlignment = Alignment.Center,
            ) {
                Icon(
                    Icons.Filled.Add,
                    contentDescription = "Add a spot",
                    tint = Hs.Go,
                    modifier = Modifier.size(22.dp),
                )
            }
        }

        Spacer(Modifier.height(10.dp))
        Text(
            "Each spot remembers how much headstart the person waiting there needs.",
            style = HsType.SmallStrong.copy(fontWeight = FontWeight.Normal),
            color = Hs.TextSecondary,
        )

        Spacer(Modifier.height(26.dp))
        if (spots.isEmpty()) {
            HsCard {
                Column(Modifier.padding(20.dp)) {
                    Text("No spots yet", style = HsType.ListTitle, color = Hs.TextPrimary)
                    Spacer(Modifier.height(4.dp))
                    Text(
                        "Add the place you get picked up from — the office door, the gym, the airport.",
                        style = HsType.Small,
                        color = Hs.TextSecondary,
                    )
                }
            }
            // Exactly one weighted child in this Column, so the footer always sits at the foot.
            Spacer(Modifier.weight(1f))
        } else {
            LazyColumn(
                modifier = Modifier.weight(1f),
                verticalArrangement = Arrangement.spacedBy(12.dp),
                contentPadding = PaddingValues(bottom = 20.dp),
            ) {
                items(spots, key = { it.id }) { spot ->
                    SpotRow(spot = spot, partnerName = partnerName, onClick = { onOpen(spot) })
                }
            }
        }

        PrivacyNote("Whoever waits at a spot sets its headstart — you can't set it for them.")
        Spacer(Modifier.height(44.dp))
    }
}

@Composable
private fun SpotRow(spot: Spot, partnerName: String, onClick: () -> Unit) {
    HsCard(onClick = onClick) {
        Row(
            modifier = Modifier.padding(start = 20.dp, top = 18.dp, end = 18.dp, bottom = 18.dp),
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
                    Icons.Filled.Place,
                    contentDescription = null,
                    tint = Hs.Go,
                    modifier = Modifier.size(21.dp),
                )
            }
            Spacer(Modifier.width(15.dp))
            Column(Modifier.weight(1f)) {
                Text(spot.name, style = HsType.ListTitle, color = Hs.TextPrimary)
                Spacer(Modifier.height(4.dp))
                Text(
                    buildAnnotatedString {
                        append("$partnerName walks out ")
                        withStyle(
                            SpanStyle(
                                color = Hs.Headstart,
                                fontWeight = FontWeight.SemiBold,
                                fontFeatureSettings = TABULAR,
                            ),
                        ) {
                            append("${spot.leadTimeMin} min")
                        }
                        append(" early")
                    },
                    style = HsType.Small,
                    color = Hs.TextSecondary,
                )
            }
            RowChevron()
        }
    }
}

private val previewSpots = listOf(
    Spot(
        id = "s1",
        pairId = "p1",
        name = "Office",
        lat = 23.7806,
        lng = 90.4074,
        radiusM = 100,
        leadTimeMin = 3,
        createdBy = "u1",
    ),
    Spot(
        id = "s2",
        pairId = "p1",
        name = "Gym",
        lat = 23.7512,
        lng = 90.3899,
        radiusM = 50,
        leadTimeMin = 2,
        createdBy = "u1",
    ),
    Spot(
        id = "s3",
        pairId = "p1",
        name = "Airport — arrivals",
        lat = 23.8433,
        lng = 90.3978,
        radiusM = 300,
        leadTimeMin = 8,
        createdBy = "u2",
    ),
)

@Preview(name = "Spots", widthDp = 390, heightDp = 844, backgroundColor = 0xFF15171B, showBackground = true)
@Composable
private fun PreviewSpots() {
    HeadstartTheme {
        SpotsScreen(spots = previewSpots, partnerName = "Sara", onAdd = {}, onOpen = {})
    }
}

@Preview(name = "Spots — empty", widthDp = 390, heightDp = 844, backgroundColor = 0xFF15171B, showBackground = true)
@Composable
private fun PreviewSpotsEmpty() {
    HeadstartTheme {
        SpotsScreen(
            spots = emptyList(),
            partnerName = "Sara",
            onAdd = {},
            onOpen = {},
            onBack = {},
        )
    }
}
