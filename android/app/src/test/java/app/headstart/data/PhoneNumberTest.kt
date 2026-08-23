package app.headstart.data

import com.google.common.truth.Truth.assertThat
import org.junit.Test

class PhoneNumberTest {

    @Test fun `builds an e164 number from a dial code and a national number`() {
        val table = listOf(
            Triple("+880", "1712 345678", "+8801712345678"),
            Triple("880", "1712345678", "+8801712345678"),
            Triple("+880", "01712345678", "+8801712345678"),   // national trunk zero is dropped
            Triple("+1", "(415) 555-0132", "+14155550132"),
            Triple("+44", "07700 900123", "+447700900123"),
        )
        for ((dial, national, expected) in table) {
            assertThat(PhoneNumber.toE164(dial, national)).isEqualTo(expected)
        }
    }

    @Test fun `rejects numbers that cannot be dialled`() {
        val table = listOf(
            "" to "1712345678",          // no dial code
            "+" to "1712345678",
            "+880" to "",                // no national part
            "+880" to "12345",           // too short
            "+880" to "1234567890123456",// too long
            "+abc" to "1712345678",
        )
        for ((dial, national) in table) {
            assertThat(PhoneNumber.toE164(dial, national)).isNull()
        }
    }

    @Test fun `formats a number for display without changing it`() {
        assertThat(PhoneNumber.display("+880", "1712345678")).isEqualTo("+880 1712345678")
        assertThat(PhoneNumber.display("880", "1712 345678")).isEqualTo("+880 1712345678")
    }

    @Test fun `sms code validity`() {
        assertThat(PhoneNumber.isValidSmsCode("492156")).isTrue()
        assertThat(PhoneNumber.isValidSmsCode("49215")).isFalse()
        assertThat(PhoneNumber.isValidSmsCode("4921567")).isFalse()
        assertThat(PhoneNumber.isValidSmsCode("49a156")).isFalse()
        assertThat(PhoneNumber.isValidSmsCode("")).isFalse()
    }
}
