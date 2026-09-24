package com.tntlikely.beecount

import android.app.Activity
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.media.projection.MediaProjectionManager
import android.media.projection.MediaProjectionConfig
import android.os.Build
import android.os.Bundle
import android.widget.Toast

/** Transparent permission host so the target screen is visible when capture starts. */
class ScreenshotCaptureActivity : Activity() {
    private val receiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            val path = intent?.getStringExtra(ScreenshotCaptureService.EXTRA_PATH)
            if (path != null) {
                startActivity(Intent(this@ScreenshotCaptureActivity, ScreenshotDraftActivity::class.java).apply {
                    putExtra(MainActivity.EXTRA_CAPTURE_PATH, path)
                })
            } else {
                Toast.makeText(this@ScreenshotCaptureActivity, "截图失败，请重试或选图", Toast.LENGTH_SHORT).show()
            }
            finish()
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val filter = IntentFilter(ScreenshotCaptureService.ACTION_CAPTURE_RESULT)
        if (Build.VERSION.SDK_INT >= 33) {
            registerReceiver(receiver, filter, RECEIVER_NOT_EXPORTED)
        } else {
            @Suppress("DEPRECATION")
            registerReceiver(receiver, filter)
        }
        if (savedInstanceState == null) {
            val manager = getSystemService(MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
            @Suppress("DEPRECATION")
            val captureIntent = if (Build.VERSION.SDK_INT >= 34) {
                manager.createScreenCaptureIntent(
                    MediaProjectionConfig.createConfigForDefaultDisplay()
                )
            } else {
                manager.createScreenCaptureIntent()
            }
            startActivityForResult(captureIntent, REQUEST_CAPTURE)
        }
    }

    @Deprecated("Activity result API for the platform projection prompt")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != REQUEST_CAPTURE) return
        if (resultCode != RESULT_OK || data == null) {
            finish()
            return
        }
        val service = Intent(this, ScreenshotCaptureService::class.java).apply {
            putExtra(ScreenshotCaptureService.EXTRA_RESULT_CODE, resultCode)
            putExtra(ScreenshotCaptureService.EXTRA_RESULT_DATA, data)
        }
        if (Build.VERSION.SDK_INT >= 26) startForegroundService(service) else startService(service)
    }

    override fun onDestroy() {
        unregisterReceiver(receiver)
        super.onDestroy()
    }

    companion object {
        private const val REQUEST_CAPTURE = 401
    }
}
