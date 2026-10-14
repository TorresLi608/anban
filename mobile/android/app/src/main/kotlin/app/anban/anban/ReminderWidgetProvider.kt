package app.anban.anban

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.os.Build
import android.os.Bundle
import android.util.SizeF
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider
import org.json.JSONArray
import android.net.Uri
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale

class ReminderWidgetProvider : HomeWidgetProvider() {

    private data class ParsedReminder(
        val label: String,
        val at: Long,
        val channel: String = "",
        val due: Long = 0L,
    )

    private data class CategoryConfig(
        val iconRes: Int,
        val badgeRes: Int,
        val symbol: String,
    )

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        appWidgetIds.forEach { id ->
            updateWidget(context, appWidgetManager, id, widgetData)
        }
    }

    override fun onAppWidgetOptionsChanged(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
        newOptions: Bundle,
    ) {
        super.onAppWidgetOptionsChanged(context, appWidgetManager, appWidgetId, newOptions)
        val prefs = context.getSharedPreferences("${context.packageName}_preferences", Context.MODE_PRIVATE)
        updateWidget(context, appWidgetManager, appWidgetId, prefs, newOptions)
    }

    private fun updateWidget(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
        widgetData: SharedPreferences,
        options: Bundle? = null,
    ) {
        val now = System.currentTimeMillis()
        val remindersRaw = widgetData.getString("reminder_plan", "[]") ?: "[]"
        val synced = widgetData.getString("reminder_synced", "") ?: ""

        val upcoming = parseUpcomingReminders(remindersRaw, now)
        val pendingIntent = HomeWidgetLaunchIntent.getActivity(
            context,
            MainActivity::class.java,
            Uri.parse("anban://reminders"),
        )

        val standardViews = buildStandardViews(context, upcoming, synced, now, pendingIntent)
        val compactViews = buildCompactViews(context, upcoming, synced, now, pendingIntent)

        val finalViews = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            RemoteViews(
                mapOf(
                    SizeF(100f, 40f) to compactViews,
                    SizeF(130f, 75f) to standardViews,
                )
            )
        } else {
            val opt = options ?: appWidgetManager.getAppWidgetOptions(appWidgetId)
            val minHeight = opt.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT, 0)
            if (minHeight in 1..75) compactViews else standardViews
        }

        appWidgetManager.updateAppWidget(appWidgetId, finalViews)
    }

    private fun parseUpcomingReminders(jsonString: String, now: Long): List<ParsedReminder> {
        val list = mutableListOf<ParsedReminder>()
        val seenLabels = mutableSetOf<String>()
        try {
            val array = JSONArray(jsonString)
            for (i in 0 until array.length()) {
                val item = array.getJSONObject(i)
                val at = item.optLong("at", 0L)
                val label = item.optString("label", "").trim()
                val channel = item.optString("channel", "").trim()
                val due = item.optLong("due", 0L)
                if (at > now && label.isNotEmpty() && seenLabels.add(label)) {
                    list.add(ParsedReminder(label = label, at = at, channel = channel, due = due))
                }
            }
        } catch (_: Exception) {
            // Safe fallback on JSON parse failure
        }
        return list.sortedBy { it.at }
    }

    private fun getCategoryConfig(label: String): CategoryConfig {
        return when {
            label.contains("餐") -> CategoryConfig(
                iconRes = R.drawable.ic_widget_meal,
                badgeRes = R.drawable.reminder_widget_badge_meal,
                symbol = "🥣",
            )
            label.contains("水") -> CategoryConfig(
                iconRes = R.drawable.ic_widget_water,
                badgeRes = R.drawable.reminder_widget_badge_water,
                symbol = "💧",
            )
            label.contains("护理") || label.contains("化疗") || label.contains("医") || label.contains("PICC") -> CategoryConfig(
                iconRes = R.drawable.ic_widget_medical,
                badgeRes = R.drawable.reminder_widget_badge_medical,
                symbol = "🏥",
            )
            else -> CategoryConfig(
                iconRes = R.drawable.ic_widget_bell,
                badgeRes = R.drawable.reminder_widget_badge_default,
                symbol = "⏰",
            )
        }
    }

    private fun formatTime(at: Long, now: Long): Pair<String, String> {
        val itemCal = Calendar.getInstance().apply { timeInMillis = at }
        val nowCal = Calendar.getInstance().apply { timeInMillis = now }

        val timeStr = SimpleDateFormat("HH:mm", Locale.CHINA).format(Date(at))

        val sameYear = itemCal.get(Calendar.YEAR) == nowCal.get(Calendar.YEAR)
        val dayDiff = if (sameYear) {
            itemCal.get(Calendar.DAY_OF_YEAR) - nowCal.get(Calendar.DAY_OF_YEAR)
        } else {
            ((at - now) / 86400000L).toInt()
        }

        val prefix = when (dayDiff) {
            0 -> "今天"
            1 -> "明天"
            2 -> "后天"
            else -> SimpleDateFormat("MM-dd", Locale.CHINA).format(Date(at))
        }
        return Pair(prefix, timeStr)
    }

    private fun buildStandardViews(
        context: Context,
        upcoming: List<ParsedReminder>,
        synced: String,
        now: Long,
        pendingIntent: PendingIntent,
    ): RemoteViews {
        return RemoteViews(context.packageName, R.layout.reminder_widget).apply {
            setOnClickPendingIntent(R.id.reminder_widget_root, pendingIntent)

            // Sync status
            val syncDisplay = if (synced.isBlank()) {
                "点击查看"
            } else {
                val clock = synced.trim().substringAfterLast(" ")
                if (clock.length >= 4) "$clock 已同步" else "已同步 · 点击查看"
            }
            setTextViewText(R.id.reminder_widget_synced, syncDisplay)

            if (upcoming.isNotEmpty()) {
                setViewVisibility(R.id.reminder_widget_active_container, View.VISIBLE)
                setViewVisibility(R.id.reminder_widget_empty_container, View.GONE)

                // Hero item
                val hero = upcoming[0]
                val cat = getCategoryConfig(hero.label)
                val (prefix, time) = formatTime(hero.at, now)

                setImageViewResource(R.id.reminder_widget_hero_icon, cat.iconRes)
                setInt(R.id.reminder_widget_hero_badge, "setBackgroundResource", cat.badgeRes)
                setTextViewText(R.id.reminder_widget_hero_time_prefix, prefix)
                setTextViewText(R.id.reminder_widget_hero_time, time)
                val baseLabel = if (hero.label.endsWith("提醒")) hero.label else "${hero.label}提醒"
                val displayLabel = if (hero.due > 0 && hero.due != hero.at) {
                    val (duePrefix, dueTime) = formatTime(hero.due, now)
                    "$baseLabel (实际执行 $duePrefix $dueTime)"
                } else {
                    baseLabel
                }
                setTextViewText(R.id.reminder_widget_hero_label, displayLabel)

                // Secondary items
                if (upcoming.size > 1) {
                    setViewVisibility(R.id.reminder_widget_secondary_container, View.VISIBLE)

                    val sub1 = upcoming[1]
                    val cat1 = getCategoryConfig(sub1.label)
                    val (p1, t1) = formatTime(sub1.at, now)
                    val sub1Text = if (sub1.due > 0 && sub1.due != sub1.at) {
                        val (dp1, dt1) = formatTime(sub1.due, now)
                        "${cat1.symbol} $p1 ${t1}提醒 ｜ 实际 $dp1 $dt1 ${sub1.label}"
                    } else {
                        "${cat1.symbol} $p1 $t1  ${sub1.label}"
                    }
                    setViewVisibility(R.id.reminder_widget_sub_item_1, View.VISIBLE)
                    setTextViewText(R.id.reminder_widget_sub_item_1, sub1Text)

                    if (upcoming.size > 2) {
                        val sub2 = upcoming[2]
                        val cat2 = getCategoryConfig(sub2.label)
                        val (p2, t2) = formatTime(sub2.at, now)
                        val sub2Text = if (sub2.due > 0 && sub2.due != sub2.at) {
                            val (dp2, dt2) = formatTime(sub2.due, now)
                            "${cat2.symbol} $p2 ${t2}提醒 ｜ 实际 $dp2 $dt2 ${sub2.label}"
                        } else {
                            "${cat2.symbol} $p2 $t2  ${sub2.label}"
                        }
                        setViewVisibility(R.id.reminder_widget_sub_item_2, View.VISIBLE)
                        setTextViewText(R.id.reminder_widget_sub_item_2, sub2Text)
                    } else {
                        setViewVisibility(R.id.reminder_widget_sub_item_2, View.GONE)
                    }
                } else {
                    setViewVisibility(R.id.reminder_widget_secondary_container, View.GONE)
                }
            } else {
                setViewVisibility(R.id.reminder_widget_active_container, View.GONE)
                setViewVisibility(R.id.reminder_widget_empty_container, View.VISIBLE)
            }

            // Legacy summary field fallback for safety
            val legacySummary = upcoming.joinToString("\n") {
                val (p, t) = formatTime(it.at, now)
                if (it.due > 0 && it.due != it.at) {
                    val (dp, dt) = formatTime(it.due, now)
                    "${it.label}  $p ${t}提醒 (实际执行 $dp $dt)"
                } else {
                    "${it.label}  $p $t"
                }
            }.ifBlank { "暂无待提醒事项，点击打开安伴" }
            setTextViewText(R.id.reminder_widget_summary, legacySummary)
        }
    }

    private fun buildCompactViews(
        context: Context,
        upcoming: List<ParsedReminder>,
        synced: String,
        now: Long,
        pendingIntent: PendingIntent,
    ): RemoteViews {
        return RemoteViews(context.packageName, R.layout.reminder_widget_compact).apply {
            setOnClickPendingIntent(R.id.reminder_widget_root, pendingIntent)

            if (upcoming.isNotEmpty()) {
                val hero = upcoming[0]
                val cat = getCategoryConfig(hero.label)
                val (prefix, time) = formatTime(hero.at, now)

                setImageViewResource(R.id.reminder_widget_compact_icon, cat.iconRes)
                setInt(R.id.reminder_widget_compact_badge, "setBackgroundResource", cat.badgeRes)
                setTextViewText(R.id.reminder_widget_compact_prefix, prefix)
                setTextViewText(R.id.reminder_widget_compact_time, time)
                setTextViewText(R.id.reminder_widget_compact_title, hero.label)

                val subText = if (hero.due > 0 && hero.due != hero.at) {
                    val (dp, dt) = formatTime(hero.due, now)
                    "实际执行: $dp $dt · 点击查看"
                } else if (upcoming.size > 1) {
                    "后续还有 ${upcoming.size - 1} 项 · 点击查看"
                } else {
                    if (synced.isNotBlank()) "已同步 · 点击打开安伴" else "点击打开安伴"
                }
                setTextViewText(R.id.reminder_widget_compact_sub, subText)
            } else {
                setImageViewResource(R.id.reminder_widget_compact_icon, R.drawable.ic_widget_check)
                setInt(R.id.reminder_widget_compact_badge, "setBackgroundResource", R.drawable.reminder_widget_badge_empty)
                setTextViewText(R.id.reminder_widget_compact_prefix, "")
                setTextViewText(R.id.reminder_widget_compact_time, "已就绪")
                setTextViewText(R.id.reminder_widget_compact_title, "待办已完成")
                setTextViewText(R.id.reminder_widget_compact_sub, "暂无待提醒事项 · 点击打开安伴")
            }
        }
    }
}
