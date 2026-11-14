package dev.sagron.zerotrustcalendar.widget

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.graphics.Color
import android.net.Uri
import android.os.Bundle
import android.view.View
import android.widget.RemoteViews
import androidx.core.widget.RemoteViewsCompat
import dev.sagron.zerotrustcalendar.R
import es.antonborri.home_widget.HomeWidgetPlugin
import es.antonborri.home_widget.HomeWidgetProvider
import org.json.JSONObject
import java.time.format.DateTimeFormatter

/**
 * Today's agenda (W9, K10): today's date and every event still to come
 * today, all-day ones first, in a list that scrolls. Tap an event to open
 * it, + for a new event.
 *
 * The app writes the rows for today and tomorrow (`calendar_agenda`, by
 * date), so after midnight this shows the new day without the app; finished
 * events drop off when they end. Titles only with "Show details on the home
 * screen"; otherwise each row says "Event" with its time, like "Up next".
 */
class AgendaWidgetProvider : HomeWidgetProvider() {

    companion object {
        fun update(context: Context, manager: AppWidgetManager, widgetId: Int) {
            val prefs = HomeWidgetPlugin.getData(context)
            val views = buildViews(context, prefs, widgetId)
            manager.updateAppWidget(widgetId, views)
        }

        private fun buildViews(context: Context, prefs: SharedPreferences, widgetId: Int): RemoteViews {
            val views = RemoteViews(context.packageName, R.layout.widget_agenda)
            val locale = CalendarWidgets.locale(prefs)
            val today = CalendarWidgets.today()
            val locked = prefs.getBoolean("calendar_widgets_locked", false)
            views.setTextViewText(R.id.agenda_date, today.format(DateTimeFormatter.ofPattern("EEEE, d MMMM", locale)))
            views.setOnClickPendingIntent(R.id.agenda_header, CalendarWidgets.launch(context, "ztcalendar://today"))
            views.setOnClickPendingIntent(R.id.agenda_add, CalendarWidgets.launch(context, "ztcalendar://new-event"))
            views.setContentDescription(
                R.id.agenda_add,
                CalendarWidgets.text(context, prefs, "new_event", R.string.agenda_new_event),
            )
            views.setOnClickPendingIntent(R.id.agenda_message, CalendarWidgets.launch(context, "ztcalendar://today"))

            val all = try {
                prefs.getString("calendar_agenda", null)?.let { JSONObject(it) }
            } catch (e: Exception) {
                null
            }
            val rows = all?.optJSONArray(today.toString())
            val items = RemoteViewsCompat.RemoteCollectionItems.Builder()
                .setHasStableIds(true)
                .setViewTypeCount(1)
            val now = System.currentTimeMillis()
            var nextEnd: Long? = null
            if (!locked && rows != null) {
                for (i in 0 until rows.length()) {
                    val row = rows.optJSONObject(i) ?: continue
                    val end = if (row.has("e")) row.optLong("e") else null
                    if (end != null && end <= now) continue
                    if (end != null && (nextEnd == null || end < nextEnd)) nextEnd = end
                    val item = RemoteViews(context.packageName, R.layout.widget_agenda_item)
                    item.setTextViewText(R.id.agenda_row_time, row.optString("t"))
                    item.setTextViewText(R.id.agenda_row_title, row.optString("ti"))
                    val color = try { Color.parseColor(row.optString("c", "#F97316")) } catch (e: Exception) { Color.GRAY }
                    item.setInt(R.id.agenda_row_bar, "setColorFilter", color)
                    val id = row.optString("id")
                    val uri = if (id.isEmpty()) {
                        "ztcalendar://today"
                    } else {
                        "ztcalendar://event?id=" + Uri.encode(id) +
                            (row.optString("s").takeIf { it.isNotEmpty() }?.let { "&start=" + Uri.encode(it) } ?: "")
                    }
                    item.setOnClickFillInIntent(R.id.agenda_row, Intent().setData(Uri.parse(uri)))
                    items.addItem((id + i).hashCode().toLong(), item)
                }
            }
            val built = items.build()
            val message = when {
                locked -> CalendarWidgets.text(context, prefs, "signed_out", R.string.agenda_signed_out)
                rows == null -> CalendarWidgets.text(context, prefs, "agenda_open", R.string.agenda_open)
                built.itemCount == 0 -> CalendarWidgets.text(context, prefs, "agenda_empty", R.string.agenda_empty)
                else -> null
            }
            views.setViewVisibility(R.id.agenda_list, if (message == null) View.VISIBLE else View.GONE)
            views.setViewVisibility(R.id.agenda_message, if (message == null) View.GONE else View.VISIBLE)
            views.setViewVisibility(R.id.agenda_lock, if (locked) View.VISIBLE else View.GONE)
            views.setTextViewText(R.id.agenda_message_text, message ?: "")
            views.setPendingIntentTemplate(R.id.agenda_list, CalendarWidgets.rowTemplate(context, widgetId))
            RemoteViewsCompat.setRemoteAdapter(context, views, widgetId, R.id.agenda_list, built)
            // Drop the next event once it is over.
            CalendarWidgets.scheduleRefresh(context, nextEnd)
            return views
        }
    }

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        appWidgetIds.forEach { appWidgetManager.updateAppWidget(it, buildViews(context, widgetData, it)) }
    }

    override fun onAppWidgetOptionsChanged(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
        newOptions: Bundle,
    ) {
        update(context, appWidgetManager, appWidgetId)
    }
}
