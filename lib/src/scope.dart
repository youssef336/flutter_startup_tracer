import 'dart:ui' show FramePhase, FrameTiming;

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import 'tracer.dart';

/// Puts a [StartupTracer] in the widget tree and captures the first frame.
///
/// Wrap the root widget with it in `runApp` (or call `trace.runApp(app)`,
/// which does it for you). When it is first built it records `runApp`, the
/// moment the first frame finished building, and the moment the engine
/// rasterized it; that last event also starts the deferred tasks.
class StartupTracerScope extends StatefulWidget {
  /// Creates a scope for [tracer].
  const StartupTracerScope({super.key, required this.tracer, required this.child});

  /// The tracer started in `main`.
  final StartupTracer tracer;

  /// The app.
  final Widget child;

  /// The tracer of the nearest scope, or null. Prefer [StartupTracer.of].
  static StartupTracer? tracerOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<_InheritedStartupTracer>()?.tracer;

  @override
  State<StartupTracerScope> createState() => _StartupTracerScopeState();
}

class _StartupTracerScopeState extends State<StartupTracerScope> {
  TimingsCallback? _timings;

  @override
  void initState() {
    super.initState();
    final StartupTracer tracer = widget.tracer;
    tracer.markRunApp();
    if (tracer.report().timeToFirstFrame != null) {
      return; // A second scope (or a rebuilt one) has nothing left to capture.
    }
    final SchedulerBinding binding = SchedulerBinding.instance;
    _timings = (List<FrameTiming> timings) {
      if (timings.isEmpty) {
        return;
      }
      _stopListening();
      final FrameTiming first = timings.first;
      tracer.markFirstFrameRasterized(
        wallTimeMicros: first.timestampInMicroseconds(FramePhase.rasterFinishWallTime),
        buildToRasterMicros: first.timestampInMicroseconds(FramePhase.rasterFinish) -
            first.timestampInMicroseconds(FramePhase.buildFinish),
      );
    };
    binding.addTimingsCallback(_timings!);
    binding.addPostFrameCallback((Duration _) => tracer.markFirstFrameBuilt());
  }

  void _stopListening() {
    final TimingsCallback? timings = _timings;
    if (timings != null) {
      SchedulerBinding.instance.removeTimingsCallback(timings);
      _timings = null;
    }
  }

  @override
  void dispose() {
    _stopListening();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      _InheritedStartupTracer(tracer: widget.tracer, child: widget.child);
}

class _InheritedStartupTracer extends InheritedWidget {
  const _InheritedStartupTracer({required this.tracer, required super.child});

  final StartupTracer tracer;

  @override
  bool updateShouldNotify(_InheritedStartupTracer oldWidget) => tracer != oldWidget.tracer;
}
