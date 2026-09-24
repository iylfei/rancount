package com.tntlikely.beecount

import android.content.Context
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject
import java.util.concurrent.Executors

/** Both Flutter engines mutate drafts through one queue, without cached preference reads. */
object ImageDraftStoreBridge {
    private val queue = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private const val KEY = "flutter.rancount_image_drafts_v1"

    fun register(context: Context, messenger: BinaryMessenger) {
        val prefs = context.applicationContext.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        MethodChannel(messenger, "com.tntlikely.beecount/draft_store").setMethodCallHandler { call, result ->
            if (call.method !in listOf("load", "put", "remove")) {
                result.notImplemented()
                return@setMethodCallHandler
            }
            queue.execute {
                try {
                    val raw = prefs.getString(KEY, "[]") ?: "[]"
                    if (call.method == "load") {
                        main.post { result.success(raw) }
                    } else {
                        val entries = JSONArray(raw)
                        val entry = if (call.method == "put") JSONObject(call.arguments as String) else null
                        val id = entry?.getString("id") ?: call.arguments as String
                        val next = JSONArray()
                        if (entry != null) next.put(entry)
                        for (i in 0 until entries.length()) {
                            val old = entries.getJSONObject(i)
                            if (old.getString("id") != id) next.put(old)
                        }
                        check(prefs.edit().putString(KEY, next.toString()).commit())
                        main.post { result.success(null) }
                    }
                } catch (_: Exception) {
                    main.post { result.error("DRAFT_STORE", "草稿暂存失败，原数据已保留", null) }
                }
            }
        }
    }
}
