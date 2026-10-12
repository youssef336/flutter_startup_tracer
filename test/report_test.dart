import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_startup_tracer/flutter_startup_tracer.dart';
import 'package:flutter_startup_tracer/src/native.dart' show parseProcessStart;
import 'package:flutter_test/flutter_test.dart';

import 'fake_clock.dart';

StartupSpan span(
  String name,
  int start,
  int end, {
  StartupSpanKind kind = StartupSpanKind.phase,
  bool isSync = false,
  bool dependsOnPrevious = false,
  String? error,
  List<StartupSpan> children = const <StartupSpan>[],
}) {
  return StartupSpan(
    name: name,
    kind: kind,
    start: ms(start),
    end: ms(end),
    isSync: isSync,
    isDeferred: kind == StartupSpanKind.deferred,
    dependsOnPrevious: dependsOnPrevious,
    error: error,
    children: children,
  );
}

StartupReport reportOf(
  List<StartupSpan> spans, {
  int? runApp,
  int? firstFrame,
  int? interactive,
  ProcessStartInfo? process,
  String buildMode = 'profile',
}) {
  return StartupReport(
    startedAt: DateTime.utc(2026, 1, 1, 12),
    buildMode: buildMode,
    spans: spans,
    marks: const <StartupMark>[],
    complete: true,
    processStart: process,
    runApp: runApp == null ? null : ms(runApp),
    firstFrameRasterized: firstFrame == null ? null : ms(firstFrame),
    interactive: interactive == null ? null : ms(interactive),
    interactiveName: interactive == null ? null : 'home',
  );
}

List<StartupAdviceCode> codes(StartupReport report) =>
    report.advice.map((StartupAdvice a) => a.code).toList();

