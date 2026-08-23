package app.headstart

import android.app.Application
import app.headstart.push.Notifications

class HeadstartApp : Application() {
    override fun onCreate() {
        super.onCreate()
        // First thing, before any other Firebase call: decides emulator vs cloud.
        ServiceLocator.init(this)
        // The two contract channels, sync_urgent and sync_updates, are created exactly
        // once — here. (The plan's Task 15 comment saying "Task 17" is stale; Task 17 is
        // the receiver screens.)
        Notifications.createChannels(this)
    }
}
