import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_startup_tracer/flutter_startup_tracer.dart';

import 'home_page.dart';
import 'slow_work.dart';

Future<void> main() async {
  // First line of main: everything is measured from here.
  final StartupTracer trace = StartupTracer.start(
    waitForInteractive: true,
    onReport: (StartupReport report) {
      // Send report.toJson() to your logs or analytics here.
    },
  );
  WidgetsFlutterBinding.ensureInitialized();

  // Synchronous work blocks the UI isolate: measured with phaseSync.
  trace.phaseSync('parse bundled config', () => busyWait(40));

  // One slow SDK on the critical path: the advice suggests deferring it.
  await trace.phase('crash reporting SDK', () => fakeIo(220));

  // Two independent awaits in a row: the advice suggests parallel().
  await trace.phase('feature flags', () => fakeIo(90));
  await trace.phase('remote strings', () => fakeIo(110));

  // Already parallel: wall time is the slowest task, not the sum.
  await trace.parallel(<String, FutureOr<Object?> Function()>{
    'database': () => fakeIo(150),
    'preferences': () => fakeIo(40),
    'secure storage': () => fakeIo(70),
  }, name: 'storage');

  // A phase that needs the previous one: no "run in parallel" advice for it.
  await trace.phase('session', () => fakeIo(30), dependsOnPrevious: true);

  trace.mark('before runApp');

  // Runs after the first frame, off the critical path.
  unawaited(trace.deferred('ads SDK', () => fakeIo(300)));
  unawaited(trace.deferred('analytics', () => fakeIo(120)));

  trace.runApp(const StartupTracerBanner(child: ExampleApp()));
}

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Startup tracer example',
      theme: ThemeData(colorSchemeSeed: Colors.teal),
      home: const HomePage(),
    );
  }
}
