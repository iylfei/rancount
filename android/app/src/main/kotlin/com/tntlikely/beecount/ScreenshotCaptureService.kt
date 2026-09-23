package com.tntlikely.beecount

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.graphics.Bitmap
import android.graphics.PixelFormat
import android.hardware.display.DisplayManager
import android.hardware.display.VirtualDisplay
import android.media.ImageReader
import android.media.projection.MediaProjection
import android.media.projection.MediaProjectionManager
import android.os.Build
import android.os.Handler
import android.os.HandlerThread
import android.os.IBinder
import android.util.DisplayMetrics
import android.view.WindowManager
import java.io.File
import java.util.concurrent.atomic.AtomicBoolean

/** One permission grant produces one frame, then immediately releases projection. */
class ScreenshotCaptureService : Service() {
    private var worker: HandlerThread? = null
    private var reader: ImageReader? = null
    private var display: VirtualDisplay? = null
    private var projection: MediaProjection? = null
    private val completed = AtomicBoolean(false)

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent == null || completed.get()) return START_NOT_STICKY
        try {
            startProjectionForeground()
            val code = intent.getIntExtra(EXTRA_RESULT_CODE, 0)
            @Suppress("DEPRECATION")
            val data = intent.getParcelableExtra<Intent>(EXTRA_RESULT_DATA)
                ?: throw IllegalArgumentException("Missing projection consent")
            val manager = getSystemService(MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
            val granted = manager.getMediaProjection(code, data)
                ?: throw IllegalStateException("Projection consent was rejected")
            projection = granted

            worker = HandlerThread("rancount-one-shot-capture").also { it.start() }
            val handler = Handler(worker!!.looper)
            granted.registerCallback(object : MediaProjection.Callback() {
                override fun onStop() {
                    finishCapture(null)
                }
            }, handler)

            @Suppress("DEPRECATION")
            val metrics = DisplayMetrics().also {
                (getSystemService(WINDOW_SERVICE) as WindowManager).defaultDisplay.getRealMetrics(it)
            }
            val width = metrics.widthPixels
            val height = metrics.heightPixels
            reader = ImageReader.newInstance(width, height, PixelFormat.RGBA_8888, 2)
            reader!!.setOnImageAvailableListener({ source ->
                if (completed.get()) return@setOnImageAvailableListener
                val image = source.acquireLatestImage() ?: return@setOnImageAvailableListener
                var capturedPath: String? = null
                try {
                    val plane = image.planes[0]
                    val paddedWidth = width +
                        (plane.rowStride - plane.pixelStride * width) / plane.pixelStride
                    val padded = Bitmap.createBitmap(paddedWidth, height, Bitmap.Config.ARGB_8888)
                    padded.copyPixelsFromBuffer(plane.buffer)
                    val bitmap = Bitmap.createBitmap(padded, 0, 0, width, height)
                    val outputDir = File(cacheDir, "rancount_capture").apply { mkdirs() }
                    val output = File(outputDir, "capture_${System.currentTimeMillis()}.jpg")
                    output.outputStream().use { bitmap.compress(Bitmap.CompressFormat.JPEG, 90, it) }
                    bitmap.recycle()
                    padded.recycle()
                    capturedPath = output.absolutePath
                } catch (_: Exception) {
                    // Capture failure leaves no transaction or attachment behind.
                } finally {
                    image.close()
                    finishCapture(capturedPath)
                }
            }, handler)

            // Consent UI has closed; let the transparent activity settle before the frame.
            handler.postDelayed({
                if (completed.get()) return@postDelayed
                try {
                    display = granted.createVirtualDisplay(
                        "rancount-capture", width, height, metrics.densityDpi,
                        DisplayManager.VIRTUAL_DISPLAY_FLAG_AUTO_MIRROR,
                        reader!!.surface, null, handler
                    )
                } catch (_: Exception) {
                    finishCapture(null)
                }
            }, 350)
            handler.postDelayed({ finishCapture(null) }, 10000)
        } catch (_: Exception) {
            finishCapture(null)
        }
        return START_NOT_STICKY
    }

    private fun startProjectionForeground() {
        val manager = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= 26) {
            manager.createNotificationChannel(NotificationChannel(
                CHANNEL_ID, "截图记账", NotificationManager.IMPORTANCE_LOW
            ))
        }
        val builder = if (Build.VERSION.SDK_INT >= 26) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        val notification = builder
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle("截图记账")
            .setContentText("正在获取当前画面")
            .setOngoing(true)
            .build()
        if (Build.VERSION.SDK_INT >= 29) {
            startForeground(NOTIFICATION_ID, notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION)
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    private fun finishCapture(path: String?) {
        if (!completed.compareAndSet(false, true)) return
        display?.release()
        reader?.close()
        projection?.stop()
        worker?.quitSafely()
        sendBroadcast(Intent(ACTION_CAPTURE_RESULT).apply {
            setPackage(packageName)
            putExtra(EXTRA_PATH, path)
        })
        if (Build.VERSION.SDK_INT >= 24) {
            stopForeground(STOP_FOREGROUND_REMOVE)
        } else {
            @Suppress("DEPRECATION")
            stopForeground(true)
        }
        stopSelf()
    }

    companion object {
        const val ACTION_CAPTURE_RESULT = "com.tntlikely.beecount.CAPTURE_RESULT"
        const val EXTRA_RESULT_CODE = "result_code"
        const val EXTRA_RESULT_DATA = "result_data"
        const val EXTRA_PATH = "capture_path"
        private const val CHANNEL_ID = "rancount_capture"
        private const val NOTIFICATION_ID = 4201
    }
}
