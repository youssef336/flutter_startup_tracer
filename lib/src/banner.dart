import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'report.dart';
import 'tracer.dart';

/// Shows the startup total on screen for a few seconds once the trace
/// completes. Does nothing in release builds unless [enabled] says so.
///
/// It needs no `MaterialApp`, so it can sit right above the app:
///
/// ```dart
/// trace.runApp(const StartupTracerBanner(child: MyApp()));
/// ```
class StartupTracerBanner extends StatefulWidget {
  /// Creates a banner over [child].
  const StartupTracerBanner({
    super.key,
    required this.child,
    this.tracer,
    this.duration = const Duration(seconds: 5),
    this.alignment = Alignment.topCenter,
    this.enabled = !kReleaseMode,
  });

  /// The app.
  final Widget child;

  /// The tracer to watch; defaults to [StartupTracer.maybeOf].
  final StartupTracer? tracer;

  /// How long the banner stays up.
  final Duration duration;

  /// Where the banner sits.
  final AlignmentGeometry alignment;

  /// Whether to show anything at all (off in release builds by default).
  final bool enabled;

  @override
  State<StartupTracerBanner> createState() => _StartupTracerBannerState();
}

class _StartupTracerBannerState extends State<StartupTracerBanner> {
  StartupTracer? _tracer;
  String? _text;
  Timer? _hide;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _attach(widget.tracer ?? StartupTracer.maybeOf(context));
  }

  @override
  void didUpdateWidget(StartupTracerBanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    _attach(widget.tracer ?? StartupTracer.maybeOf(context));
  }

  void _attach(StartupTracer? tracer) {
    if (!widget.enabled || identical(tracer, _tracer)) {
      return;
    }
    _tracer?.completed.removeListener(_onCompleted);
    _tracer = tracer;
    tracer?.completed.addListener(_onCompleted);
    if (tracer?.completed.value != null) {
      _onCompleted();
    }
  }

  void _onCompleted() {
    final StartupReport? report = _tracer?.completed.value;
    if (report == null || !mounted || _text != null) {
      return;
    }
    final String target =
        report.interactive != null ? "interactive '${report.interactiveName}'" : 'first frame';
    final Duration? fromProcess = report.totalFromProcessStart;
    setState(() {
      _text = [
        'Startup ${fmtMs(report.total)} to $target',
        if (fromProcess != null) '(${fmtMs(fromProcess)} from process start)',
        if (report.buildMode == 'debug') '- debug build, not representative',
      ].join(' ');
    });
    _hide = Timer(widget.duration, () {
      if (mounted) {
        setState(() => _text = '');
      }
    });
  }

  @override
  void dispose() {
    _hide?.cancel();
    _tracer?.completed.removeListener(_onCompleted);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final String? text = _text;
    if (text == null || text.isEmpty) {
      return widget.child;
    }
    final EdgeInsets padding =
        MediaQuery.maybePaddingOf(context) ?? MediaQueryData.fromView(View.of(context)).padding;
    return Stack(
      textDirection: TextDirection.ltr,
      fit: StackFit.passthrough,
      children: <Widget>[
        widget.child,
        Positioned.fill(
          child: IgnorePointer(
            child: Padding(
              padding: padding + const EdgeInsets.all(8),
              child: Align(
                alignment: widget.alignment,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: const Color(0xDD000000),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    child: Text(
                      text,
                      key: const ValueKey<String>('startup-tracer-banner'),
                      textDirection: TextDirection.ltr,
                      style: const TextStyle(
                        color: Color(0xFFFFFFFF),
                        fontSize: 13,
                        decoration: TextDecoration.none,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
