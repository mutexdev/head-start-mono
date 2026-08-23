package app.headstart

import android.content.Intent
import android.os.Bundle
import android.util.Log
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import app.headstart.core.HeadstartConfig
import app.headstart.ui.HeadstartNavGraph
import app.headstart.ui.inviteCodeFromIntentData
import app.headstart.ui.theme.HeadstartTheme
import app.headstart.ui.theme.Hs

/**
 * The whole app is one activity. `launchMode="singleTask"` (see AndroidManifest) means a
 * second `headstart://pair/{code}` link does NOT create a new instance — it arrives at
 * [onNewIntent], which is why the deep-link code is held in mutable state rather than read
 * once from `intent` in [onCreate].
 */
class MainActivity : ComponentActivity() {

    private var deepLinkCode by mutableStateOf<String?>(null)

    override fun onCreate(savedInstanceState: Bundle?) {
        enableEdgeToEdge()
        super.onCreate(savedInstanceState)
        deepLinkCode = readInviteCode(intent)
        setContent {
            HeadstartTheme {
                Box(Modifier.fillMaxSize().background(Hs.Base)) {
                    HeadstartNavGraph(deepLinkCode = deepLinkCode)
                }
            }
        }
    }

    /** launchMode="singleTask": a second `headstart://pair/...` link lands here. */
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        // No recreate(): updating the state re-runs the graph's deep-link effect while
        // keeping the ViewModel's Firestore listeners attached.
        readInviteCode(intent)?.let { deepLinkCode = it }
    }

    private fun readInviteCode(intent: Intent?): String? {
        val code = inviteCodeFromIntentData(intent?.dataString)
        if (code != null) {
            Log.i(HeadstartConfig.LOG_TAG, "invite deep link received: $code")
        }
        return code
    }
}
