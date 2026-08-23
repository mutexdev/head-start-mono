package app.headstart

import android.content.Context
import app.headstart.core.Callables
import app.headstart.core.HeadstartConfig
import app.headstart.data.AuthRepository
import app.headstart.data.FirestorePositionSink
import app.headstart.data.PairRepository
import app.headstart.data.PositionSink
import app.headstart.data.SpotRepository
import app.headstart.data.TripRepository
import com.google.firebase.auth.FirebaseAuth
import com.google.firebase.firestore.FirebaseFirestore
import com.google.firebase.functions.FirebaseFunctions

/**
 * Hand-wired dependency graph. Deliberately not Hilt: the object graph is a dozen
 * singletons deep, everything testable is already a pure class, and a build-time DI
 * processor would cost more than it saves in a one-module app.
 *
 * [init] runs once from [HeadstartApp.onCreate]; everything else is lazy so unit tests
 * never touch Firebase.
 */
object ServiceLocator {

    lateinit var appContext: Context
        private set

    /**
     * Point the three Firebase clients at their backend BEFORE anyone touches them.
     * [HeadstartConfig.wire] must be the first Firebase call this process makes, so this
     * function deliberately forces the `auth`/`db`/`functions` lazies itself.
     */
    fun init(context: Context) {
        appContext = context.applicationContext
        HeadstartConfig.useCloudOverride = prefs.useCloud
        HeadstartConfig.wire(auth, db, functions)
    }

    val auth: FirebaseAuth by lazy { FirebaseAuth.getInstance() }
    val db: FirebaseFirestore by lazy { FirebaseFirestore.getInstance() }
    val functions: FirebaseFunctions by lazy { FirebaseFunctions.getInstance() }

    val callables: Callables by lazy { Callables(functions) }
    val positionSink: PositionSink by lazy { FirestorePositionSink(db) }
    val prefs: Prefs by lazy { Prefs(appContext) }

    val authRepository: AuthRepository by lazy { AuthRepository(auth, callables) }
    val pairRepository: PairRepository by lazy { PairRepository(db, callables) }
    val spotRepository: SpotRepository by lazy { SpotRepository(db, callables) }
    val tripRepository: TripRepository by lazy { TripRepository(db, callables) }
}
