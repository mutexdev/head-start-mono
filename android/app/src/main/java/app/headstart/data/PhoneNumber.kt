package app.headstart.data

/**
 * Just enough phone handling for a sign-in screen. Deliberately not libphonenumber:
 * Firebase validates the number server-side, and the 2 MB metadata blob buys us nothing
 * in M1 beyond nicer formatting.
 */
object PhoneNumber {

    private const val MIN_NATIONAL_DIGITS = 6
    private const val MAX_NATIONAL_DIGITS = 14

    /** "+880" + "01712 345678" -> "+8801712345678"; null when it could not be dialled. */
    fun toE164(dialCode: String, national: String): String? {
        val dial = dialCode.filter { it.isDigit() }
        if (dial.isEmpty() || dial.length > 4) return null
        val digits = national.filter { it.isDigit() }.trimStart('0')
        if (digits.length < MIN_NATIONAL_DIGITS || digits.length > MAX_NATIONAL_DIGITS) return null
        return "+$dial$digits"
    }

    /** "+880 1712345678" for the Verify screen subtitle. */
    fun display(dialCode: String, national: String): String {
        val dial = dialCode.filter { it.isDigit() }
        val digits = national.filter { it.isDigit() }.trimStart('0')
        return "+$dial $digits"
    }

    fun isValidSmsCode(code: String): Boolean = code.length == 6 && code.all { it.isDigit() }
}
