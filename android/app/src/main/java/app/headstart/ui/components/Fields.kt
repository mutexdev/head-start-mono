package app.headstart.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsFocusedAsState
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.headstart.ui.theme.HeadstartTheme
import app.headstart.ui.theme.Hs
import app.headstart.ui.theme.HsType
import app.headstart.ui.theme.TABULAR

/** Single-line field styled like Phone.dc.html / Profile.dc.html: 60 dp, green when focused. */
@Composable
fun HsTextField(
    value: String,
    onValueChange: (String) -> Unit,
    /** Defaults to full width; pass Modifier.width(...) or Modifier.weight(...) to size it. */
    modifier: Modifier = Modifier.fillMaxWidth(),
    placeholder: String = "",
    height: Dp = 60.dp,
    textStyle: TextStyle = HsType.CardTitle,
    keyboardType: KeyboardType = KeyboardType.Text,
    imeAction: ImeAction = ImeAction.Done,
    autoFocus: Boolean = false,
) {
    val shape = RoundedCornerShape(14.dp)
    val interaction = remember { MutableInteractionSource() }
    val focused by interaction.collectIsFocusedAsState()
    val focusRequester = remember { FocusRequester() }

    BasicTextField(
        value = value,
        onValueChange = onValueChange,
        singleLine = true,
        textStyle = textStyle.copy(color = Hs.TextPrimary),
        cursorBrush = SolidColor(Hs.Go),
        interactionSource = interaction,
        keyboardOptions = KeyboardOptions(keyboardType = keyboardType, imeAction = imeAction),
        modifier = modifier
            .height(height)
            .focusRequester(focusRequester),
        decorationBox = { inner ->
            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .height(height)
                    .clip(shape)
                    .background(Hs.Card)
                    .border(if (focused) 1.5.dp else 1.dp, if (focused) Hs.Go else Hs.Line, shape)
                    .padding(horizontal = 18.dp),
                contentAlignment = Alignment.CenterStart,
            ) {
                if (value.isEmpty() && placeholder.isNotEmpty()) {
                    Text(placeholder, style = textStyle, color = Hs.TextTertiary)
                }
                inner()
            }
        },
    )

    if (autoFocus) {
        LaunchedEffect(Unit) { focusRequester.requestFocus() }
    }
}

/**
 * The six-box code entry from Verify.dc.html and PairEnter.dc.html, used by both
 * VerifyScreen (the SMS code, digits only) and PairEnter (the invite code, alphanumeric).
 * One invisible text field sits on top of the boxes and owns focus and the IME; the boxes
 * are pure painting. 64 dp tall, well over the 44 dp interactive floor.
 */
@Composable
fun CodeInput(
    value: String,
    onValueChange: (String) -> Unit,
    modifier: Modifier = Modifier,
    length: Int = 6,
    digitsOnly: Boolean = true,
    boxHeight: Dp = 64.dp,
    gap: Dp = 9.dp,
) {
    val focusRequester = remember { FocusRequester() }
    val shape = RoundedCornerShape(13.dp)

    Box(modifier = modifier.fillMaxWidth().height(boxHeight)) {
        Row(
            modifier = Modifier.fillMaxWidth().height(boxHeight),
            horizontalArrangement = Arrangement.spacedBy(gap),
        ) {
            for (i in 0 until length) {
                val char = value.getOrNull(i)
                val isCursor = i == value.length
                Box(
                    modifier = Modifier
                        .weight(1f)
                        .height(boxHeight)
                        .clip(shape)
                        .background(Hs.Card)
                        .border(if (isCursor) 1.5.dp else 1.dp, if (isCursor) Hs.Go else Hs.Line, shape),
                    contentAlignment = Alignment.Center,
                ) {
                    if (char != null) {
                        Text(
                            char.toString(),
                            style = HsType.CardTitle.copy(
                                fontSize = 26.sp,
                                fontWeight = FontWeight.SemiBold,
                                fontFeatureSettings = TABULAR,
                            ),
                            color = Hs.TextPrimary,
                        )
                    }
                }
            }
        }
        BasicTextField(
            value = value,
            onValueChange = { raw ->
                val cleaned = if (digitsOnly) {
                    raw.filter { it.isDigit() }
                } else {
                    raw.filter { it.isLetterOrDigit() }.uppercase()
                }
                onValueChange(cleaned.take(length))
            },
            singleLine = true,
            cursorBrush = SolidColor(Color.Transparent),
            keyboardOptions = KeyboardOptions(
                keyboardType = if (digitsOnly) KeyboardType.NumberPassword else KeyboardType.Ascii,
                imeAction = ImeAction.Done,
            ),
            modifier = Modifier
                .matchParentSize()
                .focusRequester(focusRequester)
                .alpha(0f),
        )
    }

    LaunchedEffect(Unit) { focusRequester.requestFocus() }
}

@Preview(name = "Fields", widthDp = 390, backgroundColor = 0xFF15171B, showBackground = true)
@Composable
private fun PreviewFields() {
    HeadstartTheme {
        Column(
            modifier = Modifier.background(Hs.Base).padding(26.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            HsTextField(value = "", onValueChange = {}, placeholder = "Your name")
            HsTextField(value = "+8801712345678", onValueChange = {})
            CodeInput(value = "417", onValueChange = {})
            CodeInput(value = "K7M2QP", onValueChange = {}, digitsOnly = false)
        }
    }
}
