import 'package:flutter/foundation.dart';

import 'model.dart';
import 'report.dart';

/// Which rule produced a piece of [StartupAdvice].
enum StartupAdviceCode {
  /// The trace was taken in debug mode, where timings are not representative.
  debugMode,

  /// A phase on the critical path took longer than
  /// [StartupAdviceConfig.slowPhase].
  slowCriticalPhase,

  /// Several independent async phases ran one after another.
  serialPhases,

  /// The first frame took long to appear after `runApp`.
  heavyFirstBuild,

  /// The gap between the process starting and Dart `main` is large.
  slowNativeStart,

  /// The process was pre-warmed (or started long before `main`), so the
  /// native gap is not what the user waited for.
  prewarmed,

  /// A phase threw.
  failedPhase,
}

/// How much a piece of [StartupAdvice] matters.
enum StartupAdviceSeverity {
  /// Context worth knowing; nothing to fix.
  info,

  /// Something that probably costs startup time.
  warning,
}

/// One suggestion derived from a [StartupReport].
@immutable
class StartupAdvice {
  /// Creates a piece of advice.
  const StartupAdvice({
    required this.code,
    required this.severity,
    required this.message,
    this.spans = const <String>[],
  });

  /// The rule that fired.
  final StartupAdviceCode code;

  /// How much it matters.
  final StartupAdviceSeverity severity;

  /// A human-readable, single-paragraph suggestion.
  final String message;

  /// The names of the spans the advice is about, if any.
  final List<String> spans;

  /// A JSON-friendly map.
  Map<String, Object?> toJson() => <String, Object?>{
        'code': code.name,
        'severity': severity.name,
        'message': message,
        if (spans.isNotEmpty) 'spans': spans,
      };

  @override
  String toString() => '[${severity.name}] $message';
}

/// Thresholds for the advice rules.
@immutable
class StartupAdviceConfig {
  /// Creates a config. Every threshold has a sensible default.
  const StartupAdviceConfig({
    this.slowPhase = const Duration(milliseconds: 100),
    this.serialMinTotal = const Duration(milliseconds: 150),
    this.serialMinPhase = const Duration(milliseconds: 20),
    this.heavyFirstFrame = const Duration(milliseconds: 500),
    this.slowNativeStart = const Duration(milliseconds: 1000),
    this.prewarmSuspect = const Duration(seconds: 10),
  });

  /// A critical-path phase at least this long gets "consider deferring".
  final Duration slowPhase;

  /// A run of serial async phases is reported when its total is at least this.
  final Duration serialMinTotal;

  /// Phases shorter than this are ignored by the serial rule (not worth it).
  final Duration serialMinPhase;

  /// `runApp` to first frame longer than this is a "heavy first build".
  final Duration heavyFirstFrame;

  /// Process start to `main` longer than this gets a warning.
  final Duration slowNativeStart;

  /// Process start to `main` longer than this is assumed to be pre-warming or
  /// a cached process rather than real launch work.
  final Duration prewarmSuspect;
}

/// Runs every advice rule over [report].
List<StartupAdvice> computeAdvice(StartupReport report, StartupAdviceConfig config) {
  final List<StartupAdvice> out = <StartupAdvice>[];

  if (report.buildMode == 'debug') {
    out.add(
      const StartupAdvice(
        code: StartupAdviceCode.debugMode,
        severity: StartupAdviceSeverity.warning,
        message: 'Measured in debug mode (JIT, asserts, no AOT): numbers are several times '
            'slower than what users see. Measure with --profile or --release.',
      ),
    );
  }

  _nativeGap(report, config, out);
  _slowPhases(report, config, out);
  _serialPhases(report, config, out);
  _heavyFirstBuild(report, config, out);
  _failures(report.spans, out);
  return out;
}

void _nativeGap(StartupReport report, StartupAdviceConfig config, List<StartupAdvice> out) {
  final ProcessStartInfo? process = report.processStart;
  final Duration? gap = report.processStartToMain;
  if (process == null || gap == null) {
    return;
  }
  if (process.prewarmed || gap >= config.prewarmSuspect) {
    out.add(
      StartupAdvice(
        code: StartupAdviceCode.prewarmed,
        severity: StartupAdviceSeverity.info,
        message: 'Process started ${fmtMs(gap)} before main'
            '${process.prewarmed ? ' and the OS reported pre-warming' : ''}; '
            'that gap is not user-visible launch time and is left out of the totals.',
      ),
    );
    return;
  }
  if (gap >= config.slowNativeStart) {
    out.add(
      StartupAdvice(
        code: StartupAdviceCode.slowNativeStart,
        severity: StartupAdviceSeverity.warning,
        message: '${fmtMs(gap)} passed between the process starting and Dart main. Look at '
            'native work before the engine runs: Application.onCreate / AppDelegate, '
            'content providers, plugin registration, and large native libraries.',
      ),
    );
  }
}

