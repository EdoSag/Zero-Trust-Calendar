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
 * "Up next": the next few events, as the app last saved them
 * (lib/widget/up_next_widget.dart). It never reads the vault. Event titles
 * are only saved when the user turned on "Show details on the home screen";
 * otherwise the rows say "Event" with the time.
 *
 * Shared Zero-Trust widget look (Zero-Trust-Core/android-widget-kit). The
 * number of rows follows the widget's height; + opens a new event.
 */
class UpNextWidgetProvider : HomeWidgetProvider() {

    companion object {
        private const val MAX_ROWS = 5
        private val ROWS = intArrayOf(R.id.row0, R.id.row1, R.id.row2, R.id.row3, R.id.row4)
        private val TIMES = intArrayOf(R.id.time0, R.id.time1, R.id.time2, R.id.time3, R.id.time4)
        private val TITLES = intArrayOf(R.id.title0, R.id.title1, R.id.title2, R.id.title3, R.id.title4)
        private val DOTS = intArrayOf(R.id.dot0, R.id.dot1, R.id.dot2, R.id.dot3, R.id.dot4)
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

    /** Resized: redraw with as many rows as now fit. */
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
        val views = RemoteViews(context.packageName, R.layout.widget_up_next)
        // Portrait height; 0 when the launcher hasn't said yet.
        val height = options?.getInt(AppWidgetManager.OPTION_APPWIDGET_MAX_HEIGHT, 0) ?: 0
        val showAppRow = height == 0 || height >= 160
        val maxRows = if (height == 0) MAX_ROWS else ((height - 78 - (if (showAppRow) 26 else 0)) / 32).coerceIn(0, MAX_ROWS)
        val locked = data.getBoolean("upnext_locked", false)
        val count = data.getInt("upnext_count", 0).coerceIn(0, maxRows)

        views.setViewVisibility(R.id.app_row, if (showAppRow) View.VISIBLE else View.GONE)
        views.setTextViewText(R.id.header_title, data.getString("upnext_header", null) ?: context.getString(R.string.up_next_header))
        val empty = data.getString("upnext_empty", null) ?: context.getString(R.string.up_next_open_app)
        // Captions the app saved in its own language, else this phone's.
        fun text(key: String, res: Int) = data.getString(key, null) ?: context.getString(res)
        val total = data.getInt("upnext_count", 0)
        // The caption: what's missing, or how many more than fit.
        val caption = when {
            locked -> text("upnext_text_signed_out", R.string.up_next_signed_out)
            total == 0 -> empty
            total > count && count > 0 ->
                text("upnext_text_more", R.string.up_next_more).replace("{n}", "${total - count}")
            count == 0 -> if (total == 1) text("upnext_text_coming_one", R.string.up_next_coming_one)
                else text("upnext_text_coming_many", R.string.up_next_coming_many).replace("{n}", "$total")
            else -> ""
        }
        views.setTextViewText(R.id.summary, caption)
        views.setViewVisibility(R.id.summary, if (caption.isEmpty()) View.GONE else View.VISIBLE)
        views.setViewVisibility(R.id.locked, if (locked && (height == 0 || height >= 100)) View.VISIBLE else View.GONE)
        views.setViewVisibility(R.id.rows, if (locked || count == 0) View.GONE else View.VISIBLE)

        for (i in ROWS.indices) {
            if (!locked && i < count) {
                views.setViewVisibility(ROWS[i], View.VISIBLE)
                views.setTextViewText(TIMES[i], data.getString("upnext_${i}_time", "") ?: "")
                views.setTextViewText(TITLES[i], data.getString("upnext_${i}_title", "") ?: "")
                val color = data.getString("upnext_${i}_color", null)
                val parsed = try { Color.parseColor(color ?: "#F97316") } catch (e: Exception) { Color.GRAY }
                views.setInt(DOTS[i], "setColorFilter", parsed)
            } else {
                views.setViewVisibility(ROWS[i], View.GONE)
            }
        }
        views.setOnClickPendingIntent(
            R.id.widget_root,
            HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java, Uri.parse("ztcalendar://today")),
        )
        views.setOnClickPendingIntent(
            R.id.add_button,
            HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java, Uri.parse("ztcalendar://new-event")),
        )
        return views
    }
}
