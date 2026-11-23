package dev.sagron.zerotrustcalendar

import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager

/**
 * ZT Keyboard's "Insert from ZT apps" key: the keyboard opens this app to let the user
 * pick a date or an event's time, and types what was picked.
 *
 * Only a Zero-Trust app may ask. All of them are signed with the same key, so the caller
 * must carry this app's own signature; anyone else is turned away before anything is
 * shown. The answer is the one text the user tapped, nothing more, and only after the
 * vault was unlocked as usual.
 */
object TextPick {
    const val ACTION = "bz.zerotrust.action.PICK_TEXT"
    const val EXTRA_TEXT = "bz.zerotrust.extra.TEXT"

    fun isPick(intent: Intent?): Boolean = intent?.action == ACTION

    /**
     * Whether [activity] was opened, for an answer, by an app signed with this app's key.
     * Android only names the caller when it waits for an answer, and that name cannot be
     * faked by the caller.
     */
    fun callerAllowed(activity: Activity): Boolean {
        val caller = activity.callingPackage ?: return false
        return try {
            activity.packageManager.checkSignatures(activity.packageName, caller) ==
                PackageManager.SIGNATURE_MATCH
        } catch (error: Exception) {
            false
        }
    }

    /**
     * Answers with [text]. When the caller asked for an item ([ZtLinks.EXTRA_WANT_ITEM], ZT
     * Time) and an event was picked, its id, title and times go along ([item]).
     */
    fun answer(activity: Activity, text: String?, item: Map<String, Any?>? = null) {
        if (text.isNullOrEmpty()) {
            activity.setResult(Activity.RESULT_CANCELED)
        } else {
            val data = Intent().putExtra(EXTRA_TEXT, text)
            if (item != null && ZtLinks.wantsItem(activity.intent)) {
                (item["id"] as? String)?.let { data.putExtra(ZtLinks.EXTRA_ITEM_ID, it) }
                (item["title"] as? String)?.let { data.putExtra(ZtLinks.EXTRA_TITLE, it) }
                (item["startMs"] as? Number)?.let { data.putExtra(ZtLinks.EXTRA_START_MS, it.toLong()) }
                (item["endMs"] as? Number)?.let { data.putExtra(ZtLinks.EXTRA_END_MS, it.toLong()) }
            }
            activity.setResult(Activity.RESULT_OK, data)
        }
        activity.finish()
    }
}
