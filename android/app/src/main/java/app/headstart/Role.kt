package app.headstart

/**
 * Which side of the pair the local user is on today. Either paired person can drive, so
 * Home carries one switch (`ui/components/RoleSwitch.kt`) rather than a fixed account role.
 *
 * NOTE for the batch that lands `Prefs.kt`: the plan doc declares this enum inside
 * `Prefs.kt`. It lives here instead because `RoleSwitch` needs it and `Prefs` pulls in
 * `android.content.Context`. Do NOT redeclare it in `Prefs.kt` — just use it.
 */
enum class Role { DRIVING, WAITING }
