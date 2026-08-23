package app.headstart.ui.settings

import android.content.Intent
import android.provider.Settings
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
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
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import app.headstart.BuildConfig
import app.headstart.core.HeadstartConfig
import app.headstart.push.CHANNEL_URGENT
import app.headstart.push.Notifications
import app.headstart.ui.components.DestructiveButton
import app.headstart.ui.components.HsCard
import app.headstart.ui.components.RowChevron
import app.headstart.ui.components.SecondaryButton
import app.headstart.ui.components.SectionLabel
import app.headstart.ui.theme.HeadstartTheme
import app.headstart.ui.theme.Hs
import app.headstart.ui.theme.HsType

/**
 * Settings.dc.html. Stateless apart from its two confirmation dialogs — the host owns
 * `revokePair`, sign-out and the fuzzy-mode preference and passes them in.
 *
 * Five rows do real work in M1: Unpair (`revokePair`), Hide my exact position (the `fuzzy`
 * flag on `startTrip`), Send me a test alert, Sign out, Delete my account. Two are drawn
 * but deferred, and say so:
 *
 * - **Loud walk-out alert** is NOT an in-app switch. Once a notification channel exists,
 *   Android owns its importance and its sound; a toggle here would be a lie. The row opens
 *   the OS settings page for `sync_urgent` (plan Task 19, line 7706).
 * - **Trip history → Clear** is M4. Positions already expire by Firestore TTL after 30
 *   days; a manual purge needs a callable that does not exist yet.
 * - **Delete my account and data** explains itself rather than calling `deleteAccount`,
 *   which addendum §A puts outside M1 on both clients and the server.
 *
 * Debug builds get one extra row, "Firebase target", so a reviewer can see and flip
 * whether this process talks to the emulator suite or the real cloud without adb.
 */
