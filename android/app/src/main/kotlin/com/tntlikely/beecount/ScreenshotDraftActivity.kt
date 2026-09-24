package com.tntlikely.beecount

import android.os.Bundle
import android.view.Gravity
import android.view.WindowManager
import android.widget.Toast
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.android.FlutterActivityLaunchConfigs.BackgroundMode
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

/** A temporary dialog in the capture task; the main app's task stays in the background. */
class ScreenshotDraftActivity : FlutterFragmentActivity() {
    private var saved = false
    override fun getDartEntrypointFunctionName() = "screenshotDraftMain"
    override fun getBackgroundMode() = BackgroundMode.transparent

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        isOpen = true
        activeCapturePath = intent.getStringExtra(MainActivity.EXTRA_CAPTURE_PATH)
        setFinishOnTouchOutside(false)
        window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
        resizeDialog()
    }

    override fun onConfigurationChanged(newConfig: android.content.res.Configuration) {
        super.onConfigurationChanged(newConfig)
        resizeDialog()
    }

    private fun resizeDialog() {
        val metrics = resources.displayMetrics
        window.setGravity(Gravity.CENTER)
        window.setLayout(
            minOf(metrics.widthPixels - (24 * metrics.density).toInt(), (600 * metrics.density).toInt()),
            (metrics.heightPixels * 0.84).toInt()
        )
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        ImageDraftStoreBridge.register(this, flutterEngine.dartExecutor.binaryMessenger)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.tntlikely.beecount/capture_dialog")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "imagePath" -> result.success(intent.getStringExtra(MainActivity.EXTRA_CAPTURE_PATH))
                    "saved" -> {
                        saved = true
                        revision++
                        result.success(null)
                    }
                    "close" -> {
                        result.success(null)
                        if (saved) Toast.makeText(this, "账单已保存", Toast.LENGTH_SHORT).show()
                        finish()
                    }
                    else -> result.notImplemented()
                }
            }
    }

    override fun onDestroy() {
        if (isFinishing) {
            try {
                activeCapturePath?.let { path ->
                    val file = File(path).canonicalFile
                    if (file.parentFile == File(cacheDir, "rancount_capture").canonicalFile) file.delete()
                }
            } catch (_: Exception) { /* Startup cleanup retries interrupted deletions. */ }
        }
        isOpen = false
        activeCapturePath = null
        revision++
        super.onDestroy()
    }

    companion object {
        var activeCapturePath: String? = null
            private set
        var isOpen = false
            private set
        var revision = 0
            private set
    }
}
