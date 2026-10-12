import Darwin
import Flutter
import Foundation

/// Answers one question for the Dart side: when did the OS start this process?
///
/// The kernel records the process start time (`kp_proc.p_starttime`, wall clock)
/// and `sysctl(KERN_PROC_PID)` returns it for our own pid; no special entitlement
/// is needed. Nothing runs at app start: the work happens only when Dart asks,
/// after the first frame.
public class FlutterStartupTracerPlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "flutter_startup_tracer", binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(FlutterStartupTracerPlugin(), channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard call.method == "getProcessStart" else {
      result(FlutterMethodNotImplemented)
      return
    }
    guard let micros = FlutterStartupTracerPlugin.processStartEpochMicros() else {
      result(nil)  // Dart reports "native start unknown".
      return
    }
    // iOS 15+ may launch ("pre-warm") the process long before the user taps the
    // icon and sets this variable for that launch. The gap is then not user time.
    let prewarmed = ProcessInfo.processInfo.environment["ActivePrewarm"] == "1"
    result([
      "startEpochMicros": micros,
      "source": "ios:sysctl(KERN_PROC_PID).p_starttime",
      "prewarmed": prewarmed,
    ])
  }

  /// Process start as microseconds since the Unix epoch, or nil if sysctl fails.
  static func processStartEpochMicros() -> Int64? {
    var info = kinfo_proc()
    var size = MemoryLayout<kinfo_proc>.stride
    var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
    let status = mib.withUnsafeMutableBufferPointer { buffer in
      sysctl(buffer.baseAddress, u_int(buffer.count), &info, &size, nil, 0)
    }
    guard status == 0 else { return nil }
    let start = info.kp_proc.p_starttime
    let micros = Int64(start.tv_sec) * 1_000_000 + Int64(start.tv_usec)
    return micros > 0 ? micros : nil
  }
}
