package dev.sagron.zerotrustcalendar.widget

import android.app.ActivityOptions
import android.app.AlarmManager
import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.net.Uri
import android.os.Build
import dev.sagron.zerotrustcalendar.MainActivity
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import java.time.LocalDate
import java.time.ZoneId
import java.util.Locale

/**
 * Shared by the month grid and agenda widgets (W9): the app's language, the
 * refresh at midnight (and when an agenda event ends), and row taps.
 */
internal object CalendarWidgets {
    const val ACTION_REFRESH = "dev.sagron.zerotrustcalendar.widget.REFRESH"

    /** The language picked in the app's Settings, else the phone's. */
    fun locale(prefs: SharedPreferences): Locale =
        prefs.getString("calendar_widget_lang", null)?.let { Locale.forLanguageTag(it) } ?: Locale.getDefault()

    fun text(context: Context, prefs: SharedPreferences, key: String, fallback: Int): String =
        prefs.getString("calendar_text_$key", null) ?: context.getString(fallback)

    fun today(): LocalDate = LocalDate.now()

    fun launch(context: Context, uri: String): PendingIntent =
        HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java, Uri.parse(uri))

    /** Redraws both widgets. */
    fun refreshAll(context: Context) {
        val manager = AppWidgetManager.getInstance(context)
        manager.getAppWidgetIds(ComponentName(context, MonthWidgetProvider::class.java)).forEach {
            MonthWidgetProvider.update(context, manager, it)
        }
        manager.getAppWidgetIds(ComponentName(context, AgendaWidgetProvider::class.java)).forEach {
            AgendaWidgetProvider.update(context, manager, it)
        }
    }

    /**
     * Wakes the widgets next at [atMillis] (an event's end) or at midnight,
     * whichever comes first. Inexact and not waking the phone: the next look
     * at the home screen is what counts.
     */
    fun scheduleRefresh(context: Context, atMillis: Long? = null) {
        val midnight = today().plusDays(1).atStartOfDay(ZoneId.systemDefault()).toInstant().toEpochMilli() + 60_000
        val at = if (atMillis != null && atMillis < midnight) atMillis + 30_000 else midnight
        val intent = Intent(context, MonthWidgetProvider::class.java).setAction(ACTION_REFRESH)
        // Midnight and "an event ended" are two alarms, so neither replaces the other.
        val pending = PendingIntent.getBroadcast(
            context,
            if (at == midnight) 0 else 1,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        context.getSystemService(AlarmManager::class.java)?.set(AlarmManager.RTC, at, pending)
    }

    /** One mutable template per list (explicit component); rows fill in their URI. */
    fun rowTemplate(context: Context, requestCode: Int): PendingIntent {
        val intent = Intent(context, MainActivity::class.java).apply {
            action = HomeWidgetLaunchIntent.HOME_WIDGET_LAUNCH_ACTION
        }
        val flags = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE
        if (Build.VERSION.SDK_INT < 34) return PendingIntent.getActivity(context, requestCode, intent, flags)
        val options = ActivityOptions.makeBasic()
        if (Build.VERSION.SDK_INT >= 35) {
            options.setPendingIntentCreatorBackgroundActivityStartMode(
                ActivityOptions.MODE_BACKGROUND_ACTIVITY_START_ALLOWED,
            )
        } else {
            @Suppress("DEPRECATION")
            options.pendingIntentBackgroundActivityStartMode =
                ActivityOptions.MODE_BACKGROUND_ACTIVITY_START_ALLOWED
        }
        return PendingIntent.getActivity(context, requestCode, intent, flags, options.toBundle())
    }
}
