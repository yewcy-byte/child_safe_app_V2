package com.example.child_safe_app

import android.graphics.PixelFormat
import android.hardware.display.DisplayManager
import android.hardware.display.VirtualDisplay
import android.media.Image
import android.media.ImageReader
import android.media.projection.MediaProjection
import android.graphics.Bitmap
import android.util.Log
import java.io.File
import java.io.FileOutputStream

object ProjectionSession {
    private const val TAG = "ProjectionSession"

    @Volatile
    var mediaProjection: MediaProjection? = null

    @Volatile
    var virtualDisplay: VirtualDisplay? = null

    @Volatile
    var imageReader: ImageReader? = null

    @Volatile
    var cacheDirPath: String? = null

    @Volatile
    private var width: Int = 480

    @Volatile
    private var height: Int = 854

    @Volatile
    private var densityDpi: Int = 320

    fun configureProjection(
        projection: MediaProjection?,
        display: VirtualDisplay?,
        reader: ImageReader?,
        cachePath: String,
        captureWidth: Int,
        captureHeight: Int,
        captureDensityDpi: Int,
    ) {
        mediaProjection = projection
        virtualDisplay = display
        imageReader = reader
        cacheDirPath = cachePath
        width = captureWidth
        height = captureHeight
        densityDpi = captureDensityDpi
    }

    fun clear() {
        try {
            virtualDisplay?.release()
        } catch (_: Exception) {
        }
        try {
            imageReader?.close()
        } catch (_: Exception) {
        }
        try {
            mediaProjection?.stop()
        } catch (_: Exception) {
        }

        mediaProjection = null
        virtualDisplay = null
        imageReader = null
        cacheDirPath = null
    }

    fun hasActiveProjection(): Boolean {
        return mediaProjection != null
    }

    @Synchronized
    private fun ensureCapturePipeline(): Boolean {
        val projection = mediaProjection ?: return false
        if (imageReader != null && virtualDisplay != null) {
            return true
        }

        return try {
            val reader = ImageReader.newInstance(width, height, PixelFormat.RGBA_8888, 2)
            val display = projection.createVirtualDisplay(
                "ScreenCaptureBackground",
                width,
                height,
                densityDpi,
                DisplayManager.VIRTUAL_DISPLAY_FLAG_AUTO_MIRROR,
                reader.surface,
                null,
                null,
            )
            imageReader = reader
            virtualDisplay = display
            true
        } catch (e: Exception) {
            Log.e(TAG, "ensureCapturePipeline failed: ${e.message}", e)
            false
        }
    }

    @Synchronized
    private fun resetCapturePipeline() {
        try {
            virtualDisplay?.release()
        } catch (_: Exception) {
        }
        try {
            imageReader?.close()
        } catch (_: Exception) {
        }
        virtualDisplay = null
        imageReader = null
    }

    private fun isAbandonedBufferError(error: Throwable): Boolean {
        val message = error.message?.lowercase() ?: return false
        return message.contains("abandoned") || message.contains("bufferqueue")
    }

    private fun acquireFrame(reader: ImageReader): Image? {
        return try {
            reader.acquireLatestImage() ?: reader.acquireNextImageSafe()
        } catch (e: IllegalStateException) {
            if (isAbandonedBufferError(e)) {
                Log.w(TAG, "acquireFrame: abandoned buffer queue detected, resetting capture pipeline")
                resetCapturePipeline()
                return null
            }
            null
        } catch (e: RuntimeException) {
            if (isAbandonedBufferError(e)) {
                Log.w(TAG, "acquireFrame: runtime abandoned buffer queue detected, resetting capture pipeline")
                resetCapturePipeline()
                return null
            }
            throw e
        }
    }

    fun captureFrameToFile(): String? {
        try {
            if (!ensureCapturePipeline()) {
                return null
            }

            var reader = imageReader ?: return null
            var image = acquireFrame(reader)

            if (image == null) {
                Log.w(TAG, "captureFrameToFile: no frame, rebuilding capture pipeline")
                resetCapturePipeline()
                if (!ensureCapturePipeline()) {
                    return null
                }
                reader = imageReader ?: return null
                image = acquireFrame(reader)
            }

            image ?: return null
            return processImage(image)
        } catch (e: IllegalStateException) {
            if (isAbandonedBufferError(e)) {
                Log.w(TAG, "captureFrameToFile: abandoned capture state detected, resetting pipeline")
                resetCapturePipeline()
                return null
            }
            Log.e(TAG, "captureFrameToFile failed: ${e.message}", e)
            return null
        } catch (e: RuntimeException) {
            if (isAbandonedBufferError(e)) {
                Log.w(TAG, "captureFrameToFile: runtime abandoned capture state detected, resetting pipeline")
                resetCapturePipeline()
                return null
            }
            Log.e(TAG, "captureFrameToFile failed: ${e.message}", e)
            return null
        } catch (e: Exception) {
            Log.e(TAG, "captureFrameToFile failed: ${e.message}", e)
            return null
        }
    }

    private fun ImageReader.acquireNextImageSafe(): Image? {
        return try {
            acquireNextImage()
        } catch (_: IllegalStateException) {
            null
        }
    }

    private fun processImage(image: Image): String? {
        val plane = image.planes[0]
        val buffer = plane.buffer
        val pixelStride = plane.pixelStride
        val rowStride = plane.rowStride
        val rowPadding = rowStride - pixelStride * image.width

        val bitmap = Bitmap.createBitmap(
            image.width + rowPadding / pixelStride,
            image.height,
            Bitmap.Config.ARGB_8888
        )

        bitmap.copyPixelsFromBuffer(buffer)
        image.close()

        val cachePath = cacheDirPath ?: return null
        val file = File(cachePath, "scan_frame_background.jpg")
        FileOutputStream(file).use { out ->
            bitmap.compress(Bitmap.CompressFormat.JPEG, 70, out)
        }
        bitmap.recycle()
        return file.absolutePath
    }
}