@Composable
fun SettingsScreen(
    partnerName: String,
    pairId: String?,
    pairedSince: String?,
    hideExactPosition: Boolean,
    /** `Prefs.useCloud`. Debug builds only; read once at process start. */
    useCloud: Boolean,
    error: String?,
    onBack: () -> Unit,
    onHideExactPositionChange: (Boolean) -> Unit,
    onUseCloudChange: (Boolean) -> Unit,
    onUnpair: () -> Unit,
    onSignOut: () -> Unit,
) {
    val context = LocalContext.current
    var confirmUnpair by remember { mutableStateOf(false) }
    var explainDelete by remember { mutableStateOf(false) }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(Hs.Base)
            .verticalScroll(rememberScrollState())
            .padding(horizontal = 26.dp),
    ) {
        Spacer(Modifier.height(78.dp))
        Text("Settings", style = HsType.HomeTitle, color = Hs.TextPrimary)
        Spacer(Modifier.height(20.dp))

        // ---- the pair ------------------------------------------------------------------
        HsCard(radius = 18.dp) {
            Row(
                modifier = Modifier.padding(18.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Box(
                    modifier = Modifier.size(50.dp).clip(CircleShape).background(Hs.Raised),
                    contentAlignment = Alignment.Center,
                ) {
                    Text(
                        partnerName.take(1).uppercase().ifEmpty { "?" },
                        style = HsType.CardTitle,
                        color = Hs.TextSecondary,
                    )
                }
                Spacer(Modifier.width(15.dp))
                Column(Modifier.weight(1f)) {
                    Text(
                        if (pairId == null) "Not paired" else "Paired with $partnerName",
                        style = HsType.CardTitle,
                        color = Hs.TextPrimary,
                    )
                    Spacer(Modifier.height(3.dp))
                    Text(pairedSince ?: "—", style = HsType.Small, color = Hs.TextTertiary)
                }
                if (pairId != null) {
                    Spacer(Modifier.width(10.dp))
                    Box(
                        modifier = Modifier
                            .height(44.dp)
                            .clip(RoundedCornerShape(12.dp))
                            .border(1.dp, Hs.Line, RoundedCornerShape(12.dp))
                            .clickable { confirmUnpair = true }
                            .padding(horizontal = 16.dp),
                        contentAlignment = Alignment.Center,
                    ) {
                        Text("Unpair", style = HsType.Small, color = Hs.Delayed)
                    }
                }
            }
        }

        // ---- privacy -------------------------------------------------------------------
        Spacer(Modifier.height(22.dp))
        SectionLabel("Privacy")
        Spacer(Modifier.height(12.dp))
        HsCard(radius = 18.dp) {
            Row(
                modifier = Modifier.padding(horizontal = 18.dp, vertical = 17.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Column(Modifier.weight(1f)) {
                    Text("Hide my exact position", style = HsType.BodyStrong, color = Hs.TextPrimary)
                    Spacer(Modifier.height(4.dp))
                    Text(
                        "${partnerName.ifEmpty { "They" }} sees the countdown but not the dot.",
                        style = HsType.Small,
                        color = Hs.TextSecondary,
                    )
                }
                Spacer(Modifier.width(15.dp))
                Switch(
                    checked = hideExactPosition,
                    onCheckedChange = onHideExactPositionChange,
                    colors = SwitchDefaults.colors(
                        checkedThumbColor = Hs.InkOnGo,
                        checkedTrackColor = Hs.Go,
                        uncheckedThumbColor = Hs.TextTertiary,
                        uncheckedTrackColor = Hs.Raised,
                        uncheckedBorderColor = Hs.Line,
                    ),
                )
            }
            Divider()
            // M4: a manual purge needs a callable that does not exist yet, so this is a
            // caption, not a button. Do not wire it to anything before deleteTripHistory
            // ships.
            Row(
                modifier = Modifier.padding(horizontal = 18.dp, vertical = 17.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Column(Modifier.weight(1f)) {
                    Text("Trip history", style = HsType.BodyStrong, color = Hs.TextPrimary)
                    Spacer(Modifier.height(4.dp))
                    Text(
                        "Deleted automatically after 30 days",
                        style = HsType.Small,
                        color = Hs.TextSecondary,
                    )
                }
                Spacer(Modifier.width(15.dp))
                Text("Clear · M4", style = HsType.Small, color = Hs.TextTertiary)
            }
        }

        // ---- notifications -------------------------------------------------------------
        Spacer(Modifier.height(22.dp))
        SectionLabel("Notifications")
        Spacer(Modifier.height(12.dp))
        HsCard(radius = 18.dp) {
            // M4 as an in-app control; today it hands off to the OS, which is the only
            // place a channel's importance and sound can actually be changed.
            SettingsRow(
                title = "Loud walk-out alert",
                subtitle = "Own sound, breaks through Do Not Disturb. Android owns this switch — opens system settings.",
                onClick = {
                    val intent = Intent(Settings.ACTION_CHANNEL_NOTIFICATION_SETTINGS)
                        .putExtra(Settings.EXTRA_APP_PACKAGE, context.packageName)
                        .putExtra(Settings.EXTRA_CHANNEL_ID, CHANNEL_URGENT)
                    context.startActivity(intent)
                },
            )
            Divider()
            SettingsRow(
                title = "Send me a test alert",
                subtitle = "Check it actually gets through",
                onClick = {
                    // Straight through the production renderer, so what arrives is exactly
                    // what a real leadTime push looks and sounds like.
                    Notifications.deliver(
                        context,
                        mapOf(
                            "kind" to "leadTime",
                            "title" to "Start walking now",
                            "body" to "This is a test. The real one looks and sounds exactly like this.",
                        ),
                    )
                },
            )
        }

        // ---- debug-only ----------------------------------------------------------------
        if (BuildConfig.DEBUG) {
            Spacer(Modifier.height(22.dp))
            SectionLabel("Debug build only")
            Spacer(Modifier.height(12.dp))
            HsCard(radius = 18.dp) {
                Row(
                    modifier = Modifier.padding(horizontal = 18.dp, vertical = 17.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Column(Modifier.weight(1f)) {
                        Text("Firebase target", style = HsType.BodyStrong, color = Hs.TextPrimary)
                        Spacer(Modifier.height(4.dp))
                        Text(
                            "Live now: " +
                                if (HeadstartConfig.useLocalEmulators) {
                                    "emulator suite on 10.0.2.2"
                                } else {
                                    "cloud (fin-e8358)"
                                } +
                                ". Switch on to use the cloud; takes effect next launch.",
                            style = HsType.Small,
                            color = Hs.TextSecondary,
                        )
                    }
                    Spacer(Modifier.width(15.dp))
                    Switch(
                        checked = useCloud,
                        onCheckedChange = onUseCloudChange,
                        colors = SwitchDefaults.colors(
                            checkedThumbColor = Hs.InkOnGo,
                            checkedTrackColor = Hs.Headstart,
                            uncheckedThumbColor = Hs.TextTertiary,
                            uncheckedTrackColor = Hs.Raised,
                            uncheckedBorderColor = Hs.Line,
                        ),
                    )
                }
            }
        }

        if (error != null) {
            Spacer(Modifier.height(16.dp))
            Text(error, style = HsType.Small, color = Hs.Delayed)
        }

        Spacer(Modifier.height(28.dp))
        SecondaryButton("Back", onClick = onBack)
        Spacer(Modifier.height(11.dp))
        SecondaryButton("Sign out", onClick = onSignOut)
        Spacer(Modifier.height(11.dp))
        DestructiveButton("Delete my account and data", onClick = { explainDelete = true })
        Spacer(Modifier.height(38.dp))
    }

    if (confirmUnpair && pairId != null) {
        AlertDialog(
            onDismissRequest = { confirmUnpair = false },
            containerColor = Hs.Card,
            titleContentColor = Hs.TextPrimary,
            textContentColor = Hs.TextSecondary,
            title = { Text("Unpair?", style = HsType.CardTitle) },
            text = {
                Text(
                    "Neither of you will get the other's alerts any more. " +
                        "You can pair again with a new code.",
                    style = HsType.Body,
                )
            },
            confirmButton = {
                TextButton(onClick = {
                    confirmUnpair = false
                    onUnpair()
                }) { Text("Unpair", color = Hs.Delayed) }
            },
            dismissButton = {
                TextButton(onClick = { confirmUnpair = false }) {
                    Text("Keep paired", color = Hs.TextSecondary)
                }
            },
        )
    }

    if (explainDelete) {
        AlertDialog(
            onDismissRequest = { explainDelete = false },
            containerColor = Hs.Card,
            titleContentColor = Hs.TextPrimary,
            textContentColor = Hs.TextSecondary,
            title = { Text("Not in this build", style = HsType.CardTitle) },
            text = {
                Text(
                    "Account deletion ships with the store release. Until then, unpairing stops all " +
                        "sharing and your positions are deleted automatically after 30 days.",
                    style = HsType.Body,
                )
            },
            confirmButton = {
                TextButton(onClick = { explainDelete = false }) { Text("OK", color = Hs.Go) }
            },
        )
    }
}

@Composable
private fun SettingsRow(title: String, subtitle: String, onClick: () -> Unit) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .heightIn(min = 56.dp)
            .clickable(onClick = onClick)
            .padding(horizontal = 18.dp, vertical = 17.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(Modifier.weight(1f)) {
            Text(title, style = HsType.BodyStrong, color = Hs.TextPrimary)
            Spacer(Modifier.height(4.dp))
            Text(subtitle, style = HsType.Small, color = Hs.TextSecondary)
        }
        Spacer(Modifier.width(15.dp))
        RowChevron()
    }
}

@Composable
private fun Divider() {
    Box(Modifier.fillMaxWidth().padding(horizontal = 18.dp).height(1.dp).background(Hs.Line))
}

@Preview(name = "Settings", widthDp = 390, heightDp = 844, backgroundColor = 0xFF15171B, showBackground = true)
@Composable
private fun PreviewSettings() {
    HeadstartTheme {
        SettingsScreen(
            partnerName = "Sara",
            pairId = "pair_demo",
            pairedSince = "since 12 August",
            hideExactPosition = true,
            useCloud = false,
            error = null,
            onBack = {},
            onHideExactPositionChange = {},
            onUseCloudChange = {},
            onUnpair = {},
            onSignOut = {},
        )
    }
}
