package app.headstart.ui.spots

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
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ChevronLeft
import androidx.compose.material3.Icon
import androidx.compose.material3.Slider
import androidx.compose.material3.SliderDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import app.headstart.data.Spot
import app.headstart.data.SpotLimits
import app.headstart.ui.components.DestructiveButton
import app.headstart.ui.components.HsCard
import app.headstart.ui.components.HsTextField
import app.headstart.ui.components.PrimaryButton
import app.headstart.ui.components.SecondaryButton
import app.headstart.ui.components.SectionLabel
import app.headstart.ui.components.StylizedMapPanel
import app.headstart.ui.theme.HeadstartTheme
import app.headstart.ui.theme.Hs
import app.headstart.ui.theme.HsType
import app.headstart.ui.theme.TABULAR

/**
 * A single coordinate handed to [SpotEditScreen] by the host. Deliberately not
 * `android.location.Location` and deliberately not a tracking type: this file must stay
 * previewable and free of Play Services.
 */
data class DeviceLocation(val lat: Double, val lng: Double)

/**
 * `design/SpotEdit.dc.html`. [existing] null creates a spot, otherwise it edits one.
 *
 * **How a spot gets its coordinates in M1:** "Use my current location". There is no draggable
 * pin — the Maps SDK is a second billing surface and a Maps API key that M1 does not have, so
 * the panel at the top is drawn with Compose `Canvas` from the map tokens (`Hs.MapBase`,
 * `Hs.MapRoad`, `Hs.MapMinor`, `Hs.MapBlock`) by `StylizedMapPanel`. It shows the pin and the
 * dashed arrival radius so the screen still reads like the artboard.
 *
 * Stateless: it holds the form the keyboard and the slider are editing, and nothing else.
 * The host (batch and7) asks the fused provider for a fix and pushes it in as
 * [deviceLocation]; a new non-null value seeds the spot. `upsertSpot` and `deleteSpot` are
 * the host's calls — the repository clamps again on the way out, so no slider position can
 * surface a raw callable error.
 *
 * @param partnerName from `pairInfo.partnerName(myUid)`. The copy says the headstart is the
 *   waiter's own value, and the server lets either member write it because either member may
 *   be the one waiting there.
 */
