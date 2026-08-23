package app.headstart.ui.components

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ChevronLeft
import androidx.compose.material.icons.filled.ChevronRight
import androidx.compose.material.icons.filled.Shield
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import app.headstart.ui.theme.HeadstartTheme
import app.headstart.ui.theme.Hs
import app.headstart.ui.theme.HsType

/**
 * Stateless building blocks shared by every screen. Colours come only from [Hs] and type
 * only from [HsType] — no screen and no component here may hardcode a hex value.
 *
 * Sizing rules from CLIENT_CONTRACT.md §"Design tokens": primary controls 56 dp tall,
 * nothing interactive under 44 dp, radii 12–14 on controls, 16–22 on cards, 26 on sheets.
 */

/** 26 dp side gutter and the base background — every full screen starts with this. */
@Composable
fun HsScreen(
    modifier: Modifier = Modifier,
    content: @Composable ColumnScope.() -> Unit,
) {
    Column(
        modifier = modifier
            .fillMaxSize()
            .background(Hs.Base)
            .padding(horizontal = 26.dp),
        content = content,
    )
}

private val ControlShape = RoundedCornerShape(14.dp)

/** 56 dp, Go green, ink-on-green label. Disabled state matches Verify.dc.html. */
@Composable
fun PrimaryButton(
    text: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
    leadingIcon: ImageVector? = null,
) {
    val bg = if (enabled) Hs.Go else Hs.Raised
    val fg = if (enabled) Hs.InkOnGo else Hs.TextTertiary
    Row(
        modifier = modifier
            .fillMaxWidth()
            .height(56.dp)
            .clip(ControlShape)
            .background(bg)
            .then(if (enabled) Modifier else Modifier.border(1.dp, Hs.Line, ControlShape))
            .clickable(enabled = enabled, onClick = onClick),
        horizontalArrangement = Arrangement.Center,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        if (leadingIcon != null) {
            Icon(leadingIcon, contentDescription = null, tint = fg, modifier = Modifier.size(20.dp))
            Spacer(Modifier.width(10.dp))
        }
        Text(text, style = HsType.ButtonLabel, color = fg)
    }
}

/** 56 dp, card background with a hairline border. "I have an invite code", "Copy code". */
@Composable
fun SecondaryButton(
    text: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
    leadingIcon: ImageVector? = null,
    contentColor: Color = Hs.TextPrimary,
) {
    Row(
        modifier = modifier
            .fillMaxWidth()
            .height(56.dp)
            .clip(ControlShape)
            .background(Hs.Card)
            .border(1.dp, Hs.Line, ControlShape)
            .clickable(enabled = enabled, onClick = onClick),
        horizontalArrangement = Arrangement.Center,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        if (leadingIcon != null) {
            Icon(leadingIcon, contentDescription = null, tint = contentColor, modifier = Modifier.size(20.dp))
            Spacer(Modifier.width(10.dp))
        }
        Text(
            text,
            style = HsType.ButtonLabel.copy(fontWeight = FontWeight.Medium),
            color = contentColor,
        )
    }
}

/** 52 dp, outlined in Delayed. "Delete my account and data", "Cancel the trip". */
@Composable
fun DestructiveButton(
    text: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    filled: Boolean = false,
) {
    Box(
        modifier = modifier
            .fillMaxWidth()
            .height(if (filled) 56.dp else 52.dp)
            .clip(ControlShape)
            .background(if (filled) Hs.Raised else Color.Transparent)
            .border(1.dp, if (filled) Hs.Line else Hs.DelayedBorder, ControlShape)
            .clickable(onClick = onClick),
        contentAlignment = Alignment.Center,
    ) {
        Text(
            text,
            style = HsType.Body.copy(fontWeight = FontWeight.Medium),
            color = Hs.Delayed,
        )
    }
}

/** 16 dp radius card, Hs.Card on an Hs.Line hairline. */
@Composable
fun HsCard(
    modifier: Modifier = Modifier,
    radius: Dp = 16.dp,
    onClick: (() -> Unit)? = null,
    content: @Composable ColumnScope.() -> Unit,
) {
    val shape = RoundedCornerShape(radius)
    Column(
        modifier = modifier
            .fillMaxWidth()
            .clip(shape)
            .background(Hs.Card)
            .border(1.dp, Hs.Line, shape)
            .then(if (onClick != null) Modifier.clickable(onClick = onClick) else Modifier),
        content = content,
    )
}

