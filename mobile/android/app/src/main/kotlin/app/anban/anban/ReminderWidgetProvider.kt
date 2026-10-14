package app.anban.anban

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider
import org.json.JSONArray
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

class ReminderWidgetProvider : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        val now = System.currentTimeMillis()
        val times = SimpleDateFormat("MM-dd HH:mm", Locale.CHINA)
        val next = linkedMapOf<String, String>()
        val reminders = JSONArray(widgetData.getString("reminder_plan", "[]") ?: "[]")
        for (i in 0 until reminders.length()) {
            val item = reminders.getJSONObject(i)
            val at = item.getLong("at")
            val label = item.getString("label")
            if (at > now && !next.containsKey(label)) {
                next[label] = "$label  ${times.format(Date(at))}"
            }
        }
        val summary = next.values.joinToString("\n").ifBlank { "暂无待提醒事项，点击打开安伴" }
        val synced = widgetData.getString("reminder_synced", "") ?: ""
        appWidgetIds.forEach { id ->
            val views = RemoteViews(context.packageName, R.layout.reminder_widget).apply {
                setTextViewText(R.id.reminder_widget_summary, summary)
                setTextViewText(R.id.reminder_widget_synced, if (synced.isBlank()) "打开安伴同步提醒" else "同步于 $synced · 点击查看")
                setOnClickPendingIntent(
                    R.id.reminder_widget_root,
                    HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java),
                )
            }
            appWidgetManager.updateAppWidget(id, views)
        }
    }
}
