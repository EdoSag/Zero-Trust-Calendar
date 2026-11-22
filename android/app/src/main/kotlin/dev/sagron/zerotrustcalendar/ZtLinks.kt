package dev.sagron.zerotrustcalendar

import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager

/**
 * Links with ZT Time (see the suite's "ZT Time links" protocol, TM-2 / TM-5):
 *
 * - [trackTime]: "Log as time entry" on an event hands its id, title and times to ZT Time,
 *   which opens "Add time" filled in. Started for a result, so Time can tell which app
 *   asked (only apps signed with the suite's key are answered).
 * - [OPEN_ITEM]: ZT Time opens an event it is linked to. The id only says which event to
 *   show after the normal unlock; nothing is sent back.
 * - [EXTRA_WANT_ITEM] on a [TextPick] request: the picker answers with the picked event's
 *   id, title and times as well as its text.
 */
object ZtLinks {
    const val TIME_PACKAGE = "dev.sagron.zerotrusttime"
    const val ACTION_TRACK_TIME = "bz.zerotrust.action.TRACK_TIME"
    const val OPEN_ITEM = "bz.zerotrust.action.OPEN_ITEM"
    const val EXTRA_ITEM_ID = "bz.zerotrust.extra.ITEM_ID"
    const val EXTRA_TITLE = "bz.zerotrust.extra.TITLE"
    const val EXTRA_START_MS = "bz.zerotrust.extra.START_MS"
    const val EXTRA_END_MS = "bz.zerotrust.extra.END_MS"
    const val EXTRA_WANT_ITEM = "bz.zerotrust.extra.WANT_ITEM"
    const val REQUEST_TRACK_TIME = 4108

    /** Whether ZT Time is installed and signed with this app's key. */
    fun timeInstalled(activity: Activity): Boolean = try {
        activity.packageManager.getPackageInfo(TIME_PACKAGE, 0)
        activity.packageManager.checkSignatures(activity.packageName, TIME_PACKAGE) ==
            PackageManager.SIGNATURE_MATCH
    } catch (e: Exception) {
        false
    }

    /** Opens ZT Time's "Add time" for an event. False when Time can't take it. */
    fun trackTime(activity: Activity, itemId: String, title: String, startMs: Long?, endMs: Long?): Boolean {
        if (!timeInstalled(activity)) return false
        val intent = Intent(ACTION_TRACK_TIME).setPackage(TIME_PACKAGE).apply {
            putExtra(EXTRA_ITEM_ID, itemId)
            putExtra(EXTRA_TITLE, title)
            if (startMs != null && endMs != null) {
                putExtra(EXTRA_START_MS, startMs)
                putExtra(EXTRA_END_MS, endMs)
            }
        }
        if (intent.resolveActivity(activity.packageManager) == null) return false
        return try {
            activity.startActivityForResult(intent, REQUEST_TRACK_TIME)
            true
        } catch (e: Exception) {
            false
        }
    }

    /** The event id ZT Time asked to open, or null for another intent. */
    fun openItemId(intent: Intent?): String? =
        if (intent?.action == OPEN_ITEM) intent.getStringExtra(EXTRA_ITEM_ID)?.takeIf { it.isNotBlank() && it.length <= 512 } else null

    fun wantsItem(intent: Intent?): Boolean = intent?.getBooleanExtra(EXTRA_WANT_ITEM, false) ?: false
}
