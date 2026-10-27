package com.example.trabajo_app

import android.content.Context
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.net.Network
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.EventChannel

/** Read-only connectivity signal; never schedules work while the app is closed. */
class UploadConnection(context: Context, messenger: BinaryMessenger) {
    private val manager = context.getSystemService(ConnectivityManager::class.java)
    private val channel = MethodChannel(messenger, "micomunidad/upload_connection")
    private val events = EventChannel(messenger, "micomunidad/upload_connection_changes")
    private var callback: ConnectivityManager.NetworkCallback? = null
    private val main = Handler(Looper.getMainLooper())

    private fun offline(): Boolean? {
        val network = manager.activeNetwork ?: return true
        val capabilities = manager.getNetworkCapabilities(network) ?: return null
        return when {
            !capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET) -> true
            capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED) -> false
            capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_CAPTIVE_PORTAL) -> true
            else -> null
        }
    }

    private fun unregister() {
        callback?.let { try { manager.unregisterNetworkCallback(it) } catch (_: Exception) {} }
        callback = null
    }

    init {
        channel.setMethodCallHandler { call, result ->
            if (call.method != "isOffline") {
                result.notImplemented()
            } else {
                try {
                    result.success(offline())
                } catch (_: Exception) {
                    result.success(null)
                }
            }
        }
        events.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, sink: EventChannel.EventSink) {
                unregister()
                val listener = object : ConnectivityManager.NetworkCallback() {
                    private fun emit() {
                        main.post {
                            if (callback === this) {
                                try { sink.success(offline()) } catch (_: Exception) { sink.success(null) }
                            }
                        }
                    }
                    override fun onAvailable(network: Network) = emit()
                    override fun onLost(network: Network) = emit()
                    override fun onCapabilitiesChanged(network: Network, capabilities: NetworkCapabilities) = emit()
                }
                callback = listener
                try {
                    manager.registerDefaultNetworkCallback(listener)
                    sink.success(offline())
                } catch (_: Exception) {
                    unregister()
                    sink.success(null)
                }
            }
            override fun onCancel(arguments: Any?) = unregister()
        })
    }

    fun close() {
        unregister()
        events.setStreamHandler(null)
        channel.setMethodCallHandler(null)
    }
}
