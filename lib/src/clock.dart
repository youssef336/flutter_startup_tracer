/// The time source of a `StartupTracer`.
///
/// Production code uses [StopwatchTracerClock]. Tests inject their own clock
/// so phase durations are exact and deterministic.
abstract class TracerClock {
  /// Monotonic time elapsed since an arbitrary, fixed origin.
  ///
  /// Only differences between two readings are used, so the origin does not
  /// matter. It must never go backwards.
  Duration get elapsed;

  /// The current wall-clock time.
  ///
  /// Used once, when tracing starts, to line Dart time up with timestamps that
  /// only exist as wall-clock values (native process start, the engine's
  /// `rasterFinishWallTime`).
  DateTime now();
}

/// The default [TracerClock]: a [Stopwatch] for durations, [DateTime.now] for
/// the wall clock.
class StopwatchTracerClock implements TracerClock {
  /// Creates a clock whose stopwatch starts immediately.
  StopwatchTracerClock() : _stopwatch = Stopwatch()..start();

  final Stopwatch _stopwatch;

  @override
  Duration get elapsed => _stopwatch.elapsed;

  @override
  DateTime now() => DateTime.now();
}
