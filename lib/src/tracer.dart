import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' as widgets;

import 'advice.dart';
import 'clock.dart';
import 'model.dart';
import 'native.dart';
import 'report.dart';
import 'scope.dart';

/// Called once with the final report when the trace completes.
typedef StartupReportCallback = void Function(StartupReport report);

class _LiveSpan {
  _LiveSpan({
    required this.name,
    required this.kind,
    required this.start,
    required this.parent,
    required this.isSync,
    required this.isDeferred,
    required this.dependsOnPrevious,
  });

  final String name;
  final StartupSpanKind kind;
  final Duration start;
  final _LiveSpan? parent;
  final bool isSync;
  final bool isDeferred;
  final bool dependsOnPrevious;
  final List<_LiveSpan> children = <_LiveSpan>[];
  Duration? end;
  String? error;
  developer.TimelineTask? task;

  StartupSpan freeze() => StartupSpan(
        name: name,
        kind: kind,
        start: start,
        end: end,
        isSync: isSync,
        isDeferred: isDeferred,
        dependsOnPrevious: dependsOnPrevious,
        error: error,
        children: List<StartupSpan>.unmodifiable(children.map((_LiveSpan c) => c.freeze())),
      );
}

String _describe(Object error) {
  final String text = error.toString();
  return text.length <= 160 ? text : '${text.substring(0, 157)}...';
}

/// Measures and explains app startup.
///
/// ```dart
/// Future<void> main() async {
///   final trace = StartupTracer.start();
///   WidgetsFlutterBinding.ensureInitialized();
///   await trace.phase('config', loadConfig);
///   await trace.parallel({'db': openDb, 'prefs': loadPrefs});
///   trace.deferred('analytics', initAnalytics);
///   trace.runApp(const MyApp());
/// }
/// ```
///
/// Every time is measured from the [StartupTracer.start] call, so call it as
/// the very first statement of `main`.
class StartupTracer {
  StartupTracer._({
    required this.clock,
    required this.waitForInteractive,
    required this.adviceConfig,
    required this.timelineEvents,
    required this.deferredFallback,
    required this.printer,
    required ProcessStartReader processStartReader,
    this.onReport,
  })  : _processStartReader = processStartReader,
        _t0 = clock.elapsed,
        _t0Wall = clock.now();

  /// Starts tracing. Call it as the first line of `main`.
  ///
  /// * [waitForInteractive]: when true the trace completes only after
  ///   [markInteractive]; otherwise it completes once the first frame is
  ///   drawn and every deferred task has finished.
  /// * [onReport]: receives the final report once (send it to your logs or
  ///   analytics). The last [historyLimit] reports are also kept in memory in
  ///   [history]; nothing is written to disk.
  /// * [printReport]: print the report to the console when it completes
  ///   (defaults to on outside release builds). [printer] defaults to
  ///   [debugPrint].
  /// * [timelineEvents]: also emit `dart:developer` timeline events so phases
  ///   show up in the DevTools performance view.
  /// * [deferredFallback]: deferred tasks start when the engine reports the
  ///   first frame as rasterized; if it never does (tests, headless), they
  ///   start this long after the first frame was built.
  /// * [clock] and [processStartReader] exist for tests.
  factory StartupTracer.start({
    bool waitForInteractive = false,
    StartupReportCallback? onReport,
    bool printReport = !kReleaseMode,
    void Function(String line)? printer,
    bool timelineEvents = true,
    StartupAdviceConfig adviceConfig = const StartupAdviceConfig(),
    Duration deferredFallback = const Duration(seconds: 2),
    TracerClock? clock,
    ProcessStartReader? processStartReader,
  }) {
    final StartupTracer tracer = StartupTracer._(
      clock: clock ?? StopwatchTracerClock(),
      waitForInteractive: waitForInteractive,
      onReport: onReport,
      adviceConfig: adviceConfig,
      timelineEvents: timelineEvents,
      deferredFallback: deferredFallback,
      printer: printReport ? (printer ?? (String line) => debugPrint(line)) : null,
      processStartReader: processStartReader ?? readNativeProcessStart,
    );
    _current = tracer;
    tracer._instant('main');
    return tracer;
  }

  /// The time source.
  final TracerClock clock;

  /// Whether completion waits for [markInteractive].
  final bool waitForInteractive;

  /// Receives the final report once.
  final StartupReportCallback? onReport;

  /// Thresholds for the advice rules.
  final StartupAdviceConfig adviceConfig;

  /// Whether `dart:developer` timeline events are emitted.
  final bool timelineEvents;

  /// See [StartupTracer.start].
  final Duration deferredFallback;

