package com.dukandar.dukandar

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {

    private val channelName = "com.dukandar/security"
    private val executor = Executors.newSingleThreadExecutor()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName).setMethodCallHandler { call, result ->
            when (call.method) {
                "inspect" -> {
                    // File-system scans can take a moment; keep the UI thread free.
                    executor.execute {
                        val report = try {
                            SecurityInspector.inspect(applicationContext)
                        } catch (t: Throwable) {
                            mapOf<String, Any?>(
                                "isRooted" to false,
                                "isDebuggerAttached" to false,
                                "hookingDetected" to false,
                                "isEmulator" to false,
                                "signatureSha256" to "",
                                "isDebugBuild" to BuildConfig.DEBUG,
                                "details" to mapOf("error" to (t.message ?: "inspect failed")),
                            )
                        }
                        runOnUiThread { result.success(report) }
                    }
                }
                "signature" -> result.success(SecurityInspector.signatureSha256(applicationContext))
                else -> result.notImplemented()
            }
        }
    }

    override fun onDestroy() {
        executor.shutdownNow()
        super.onDestroy()
    }
}
