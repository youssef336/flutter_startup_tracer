import 'dart:async';

import 'package:flutter_startup_tracer/flutter_startup_tracer.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_clock.dart';

void main() {
  late FakeClock clock;

  setUp(() {
    StartupTracer.debugReset();
    clock = FakeClock();
  });

  group('phases', () {
    test('phase measures async work and returns its value', () async {
      final StartupTracer trace = quietTracer(clock);
      clock.advance(5);
      final int value = await trace.phase('config', () async {
        await Future<void>.delayed(Duration.zero);
        clock.advance(120);
        return 42;
      });

      expect(value, 42);
      final StartupSpan span = trace.report().spans.single;
      expect(span.name, 'config');
      expect(span.kind, StartupSpanKind.phase);
      expect(span.start, ms(5));
      expect(span.duration, ms(120));
      expect(span.isSync, isFalse);
      expect(span.isCritical, isTrue);
    });

    test('phaseSync measures sync work and nests', () {
      final StartupTracer trace = quietTracer(clock);
      final String result = trace.phaseSync('outer', () {
        clock.advance(10);
        trace.phaseSync('inner', () => clock.advance(30));
        clock.advance(10);
        return 'ok';
      });

      expect(result, 'ok');
      final StartupSpan outer = trace.report().spans.single;
      expect(outer.isSync, isTrue);
      expect(outer.duration, ms(50));
      expect(outer.children.single.name, 'inner');
      expect(outer.children.single.start, ms(10));
      expect(outer.children.single.duration, ms(30));
    });

    test('async phases nest through awaits', () async {
      final StartupTracer trace = quietTracer(clock);
      await trace.phase('storage', () async {
        clock.advance(5);
        await trace.phase('open box', () async {
          await Future<void>.delayed(Duration.zero);
          clock.advance(40);
        });
        await trace.phase('migrate', () async => clock.advance(15));
      });
      await trace.phase('after', () async => clock.advance(1));

      final List<StartupSpan> roots = trace.report().spans;
      expect(roots.map((StartupSpan s) => s.name), <String>['storage', 'after']);
      expect(roots.first.children.map((StartupSpan s) => s.name), <String>['open box', 'migrate']);
      expect(roots.first.duration, ms(60));
      expect(roots.last.children, isEmpty);
    });

    test('a throwing phase is recorded and rethrown', () async {
      final StartupTracer trace = quietTracer(clock);
      await expectLater(
        trace.phase<void>('boom', () async {
          clock.advance(7);
          throw StateError('no network');
        }),
        throwsStateError,
      );
      expect(() => trace.phaseSync<void>('sync boom', () => throw ArgumentError('bad')),
          throwsArgumentError);

      final List<StartupSpan> spans = trace.report().spans;
      expect(spans[0].duration, ms(7));
      expect(spans[0].error, contains('no network'));
      expect(spans[1].error, contains('bad'));
    });
  });

  group('parallel', () {
    test('records wall time vs sum and returns results by name', () async {
      final StartupTracer trace = quietTracer(clock);
      final Completer<String> hive = Completer<String>();
      final Completer<int> prefs = Completer<int>();

      final Future<Map<String, Object?>> group =
          trace.parallel(<String, FutureOr<Object?> Function()>{
        'hive': () => hive.future,
        'prefs': () => prefs.future,
      }, name: 'storage');

      clock.advance(100);
      hive.complete('box');
      await Future<void>.delayed(Duration.zero);
      clock.advance(200);
      prefs.complete(3);
      final Map<String, Object?> results = await group;

      expect(results, <String, Object?>{'hive': 'box', 'prefs': 3});
      final StartupSpan span = trace.report().spans.single;
      expect(span.kind, StartupSpanKind.group);
      expect(span.name, 'storage');
      expect(span.duration, ms(300));
      expect(span.childrenSum, ms(400));
      expect(span.children.map((StartupSpan s) => s.kind), everyElement(StartupSpanKind.groupTask));
      expect(span.children.map((StartupSpan s) => s.duration), <Duration>[ms(100), ms(300)]);
    });

    test('waits for every task, then throws the first error', () async {
      final StartupTracer trace = quietTracer(clock);
      final Completer<void> slow = Completer<void>();
      final Future<Map<String, Object?>> group =
          trace.parallel(<String, FutureOr<Object?> Function()>{
        'bad': () async => throw StateError('bad'),
        'slow': () => slow.future,
      });
      var settled = false;
      unawaited(group.then((_) {}, onError: (Object _) => settled = true));
      await Future<void>.delayed(Duration.zero);
      expect(settled, isFalse);

      clock.advance(50);
      slow.complete();
      await expectLater(group, throwsStateError);

      final StartupSpan span = trace.report().spans.single;
      expect(span.error, contains('bad'));
      expect(span.children.first.error, contains('bad'));
      expect(span.children.last.error, isNull);
      expect(span.children.last.duration, ms(50));
    });
  });

  group('deferred and completion', () {
    test('deferred tasks wait for the first frame and stay off the critical path', () async {
      final List<StartupReport> reports = <StartupReport>[];
      final StartupTracer trace = quietTracer(clock, onReport: reports.add);
      var ran = false;
      final Future<void> ads = trace.deferred('ads', () async {
        ran = true;
        clock.advance(250);
      });

      await Future<void>.delayed(Duration.zero);
      expect(ran, isFalse);

      clock.advance(400);
      trace.markRunApp();
      clock.advance(300);
      trace.markFirstFrameBuilt();
      trace.markFirstFrameRasterized();
      await ads;

      expect(ran, isTrue);
      final StartupReport report = trace.completed.value!;
      expect(reports, <StartupReport>[report]);
      expect(StartupTracer.history, <StartupReport>[report]);
      expect(report.complete, isTrue);
      final StartupSpan span = report.spans.single;
      expect(span.kind, StartupSpanKind.deferred);
      expect(span.isCritical, isFalse);
      expect(span.start, ms(700));
      expect(span.duration, ms(250));
      expect(report.total, ms(700));
      expect(report.criticalPathEnd, isNull);
      trace.dispose();
    });

    test('a deferred call after release runs on the next event-loop turn', () async {
      final StartupTracer trace = quietTracer(clock);
      trace.markFirstFrameBuilt();
      trace.releaseDeferred();
      var ran = false;
      final Future<void> late = trace.deferred('late', () => ran = true);
      expect(ran, isFalse);
      await late;
      expect(ran, isTrue);
    });

    test('a failing deferred task completes its future with the error', () async {
      final StartupTracer trace = quietTracer(clock);
      final Future<void> task = trace.deferred('crash', () => throw StateError('x'));
      trace.markFirstFrameBuilt();
      trace.releaseDeferred();
      await expectLater(task, throwsStateError);
      await pumpEventQueue();
      expect(trace.completed.value!.spans.single.error, contains('x'));
    });

    test('waitForInteractive holds completion until markInteractive', () async {
      final StartupTracer trace = quietTracer(clock, waitForInteractive: true);
      trace.markFirstFrameBuilt();
      trace.releaseDeferred();
      await pumpEventQueue();
      expect(trace.isComplete, isFalse);

      clock.advance(900);
      trace.markInteractive('home');
      trace.markInteractive('ignored');
      expect(trace.isComplete, isTrue);
      final StartupReport report = trace.completed.value!;
      expect(report.interactive, ms(900));
      expect(report.interactiveName, 'home');
      expect(report.total, ms(900));
      expect(trace.report().marks.map((StartupMark m) => m.name), <String>['interactive: ignored']);
    });

    test('history keeps only the last historyLimit reports', () async {
      StartupTracer.historyLimit = 2;
      addTearDown(() => StartupTracer.historyLimit = 5);
      for (int i = 0; i < 3; i++) {
        final StartupTracer trace = quietTracer(clock);
        trace.markFirstFrameBuilt();
        trace.releaseDeferred();
        await pumpEventQueue();
      }
      expect(StartupTracer.history, hasLength(2));
    });

    test('rasterized time comes from the engine wall clock when plausible', () {
      final StartupTracer trace = quietTracer(clock);
      clock.advance(500);
      final int wall = clock.wallAtZero.add(ms(420)).microsecondsSinceEpoch;
      trace.markFirstFrameBuilt();
      trace.markFirstFrameRasterized(wallTimeMicros: wall, buildToRasterMicros: 30000);
      expect(trace.report().firstFrameRasterized, ms(420));
      // The engine's build-finish instant wins over the late post-frame callback.
      expect(trace.report().firstFrameBuilt, ms(390));
      trace.dispose();

      final StartupTracer future = quietTracer(clock);
      future.markFirstFrameRasterized(
        wallTimeMicros: clock.now().add(const Duration(hours: 1)).microsecondsSinceEpoch,
      );
      expect(future.report().firstFrameRasterized, Duration.zero);
    });

    test('native process start is read once and lines up with main', () async {
      final ProcessStartInfo process = ProcessStartInfo(
        startedAt: clock.wallAtZero.subtract(ms(350)),
        source: 'test',
      );
      final StartupTracer trace = quietTracer(clock, process: process);
      clock.advance(800);
      trace.markFirstFrameBuilt();
      trace.releaseDeferred();
      await pumpEventQueue();

      final StartupReport report = trace.completed.value!;
      expect(report.processStartToMain, ms(350));
      expect(report.totalFromProcessStart, ms(1150));
    });

    test('a throwing process reader means unknown, not a crash', () async {
      final StartupTracer trace = StartupTracer.start(
        clock: clock,
        printReport: false,
        processStartReader: () async => throw StateError('nope'),
      );
      await trace.resolveProcessStart();
      expect(trace.report().processStart, isNull);
      expect(trace.report().toPrettyString(), contains('unknown'));
    });

    test('prints the report when it completes', () async {
      final List<String> printed = <String>[];
      final StartupTracer trace = StartupTracer.start(
        clock: clock,
        printer: printed.add,
        processStartReader: () async => null,
      );
      trace.markFirstFrameBuilt();
      trace.releaseDeferred();
      await pumpEventQueue();
      expect(printed.single, startsWith('== Startup trace (debug)'));
    });
  });
}
