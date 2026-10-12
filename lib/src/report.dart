import 'package:flutter/foundation.dart';

import 'advice.dart';
import 'model.dart';
import 'waterfall.dart';

/// Formats a duration as whole milliseconds, for example `120 ms`.
String fmtMs(Duration d) => '${(d.inMicroseconds / 1000).round()} ms';

double _ms(Duration d) => (d.inMicroseconds / 100).round() / 10;

/// A snapshot of everything a `StartupTracer` measured.
///
/// Times are offsets from Dart `main` (the `StartupTracer.start` call).
@immutable
class StartupReport {
  /// Creates a report. Normally built by `StartupTracer.report`.
  StartupReport({
    required this.startedAt,
    required this.buildMode,
    required this.spans,
    required this.marks,
    required this.complete,
    this.processStart,
    this.runApp,
    this.firstFrameBuilt,
    this.firstFrameRasterized,
    this.interactive,
    this.interactiveName,
    this.adviceConfig = const StartupAdviceConfig(),
  });

  /// Wall-clock time of Dart `main`.
  final DateTime startedAt;

  /// `debug`, `profile` or `release`.
  final String buildMode;

  /// Top-level spans in start order; nested spans are in
  /// [StartupSpan.children].
  final List<StartupSpan> spans;

  /// Every `mark` call, in order.
  final List<StartupMark> marks;

  /// True when the trace has settled: first frame drawn, deferred tasks done,
  /// interactive marked (when waited for) and the native start read.
  final bool complete;

  /// When the OS started the process, or null when unknown.
  final ProcessStartInfo? processStart;

  /// When `runApp` attached the root widget.
  final Duration? runApp;

  /// When the first frame finished building on the UI thread.
  final Duration? firstFrameBuilt;

  /// When the engine finished rasterizing the first frame (the user can see
  /// it). Null when the engine never reported frame timings (tests,
  /// headless runs).
  final Duration? firstFrameRasterized;

  /// When the app called `markInteractive`.
  final Duration? interactive;

  /// The name passed to `markInteractive`.
  final String? interactiveName;

  /// Thresholds used to compute [advice].
  final StartupAdviceConfig adviceConfig;

  /// Suggestions derived from this report.
  late final List<StartupAdvice> advice = computeAdvice(this, adviceConfig);

  /// Process start to Dart `main`, or null when the process start is unknown.
  Duration? get processStartToMain {
    final ProcessStartInfo? process = processStart;
    if (process == null) {
      return null;
    }
    final Duration gap = startedAt.difference(process.startedAt);
    return gap.isNegative ? null : gap;
  }

  /// The process-start gap only when it looks like real launch work (not
  /// pre-warming or a cached process).
  Duration? get trustedProcessStartToMain {
    final Duration? gap = processStartToMain;
    if (gap == null || processStart!.prewarmed || gap >= adviceConfig.prewarmSuspect) {
      return null;
    }
    return gap;
  }

  /// First frame on screen: rasterized when known, otherwise built.
  Duration? get timeToFirstFrame => firstFrameRasterized ?? firstFrameBuilt;

  /// `main` to the `markInteractive` call.
  Duration? get timeToInteractive => interactive;

  /// End of the last critical (non-deferred) top-level span.
  Duration? get criticalPathEnd {
    Duration? end;
    for (final StartupSpan span in spans) {
      final Duration? spanEnd = span.end;
      if (span.isCritical && spanEnd != null && (end == null || spanEnd > end)) {
        end = spanEnd;
      }
    }
    return end;
  }

  /// The headline number: `main` to interactive, else to first frame, else
  /// to the end of the critical path.
  Duration get total => interactive ?? timeToFirstFrame ?? criticalPathEnd ?? Duration.zero;

  /// [total] plus the trusted process-start gap, or null when it is unknown.
  Duration? get totalFromProcessStart {
    final Duration? gap = trustedProcessStartToMain;
    return gap == null ? null : gap + total;
  }

