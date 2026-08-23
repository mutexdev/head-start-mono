package app.headstart.ui

import com.google.common.truth.Truth.assertThat
import org.junit.Test

class OemGuidanceTest {

    @Test fun `the aggressive battery killers are recognised, whatever the casing`() {
        val table = listOf(
            "Xiaomi", "xiaomi", "XIAOMI",
            "Redmi", "POCO",
            "HUAWEI", "HONOR",
            "OnePlus", "oneplus",
            "OPPO", "realme",
            "vivo",
        )
        for (manufacturer in table) {
            assertThat(needsBatteryGuidance(manufacturer)).isTrue()
        }
    }

    @Test fun `phones that respect foreground services are left alone`() {
        for (manufacturer in listOf("Google", "samsung", "Sony", "Motorola", "Nothing", "")) {
            assertThat(needsBatteryGuidance(manufacturer)).isFalse()
        }
    }
}
