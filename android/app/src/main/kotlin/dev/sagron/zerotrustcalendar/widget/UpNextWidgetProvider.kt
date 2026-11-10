package dev.sagron.zerotrustcalendar.widget

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.graphics.Color
import android.net.Uri
import android.view.View
import android.widget.RemoteViews
import dev.sagron.zerotrustcalendar.MainActivity
import dev.sagron.zerotrustcalendar.R
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider

/**
 * "Up next": the next few events, as the app last saved them
 * (lib/widget/up_next_widget.dart). It never reads the vault. Event titles
 * are only saved when the user turned on "Show event titles on the widget";
 * otherwise the rows say "Event" with the time.
 */
class UpNextWidgetProvider : HomeWidgetProvider() {

    companion object {
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
        val header = widgetData.getString("upnext_header", null) ?: "ZT Calendar"
        val count = widgetData.getInt("upnext_count", 0)
        val empty = widgetData.getString("upnext_empty", null) ?: "Open ZT Calendar to see what's next"
        appWidgetIds.forEach { widgetId ->
            val views = RemoteViews(context.packageName, R.layout.widget_up_next)
            views.setTextViewText(R.id.header, header)
            for (i in ROWS.indices) {
                if (i < count) {
                    views.setViewVisibility(ROWS[i], View.VISIBLE)
                    views.setTextViewText(TIMES[i], widgetData.getString("upnext_${i}_time", "") ?: "")
                    views.setTextViewText(TITLES[i], widgetData.getString("upnext_${i}_title", "") ?: "")
                    val color = widgetData.getString("upnext_${i}_color", null)
                    val parsed = try { Color.parseColor(color ?: "#F97316") } catch (e: Exception) { Color.GRAY }
                    views.setInt(DOTS[i], "setColorFilter", parsed)
                } else {
                    views.setViewVisibility(ROWS[i], View.GONE)
                }
            }
            views.setViewVisibility(R.id.empty, if (count == 0) View.VISIBLE else View.GONE)
            views.setTextViewText(R.id.empty, empty)
            val open = HomeWidgetLaunchIntent.getActivity(
                context, MainActivity::class.java, Uri.parse("ztcalendar://today"),
            )
            views.setOnClickPendingIntent(R.id.widget_root, open)
            appWidgetManager.updateAppWidget(widgetId, views)
        }
    }
}
