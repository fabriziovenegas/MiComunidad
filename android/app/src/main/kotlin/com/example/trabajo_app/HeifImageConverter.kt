package com.example.trabajo_app

import android.graphics.Bitmap
import android.graphics.ColorSpace
import android.graphics.ImageDecoder
import android.os.Build
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.IOException
import java.nio.ByteBuffer
import java.util.concurrent.Executors
import kotlin.math.min
import kotlin.math.sqrt

/** No network, no output file, and no changes to the original photograph. */
class HeifImageConverter(messenger: BinaryMessenger) {
    private val channel = MethodChannel(messenger, "micomunidad/image_conversion")
    private val worker = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())

    init {
        channel.setMethodCallHandler { call, result ->
            if (call.method != "heifToJpeg") {
                result.notImplemented()
            } else if (Build.VERSION.SDK_INT < 28) {
                // Keep existing image formats working on older Android versions.
                result.error("unsupported_device", null, null)
            } else {
                val path = call.argument<String>("path")
                val bytes = call.argument<ByteArray>("bytes")
                val limit = call.argument<Number>("maxBytes")?.toLong() ?: 0
                if (limit !in 1..(10L * 1024 * 1024)) {
                    result.error("invalid_input", null, null)
                } else {
                    worker.execute {
                        try {
                            val converted = convert(path, bytes, limit)
                            main.post { result.success(converted) }
                        } catch (_: TooLarge) {
                            main.post { result.error("too_large", null, null) }
                        } catch (_: OutOfMemoryError) {
                            main.post { result.error("conversion_failed", null, null) }
                        } catch (_: Exception) {
                            main.post { result.error("conversion_failed", null, null) }
                        }
                    }
                }
            }
        }
    }

    @android.annotation.TargetApi(28)
    private fun convert(path: String?, bytes: ByteArray?, limit: Long): ByteArray {
        val source = if (bytes != null) {
            if (bytes.isEmpty()) throw IOException()
            if (bytes.size > limit) throw TooLarge()
            ImageDecoder.createSource(ByteBuffer.wrap(bytes))
        } else {
            val file = path?.let { File(it) } ?: throw IOException()
            if (!file.isFile || !file.canRead() || file.length() == 0L) throw IOException()
            if (file.length() > limit) throw TooLarge()
            ImageDecoder.createSource(file)
        }
        val bitmap = ImageDecoder.decodeBitmap(source) { decoder, info, _ ->
            if (info.mimeType !in setOf("image/heif", "image/heic")) throw IOException()
            val width = info.size.width
            val height = info.size.height
            if (width <= 0 || height <= 0) throw IOException()
            // Bound decoded memory to 12 MP, preserving aspect ratio. Standard
            // 12 MP photos retain their dimensions; very large images are reduced.
            val scale = min(1.0, min(
                sqrt(12_000_000.0 / (width.toDouble() * height)),
                8192.0 / maxOf(width, height)
            ))
            if (scale < 1.0) decoder.setTargetSize(
                maxOf(1, (width * scale).toInt()), maxOf(1, (height * scale).toInt()))
            decoder.allocator = ImageDecoder.ALLOCATOR_SOFTWARE
            decoder.setTargetColorSpace(ColorSpace.get(ColorSpace.Named.SRGB))
            decoder.setOnPartialImageListener { false }
            // ImageDecoder applies the image orientation before JPEG encoding.
        }
        try {
            val output = LimitedOutput(limit)
            if (!bitmap.compress(Bitmap.CompressFormat.JPEG, 92, output)) throw IOException()
            return output.toByteArray()
        } finally {
            bitmap.recycle()
        }
    }

    fun close() {
        channel.setMethodCallHandler(null)
        worker.shutdown()
    }

    private class TooLarge : IOException()

    private class LimitedOutput(private val limit: Long) : ByteArrayOutputStream() {
        override fun write(value: Int) {
            if (count.toLong() + 1 > limit) throw TooLarge()
            super.write(value)
        }

        override fun write(buffer: ByteArray, offset: Int, length: Int) {
            if (count.toLong() + length > limit) throw TooLarge()
            super.write(buffer, offset, length)
        }
    }
}