/** 46 dp pill. ReceiverTrip quick replies. */
@Composable
fun HsChip(
    text: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
) {
    val shape = RoundedCornerShape(23.dp)
    Box(
        modifier = modifier
            .height(46.dp)
            .clip(shape)
            .background(Hs.Card)
            .border(1.dp, Hs.Line, shape)
            .clickable(enabled = enabled, onClick = onClick)
            .padding(horizontal = 18.dp),
        contentAlignment = Alignment.Center,
    ) {
        Text(
            text,
            style = HsType.SmallStrong.copy(fontWeight = FontWeight.Medium),
            color = if (enabled) Hs.TextPrimary else Hs.TextTertiary,
        )
    }
}

/** 48 dp compact action used in the DriverTrip "Late +5 / +10 / +15 / Cancel" row. */
@Composable
fun SmallAction(
    text: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    contentColor: Color = Hs.TextSecondary,
) {
    val shape = RoundedCornerShape(12.dp)
    Box(
        modifier = modifier
            .height(48.dp)
            .clip(shape)
            .background(Hs.Card)
            .border(1.dp, Hs.Line, shape)
            .clickable(onClick = onClick),
        contentAlignment = Alignment.Center,
    ) {
        Text(text, style = HsType.SmallStrong, color = contentColor)
    }
}

/** "OTHER SPOTS" — 12 sp, 1.4 sp tracking, upper case, tertiary. */
@Composable
fun SectionLabel(text: String, modifier: Modifier = Modifier, color: Color = Hs.TextTertiary) {
    Text(text.uppercase(), style = HsType.SectionLabel, color = color, modifier = modifier)
}

/** The 88 sp tabular ETA with its unit on the same baseline. */
@Composable
fun BigEta(
    value: String,
    unit: String,
    modifier: Modifier = Modifier,
    valueColor: Color = Hs.TextPrimary,
) {
    Row(modifier = modifier, verticalAlignment = Alignment.Bottom) {
        Text(value, style = HsType.EtaHuge, color = valueColor, modifier = Modifier.alignByBaseline())
        Spacer(Modifier.width(12.dp))
        Text(unit, style = HsType.EtaUnit, color = Hs.TextSecondary, modifier = Modifier.alignByBaseline())
    }
}

/** Shield icon + tertiary caption. Used at the foot of most screens. */
@Composable
fun PrivacyNote(text: String, modifier: Modifier = Modifier, centered: Boolean = false) {
    Row(
        modifier = modifier.fillMaxWidth(),
        horizontalArrangement = if (centered) Arrangement.Center else Arrangement.Start,
        verticalAlignment = Alignment.Top,
    ) {
        Icon(Icons.Filled.Shield, contentDescription = null, tint = Hs.TextTertiary, modifier = Modifier.size(16.dp))
        Spacer(Modifier.width(10.dp))
        Text(
            text,
            style = HsType.Caption,
            color = Hs.TextTertiary,
            textAlign = if (centered) TextAlign.Center else TextAlign.Start,
        )
    }
}

/** 44 dp back chevron row, matching the top of Phone/Verify/Profile/PairEnter. */
@Composable
fun BackBar(onBack: () -> Unit, modifier: Modifier = Modifier) {
    Box(
        modifier = modifier
            .size(44.dp)
            .clip(RoundedCornerShape(12.dp))
            .clickable(onClick = onBack),
        contentAlignment = Alignment.CenterStart,
    ) {
        Icon(Icons.Filled.ChevronLeft, contentDescription = "Back", tint = Hs.TextSecondary, modifier = Modifier.size(24.dp))
    }
}

@Composable
fun RowChevron(modifier: Modifier = Modifier) {
    Icon(Icons.Filled.ChevronRight, contentDescription = null, tint = Hs.TextTertiary, modifier = modifier.size(18.dp))
}

/**
 * The stylised map panel from SpotEdit.dc.html / ReceiverTrip.dc.html, drawn rather than
 * fetched. M1 has no Maps SDK — this shows the destination pin, an optional dashed arrival
 * radius, and an optional driver dot whose position is a normalised 0..1 progress along a
 * fixed diagonal, purely as reassurance.
 */
