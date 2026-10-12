import 'package:flutter/widgets.dart';
import 'package:flutter_startup_tracer/flutter_startup_tracer.dart';
import 'package:flutter_startup_tracer_example/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('home marks interactive and renders the report', (WidgetTester tester) async {
    StartupTracer.debugReset();
    final StartupTracer trace = StartupTracer.start(
      waitForInteractive: true,
      printReport: false,
      timelineEvents: false,
      // Widget tests run on fake time; the real platform channel would answer
      // outside it, so stand in for the native lookup.
      processStartReader: () async => null,
    );
    await tester.pumpWidget(StartupTracerScope(tracer: trace, child: const ExampleApp()));
    expect(trace.report().runApp, isNotNull);
    expect(trace.isComplete, isFalse);

    await tester.pump(const Duration(milliseconds: 250)); // Home finishes loading.
    expect(trace.report().interactiveName, 'home');

    await tester.pump(const Duration(seconds: 2)); // Deferred fallback (no engine timings).
    await tester.pump(const Duration(milliseconds: 1));
    expect(trace.isComplete, isTrue);
    expect(trace.report().processStart, isNull); // No native side in widget tests.
    expect(find.byKey(const Key('report')), findsOneWidget);
    expect(find.textContaining('interactive: home'), findsWidgets);
  });
}