/// Spans the "slow phase" rule looks at: top-level critical phases and the
/// tasks of top-level parallel groups. Nested phases are left out so one slow
/// leaf does not produce three warnings.
Iterable<StartupSpan> _criticalCandidates(StartupReport report) sync* {
  for (final StartupSpan span in report.spans) {
    if (!span.isCritical || !_beforeRunApp(report, span)) {
      continue;
    }
    if (span.kind == StartupSpanKind.group) {
      yield* span.children;
    } else {
      yield span;
    }
  }
}

bool _beforeRunApp(StartupReport report, StartupSpan span) {
  final Duration? runApp = report.runApp;
  return runApp == null || span.start <= runApp;
}

void _slowPhases(StartupReport report, StartupAdviceConfig config, List<StartupAdvice> out) {
  for (final StartupSpan span in _criticalCandidates(report)) {
    final Duration? duration = span.duration;
    if (duration == null || duration < config.slowPhase) {
      continue;
    }
    out.add(
      StartupAdvice(
        code: StartupAdviceCode.slowCriticalPhase,
        severity: StartupAdviceSeverity.warning,
        message: "'${span.name}' took ${fmtMs(duration)} on the critical path. If the first "
            "screen does not need it, consider deferring it with deferred('${span.name}', ...) "
            'or initialising it lazily on first use.',
        spans: <String>[span.name],
      ),
    );
  }
}

void _serialPhases(StartupReport report, StartupAdviceConfig config, List<StartupAdvice> out) {
  final List<StartupSpan> run = <StartupSpan>[];

  void flush() {
    if (run.length >= 2) {
      final Duration sum = run.fold<Duration>(
        Duration.zero,
        (Duration acc, StartupSpan s) => acc + s.duration!,
      );
      final Duration longest =
          run.map((StartupSpan s) => s.duration!).reduce((Duration a, Duration b) => a > b ? a : b);
      if (sum >= config.serialMinTotal) {
        final List<String> names = run.map((StartupSpan s) => s.name).toList();
        out.add(
          StartupAdvice(
            code: StartupAdviceCode.serialPhases,
            severity: StartupAdviceSeverity.warning,
            message: '${names.map((String n) => "'$n'").join(', ')} ran one after another '
                '(${fmtMs(sum)} in total). If they do not depend on each other, run them '
                'with parallel({...}): best case about ${fmtMs(longest)}, saving up to '
                '${fmtMs(sum - longest)}. Pass dependsOnPrevious: true to a phase that '
                'really needs the one before it.',
            spans: names,
          ),
        );
      }
    }
    run.clear();
  }

  for (final StartupSpan span in report.spans) {
    if (!span.isCritical || !_beforeRunApp(report, span)) {
      continue;
    }
    final Duration? duration = span.duration;
    final bool eligible = span.kind == StartupSpanKind.phase &&
        !span.isSync &&
        span.error == null &&
        duration != null &&
        duration >= config.serialMinPhase;
    if (!eligible) {
      flush();
      continue;
    }
    if (span.dependsOnPrevious || (run.isNotEmpty && span.start < run.last.end!)) {
      // Either declared dependent, or it overlapped the previous one (already
      // concurrent): start a new run from here.
      flush();
    }
    run.add(span);
  }
  flush();
}

void _heavyFirstBuild(StartupReport report, StartupAdviceConfig config, List<StartupAdvice> out) {
  final Duration? runApp = report.runApp;
  final Duration? firstFrame = report.timeToFirstFrame;
  if (runApp == null || firstFrame == null) {
    return;
  }
  final Duration gap = firstFrame - runApp;
  if (gap <= config.heavyFirstFrame) {
    return;
  }
  out.add(
    StartupAdvice(
      code: StartupAdviceCode.heavyFirstBuild,
      severity: StartupAdviceSeverity.warning,
      message: 'The first frame appeared ${fmtMs(gap)} after runApp: a heavy first build. '
          'Check synchronous work in build()/initState of the first screen, large '
          'images or fonts decoded up front, and a splash that waits on I/O before '
          'drawing anything.',
    ),
  );
}

void _failures(List<StartupSpan> spans, List<StartupAdvice> out) {
  for (final StartupSpan span in spans) {
    if (span.error != null) {
      out.add(
        StartupAdvice(
          code: StartupAdviceCode.failedPhase,
          severity: StartupAdviceSeverity.warning,
          message: "'${span.name}' threw: ${span.error}",
          spans: <String>[span.name],
        ),
      );
    }
    _failures(span.children, out);
  }
}
