package app.headstart.ui

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.platform.LocalContext
import app.headstart.ServiceLocator
import app.headstart.ui.theme.Hs
import app.headstart.ui.theme.HsType

/**
 * Several OEMs kill foreground services regardless of the foreground-service contract, so
 * the driver's positions simply stop arriving with the screen off. We cannot fix that from
 * inside the app — we can only tell the user once, the first time they start a trip, and
 * hand them the settings screen. See dontkillmyapp.com for the per-vendor details.
 */
private val AGGRESSIVE = setOf(
    "xiaomi", "redmi", "poco",
    "huawei", "honor",
    "oneplus",
    "oppo", "realme",
    "vivo",
)

fun needsBatteryGuidance(manufacturer: String): Boolean =
    manufacturer.lowercase() in AGGRESSIVE

fun needsBatteryGuidance(): Boolean = needsBatteryGuidance(Build.MANUFACTURER ?: "")

/** Shown once ever, right after the first successful `startTrip`. */
@Composable
fun BatteryGuidanceDialog(onDismiss: () -> Unit) {
    val context = LocalContext.current
    AlertDialog(
        onDismissRequest = {
            ServiceLocator.prefs.oemNoticeShown = true
            onDismiss()
        },
        containerColor = Hs.Card,
        titleContentColor = Hs.TextPrimary,
        textContentColor = Hs.TextSecondary,
        title = { Text("One thing about this phone", style = HsType.CardTitle) },
        text = {
            Text(
                "${Build.MANUFACTURER} phones stop apps in the background more aggressively than " +
                    "Android asks them to. If Headstart is restricted, your ETA can freeze mid-drive. " +
                    "Set Headstart's battery usage to \"Unrestricted\" and allow autostart.",
                style = HsType.Body,
            )
        },
        confirmButton = {
            TextButton(onClick = {
                ServiceLocator.prefs.oemNoticeShown = true
                val intent = Intent(
                    Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                    Uri.fromParts("package", context.packageName, null),
                )
                runCatching { context.startActivity(intent) }
                onDismiss()
            }) { Text("Open app settings", color = Hs.Go) }
        },
        dismissButton = {
            TextButton(onClick = {
                ServiceLocator.prefs.oemNoticeShown = true
                onDismiss()
            }) { Text("Later", color = Hs.TextSecondary) }
        },
    )
}
