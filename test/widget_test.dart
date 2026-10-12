import 'dart:async';
import 'dart:ui' show FrameTiming;

import 'package:flutter/widgets.dart';
import 'package:flutter_startup_tracer/flutter_startup_tracer.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_clock.dart';

class _Home extends StatelessWidget {
  const _Home();

  @override
  Widget build(BuildContext context) {
    final StartupTracer trace = StartupTracer.of(context);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => trace.markInteractive('home'),
      child: const SizedBox.expand(key: Key('home')),
    );
  }
}

FrameTiming timingAt(DateTime wall) => FrameTiming(
      vsyncStart: 0,
      buildStart: 1,
      buildFinish: 2,
      rasterStart: 3,
      rasterFinish: 4,
      rasterFinishWallTime: wall.microsecondsSinceEpoch,
    );

void main() {
  late FakeClock clock;

  setUp(() {
    StartupTracer.debugReset();
    clock = FakeClock();
  });

  testWidgets(
      'scope records runApp and the first frame built, then falls back to '
      'starting deferred work when no frame timing arrives', (WidgetTester tester) async {
    final StartupTracer trace = quietTracer(clock);
    var adsStarted = false;
    unawaited(trace.deferred('ads', () => adsStarted = true));

    clock.advance(300);
    await tester.pumpWidget(StartupTracerScope(tracer: trace, child: const _Home()));
    final StartupReport early = trace.report();
    expect(early.runApp, ms(300));
    expect(early.firstFrameBuilt, ms(300));
    expect(early.firstFrameRasterized, isNull);
    expect(adsStarted, isFalse);

    await tester.pump(const Duration(seconds: 2));
    await tester.pump();
    expect(adsStarted, isTrue);
    expect(trace.isComplete, isTrue);
  });

  testWidgets(
      'the engine frame timing marks the first frame rasterized and releases '
      'deferred work', (WidgetTester tester) async {
    final StartupTracer trace = quietTracer(clock);
    var adsStarted = false;
    unawaited(trace.deferred('ads', () => adsStarted = true));

    clock.advance(200);
    await tester.pumpWidget(StartupTracerScope(tracer: trace, child: const _Home()));
    clock.advance(50);
    tester.binding.platformDispatcher.onReportTimings!(<FrameTiming>[
      timingAt(clock.wallAtZero.add(ms(240))),
    ]);
    expect(trace.report().firstFrameRasterized, ms(240));
    expect(trace.report().firstFrameBuilt, ms(240) - const Duration(microseconds: 2));

    await tester.pump(const Duration(milliseconds: 1)); // Timer.run needs time to pass here.
    expect(adsStarted, isTrue);
    await tester.pump(const Duration(seconds: 3)); // No fallback timer left behind.
  });

  testWidgets('StartupTracer.of finds the tracer and markInteractive completes the trace',
      (WidgetTester tester) async {
    final StartupTracer trace = quietTracer(clock, waitForInteractive: true);
    await tester.pumpWidget(StartupTracerScope(tracer: trace, child: const _Home()));
    await tester.pump(const Duration(seconds: 2));
    expect(trace.isComplete, isFalse);

    clock.advance(640);
    await tester.tap(find.byKey(const Key('home')));
    expect(trace.isComplete, isTrue);
    expect(trace.completed.value!.interactiveName, 'home');
    expect(trace.completed.value!.interactive, ms(640));
  });

  testWidgets('StartupTracer.of throws a helpful error without a tracer',
      (WidgetTester tester) async {
    late Object error;
    await tester.pumpWidget(Builder(builder: (BuildContext context) {
      try {
        StartupTracer.of(context);
      } catch (e) {
        error = e;
      }
      return const SizedBox();
    }));
    expect(error, isA<FlutterError>());
    expect(error.toString(), contains('StartupTracerScope'));
  });

  testWidgets('the banner shows the total once complete, then hides', (WidgetTester tester) async {
    final StartupTracer trace = quietTracer(clock);
    clock.advance(420);
    await tester.pumpWidget(
      StartupTracerScope(
        tracer: trace,
        child: const StartupTracerBanner(child: _Home()),
      ),
    );
    expect(find.byKey(const ValueKey<String>('startup-tracer-banner')), findsNothing);

    await tester.pump(const Duration(seconds: 2));
    await tester.pump();
    final Finder banner = find.byKey(const ValueKey<String>('startup-tracer-banner'));
    expect(banner, findsOneWidget);
    expect(
      tester.widget<Text>(banner).data,
      'Startup 420 ms to first frame - debug build, not representative',
    );

    await tester.pump(const Duration(seconds: 5));
    expect(banner, findsNothing);
  });

  testWidgets('a disabled banner renders only the child', (WidgetTester tester) async {
    final StartupTracer trace = quietTracer(clock);
    await tester.pumpWidget(
      StartupTracerScope(
        tracer: trace,
        child: const StartupTracerBanner(enabled: false, child: _Home()),
      ),
    );
    await tester.pump(const Duration(seconds: 3));
    expect(trace.isComplete, isTrue);
    expect(find.byKey(const ValueKey<String>('startup-tracer-banner')), findsNothing);
  });
}
