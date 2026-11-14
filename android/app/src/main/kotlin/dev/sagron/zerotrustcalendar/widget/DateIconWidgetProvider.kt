package dev.sagron.zerotrustcalendar.widget

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.widget.RemoteViews
import dev.sagron.zerotrustcalendar.R
import es.antonborri.home_widget.HomeWidgetProvider

/**
 * 1x1 date icon (W9): today's weekday and day number, like a calendar app's
 * icon. Both are TextClocks, so the system keeps them current with no
 * alarm and no data from the app. Tap to open today.
 */
class DateIconWidgetProvider : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        appWidgetIds.forEach { widgetId ->
            val views = RemoteViews(context.packageName, R.layout.widget_date_icon)
            views.setOnClickPendingIntent(R.id.date_icon_root, CalendarWidgets.launch(context, "ztcalendar://today"))
            appWidgetManager.updateAppWidget(widgetId, views)
        }
    }
}
