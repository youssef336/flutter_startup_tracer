import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'model.dart';

/// Reads when the app's process started. Returns null when it is unknown.
typedef ProcessStartReader = Future<ProcessStartInfo?> Function();

const MethodChannel _channel = MethodChannel('flutter_startup_tracer');

/// Asks the native side of the plugin for the process start time.
///
/// Never throws: on web, desktop, in tests, or when the plugin is not
/// registered, it returns null and the report marks native start as unknown.
Future<ProcessStartInfo?> readNativeProcessStart() async {
  if (kIsWeb) {
    return null;
  }
  try {
    final Map<String, Object?>? raw = await _channel.invokeMapMethod<String, Object?>(
      'getProcessStart',
    );
    return parseProcessStart(raw);
  } on MissingPluginException {
    return null;
  } on PlatformException {
    return null;
  }
}

/// Turns the native reply into a [ProcessStartInfo], or null when it is
/// missing or malformed.
@visibleForTesting
ProcessStartInfo? parseProcessStart(Map<String, Object?>? raw) {
  if (raw == null) {
    return null;
  }
  final Object? micros = raw['startEpochMicros'];
  if (micros is! int || micros <= 0) {
    return null;
  }
  final Object? source = raw['source'];
  return ProcessStartInfo(
    startedAt: DateTime.fromMicrosecondsSinceEpoch(micros),
    source: source is String ? source : 'native',
    prewarmed: raw['prewarmed'] == true,
  );
}