@Composable
fun SpotEditScreen(
    existing: Spot?,
    partnerName: String,
    onBack: () -> Unit,
    onUseCurrentLocation: () -> Unit,
    onSave: (name: String, lat: Double, lng: Double, leadTimeMin: Int, radiusM: Int) -> Unit,
    onDelete: () -> Unit,
    modifier: Modifier = Modifier,
    deviceLocation: DeviceLocation? = null,
    locating: Boolean = false,
    saving: Boolean = false,
    errorMessage: String? = null,
) {
    var name by rememberSaveable(existing?.id) { mutableStateOf(existing?.name.orEmpty()) }
    var leadTimeMin by rememberSaveable(existing?.id) {
        mutableStateOf(existing?.leadTimeMin ?: SpotLimits.DEFAULT_LEAD_MIN)
    }
    var radiusM by rememberSaveable(existing?.id) {
        mutableStateOf(existing?.radiusM ?: SpotLimits.DEFAULT_RADIUS_M)
    }
    var lat by rememberSaveable(existing?.id) { mutableStateOf(existing?.lat) }
    var lng by rememberSaveable(existing?.id) { mutableStateOf(existing?.lng) }

    // The host hands in a fresh fix; the newest one always wins, so tapping
    // "Use my current location" a second time after walking ten metres re-seeds the spot.
    LaunchedEffect(deviceLocation) {
        deviceLocation?.let { lat = it.lat; lng = it.lng }
    }

    val trimmedName = remember(name) { SpotLimits.validName(name) }
    val placed = lat != null && lng != null

    Column(
        modifier = modifier
            .fillMaxWidth()
            .background(Hs.Base)
            .verticalScroll(rememberScrollState())
            .imePadding(),
    ) {
        Box {
            StylizedMapPanel(height = 264.dp, showRadius = true)
            Box(
                modifier = Modifier
                    .padding(start = 22.dp, top = 70.dp)
                    .size(44.dp)
                    .clip(RoundedCornerShape(14.dp))
                    .background(Hs.Base.copy(alpha = 0.82f))
                    .border(1.dp, Hs.Line, RoundedCornerShape(14.dp))
                    .clickable(onClick = onBack),
                contentAlignment = Alignment.Center,
            ) {
                Icon(
                    Icons.Filled.ChevronLeft,
                    contentDescription = "Back",
                    tint = Hs.TextPrimary,
                    modifier = Modifier.size(22.dp),
                )
            }
        }

        Column(Modifier.padding(horizontal = 26.dp)) {
            Spacer(Modifier.height(20.dp))
            SectionLabel("Spot name")
            Spacer(Modifier.height(9.dp))
            HsTextField(
                value = name,
                onValueChange = { name = it.take(SpotLimits.MAX_NAME_LENGTH) },
                placeholder = "Office",
                height = 56.dp,
            )

            Spacer(Modifier.height(22.dp))
            SectionLabel("Location")
            Spacer(Modifier.height(9.dp))
            HsCard {
                Column(Modifier.padding(18.dp)) {
                    Text(
                        if (placed) "%.5f, %.5f".format(lat, lng) else "No location set yet",
                        style = HsType.BodyStrong.copy(fontFeatureSettings = TABULAR),
                        color = if (placed) Hs.TextPrimary else Hs.TextTertiary,
                    )
                    Spacer(Modifier.height(4.dp))
                    Text(
                        "Stand at the pickup point and tap the button below. " +
                            "A draggable map arrives in the next release.",
                        style = HsType.Small,
                        color = Hs.TextSecondary,
                    )
                    Spacer(Modifier.height(14.dp))
                    SecondaryButton(
                        text = if (locating) "Finding you…" else "Use my current location",
                        enabled = !locating,
                        onClick = onUseCurrentLocation,
                    )
                }
            }

            Spacer(Modifier.height(22.dp))
            SectionLabel("Your headstart")
            Spacer(Modifier.height(12.dp))
            Text(
                "How long from your desk to the curb? Only you can change this — " +
                    "$partnerName can't set it for you.",
                style = HsType.Body,
                color = Hs.TextSecondary,
            )
            Spacer(Modifier.height(12.dp))
            HsCard {
                Column(Modifier.padding(horizontal = 20.dp, vertical = 22.dp)) {
                    Row(verticalAlignment = Alignment.Bottom) {
                        Text(
                            "$leadTimeMin",
                            style = HsType.NumberLarge,
                            color = Hs.Headstart,
                            modifier = Modifier.alignByBaseline(),
                        )
                        Spacer(Modifier.size(8.dp))
                        Text(
                            "minutes",
                            style = HsType.CardTitle,
                            color = Hs.TextSecondary,
                            modifier = Modifier.alignByBaseline(),
                        )
                    }
                    Spacer(Modifier.height(18.dp))
                    Slider(
                        value = leadTimeMin.toFloat(),
                        onValueChange = { leadTimeMin = SpotLimits.clampLeadTimeMin(it.toInt()) },
                        valueRange = SpotLimits.MIN_LEAD_MIN.toFloat()..
                            SpotLimits.SLIDER_MAX_LEAD_MIN.toFloat(),
                        steps = SpotLimits.SLIDER_MAX_LEAD_MIN - SpotLimits.MIN_LEAD_MIN - 1,
                        colors = SliderDefaults.colors(
                            thumbColor = Hs.Headstart,
                            activeTrackColor = Hs.Headstart,
                            inactiveTrackColor = Hs.Line,
                            activeTickColor = Hs.Headstart,
                            inactiveTickColor = Hs.Line,
                        ),
                        modifier = Modifier.height(44.dp),
                    )
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween,
                    ) {
                        Text(
                            "${SpotLimits.MIN_LEAD_MIN} min",
                            style = HsType.Caption,
                            color = Hs.TextTertiary,
                        )
                        Text(
                            "${SpotLimits.SLIDER_MAX_LEAD_MIN} min",
                            style = HsType.Caption,
                            color = Hs.TextTertiary,
                        )
                    }
                }
            }

            Spacer(Modifier.height(22.dp))
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.SpaceBetween,
            ) {
                Column {
                    Text("Arrival radius", style = HsType.BodyStrong, color = Hs.TextPrimary)
                    Spacer(Modifier.height(3.dp))
                    Text("counts as arrived within", style = HsType.Small, color = Hs.TextTertiary)
                }
                Box(
                    modifier = Modifier
                        .height(44.dp)
                        .clip(RoundedCornerShape(12.dp))
                        .background(Hs.Card)
                        .border(1.dp, Hs.Line, RoundedCornerShape(12.dp))
                        .clickable { radiusM = SpotLimits.nextRadius(radiusM) }
                        .padding(horizontal = 16.dp),
                    contentAlignment = Alignment.Center,
                ) {
                    Text(
                        "$radiusM m",
                        style = HsType.BodyStrong.copy(fontFeatureSettings = TABULAR),
                        color = Hs.TextPrimary,
                    )
                }
            }

            if (errorMessage != null) {
                Spacer(Modifier.height(16.dp))
                Text(errorMessage, style = HsType.Small, color = Hs.Delayed)
            }

            Spacer(Modifier.height(28.dp))
            PrimaryButton(
                text = if (saving) "Saving…" else "Save spot",
                enabled = !saving && trimmedName != null && placed,
                onClick = {
                    val la = lat
                    val ln = lng
                    if (trimmedName != null && la != null && ln != null) {
                        onSave(trimmedName, la, ln, leadTimeMin, radiusM)
                    }
                },
            )

            if (existing != null) {
                Spacer(Modifier.height(12.dp))
                DestructiveButton(text = "Delete this spot", onClick = onDelete)
            }
            Spacer(Modifier.height(38.dp))
        }
    }
}

@Preview(name = "SpotEdit — new", widthDp = 390, heightDp = 1100, backgroundColor = 0xFF15171B, showBackground = true)
@Composable
private fun PreviewSpotEditNew() {
    HeadstartTheme {
        SpotEditScreen(
            existing = null,
            partnerName = "Sara",
            onBack = {},
            onUseCurrentLocation = {},
            onSave = { _, _, _, _, _ -> },
            onDelete = {},
        )
    }
}

@Preview(name = "SpotEdit — existing", widthDp = 390, heightDp = 1100, backgroundColor = 0xFF15171B, showBackground = true)
@Composable
private fun PreviewSpotEditExisting() {
    HeadstartTheme {
        SpotEditScreen(
            existing = Spot(
                id = "s1",
                pairId = "p1",
                name = "Office",
                lat = 23.78063,
                lng = 90.40744,
                radiusM = 100,
                leadTimeMin = 3,
                createdBy = "u1",
            ),
            partnerName = "Sara",
            onBack = {},
            onUseCurrentLocation = {},
            onSave = { _, _, _, _, _ -> },
            onDelete = {},
        )
    }
}
