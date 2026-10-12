package io.github.youssef336.flutter_startup_tracer

import android.os.Build
import android.os.Process
import android.os.SystemClock
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Answers one question for the Dart side: when did the OS start this process?
 *
 * The answer is a wall-clock timestamp (epoch microseconds) so Dart can compare it
 * with `DateTime.now()` taken at the top of `main()`. Android exposes the start as a
 * value on the `elapsedRealtime` clock, so it is converted with
 *   start = now(wall) - (elapsedRealtime(now) - start(elapsedRealtime)).
 * Nothing runs at app start: the work happens only when Dart asks, after the
 * first frame.
 */
class FlutterStartupTracerPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    private var channel: MethodChannel? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(binding.binaryMessenger, "flutter_startup_tracer").also {
            it.setMethodCallHandler(this)
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel?.setMethodCallHandler(null)
        channel = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method != "getProcessStart") {
            result.notImplemented()
            return
        }
        // Both clocks are read back to back so the conversion error is microseconds.
        val nowWallMs = System.currentTimeMillis()
        val nowElapsedMs = SystemClock.elapsedRealtime()
        val (startElapsedMs, source) =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                // API 33+: when the launch was requested, before zygote forked us.
                // Closest to "the user tapped the icon".
                Process.getStartRequestedElapsedRealtime() to
                    "android:Process.getStartRequestedElapsedRealtime"
            } else {
                // API 24+ (the plugin's minSdk): when the process was forked.
                Process.getStartElapsedRealtime() to "android:Process.getStartElapsedRealtime"
            }
        val startWallMs = nowWallMs - (nowElapsedMs - startElapsedMs)
        result.success(
            mapOf(
                "startEpochMicros" to startWallMs * 1000L,
                "source" to source,
                "prewarmed" to false,
            ),
        )
    }
}