  /// Where the final report is printed, or null to stay silent.
  final void Function(String line)? printer;

  final ProcessStartReader _processStartReader;
  final Duration _t0;
  final DateTime _t0Wall;
  final Object _zoneKey = Object();
  final List<_LiveSpan> _roots = <_LiveSpan>[];
  final List<_LiveSpan> _syncStack = <_LiveSpan>[];
  final List<StartupMark> _marks = <StartupMark>[];
  final List<void Function()> _deferredQueue = <void Function()>[];

  Duration? _runApp;
  Duration? _firstFrameBuilt;
  Duration? _firstFrameRasterized;
  Duration? _interactive;
  String? _interactiveName;
  ProcessStartInfo? _processStart;
  Future<void>? _processStartFuture;
  bool _processResolved = false;
  bool _deferredReleased = false;
  int _pendingDeferred = 0;
  Timer? _fallbackTimer;

  /// Holds the final report once the trace completes (null until then).
  /// Listen to it to react to completion, for example to show a banner.
  final ValueNotifier<StartupReport?> completed = ValueNotifier<StartupReport?>(null);

  static StartupTracer? _current;
  static final List<StartupReport> _history = <StartupReport>[];

  /// How many completed reports [history] keeps.
  static int historyLimit = 5;

  /// The most recently started tracer, for code that has no [BuildContext].
  static StartupTracer? get current => _current;

  /// The last [historyLimit] completed reports of this process, oldest
  /// first. Memory only: use `onReport` to persist or upload them.
  static List<StartupReport> get history => List<StartupReport>.unmodifiable(_history);

  /// Forgets [current] and [history]. For tests.
  @visibleForTesting
  static void debugReset() {
    _current = null;
    _history.clear();
  }

  /// The tracer of the nearest [StartupTracerScope], falling back to
  /// [current]. Throws when there is neither.
  static StartupTracer of(widgets.BuildContext context) {
    final StartupTracer? tracer = maybeOf(context);
    if (tracer == null) {
      throw FlutterError(
        'StartupTracer.of() found no tracer.\n'
        'Call StartupTracer.start() in main() and wrap the app in a '
        'StartupTracerScope (or use trace.runApp(app)).',
      );
    }
    return tracer;
  }

  /// Like [of], but returns null when there is no tracer.
  static StartupTracer? maybeOf(widgets.BuildContext context) =>
      StartupTracerScope.tracerOf(context) ?? _current;

  /// Time elapsed since [StartupTracer.start].
  Duration get elapsed => clock.elapsed - _t0;

  /// Wall-clock time of [StartupTracer.start].
  DateTime get startedAt => _t0Wall;

  /// Whether the trace has completed (see [completed]).
  bool get isComplete => completed.value != null;

  // ---------------------------------------------------------------- phases

  _LiveSpan? get _parent {
    if (_syncStack.isNotEmpty) {
      return _syncStack.last;
    }
    final Object? fromZone = Zone.current[_zoneKey];
    return fromZone is _LiveSpan ? fromZone : null;
  }

  _LiveSpan _open(
    String name,
    StartupSpanKind kind, {
    required bool isSync,
    bool dependsOnPrevious = false,
    bool root = false,
  }) {
    final _LiveSpan? parent = root ? null : _parent;
    final _LiveSpan span = _LiveSpan(
      name: name,
      kind: kind,
      start: elapsed,
      parent: parent,
      isSync: isSync,
      isDeferred: kind == StartupSpanKind.deferred || (parent?.isDeferred ?? false),
      dependsOnPrevious: dependsOnPrevious,
    );
    (parent?.children ?? _roots).add(span);
    if (timelineEvents && !isSync) {
      span.task = developer.TimelineTask(parent: parent?.task, filterKey: 'startup')
        ..start('startup: $name', arguments: <String, Object?>{'kind': kind.name});
    }
    return span;
  }

  void _close(_LiveSpan span, [Object? error]) {
    span.end = elapsed;
    if (error != null) {
      span.error = _describe(error);
    }
    span.task?.finish(arguments: error == null ? null : <String, Object?>{'error': span.error});
    span.task = null;
  }

  Future<T> _runAsync<T>(_LiveSpan span, FutureOr<T> Function() body) async {
    try {
      final T result = await runZoned(
        () => Future<T>.sync(body),
        zoneValues: <Object, Object?>{_zoneKey: span},
      );
      _close(span);
      return result;
    } catch (error) {
      _close(span, error);
      rethrow;
    }
  }

