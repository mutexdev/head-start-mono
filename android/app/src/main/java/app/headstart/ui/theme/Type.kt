package app.headstart.ui.theme

import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.Font
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.sp
import app.headstart.R

val Archivo = FontFamily(
    Font(R.font.archivo_regular, FontWeight.Normal),
    Font(R.font.archivo_medium, FontWeight.Medium),
    Font(R.font.archivo_semibold, FontWeight.SemiBold),
    Font(R.font.archivo_bold, FontWeight.Bold),
)

/** Applied to every number that changes: countdowns, ETAs, clock times, codes. */
const val TABULAR = "tnum"

/**
 * Named styles lifted straight off the artboards, so a screen never invents a size.
 * Font sizes are the artboards' px values read as sp (the artboards are 390 px wide,
 * i.e. a 1x mdpi-equivalent frame).
 */
object HsType {
    /** Welcome.dc.html hero. */
    val Hero = TextStyle(fontFamily = Archivo, fontWeight = FontWeight.Bold, fontSize = 38.sp, lineHeight = 42.sp, letterSpacing = (-1.5).sp)

    /** "What's your number?", "Pickup spots", "Enter their code". */
    val ScreenTitle = TextStyle(fontFamily = Archivo, fontWeight = FontWeight.Bold, fontSize = 30.sp, lineHeight = 35.sp, letterSpacing = (-1).sp)

    /** "Where to, Mostafi?", "Settings", "Nothing on the way". */
    val HomeTitle = TextStyle(fontFamily = Archivo, fontWeight = FontWeight.Bold, fontSize = 28.sp, lineHeight = 32.sp, letterSpacing = (-0.9).sp)

    /** DriverNudge sheet heading. */
    val SheetTitle = TextStyle(fontFamily = Archivo, fontWeight = FontWeight.Bold, fontSize = 27.sp, lineHeight = 31.sp, letterSpacing = (-0.9).sp)

    /** DriverTrip "18". */
    val EtaHuge = TextStyle(fontFamily = Archivo, fontWeight = FontWeight.Bold, fontSize = 88.sp, lineHeight = 80.sp, letterSpacing = (-4).sp, fontFeatureSettings = TABULAR)

    /** ReceiverTrip "7:20". */
    val CountdownBig = TextStyle(fontFamily = Archivo, fontWeight = FontWeight.Bold, fontSize = 56.sp, lineHeight = 56.sp, letterSpacing = (-2.4).sp, fontFeatureSettings = TABULAR)

    /** SpotEdit "3" minutes. */
    val NumberLarge = TextStyle(fontFamily = Archivo, fontWeight = FontWeight.Bold, fontSize = 52.sp, lineHeight = 52.sp, letterSpacing = (-2).sp, fontFeatureSettings = TABULAR)

    /** PairInvite "K7M2QP". */
    val Code = TextStyle(fontFamily = Archivo, fontWeight = FontWeight.Bold, fontSize = 44.sp, lineHeight = 48.sp, letterSpacing = 8.sp, fontFeatureSettings = TABULAR)

    /** DriverHome green card headline. */
    val CardHeadline = TextStyle(fontFamily = Archivo, fontWeight = FontWeight.Bold, fontSize = 34.sp, lineHeight = 36.sp, letterSpacing = (-1.3).sp)

    /** ReceiverHome headstart value. */
    val NumberMedium = TextStyle(fontFamily = Archivo, fontWeight = FontWeight.Bold, fontSize = 30.sp, lineHeight = 32.sp, fontFeatureSettings = TABULAR)

    /** "min away" next to the huge ETA. */
    val EtaUnit = TextStyle(fontFamily = Archivo, fontWeight = FontWeight.Medium, fontSize = 26.sp, lineHeight = 30.sp)

    val CardTitle = TextStyle(fontFamily = Archivo, fontWeight = FontWeight.SemiBold, fontSize = 18.sp, lineHeight = 24.sp)
    val ListTitle = TextStyle(fontFamily = Archivo, fontWeight = FontWeight.SemiBold, fontSize = 17.sp, lineHeight = 22.sp)
    val ButtonLabel = TextStyle(fontFamily = Archivo, fontWeight = FontWeight.SemiBold, fontSize = 17.sp, lineHeight = 22.sp)
    val Body = TextStyle(fontFamily = Archivo, fontWeight = FontWeight.Normal, fontSize = 16.sp, lineHeight = 24.sp)
    val BodyStrong = TextStyle(fontFamily = Archivo, fontWeight = FontWeight.SemiBold, fontSize = 16.sp, lineHeight = 22.sp)
    val Small = TextStyle(fontFamily = Archivo, fontWeight = FontWeight.Normal, fontSize = 14.sp, lineHeight = 21.sp)
    val SmallStrong = TextStyle(fontFamily = Archivo, fontWeight = FontWeight.SemiBold, fontSize = 15.sp, lineHeight = 20.sp)
    val Caption = TextStyle(fontFamily = Archivo, fontWeight = FontWeight.Normal, fontSize = 13.sp, lineHeight = 19.sp)

    /** "OTHER SPOTS", "QUICK REPLY", "YOUR HEADSTART". */
    val SectionLabel = TextStyle(fontFamily = Archivo, fontWeight = FontWeight.SemiBold, fontSize = 12.sp, lineHeight = 16.sp, letterSpacing = 1.4.sp)

    /** "SHARING WITH SARA" — same tracking, one size up. */
    val StatusLabel = TextStyle(fontFamily = Archivo, fontWeight = FontWeight.SemiBold, fontSize = 14.sp, lineHeight = 18.sp, letterSpacing = 1.2.sp)

    /** Clock times and any inline number that must not jitter. */
    val TabularSmall = TextStyle(fontFamily = Archivo, fontWeight = FontWeight.Normal, fontSize = 14.sp, lineHeight = 20.sp, fontFeatureSettings = TABULAR)
}