  /// The furthest point on the timeline (used to scale the waterfall).
  Duration get timelineEnd {
    Duration end = total;
    void visit(StartupSpan span) {
      final Duration last = span.end ?? span.start;
      if (last > end) {
        end = last;
      }
      span.children.forEach(visit);
    }

    spans.forEach(visit);
    for (final StartupMark mark in marks) {
      if (mark.at > end) {
        end = mark.at;
      }
    }
    for (final Duration? d in <Duration?>[runApp, firstFrameBuilt, firstFrameRasterized]) {
      if (d != null && d > end) {
        end = d;
      }
    }
    return end;
  }

  /// A JSON-friendly map (all times in milliseconds, one decimal).
  Map<String, Object?> toJson() {
    Map<String, Object?> span(StartupSpan s) => <String, Object?>{
          'name': s.name,
          'kind': s.kind.name,
          'startMs': _ms(s.start),
          'endMs': s.end == null ? null : _ms(s.end!),
          'durationMs': s.duration == null ? null : _ms(s.duration!),
          if (s.kind == StartupSpanKind.group) 'sumMs': _ms(s.childrenSum),
          if (s.isSync) 'sync': true,
          if (s.isDeferred) 'deferred': true,
          if (s.dependsOnPrevious) 'dependsOnPrevious': true,
          if (s.error != null) 'error': s.error,
          if (s.children.isNotEmpty) 'children': s.children.map(span).toList(),
        };
    double? ms(Duration? d) => d == null ? null : _ms(d);

    final ProcessStartInfo? process = processStart;
    return <String, Object?>{
      'schema': 1,
      'buildMode': buildMode,
      'startedAt': startedAt.toUtc().toIso8601String(),
      'complete': complete,
      'processStart': process == null
          ? null
          : <String, Object?>{
              'at': process.startedAt.toUtc().toIso8601String(),
              'toMainMs': ms(processStartToMain),
              'source': process.source,
              'prewarmed': process.prewarmed,
            },
      'milestones': <String, Object?>{
        'runAppMs': ms(runApp),
        'firstFrameBuiltMs': ms(firstFrameBuilt),
        'firstFrameRasterizedMs': ms(firstFrameRasterized),
        'interactiveMs': ms(interactive),
        'interactiveName': interactiveName,
        'totalMs': _ms(total),
        'totalFromProcessStartMs': ms(totalFromProcessStart),
      },
      'spans': spans.map(span).toList(),
      'marks': marks
          .map((StartupMark m) => <String, Object?>{'name': m.name, 'atMs': _ms(m.at)})
          .toList(),
      'advice': advice.map((StartupAdvice a) => a.toJson()).toList(),
    };
  }

  /// Summary lines shared by the console and Markdown output.
  List<(String, String)> summary() {
    final ProcessStartInfo? process = processStart;
    final Duration? gap = processStartToMain;
    final Duration? firstFrame = timeToFirstFrame;
    return <(String, String)>[
      (
        'process start -> main',
        process == null || gap == null
            ? 'unknown (native start not available)'
            : '${fmtMs(gap)} (${process.source}'
                '${trustedProcessStartToMain == null ? ', not counted' : ''})',
      ),
      if (runApp != null) ('main -> runApp', fmtMs(runApp!)),
      if (firstFrame != null)
        (
          'main -> first frame',
          '${fmtMs(firstFrame)} (${firstFrameRasterized != null ? 'rasterized' : 'built'})',
        ),
      if (interactive != null)
        ('main -> interactive', "${fmtMs(interactive!)} ('$interactiveName')"),
      if (totalFromProcessStart != null)
        (
          'process start -> ${interactive != null ? 'interactive' : 'first frame'}',
          fmtMs(totalFromProcessStart!)
        ),
    ];
  }

  /// A console-friendly report with an ASCII waterfall and the advice.
  String toPrettyString({int barWidth = 40}) => renderPretty(this, barWidth: barWidth);

  /// A Markdown report (summary table, phases table, waterfall, advice).
  String toMarkdown({int barWidth = 40}) => renderMarkdown(this, barWidth: barWidth);

  @override
  String toString() => 'StartupReport(total: ${fmtMs(total)}, complete: $complete)';
}
