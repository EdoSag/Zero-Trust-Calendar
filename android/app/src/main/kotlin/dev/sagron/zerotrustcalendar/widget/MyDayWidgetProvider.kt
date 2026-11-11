package dev.sagron.zerotrustcalendar.widget

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.graphics.Color
import android.net.Uri
import android.os.Bundle
import android.view.View
import android.widget.RemoteViews
import dev.sagron.zerotrustcalendar.MainActivity
import dev.sagron.zerotrustcalendar.R
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetPlugin
import es.antonborri.home_widget.HomeWidgetProvider

/**
 * "My day" (roadmap W15): the next event, then the ZT Tasks tasks due
 * today, as the app last saved them (lib/widget/my_day_widget.dart). It
 * never reads the vault. Titles are only saved when the user turned on
 * "Show details on the home screen"; otherwise rows say "Event" and "Task".
 *
 * Shared Zero-Trust widget look (Zero-Trust-Core/android-widget-kit). How
 * many tasks show follows the widget's height; when none fit, a count does.
 * Tapping the tasks opens ZT Tasks; the rest opens today; + a new event.
 */
class MyDayWidgetProvider : HomeWidgetProvider() {

    companion object {
        private const val MAX_TASKS = 6
        private val ROWS = intArrayOf(
            R.id.task_row0, R.id.task_row1, R.id.task_row2,
            R.id.task_row3, R.id.task_row4, R.id.task_row5,
        )
        private val TITLES = intArrayOf(
            R.id.task_title0, R.id.task_title1, R.id.task_title2,
            R.id.task_title3, R.id.task_title4, R.id.task_title5,
        )
        private val TIMES = intArrayOf(
            R.id.task_time0, R.id.task_time1, R.id.task_time2,
            R.id.task_time3, R.id.task_time4, R.id.task_time5,
        )
    }

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        appWidgetIds.forEach { widgetId ->
            appWidgetManager.updateAppWidget(
                widgetId,
                buildViews(context, widgetData, appWidgetManager.getAppWidgetOptions(widgetId)),
            )
        }
    }

    /** Resized: redraw with as many tasks as now fit. */
    override fun onAppWidgetOptionsChanged(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
        newOptions: Bundle,
    ) {
        appWidgetManager.updateAppWidget(
            appWidgetId,
            buildViews(context, HomeWidgetPlugin.getData(context), newOptions),
        )
    }

    private fun buildViews(context: Context, data: SharedPreferences, options: Bundle?): RemoteViews {
        val views = RemoteViews(context.packageName, R.layout.widget_my_day)
        fun text(key: String, res: Int) = data.getString(key, null) ?: context.getString(res)
        // Portrait height; 0 when the launcher hasn't said yet.
        val height = options?.getInt(AppWidgetManager.OPTION_APPWIDGET_MAX_HEIGHT, 0) ?: 0
        val showAppRow = height == 0 || height >= 200
        // Header (~72dp) + "Next" label and row (~52dp) + tasks label (~22dp).
        val used = 146 + (if (showAppRow) 26 else 0)
        val maxTasks = if (height == 0) MAX_TASKS else ((height - used) / 28).coerceIn(0, MAX_TASKS)
        val locked = data.getBoolean("myday_locked", false)
        // Never saved yet (the app hasn't run since the widget was added).
        val empty = !data.contains("myday_header")

        views.setViewVisibility(R.id.app_row, if (showAppRow) View.VISIBLE else View.GONE)
        views.setTextViewText(R.id.header_title, text("myday_header", R.string.my_day_header))
        val date = data.getString("myday_date", null) ?: ""
        views.setTextViewText(R.id.date, date)
        views.setViewVisibility(R.id.date, if (locked || date.isEmpty()) View.GONE else View.VISIBLE)

        val hidden = locked || empty
        views.setViewVisibility(R.id.content, if (hidden) View.GONE else View.VISIBLE)
        views.setViewVisibility(R.id.locked, if (hidden) View.VISIBLE else View.GONE)
        views.setTextViewText(
            R.id.locked_text,
            if (locked) text("myday_locked_text", R.string.my_day_signed_out)
            else context.getString(R.string.my_day_open_app),
        )

        if (!hidden) {
            views.setTextViewText(R.id.next_label, text("myday_next_label", R.string.my_day_next))
            val nextTime = data.getString("myday_next_time", null)
            views.setTextViewText(R.id.next_title, data.getString("myday_next_title", "") ?: "")
            views.setTextViewText(R.id.next_time, nextTime ?: "")
            views.setViewVisibility(R.id.next_time, if (nextTime == null) View.GONE else View.VISIBLE)
            val color = data.getString("myday_next_color", null)
            views.setViewVisibility(R.id.next_dot, if (color == null) View.INVISIBLE else View.VISIBLE)
            if (color != null) {
                val parsed = try { Color.parseColor(color) } catch (e: Exception) { Color.GRAY }
                views.setInt(R.id.next_dot, "setColorFilter", parsed)
            }

            val total = data.getInt("myday_count", 0)
            val shown = total.coerceAtMost(maxTasks)
            views.setTextViewText(R.id.tasks_label, text("myday_tasks_label", R.string.my_day_tasks))
            val overdue = data.getString("myday_overdue", null)
            views.setTextViewText(R.id.overdue, overdue ?: "")
            views.setViewVisibility(R.id.overdue, if (overdue == null) View.GONE else View.VISIBLE)
            // No room for rows, or nothing due: one line says so.
            val summary = when {
                total == 0 -> text("myday_no_tasks", R.string.my_day_no_tasks)
                total > shown && shown > 0 ->
                    text("myday_text_more", R.string.up_next_more).replace("{n}", "${total - shown}")
                else -> ""
            }
            views.setTextViewText(R.id.tasks_summary, summary)
            views.setViewVisibility(
                R.id.tasks_summary,
                if (summary.isEmpty() || (total > 0 && shown == 0)) View.GONE else View.VISIBLE,
            )
            for (i in ROWS.indices) {
                if (i < shown) {
                    views.setViewVisibility(ROWS[i], View.VISIBLE)
                    views.setTextViewText(TITLES[i], data.getString("myday_${i}_title", "") ?: "")
                    val time = data.getString("myday_${i}_time", "") ?: ""
                    views.setTextViewText(TIMES[i], time)
                    views.setViewVisibility(TIMES[i], if (time.isEmpty()) View.GONE else View.VISIBLE)
                } else {
                    views.setViewVisibility(ROWS[i], View.GONE)
                }
            }
        }

        views.setOnClickPendingIntent(
            R.id.widget_root,
            HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java, Uri.parse("ztcalendar://today")),
        )
        views.setOnClickPendingIntent(
            R.id.tasks,
            HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java, Uri.parse("ztcalendar://tasks")),
        )
        views.setOnClickPendingIntent(
            R.id.add_button,
            HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java, Uri.parse("ztcalendar://new-event")),
        )
        return views
    }
}
