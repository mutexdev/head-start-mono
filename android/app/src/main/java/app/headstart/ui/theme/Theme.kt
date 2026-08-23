package app.headstart.ui.theme

import android.app.Activity
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Typography
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.SideEffect
import androidx.compose.ui.platform.LocalView
import androidx.core.view.WindowCompat

private val HeadstartColors = darkColorScheme(
    primary = Hs.Go,
    onPrimary = Hs.InkOnGo,
    secondary = Hs.Raised,
    onSecondary = Hs.TextPrimary,
    tertiary = Hs.Headstart,
    onTertiary = Hs.InkOnHeadstart,
    background = Hs.Base,
    onBackground = Hs.TextPrimary,
    surface = Hs.Card,
    onSurface = Hs.TextPrimary,
    surfaceVariant = Hs.Raised,
    onSurfaceVariant = Hs.TextSecondary,
    outline = Hs.Line,
    outlineVariant = Hs.Line,
    error = Hs.Delayed,
    onError = Hs.TextPrimary,
    scrim = Hs.Base,
)

private val HeadstartTypography = Typography(
    displayLarge = HsType.Hero,
    headlineLarge = HsType.ScreenTitle,
    headlineMedium = HsType.HomeTitle,
    titleLarge = HsType.CardTitle,
    titleMedium = HsType.ListTitle,
    bodyLarge = HsType.Body,
    bodyMedium = HsType.Small,
    bodySmall = HsType.Caption,
    labelLarge = HsType.ButtonLabel,
    labelSmall = HsType.SectionLabel,
)

/**
 * Dark-only in M1: [isSystemInDarkTheme] is deliberately ignored. If M2 adds a light
 * scheme, add it here — no screen reads colours from anywhere but [Hs] and this scheme.
 */
@Composable
fun HeadstartTheme(content: @Composable () -> Unit) {
    @Suppress("UNUSED_EXPRESSION")
    isSystemInDarkTheme()

    val view = LocalView.current
    if (!view.isInEditMode) {
        SideEffect {
            val window = (view.context as Activity).window
            WindowCompat.getInsetsController(window, view).isAppearanceLightStatusBars = false
            WindowCompat.getInsetsController(window, view).isAppearanceLightNavigationBars = false
        }
    }

    MaterialTheme(
        colorScheme = HeadstartColors,
        typography = HeadstartTypography,
        content = content,
    )
}
