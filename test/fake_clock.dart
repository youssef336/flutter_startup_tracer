import 'package:flutter_startup_tracer/flutter_startup_tracer.dart';

/// A clock that only moves when the test says so.
class FakeClock implements TracerClock {
  FakeClock([DateTime? wallAtZero]) : wallAtZero = wallAtZero ?? DateTime.utc(2026, 1, 1, 12);

  final DateTime wallAtZero;
  Duration _elapsed = Duration.zero;

  void advance(int ms) => _elapsed += Duration(milliseconds: ms);

  @override
  Duration get elapsed => _elapsed;

  @override
  DateTime now() => wallAtZero.add(_elapsed);
}

const Duration ms0 = Duration.zero;

Duration ms(int value) => Duration(milliseconds: value);

/// Starts a silent tracer on [clock] whose native start is [process].
StartupTracer quietTracer(
  FakeClock clock, {
  ProcessStartInfo? process,
  bool waitForInteractive = false,
  StartupReportCallback? onReport,
}) {
  return StartupTracer.start(
    clock: clock,
    printReport: false,
    waitForInteractive: waitForInteractive,
    onReport: onReport,
    processStartReader: () async => process,
  );
}
