package com.example.trabajo_app

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    private var imageConverter: HeifImageConverter? = null
    private var privateFileOpener: PrivateFileOpener? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        imageConverter = HeifImageConverter(flutterEngine.dartExecutor.binaryMessenger)
        privateFileOpener = PrivateFileOpener(this, flutterEngine.dartExecutor.binaryMessenger)
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        imageConverter?.close()
        imageConverter = null
        privateFileOpener?.close()
        privateFileOpener = null
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
