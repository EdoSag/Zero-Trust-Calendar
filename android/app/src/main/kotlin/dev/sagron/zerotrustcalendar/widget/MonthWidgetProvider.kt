package dev.sagron.zerotrustcalendar.widget

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.graphics.Color
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.view.View
import android.widget.RemoteViews
import dev.sagron.zerotrustcalendar.R
import es.antonborri.home_widget.HomeWidgetPlugin
import es.antonborri.home_widget.HomeWidgetProvider
import org.json.JSONObject
import java.time.DayOfWeek
import java.time.LocalDate
import java.time.format.DateTimeFormatter
import java.time.format.TextStyle

/**
 * Month grid (W9, K10): six weeks around the month, today in the accent
 * circle, a dot under days with events (in the first event's calendar
 * colour), arrows to the previous and next month. Tap a day to open it in
 * the app.
 *
 * The grid itself is drawn here from the date, so it is right even before
 * the app has run. The app only writes which days have events
 * (`calendar_month_dots`, colours only, never titles) for the previous month
 * to two months ahead, and the week start and language.
 */
class MonthWidgetProvider : HomeWidgetProvider() {

    companion object {
        private const val ACTION_MONTH = "dev.sagron.zerotrustcalendar.widget.MONTH"
        private const val EXTRA_DELTA = "delta"

        private fun offsetKey(widgetId: Int) = "calendar_month_${widgetId}_offset"

        fun update(context: Context, manager: AppWidgetManager, widgetId: Int) {
            val prefs = HomeWidgetPlugin.getData(context)
            manager.updateAppWidget(widgetId, buildViews(context, prefs, widgetId))
        }

        private fun buildViews(context: Context, prefs: SharedPreferences, widgetId: Int): RemoteViews {
            val views = RemoteViews(context.packageName, R.layout.widget_month)
            val locale = CalendarWidgets.locale(prefs)
            val today = CalendarWidgets.today()
            val month = today.withDayOfMonth(1).plusMonths(prefs.getInt(offsetKey(widgetId), 0).toLong())
            val weekStart = DayOfWeek.of(prefs.getInt("calendar_week_start", 1).coerceIn(1, 7))
            val dots = try {
                prefs.getString("calendar_month_dots", null)?.let { JSONObject(it) }
            } catch (e: Exception) {
                null
            }

            views.setTextViewText(
                R.id.month_title,
                month.format(DateTimeFormatter.ofPattern("LLLL yyyy", locale)),
            )
            views.setOnClickPendingIntent(
                R.id.month_title,
                CalendarWidgets.launch(context, "ztcalendar://day?date=$month"),
            )
            views.setOnClickPendingIntent(R.id.month_app_icon, CalendarWidgets.launch(context, "ztcalendar://today"))
            views.setOnClickPendingIntent(R.id.month_prev, monthIntent(context, widgetId, -1))
            views.setOnClickPendingIntent(R.id.month_next, monthIntent(context, widgetId, 1))
            views.setContentDescription(
                R.id.month_prev,
                CalendarWidgets.text(context, prefs, "prev_month", R.string.month_prev),
            )
            views.setContentDescription(
                R.id.month_next,
                CalendarWidgets.text(context, prefs, "next_month", R.string.month_next),
            )

            // Hebrew short names are whole words ("יום א׳"): use the letter.
            val style = if (locale.language == "he" || locale.language == "iw") TextStyle.NARROW_STANDALONE else TextStyle.SHORT_STANDALONE
            for (i in 0 until 7) {
                views.setTextViewText(MonthGridIds.WEEKDAYS[i], weekStart.plus(i.toLong()).getDisplayName(style, locale))
            }

            val back = ((month.dayOfWeek.value - weekStart.value) + 7) % 7
            val first = month.minusDays(back.toLong())
            val onAccent = context.getColor(R.color.zt_widget_on_accent)
            val dayFormat = DateTimeFormatter.ofPattern("EEEE d MMMM", locale)
            for (i in 0 until 42) {
                val date: LocalDate = first.plusDays(i.toLong())
                val dayId = MonthGridIds.DAYS[i]
                val inMonth = date.month == month.month
                views.setTextViewText(dayId, date.dayOfMonth.toString())
                views.setContentDescription(MonthGridIds.CELLS[i], date.format(dayFormat))
                if (date == today) {
                    views.setInt(dayId, "setBackgroundResource", R.drawable.zt_widget_accent_circle)
                    views.setTextColor(dayId, onAccent)
                } else if (!inMonth) {
                    // Days of the months around it: muted.
                    if (Build.VERSION.SDK_INT >= 31) {
                        // Resolved by the launcher, so it follows light and dark.
                        views.setColorStateList(dayId, "setTextColor", R.color.zt_widget_on_surface_variant)
                    } else {
                        views.setTextColor(dayId, context.getColor(R.color.zt_widget_on_surface_variant))
                    }
                }
                val color = dots?.optJSONArray(date.toString())?.optString(0)
                if (color.isNullOrEmpty()) {
                    views.setViewVisibility(MonthGridIds.DOTS[i], View.GONE)
                } else {
                    views.setViewVisibility(MonthGridIds.DOTS[i], View.VISIBLE)
                    val parsed = try { Color.parseColor(color) } catch (e: Exception) { Color.GRAY }
                    views.setInt(MonthGridIds.DOTS[i], "setColorFilter", parsed)
                }
                views.setOnClickPendingIntent(
                    MonthGridIds.CELLS[i],
                    CalendarWidgets.launch(context, "ztcalendar://day?date=$date"),
                )
            }
            return views
        }

        private fun monthIntent(context: Context, widgetId: Int, delta: Int): PendingIntent {
            val intent = Intent(context, MonthWidgetProvider::class.java).apply {
                action = ACTION_MONTH
                putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, widgetId)
                putExtra(EXTRA_DELTA, delta)
                data = Uri.parse("ztcalendar://widget/$widgetId/month/$delta")
            }
            return PendingIntent.getBroadcast(
                context,
                widgetId * 2 + (if (delta > 0) 1 else 0),
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        }
    }

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        appWidgetIds.forEach { appWidgetManager.updateAppWidget(it, buildViews(context, widgetData, it)) }
        CalendarWidgets.scheduleRefresh(context)
    }

    override fun onAppWidgetOptionsChanged(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
        newOptions: Bundle,
    ) {
        update(context, appWidgetManager, appWidgetId)
    }

    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            ACTION_MONTH -> {
                val widgetId = intent.getIntExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, AppWidgetManager.INVALID_APPWIDGET_ID)
                if (widgetId == AppWidgetManager.INVALID_APPWIDGET_ID) return
                val prefs = HomeWidgetPlugin.getData(context)
                // Up to a year either way.
                val offset = (prefs.getInt(offsetKey(widgetId), 0) + intent.getIntExtra(EXTRA_DELTA, 0)).coerceIn(-12, 12)
                prefs.edit().putInt(offsetKey(widgetId), offset).apply()
                update(context, AppWidgetManager.getInstance(context), widgetId)
            }
            // Midnight, an agenda event ended, or the clock or time zone changed.
            CalendarWidgets.ACTION_REFRESH,
            Intent.ACTION_DATE_CHANGED,
            Intent.ACTION_TIME_CHANGED,
            Intent.ACTION_TIMEZONE_CHANGED -> {
                // A new day: every month grid goes back to this month.
                if (intent.action != CalendarWidgets.ACTION_REFRESH) clearOffsets(context)
                CalendarWidgets.refreshAll(context)
                CalendarWidgets.scheduleRefresh(context)
            }
            else -> super.onReceive(context, intent)
        }
    }

    override fun onDeleted(context: Context, appWidgetIds: IntArray) {
        super.onDeleted(context, appWidgetIds)
        val editor = HomeWidgetPlugin.getData(context).edit()
        appWidgetIds.forEach { editor.remove(offsetKey(it)) }
        editor.apply()
    }

    private fun clearOffsets(context: Context) {
        val manager = AppWidgetManager.getInstance(context)
        val editor = HomeWidgetPlugin.getData(context).edit()
        manager.getAppWidgetIds(android.content.ComponentName(context, MonthWidgetProvider::class.java))
            .forEach { editor.remove(offsetKey(it)) }
        editor.apply()
    }
}
