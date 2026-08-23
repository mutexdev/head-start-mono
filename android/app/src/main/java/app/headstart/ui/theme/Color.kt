package app.headstart.ui.theme

import androidx.compose.ui.graphics.Color

/**
 * The palette from design/README.md. Dark-only in M1 — there is no light scheme,
 * and screens must not assume one exists.
 */
object Hs {
    val Base = Color(0xFF15171B)
    val Card = Color(0xFF1E2126)
    val Raised = Color(0xFF262A30)
    val Line = Color(0xFF31363D)

    val TextPrimary = Color(0xFFF2F4F7)
    val TextSecondary = Color(0xFFA8B0BA)
    val TextTertiary = Color(0xFF6D7681)

    /** Driver acts. */
    val Go = Color(0xFF3AD693)
    /** Walk out now. */
    val Headstart = Color(0xFFF0A13C)
    /** Stay inside. */
    val Delayed = Color(0xFFEF6F52)

    val InkOnGo = Color(0xFF0C1C14)
    val InkOnHeadstart = Color(0xFF241804)

    // Stylised map panel (SpotEdit / ReceiverTrip)
    val MapBase = Color(0xFF1A1D22)
    val MapRoad = Color(0xFF23272D)
    val MapMinor = Color(0xFF20242A)
    val MapBlock = Color(0xFF1E2228)

    // Translucent accents used by the armed banner and the nudge sheet icon
    val HeadstartWash = Color(0x1AF0A13C)       // rgba(240,161,60,0.10)
    val HeadstartWashStrong = Color(0x24F0A13C) // rgba(240,161,60,0.14)
    val HeadstartBorder = Color(0x66F0A13C)     // rgba(240,161,60,0.40)
    val DelayedBorder = Color(0x8CEF6F52)       // rgba(239,111,82,0.55)
}