void main() {
  group('advice', () {
    test('debug builds get a warning', () {
      expect(codes(reportOf(const <StartupSpan>[], buildMode: 'debug')),
          <StartupAdviceCode>[StartupAdviceCode.debugMode]);
      expect(codes(reportOf(const <StartupSpan>[])), isEmpty);
    });

    test('slow critical phases suggest deferring; deferred and post-runApp ones do not', () {
      final StartupReport report = reportOf(
        <StartupSpan>[
          span('firebase', 0, 180),
          span('quick', 180, 200),
          span('group', 200, 330, kind: StartupSpanKind.group, children: <StartupSpan>[
            span('hive', 200, 330, kind: StartupSpanKind.groupTask),
            span('prefs', 200, 220, kind: StartupSpanKind.groupTask),
          ]),
          span('late', 400, 900),
          span('ads', 500, 1500, kind: StartupSpanKind.deferred),
        ],
        runApp: 350,
      );
      final List<StartupAdvice> slow = report.advice
          .where((StartupAdvice a) => a.code == StartupAdviceCode.slowCriticalPhase)
          .toList();
      expect(slow.map((StartupAdvice a) => a.spans.single), <String>['firebase', 'hive']);
      expect(slow.first.message, contains("deferred('firebase'"));
      expect(slow.first.message, contains('180 ms'));
    });

    test('serial independent async phases suggest parallel()', () {
      final StartupReport report = reportOf(<StartupSpan>[
        span('a', 0, 60),
        span('b', 60, 140),
        span('c', 140, 230),
      ]);
      final StartupAdvice serial =
          report.advice.singleWhere((StartupAdvice a) => a.code == StartupAdviceCode.serialPhases);
      expect(serial.spans, <String>['a', 'b', 'c']);
      expect(serial.message, contains('230 ms in total'));
      expect(serial.message, contains('about 90 ms'));
      expect(serial.message, contains('saving up to 140 ms'));
    });

    test('dependsOnPrevious, sync phases, tiny phases and overlaps break the chain', () {
      expect(
        codes(reportOf(<StartupSpan>[
          span('a', 0, 90),
          span('b', 90, 180, dependsOnPrevious: true),
        ])),
        isNot(contains(StartupAdviceCode.serialPhases)),
      );
      expect(
        codes(reportOf(<StartupSpan>[
          span('a', 0, 90),
          span('sync', 90, 180, isSync: true),
          span('b', 180, 270),
        ])),
        isNot(contains(StartupAdviceCode.serialPhases)),
      );
      expect(
        codes(reportOf(<StartupSpan>[span('a', 0, 140), span('tiny', 140, 150)])),
        isNot(contains(StartupAdviceCode.serialPhases)),
      );
      expect(
        codes(reportOf(<StartupSpan>[span('a', 0, 100), span('b', 50, 150)])),
        isNot(contains(StartupAdviceCode.serialPhases)),
      );
      expect(
        codes(reportOf(<StartupSpan>[span('a', 0, 60), span('b', 60, 120)])),
        isNot(contains(StartupAdviceCode.serialPhases)),
        reason: 'below serialMinTotal',
      );
    });

    test('heavy first build after runApp', () {
      expect(codes(reportOf(const <StartupSpan>[], runApp: 100, firstFrame: 700)),
          <StartupAdviceCode>[StartupAdviceCode.heavyFirstBuild]);
      expect(codes(reportOf(const <StartupSpan>[], runApp: 100, firstFrame: 500)), isEmpty);
    });

    test('native start gap: slow, prewarmed, or fine', () {
      ProcessStartInfo before(int msBefore, {bool prewarmed = false}) => ProcessStartInfo(
            startedAt: DateTime.utc(2026, 1, 1, 12).subtract(ms(msBefore)),
            source: 'test',
            prewarmed: prewarmed,
          );

      final StartupReport slow = reportOf(const <StartupSpan>[], process: before(1500));
      expect(codes(slow), <StartupAdviceCode>[StartupAdviceCode.slowNativeStart]);
      expect(slow.trustedProcessStartToMain, ms(1500));

      final StartupReport prewarmed =
          reportOf(const <StartupSpan>[], process: before(300, prewarmed: true));
      expect(codes(prewarmed), <StartupAdviceCode>[StartupAdviceCode.prewarmed]);
      expect(prewarmed.trustedProcessStartToMain, isNull);
      expect(prewarmed.totalFromProcessStart, isNull);

      expect(codes(reportOf(const <StartupSpan>[], process: before(60000))),
          <StartupAdviceCode>[StartupAdviceCode.prewarmed]);
      expect(codes(reportOf(const <StartupSpan>[], process: before(200))), isEmpty);
    });

    test('failed phases, including nested ones', () {
      final StartupReport report = reportOf(<StartupSpan>[
        span('outer', 0, 10, children: <StartupSpan>[span('inner', 1, 2, error: 'StateError: x')]),
      ]);
      final StartupAdvice failed = report.advice.single;
      expect(failed.code, StartupAdviceCode.failedPhase);
      expect(failed.message, "'inner' threw: StateError: x");
    });

    test('thresholds are configurable', () {
      final StartupReport report = StartupReport(
        startedAt: DateTime.utc(2026),
        buildMode: 'release',
        spans: <StartupSpan>[span('a', 0, 60)],
        marks: const <StartupMark>[],
        complete: true,
        adviceConfig: const StartupAdviceConfig(slowPhase: Duration(milliseconds: 50)),
      );
      expect(codes(report), <StartupAdviceCode>[StartupAdviceCode.slowCriticalPhase]);
    });
  });

  group('output', () {
    StartupReport sample() => StartupReport(
          startedAt: DateTime.utc(2026, 1, 1, 12),
          buildMode: 'profile',
          spans: <StartupSpan>[
            span('config', 0, 100),
            span('storage', 100, 300, kind: StartupSpanKind.group, children: <StartupSpan>[
              span('hive', 100, 300, kind: StartupSpanKind.groupTask),
              span('prefs', 100, 150, kind: StartupSpanKind.groupTask),
            ]),
            span('ads', 400, 600, kind: StartupSpanKind.deferred),
          ],
          marks: <StartupMark>[StartupMark('before runApp', ms(300))],
          complete: true,
          processStart: ProcessStartInfo(
            startedAt: DateTime.utc(2026, 1, 1, 12).subtract(ms(250)),
            source: 'test',
          ),
          runApp: ms(300),
          firstFrameRasterized: ms(380),
          interactive: ms(400),
          interactiveName: 'home',
        );

    test('pretty print has a summary, a scaled waterfall and advice', () {
      final String text = sample().toPrettyString(barWidth: 20);
      final List<String> lines = text.split('\n');
      expect(lines.first, '== Startup trace (profile) - total 400 ms ==');
      expect(text, contains('process start -> main       : 250 ms (test)'));
      expect(text, contains("main -> interactive         : 400 ms ('home')"));
      expect(text, contains('process start -> interactive: 650 ms'));

      // 600 ms timeline over 20 columns: 30 ms per column.
      String row(String label) => lines.firstWhere((String l) => l.startsWith(label));
      expect(row('config '), endsWith('|####                |'));
      expect(row('[parallel] storage'), endsWith('|   =======          | wall 200 / sum 250 ms'));
      expect(row('  hive'), endsWith('|   #######          |'));
      expect(row('(deferred) ads'), endsWith('|             ~~~~~~~|'));
      expect(row('> first frame rasterized'), contains('|            |       |'));
      expect(row('phase'), endsWith('|0             600 ms|'));
      expect(text, contains('Advice:'));
      expect(text, contains("[!] 'config' took 100 ms"));
    });

    test('markdown has a summary table, a phases table and the waterfall', () {
      final String md = sample().toMarkdown();
      expect(md, startsWith('## Startup report'));
      expect(md, contains('| total | **400 ms** |'));
      expect(md, contains('| config | phase | 0 | 100 |  |'));
      expect(md, contains('| storage | group | 100 | 200 | sum 250 ms |'));
      expect(md, contains('| &nbsp;&nbsp;hive | groupTask | 100 | 200 |  |'));
      expect(md, contains('```text'));
      expect(md, contains('### Advice'));
    });

    test('json round-trips through jsonEncode with millisecond values', () {
      final Map<String, Object?> json =
          jsonDecode(jsonEncode(sample().toJson())) as Map<String, Object?>;
      expect(json['buildMode'], 'profile');
      final Map<String, Object?> milestones = json['milestones']! as Map<String, Object?>;
      expect(milestones['interactiveMs'], 400.0);
      expect(milestones['totalFromProcessStartMs'], 650.0);
      final Map<String, Object?> process = json['processStart']! as Map<String, Object?>;
      expect(process['toMainMs'], 250.0);
      final List<Object?> spans = json['spans']! as List<Object?>;
      final Map<String, Object?> group = spans[1]! as Map<String, Object?>;
      expect(group['kind'], 'group');
      expect(group['sumMs'], 250.0);
      expect((group['children']! as List<Object?>), hasLength(2));
      expect((spans[2]! as Map<String, Object?>)['deferred'], isTrue);
      expect(json['advice'], isNotEmpty);
    });

    test('an unfinished span is drawn to the end and flagged', () {
      final StartupReport report = reportOf(<StartupSpan>[
        const StartupSpan(
          name: 'hang',
          kind: StartupSpanKind.phase,
          start: Duration.zero,
          end: null,
          isSync: false,
          isDeferred: false,
          dependsOnPrevious: false,
        ),
      ], firstFrame: 100);
      expect(report.toPrettyString(barWidth: 10), contains('|##########| still running'));
      expect(report.toMarkdown(), contains('| hang | phase | 0 | running |'));
    });
  });

  group('native bridge', () {
    TestWidgetsFlutterBinding.ensureInitialized();
    const MethodChannel channel = MethodChannel('flutter_startup_tracer');

    test('parses the native reply', () {
      final ProcessStartInfo info = parseProcessStart(<String, Object?>{
        'startEpochMicros': 1767268800000000,
        'source': 'ios:sysctl',
        'prewarmed': true,
      })!;
      expect(info.startedAt, DateTime.fromMicrosecondsSinceEpoch(1767268800000000));
      expect(info.source, 'ios:sysctl');
      expect(info.prewarmed, isTrue);
      expect(parseProcessStart(null), isNull);
      expect(parseProcessStart(<String, Object?>{'startEpochMicros': 'x'}), isNull);
      expect(parseProcessStart(<String, Object?>{'startEpochMicros': 0}), isNull);
    });

    test('no plugin means unknown', () async {
      expect(await readNativeProcessStart(), isNull);
    });

    test('reads through the method channel', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        (MethodCall call) async {
          expect(call.method, 'getProcessStart');
          return <String, Object?>{'startEpochMicros': 1000000, 'source': 'android:test'};
        },
      );
      addTearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null));
      final ProcessStartInfo? info = await readNativeProcessStart();
      expect(info?.source, 'android:test');
      expect(info?.prewarmed, isFalse);
    });

    test('a platform error means unknown', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        (MethodCall call) async => throw PlatformException(code: 'x'),
      );
      addTearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null));
      expect(await readNativeProcessStart(), isNull);
    });
  });
}