  /// Measures an async (or sync) piece of startup work and returns its
  /// result. Phases started inside [body] are recorded as its children.
  ///
  /// Set [dependsOnPrevious] when this phase needs the one before it, so the
  /// advice does not suggest running them in parallel.
  ///
  /// [body] runs in a child zone (that is how nesting is tracked). Do not call
  /// `WidgetsFlutterBinding.ensureInitialized()` inside it, or Flutter warns
  /// about a zone mismatch at `runApp`; use [phaseSync] for that, or call it
  /// outside any phase.
  Future<T> phase<T>(
    String name,
    FutureOr<T> Function() body, {
    bool dependsOnPrevious = false,
  }) {
    final _LiveSpan span = _open(
      name,
      StartupSpanKind.phase,
      isSync: false,
      dependsOnPrevious: dependsOnPrevious,
    );
    return _runAsync<T>(span, body);
  }

  /// Measures synchronous work and returns its result. Shows up as a
  /// synchronous slice in the DevTools timeline. Runs in the caller's zone.
  T phaseSync<T>(String name, T Function() body) {
    assert(
      body is! Future<Object?> Function(),
      'phaseSync("$name") got an async body; use phase() instead.',
    );
    final _LiveSpan span = _open(name, StartupSpanKind.phase, isSync: true);
    _syncStack.add(span);
    if (timelineEvents) {
      developer.Timeline.startSync('startup: $name');
    }
    Object? failure;
    try {
      return body();
    } catch (error) {
      failure = error;
      rethrow;
    } finally {
      if (timelineEvents) {
        developer.Timeline.finishSync();
      }
      _syncStack.removeLast();
      _close(span, failure);
    }
  }

  /// Runs [tasks] concurrently and measures each one plus the group's wall
  /// time. Returns each task's result under its name.
  ///
  /// Like `Future.wait`, it waits for every task and then throws the first
  /// error, if any.
  Future<Map<String, Object?>> parallel(
    Map<String, FutureOr<Object?> Function()> tasks, {
    String name = 'parallel',
    bool dependsOnPrevious = false,
  }) {
    final _LiveSpan group = _open(
      name,
      StartupSpanKind.group,
      isSync: false,
      dependsOnPrevious: dependsOnPrevious,
    );
    final List<String> names = tasks.keys.toList();
    return _runAsync<Map<String, Object?>>(group, () async {
      final List<Object?> results = await Future.wait<Object?>(<Future<Object?>>[
        for (final MapEntry<String, FutureOr<Object?> Function()> task in tasks.entries)
          _runAsync<Object?>(
            _open(task.key, StartupSpanKind.groupTask, isSync: false),
            task.value,
          ),
      ]);
      return Map<String, Object?>.fromIterables(names, results);
    });
  }

  /// Schedules [body] to run after the first frame is on screen, measured
  /// separately from the critical path.
  ///
  /// The returned future completes when the task finishes (with its error,
  /// if it throws). Ignoring it is fine, but then an error is reported as
  /// uncaught, exactly like an un-awaited future.
  Future<void> deferred(String name, FutureOr<void> Function() body) {
    final Completer<void> done = Completer<void>();
    _pendingDeferred++;
    Future<void> job() async {
      try {
        await _runAsync<void>(
          _open(name, StartupSpanKind.deferred, isSync: false, root: true),
          body,
        );
        done.complete();
      } catch (error, stack) {
        done.completeError(error, stack);
      } finally {
        _pendingDeferred--;
        _maybeComplete();
      }
    }

    if (_deferredReleased) {
      Timer.run(job);
    } else {
      _deferredQueue.add(job);
    }
    return done.future;
  }

  // ----------------------------------------------------------- milestones

  void _instant(String name) {
    if (timelineEvents) {
      developer.Timeline.instantSync('startup: $name');
    }
  }

  /// Records a named instant on the timeline.
  void mark(String name) {
    _marks.add(StartupMark(name, elapsed));
    _instant(name);
  }

  /// Records when `runApp` happened. [StartupTracerScope] calls this when it
  /// is first built; only the first call counts.
  void markRunApp() {
    if (_runApp == null) {
      _runApp = elapsed;
      _instant('runApp');
    }
  }

  /// Wraps [app] in a [StartupTracerScope] and calls Flutter's `runApp`.
  void runApp(widgets.Widget app) {
    markRunApp();
    widgets.runApp(StartupTracerScope(tracer: this, child: app));
  }

  /// Records that the first frame finished building. Called by
  /// [StartupTracerScope]; call it yourself only if you do not use the scope.
  void markFirstFrameBuilt() {
    if (_firstFrameBuilt != null) {
      return;
    }
    _firstFrameBuilt = elapsed;
    _instant('first frame built');
    if (!_deferredReleased) {
      _fallbackTimer = Timer(deferredFallback, releaseDeferred);
    }
    _maybeComplete();
  }