@Composable
fun StylizedMapPanel(
    height: Dp,
    modifier: Modifier = Modifier,
    showRadius: Boolean = false,
    driverProgress: Float? = null,
) {
    Canvas(modifier = modifier.fillMaxWidth().height(height).background(Hs.MapBase)) {
        val w = size.width
        val h = size.height
        // Major roads
        listOf(0.28f, 0.72f).forEach { f ->
            drawLine(Hs.MapRoad, Offset(0f, h * f), Offset(w, h * f), strokeWidth = 15f)
        }
        listOf(0.24f, 0.76f).forEach { f ->
            drawLine(Hs.MapRoad, Offset(w * f, 0f), Offset(w * f, h), strokeWidth = 15f)
        }
        // Minor roads
        drawLine(Hs.MapMinor, Offset(0f, h * 0.5f), Offset(w, h * 0.5f), strokeWidth = 6f)
        drawLine(Hs.MapMinor, Offset(w * 0.48f, 0f), Offset(w * 0.48f, h), strokeWidth = 6f)
        // Blocks
        val blocks = listOf(
            Offset(w * 0.27f, h * 0.33f) to Size(w * 0.18f, h * 0.13f),
            Offset(w * 0.52f, h * 0.33f) to Size(w * 0.20f, h * 0.13f),
            Offset(w * 0.27f, h * 0.56f) to Size(w * 0.18f, h * 0.15f),
            Offset(w * 0.52f, h * 0.56f) to Size(w * 0.20f, h * 0.15f),
        )
        blocks.forEach { (at, sz) -> drawRect(Hs.MapBlock, topLeft = at, size = sz) }

        val pin = Offset(w * 0.5f, h * 0.5f)
        if (showRadius) {
            drawCircle(Hs.Go.copy(alpha = 0.07f), radius = h * 0.29f, center = pin)
            drawCircle(
                Hs.Go.copy(alpha = 0.32f),
                radius = h * 0.29f,
                center = pin,
                style = Stroke(width = 1.5f, pathEffect = PathEffect.dashPathEffect(floatArrayOf(5f, 5f))),
            )
        }
        if (driverProgress != null) {
            val p = driverProgress.coerceIn(0f, 1f)
            val from = Offset(w * 0.9f, h * 0.92f)
            val at = Offset(from.x + (pin.x - from.x) * p, from.y + (pin.y - from.y) * p)
            drawCircle(Hs.Go, radius = 5f, center = at)
            drawCircle(Hs.Go.copy(alpha = 0.18f), radius = 17f, center = at)
        }
        drawCircle(Hs.Go, radius = 7f, center = pin)
    }
}

// ---------------------------------------------------------------------------------------
// Previews. There are deliberately no instrumentation or screenshot tests for this file —
// it is declarative layout with no branching worth asserting, and M1 carries no Robolectric
// or Paparazzi harness. A human eyeballs these in Android Studio, or on a device once the
// first real screen lands.
// ---------------------------------------------------------------------------------------

@Preview(name = "Buttons", widthDp = 390, backgroundColor = 0xFF15171B, showBackground = true)
@Composable
private fun PreviewButtons() {
    HeadstartTheme {
        Column(
            modifier = Modifier.background(Hs.Base).padding(26.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            PrimaryButton("I'm coming", onClick = {})
            PrimaryButton("Verify", onClick = {}, enabled = false)
            SecondaryButton("I have an invite code", onClick = {})
            DestructiveButton("Cancel the trip", onClick = {})
            Row(horizontalArrangement = Arrangement.spacedBy(9.dp)) {
                SmallAction("Late +5", onClick = {}, modifier = Modifier.weight(1f))
                SmallAction("Late +10", onClick = {}, modifier = Modifier.weight(1f))
                SmallAction("Late +15", onClick = {}, modifier = Modifier.weight(1f))
            }
            Row(horizontalArrangement = Arrangement.spacedBy(9.dp)) {
                HsChip("5 more min", onClick = {})
                HsChip("Take your time", onClick = {})
            }
            BackBar(onBack = {})
        }
    }
}

@Preview(name = "Surfaces", widthDp = 390, backgroundColor = 0xFF15171B, showBackground = true)
@Composable
private fun PreviewSurfaces() {
    HeadstartTheme {
        Column(
            modifier = Modifier.background(Hs.Base).padding(26.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            SectionLabel("Other spots")
            HsCard {
                Row(
                    modifier = Modifier.fillMaxWidth().padding(18.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Text("Sara's office", style = HsType.ListTitle, color = Hs.TextPrimary)
                    Spacer(Modifier.weight(1f))
                    RowChevron()
                }
            }
            BigEta("18", "min away")
            StylizedMapPanel(height = 180.dp, showRadius = true, driverProgress = 0.55f)
            PrivacyNote("Your exact position is never shown to anyone but you.", centered = true)
        }
    }
}
