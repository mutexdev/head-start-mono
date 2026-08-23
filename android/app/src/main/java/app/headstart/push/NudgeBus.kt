package app.headstart.push

import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow

/**
 * A `didYouLeave` push has to do two things: land in the tray, and — if the driver is
 * looking at the trip screen — raise the bottom sheet from DriverNudge.dc.html. This is
 * the second half. One boolean, no library.
 */
object NudgeBus {
    private val _showDidYouLeave = MutableStateFlow(false)
    val showDidYouLeave: StateFlow<Boolean> = _showDidYouLeave

    fun raise() {
        _showDidYouLeave.value = true
    }

    fun clear() {
        _showDidYouLeave.value = false
    }
}
