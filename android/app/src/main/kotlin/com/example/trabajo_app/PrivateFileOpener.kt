package com.example.trabajo_app

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.ClipData
import android.content.Intent
import androidx.core.content.FileProvider
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.UUID
import java.util.concurrent.Executors

/** Grant only a temporary content URI for bytes already downloaded with Auth. */
class PrivateFileOpener(private val activity: Activity, messenger: BinaryMessenger) {
    private val channel = MethodChannel(messenger, "micomunidad/private_files")
    private val worker = Executors.newSingleThreadExecutor()

    init {
        channel.setMethodCallHandler { call, result ->
            if (call.method != "openDocument") {
                result.notImplemented()
            } else {
                val bytes = call.argument<ByteArray>("bytes")
                val mime = call.argument<String>("contentType")
                val extension = mapOf("application/pdf" to "pdf", "image/jpeg" to "jpg",
                    "image/png" to "png", "image/webp" to "webp")[mime]
                if (bytes == null || bytes.isEmpty() || bytes.size > 10 * 1024 * 1024 || extension == null) {
                    result.error("invalid-file", "No se pudo abrir el archivo.", null)
                } else {
                    worker.execute {
                        try {
                            val folder = File(activity.cacheDir, "private-attachments").apply { mkdirs() }
                            // Clear only this viewer's files older than one day. Never external storage.
                            folder.listFiles()?.filter { it.isFile && System.currentTimeMillis() - it.lastModified() > 86_400_000 }
                                ?.forEach { it.delete() }
                            val file = File(folder, "${UUID.randomUUID()}.$extension")
                            file.writeBytes(bytes)
                            activity.runOnUiThread {
                                try {
                                    val uri = FileProvider.getUriForFile(activity, "${activity.packageName}.privatefiles", file)
                                    activity.startActivity(Intent(Intent.ACTION_VIEW).apply {
                                        setDataAndType(uri, mime)
                                        clipData = ClipData.newRawUri("Archivo compartido", uri)
                                        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                                    })
                                    result.success(null)
                                } catch (_: ActivityNotFoundException) {
                                    file.delete()
                                    result.error("no-viewer", "No hay una aplicación para abrir este archivo.", null)
                                } catch (_: Exception) {
                                    file.delete()
                                    result.error("open-failed", "No se pudo abrir el archivo.", null)
                                }
                            }
                        } catch (_: Exception) {
                            activity.runOnUiThread { result.error("read-failed", "No se pudo preparar el archivo.", null) }
                        }
                    }
                }
            }
        }
    }

    fun close() {
        channel.setMethodCallHandler(null)
        worker.shutdown()
    }
}
