package com.example.today_bob_app.widget

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.widget.RemoteViews
import com.example.today_bob_app.MainActivity
import com.example.today_bob_app.R
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone
import kotlin.concurrent.thread

class TodayBobWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
    ) {
        appWidgetIds.forEach { appWidgetId ->
            appWidgetManager.updateAppWidget(
                appWidgetId,
                widgetViews(context, WidgetMealData(listOf("불러오는 중..."), "")),
            )
        }

        thread(name = "TodayBobWidgetUpdater") {
            val mealData = fetchCurrentMealData()
            appWidgetIds.forEach { appWidgetId ->
                appWidgetManager.updateAppWidget(
                    appWidgetId,
                    widgetViews(context, mealData),
                )
            }
        }
    }

    private fun widgetViews(context: Context, mealData: WidgetMealData): RemoteViews {
        val views = RemoteViews(context.packageName, R.layout.today_bob_widget)
        views.setImageViewResource(R.id.today_bob_widget_icon, R.drawable.tomato_gold)
        views.setTextViewText(R.id.today_bob_widget_menu, mealData.menuItems.joinToString("\n"))
        views.setTextViewText(R.id.today_bob_widget_hours, mealData.hoursLabel)
        views.setOnClickPendingIntent(R.id.today_bob_widget_root, launchAppIntent(context))
        return views
    }

    private fun launchAppIntent(context: Context): PendingIntent {
        val intent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }

        return PendingIntent.getActivity(
            context,
            0,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    private fun fetchCurrentMealData(): WidgetMealData {
        val fallback = WidgetMealData(listOf("등록된 식단이 없어요"), "")

        return runCatching {
            val uri = Uri.parse("$API_BASE_URL/api/home")
                .buildUpon()
                .appendQueryParameter("date", koreanDateString())
                .appendQueryParameter("at", utcIsoString())
                .build()
            val connection = (URL(uri.toString()).openConnection() as HttpURLConnection).apply {
                connectTimeout = 5000
                readTimeout = 5000
                requestMethod = "GET"
            }

            connection.inputStream.bufferedReader().use { reader ->
                val body = reader.readText()
                val json = JSONObject(body)
                val items = json
                    .getJSONObject("menu")
                    .getJSONArray("items")
                val menuItems = (0 until items.length())
                    .map { items.getString(it).trim() }
                    .filter { it.isNotEmpty() }
                    .take(MAX_MENU_LINES)
                    .ifEmpty { fallback.menuItems }
                val hoursLabel = json
                    .optJSONObject("operatingHours")
                    ?.optString("label")
                    ?.replace(" ", "")
                    .orEmpty()

                WidgetMealData(menuItems, hoursLabel)
            }
        }.getOrDefault(fallback)
    }

    private fun koreanDateString(): String {
        return SimpleDateFormat("yyyy-MM-dd", Locale.US).apply {
            timeZone = TimeZone.getTimeZone("Asia/Seoul")
        }.format(Date())
    }

    private fun utcIsoString(): String {
        return SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", Locale.US).apply {
            timeZone = TimeZone.getTimeZone("UTC")
        }.format(Date())
    }

    private companion object {
        private const val API_BASE_URL = "https://today-bob-server.vercel.app"
        private const val MAX_MENU_LINES = 6
    }
}

private data class WidgetMealData(
    val menuItems: List<String>,
    val hoursLabel: String,
)