  /// Records that the engine rasterized the first frame. Also starts the
  /// deferred tasks.
  ///
  /// [wallTimeMicros] is the engine's `rasterFinishWallTime`. When
  /// [buildToRasterMicros] (the frame's `rasterFinish - buildFinish`) is also
  /// given, the first-frame-built time is corrected to the engine's own
  /// build-finish instant: the post-frame callback that first records it runs
  /// after the frame is handed to the raster thread and can land later than
  /// the raster finish itself. Missing or implausible values fall back to the
  /// current time.
  void markFirstFrameRasterized({int? wallTimeMicros, int? buildToRasterMicros}) {
    if (_firstFrameRasterized != null) {
      return;
    }
    final Duration now = elapsed;
    Duration at = now;
    if (wallTimeMicros != null && wallTimeMicros > 0) {
      final Duration fromWall = Duration(
        microseconds: wallTimeMicros - _t0Wall.microsecondsSinceEpoch,
      );
      if (!fromWall.isNegative && fromWall <= now) {
        at = fromWall;
        if (buildToRasterMicros != null && buildToRasterMicros >= 0) {
          final Duration built = at - Duration(microseconds: buildToRasterMicros);
          if (!built.isNegative) {
            _firstFrameBuilt = built;
          }
        }
      }
    }
    _firstFrameRasterized = at;
    _instant('first frame rasterized');
    releaseDeferred();
  }

  /// Marks the app as usable (for example, when the home screen has its
  /// data). Only the first call counts as "interactive"; later calls are
  /// recorded as marks.
  void markInteractive([String name = 'interactive']) {
    if (_interactive == null) {
      _interactive = elapsed;
      _interactiveName = name;
      _instant('interactive: $name');
    } else {
      mark('interactive: $name');
    }
    _maybeComplete();
  }

  /// Starts the deferred tasks now (normally triggered by the first frame)
  /// and reads the native process start. Safe to call more than once.
  void releaseDeferred() {
    _fallbackTimer?.cancel();
    _fallbackTimer = null;
    if (!_deferredReleased) {
      _deferredReleased = true;
      final List<void Function()> jobs = List<void Function()>.of(_deferredQueue);
      _deferredQueue.clear();
      jobs.forEach(Timer.run);
    }
    unawaited(resolveProcessStart());
    _maybeComplete();
  }

  /// Reads the native process start time (once). Never throws.
  Future<void> resolveProcessStart() {
    return _processStartFuture ??= () async {
      try {
        _processStart = await _processStartReader();
      } catch (_) {
        _processStart = null;
      }
      _processResolved = true;
      _maybeComplete();
    }();
  }

  /// Stops pending timers. Deferred tasks that have not started are dropped.
  void dispose() {
    _fallbackTimer?.cancel();
    _fallbackTimer = null;
    _deferredQueue.clear();
  }

  // --------------------------------------------------------------- report

  /// A snapshot of everything measured so far. Safe to call at any time.
  StartupReport report() => _build(complete: isComplete);

  StartupReport _build({required bool complete}) {
    final List<StartupSpan> spans = _roots.map((_LiveSpan s) => s.freeze()).toList()
      ..sort((StartupSpan a, StartupSpan b) => a.start.compareTo(b.start));
    return StartupReport(
      startedAt: _t0Wall,
      buildMode: kReleaseMode ? 'release' : (kProfileMode ? 'profile' : 'debug'),
      spans: List<StartupSpan>.unmodifiable(spans),
      marks: List<StartupMark>.unmodifiable(_marks),
      complete: complete,
      processStart: _processStart,
      runApp: _runApp,
      firstFrameBuilt: _firstFrameBuilt,
      firstFrameRasterized: _firstFrameRasterized,
      interactive: _interactive,
      interactiveName: _interactiveName,
      adviceConfig: adviceConfig,
    );
  }

  void _maybeComplete() {
    if (isComplete ||
        (_firstFrameBuilt == null && _firstFrameRasterized == null) ||
        !_deferredReleased ||
        _pendingDeferred > 0 ||
        !_processResolved ||
        (waitForInteractive && _interactive == null)) {
      return;
    }
    final StartupReport report = _build(complete: true);
    _history.add(report);
    while (_history.length > historyLimit && _history.isNotEmpty) {
      _history.removeAt(0);
    }
    completed.value = report;
    printer?.call(report.toPrettyString());
    onReport?.call(report);
  }
}
