package app.headstart.ui.components

import androidx.compose.animation.animateColorAsState
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import app.headstart.Role
import app.headstart.ui.theme.HeadstartTheme
import app.headstart.ui.theme.Hs
import app.headstart.ui.theme.HsType

/**
 * Not in the artboards — the deliberate deviation. Either paired person can drive, so Home
 * needs one control to say which side you are on today. 44 dp tall, which is the floor for
 * anything interactive in this design (CLIENT_CONTRACT.md §"Design tokens").
 */
@Composable
fun RoleSwitch(
    role: Role,
    onRoleChange: (Role) -> Unit,
    modifier: Modifier = Modifier,
) {
    val shape = RoundedCornerShape(12.dp)
    Row(
        modifier = modifier
            .fillMaxWidth()
            .height(44.dp)
            .clip(shape)
            .background(Hs.Card)
            .border(1.dp, Hs.Line, shape),
    ) {
        Segment("I'm driving", role == Role.DRIVING, Modifier.weight(1f)) { onRoleChange(Role.DRIVING) }
        Segment("I'm waiting", role == Role.WAITING, Modifier.weight(1f)) { onRoleChange(Role.WAITING) }
    }
}

@Composable
private fun Segment(
    text: String,
    selected: Boolean,
    modifier: Modifier,
    onClick: () -> Unit,
) {
    val background by animateColorAsState(
        targetValue = if (selected) Hs.Raised else Hs.Card,
        label = "roleSegmentBackground",
    )
    // The clickable sits OUTSIDE the 3 dp track inset, so the tap target is the full 44 dp
    // even though the painted pill is 38 dp. CLIENT_CONTRACT.md: nothing interactive under 44.
    Box(
        modifier = modifier
            .fillMaxHeight()
            .clickable(onClick = onClick)
            .padding(3.dp),
        contentAlignment = Alignment.Center,
    ) {
        Box(
            Modifier
                .matchParentSize()
                .clip(RoundedCornerShape(10.dp))
                .background(background),
        )
        Text(
            text,
            style = HsType.SmallStrong,
            color = if (selected) Hs.TextPrimary else Hs.TextTertiary,
        )
    }
}

@Preview(name = "RoleSwitch", widthDp = 390, backgroundColor = 0xFF15171B, showBackground = true)
@Composable
private fun PreviewRoleSwitch() {
    HeadstartTheme {
        Column(modifier = Modifier.background(Hs.Base).padding(26.dp)) {
            RoleSwitch(role = Role.DRIVING, onRoleChange = {})
            Box(Modifier.height(12.dp))
            RoleSwitch(role = Role.WAITING, onRoleChange = {})
        }
    }
}
