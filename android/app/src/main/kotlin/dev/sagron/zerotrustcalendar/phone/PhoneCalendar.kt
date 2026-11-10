package dev.sagron.zerotrustcalendar.phone

import android.content.ContentProviderOperation
import android.content.ContentResolver
import android.content.ContentValues
import android.net.Uri
import android.provider.CalendarContract
import android.provider.CalendarContract.Calendars
import android.provider.CalendarContract.Events

/**
 * Copies events into calendars of a local "ZT Calendar" account in Android's
 * calendar, so the clock, Wear OS, Android Auto and other apps can show them.
 *
 * Only calendars the user turned on are passed in; every other ZT calendar
 * on this phone is removed with its events. Local account calendars are
 * never synced anywhere by Android. Events are written as single
 * occurrences (the app expands repeats), read-only, without reminders (ZT
 * Calendar shows its own).
 */
class PhoneCalendar(private val resolver: ContentResolver) {

    fun sync(calendars: List<Map<String, Any?>>) {
        val existing = existingCalendars()
        val wanted = calendars.associateBy { it["id"] as String }
        for ((ztId, rowId) in existing) {
            if (ztId !in wanted) {
                resolver.delete(asSyncAdapter(Calendars.CONTENT_URI), "${Calendars._ID} = ?", arrayOf(rowId.toString()))
            }
        }
        for ((ztId, cal) in wanted) {
            val rowId = existing[ztId] ?: insertCalendar(ztId, cal)
            updateCalendar(rowId, cal)
            replaceEvents(rowId, cal)
        }
    }

    private fun existingCalendars(): Map<String, Long> {
        val out = mutableMapOf<String, Long>()
        resolver.query(
            Calendars.CONTENT_URI,
            arrayOf(Calendars._ID, Calendars._SYNC_ID),
            "${Calendars.ACCOUNT_NAME} = ? AND ${Calendars.ACCOUNT_TYPE} = ?",
            arrayOf(ACCOUNT_NAME, CalendarContract.ACCOUNT_TYPE_LOCAL),
            null,
        )?.use { c ->
            while (c.moveToNext()) {
                val syncId = c.getString(1) ?: continue
                out[syncId] = c.getLong(0)
            }
        }
        return out
    }

    private fun insertCalendar(ztId: String, cal: Map<String, Any?>): Long {
        val values = ContentValues().apply {
            put(Calendars.ACCOUNT_NAME, ACCOUNT_NAME)
            put(Calendars.ACCOUNT_TYPE, CalendarContract.ACCOUNT_TYPE_LOCAL)
            put(Calendars.OWNER_ACCOUNT, ACCOUNT_NAME)
            put(Calendars._SYNC_ID, ztId)
            put(Calendars.NAME, cal["name"] as String)
            put(Calendars.CALENDAR_DISPLAY_NAME, cal["name"] as String)
            put(Calendars.CALENDAR_COLOR, (cal["color"] as Number).toInt())
            put(Calendars.CALENDAR_ACCESS_LEVEL, Calendars.CAL_ACCESS_READ)
            put(Calendars.VISIBLE, 1)
            put(Calendars.SYNC_EVENTS, 1)
        }
        val uri = resolver.insert(asSyncAdapter(Calendars.CONTENT_URI), values)
            ?: throw IllegalStateException("Calendar provider refused the calendar")
        return uri.lastPathSegment!!.toLong()
    }

    private fun updateCalendar(rowId: Long, cal: Map<String, Any?>) {
        val values = ContentValues().apply {
            put(Calendars.CALENDAR_DISPLAY_NAME, cal["name"] as String)
            put(Calendars.CALENDAR_COLOR, (cal["color"] as Number).toInt())
        }
        resolver.update(asSyncAdapter(Calendars.CONTENT_URI), values, "${Calendars._ID} = ?", arrayOf(rowId.toString()))
    }

    private fun replaceEvents(rowId: Long, cal: Map<String, Any?>) {
        val ops = ArrayList<ContentProviderOperation>()
        ops.add(
            ContentProviderOperation.newDelete(asSyncAdapter(Events.CONTENT_URI))
                .withSelection("${Events.CALENDAR_ID} = ?", arrayOf(rowId.toString()))
                .build(),
        )
        @Suppress("UNCHECKED_CAST")
        val events = cal["events"] as? List<Map<String, Any?>> ?: emptyList()
        for (e in events) {
            val allDay = e["allDay"] == true
            ops.add(
                ContentProviderOperation.newInsert(asSyncAdapter(Events.CONTENT_URI))
                    .withValue(Events.CALENDAR_ID, rowId)
                    .withValue(Events.TITLE, e["title"] as? String ?: "")
                    .withValue(Events.EVENT_LOCATION, e["location"] as? String ?: "")
                    .withValue(Events.DTSTART, (e["start"] as Number).toLong())
                    .withValue(Events.DTEND, (e["end"] as Number).toLong())
                    .withValue(Events.ALL_DAY, if (allDay) 1 else 0)
                    // All-day events are UTC midnights, as Android expects.
                    .withValue(Events.EVENT_TIMEZONE, if (allDay) "UTC" else java.util.TimeZone.getDefault().id)
                    .withValue(Events.HAS_ALARM, 0)
                    .withValue(Events.ACCESS_LEVEL, Events.ACCESS_DEFAULT)
                    .build(),
            )
            if (ops.size >= 400) {
                resolver.applyBatch(CalendarContract.AUTHORITY, ops)
                ops.clear()
            }
        }
        if (ops.isNotEmpty()) resolver.applyBatch(CalendarContract.AUTHORITY, ops)
    }

    private fun asSyncAdapter(uri: Uri): Uri = uri.buildUpon()
        .appendQueryParameter(CalendarContract.CALLER_IS_SYNCADAPTER, "true")
        .appendQueryParameter(Calendars.ACCOUNT_NAME, ACCOUNT_NAME)
        .appendQueryParameter(Calendars.ACCOUNT_TYPE, CalendarContract.ACCOUNT_TYPE_LOCAL)
        .build()

    companion object {
        const val ACCOUNT_NAME = "ZT Calendar"
    }
}
