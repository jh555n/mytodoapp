package dev.dayweave.dayweave

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "dev.dayweave/privacy")
            .setMethodCallHandler { call, result ->
                if (call.method == "excludeFromBackup") result.success(null)
                else result.notImplemented()
            }
    }
}
