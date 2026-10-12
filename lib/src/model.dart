import 'package:flutter/foundation.dart';

/// What produced a [StartupSpan].
enum StartupSpanKind {
  /// A single unit of work: `phase` or `phaseSync`.
  phase,

  /// A `parallel` group. Its duration is the wall time of the whole group.
  group,

  /// One task inside a `parallel` group.
  groupTask,

  /// A task started by `deferred`, after the first frame.
  deferred,
}

/// One measured piece of startup work.
///
/// All times are offsets from the moment `StartupTracer.start` was called
/// (Dart `main`). A span that has not finished yet has a null [end].
@immutable
class StartupSpan {
  /// Creates a span record.
  const StartupSpan({
    required this.name,
    required this.kind,
    required this.start,
    required this.end,
    required this.isSync,
    required this.isDeferred,
    required this.dependsOnPrevious,
    this.error,
    this.children = const <StartupSpan>[],
  });

  /// The name passed to the tracer.
  final String name;

  /// How the span was started.
  final StartupSpanKind kind;

  /// When the span started, relative to Dart `main`.
  final Duration start;

  /// When the span finished, or null while it is still running.
  final Duration? end;

  /// True for `phaseSync` spans: they block the UI isolate and cannot be
  /// overlapped with other Dart work.
  final bool isSync;

  /// True when the span (or an ancestor) was started with `deferred`, so it
  /// ran after the first frame and is not on the critical path.
  final bool isDeferred;

  /// True when the caller declared that this phase needs the previous one, so
  /// the "could run in parallel" advice skips it.
  final bool dependsOnPrevious;

  /// A short description of the error the span's body threw, if any.
  final String? error;

  /// Spans started while this one was running.
  final List<StartupSpan> children;

  /// How long the span took, or null while it is still running.
  ///
  /// For a [StartupSpanKind.group] this is the wall time of the whole group.
  Duration? get duration => end == null ? null : end! - start;

  /// For a group: the sum of its tasks' durations (what the group would have
  /// cost had they run one after another). Zero for other spans.
  Duration get childrenSum => children.fold<Duration>(
        Duration.zero,
        (Duration sum, StartupSpan child) => sum + (child.duration ?? Duration.zero),
      );

  /// True when the span ran on the critical path (before the first frame was
  /// unblocked), i.e. it is not deferred.
  bool get isCritical => !isDeferred;

  @override
  String toString() => 'StartupSpan($name, ${kind.name}, $start..$end)';
}

/// A named instant on the startup timeline.
@immutable
class StartupMark {
  /// Creates a mark.
  const StartupMark(this.name, this.at);

  /// The label passed to `mark`.
  final String name;

  /// When the mark was recorded, relative to Dart `main`.
  final Duration at;

  @override
  String toString() => 'StartupMark($name, $at)';
}

/// When the operating system started the app's process.
///
/// Read through the plugin's tiny native piece on Android and iOS. On other
/// platforms (and in tests) it is unknown and the report says so.
@immutable
class ProcessStartInfo {
  /// Creates a process start record.
  const ProcessStartInfo({
    required this.startedAt,
    required this.source,
    this.prewarmed = false,
  });

  /// Wall-clock time the process was started.
  final DateTime startedAt;

  /// Which native API produced [startedAt], for example
  /// `Process.getStartRequestedElapsedRealtime` or `sysctl(KERN_PROC_PID)`.
  final String source;

  /// True when the OS reported that the process was pre-warmed (iOS 15+
  /// launches apps ahead of time). The gap before `main` is then not what the
  /// user waited for.
  final bool prewarmed;
}
