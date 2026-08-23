package app.headstart.ui

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.core.content.ContextCompat

/**
 * Location first, notifications second — in that order, one prompt at a time, and only
 * after ProfileScreen has explained both in the app's own words. Never
 * ACCESS_BACKGROUND_LOCATION: see the plan header for why that permission is not worth a
 * Play policy review.
 *
 * The two OS dialogs are never raised simultaneously: the notification launcher fires from
 * the *result callback* of the location launcher, so the second sheet only appears once the
 * first has been answered.
 */
class PermissionFlow(
    private val requestLocation: () -> Unit,
    private val requestNotifications: () -> Unit,
    private val onAlreadyGranted: () -> Unit,
) {
    fun start(context: Context) {
        if (!hasLocation(context)) {
            requestLocation()
        } else if (!hasNotifications(context)) {
            requestNotifications()
        } else {
            onAlreadyGranted()
        }
    }

    companion object {
        fun hasLocation(context: Context): Boolean =
            ContextCompat.checkSelfPermission(context, Manifest.permission.ACCESS_FINE_LOCATION) ==
                PackageManager.PERMISSION_GRANTED

        fun hasNotifications(context: Context): Boolean =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) ==
                    PackageManager.PERMISSION_GRANTED
            } else {
                true // pre-13 grants it at install time
            }
    }
}

@Composable
fun rememberPermissionFlow(onFinished: () -> Unit): PermissionFlow {
    val notificationLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestPermission(),
    ) { onFinished() }

    val locationLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestMultiplePermissions(),
    ) {
        // Second prompt only after the first has been answered — never both at once.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            notificationLauncher.launch(Manifest.permission.POST_NOTIFICATIONS)
        } else {
            onFinished()
        }
    }

    return remember {
        PermissionFlow(
            requestLocation = {
                locationLauncher.launch(
                    arrayOf(
                        Manifest.permission.ACCESS_FINE_LOCATION,
                        Manifest.permission.ACCESS_COARSE_LOCATION,
                    ),
                )
            },
            requestNotifications = {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    notificationLauncher.launch(Manifest.permission.POST_NOTIFICATIONS)
                } else {
                    onFinished()
                }
            },
            onAlreadyGranted = onFinished,
        )
    }
}
