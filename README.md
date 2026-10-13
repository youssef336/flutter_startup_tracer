<p align="center"><a href="README.ar.md">العربية</a></p>

<h1 align="center">Flutter Startup Tracer</h1>

<p align="center">
  Measure your Flutter app's startup from process start to "the user can actually use it", see every phase on a waterfall, and get told what to fix.
</p>

<p align="center">
  <a href="https://pub.dev/packages/flutter_startup_tracer"><img src="https://img.shields.io/pub/v/flutter_startup_tracer?style=for-the-badge&logo=dart&label=pub.dev" alt="pub.dev"/></a>
  <img src="https://img.shields.io/badge/Flutter-plugin-02569B?style=for-the-badge&logo=flutter&logoColor=white" alt="Flutter">
  <img src="https://img.shields.io/badge/Dart-3.5%2B-0175C2?style=for-the-badge&logo=dart&logoColor=white" alt="Dart">
  <img src="https://img.shields.io/badge/Android-Kotlin-7F52FF?style=for-the-badge&logo=kotlin&logoColor=white" alt="Kotlin">
  <img src="https://img.shields.io/badge/iOS-Swift-F05138?style=for-the-badge&logo=swift&logoColor=white" alt="Swift">
  <img src="https://img.shields.io/badge/Dependencies-zero-2ea44f?style=for-the-badge" alt="Zero dependencies">
  <img src="https://img.shields.io/badge/License-MIT-blue?style=for-the-badge" alt="MIT">
</p>

> **Summary.** `flutter_startup_tracer` measures and explains app startup for any
> Flutter app. Call `StartupTracer.start()` on the first line of `main`, wrap your init calls in
> `trace.phase(...)` / `trace.parallel({...})`, start the app with `trace.runApp(...)`, and mark
> the moment your first real screen is usable with `markInteractive('home')`. You get one
> timeline: **process start** (read natively on Android and iOS, with iOS pre-warm detection)
> → **Dart main** → every phase (sync or async, nested, parallel groups with wall time vs sum)
> → **runApp** → **first frame built / rasterized** (engine `FrameTiming`) → **interactive** →
> **deferred** tasks that run after the first frame. The report prints as an ASCII waterfall,
> exports to Markdown and JSON, shows up in the DevTools timeline, and comes with advice:
> slow phases to defer, serial awaits that could run in parallel, a heavy first build, a slow
> native start, and a warning when you measured in debug mode. No dependencies beyond Flutter.

You add one line at the start of `main`, wrap your init in `phase` and `parallel`, and the package
tells you where your app spends its time, from the moment the OS starts the process until the user
can use the first screen, and what to defer or run in parallel so it opens faster.

## ✨ What it does

- ⏱ **Measures everything from the start of `main`**: every `phase` (sync or async), phases nested
  inside each other, and for `parallel` you get the **wall time** (what you actually waited) next to
  the **sum** of the tasks (what you would have waited if you ran them one after another).
- 📱 **Native process start time**: on Android from
  `Process.getStartRequestedElapsedRealtime` (or `getStartElapsedRealtime` before API 33),
  and on iOS from `sysctl(KERN_PROC_PID)`, together with detection of iOS **pre-warming**. On
  web/desktop and in tests it reports "unknown" and doesn't crash.
- 🖼 **First frame**: `StartupTracerScope` records `runApp`, when the first frame was built, and when
  the engine actually rasterized it (`FrameTiming.rasterFinishWallTime`), so you're not just measuring
  "the code finished", you're measuring "the screen appeared".
- ✅ **"The user can use it"**: `markInteractive('home')` from the first real screen once its data
  has arrived.
- 💤 **`deferred`**: things the first screen doesn't need (ads, analytics…) run after the first frame
  and are measured separately, outside the critical path.
- 📊 **The report**: in the console as an ASCII waterfall, or `toMarkdown()` to put in a PR, or
  `toJson()` to send to any backend.
- 🧭 **Advice**: tells you what to defer, what could be `parallel`, whether the first build is heavy,
  whether the native start is slow, or whether you're measuring in debug in the first place.
- 🔬 **DevTools**: every phase shows up in the Performance view as timeline events.
- 🏷 **Banner**: a small banner over the app that shows the number for 5 seconds (debug/profile only).

## 📦 Installation

Add it from [pub.dev](https://pub.dev/packages/flutter_startup_tracer):

```yaml
dependencies:
  flutter_startup_tracer: ^0.1.0
```

Then `flutter pub get`. There is no native setup: the plugin registers itself on Android and iOS.

## 🚀 Usage

```dart
import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_startup_tracer/flutter_startup_tracer.dart';

Future<void> main() async {
  final trace = StartupTracer.start(        // first line: t0 = Dart main
    waitForInteractive: true,               // finish only after markInteractive()
    onReport: (report) => myLogger.info(report.toJson()),
  );
  WidgetsFlutterBinding.ensureInitialized(); // outside any phase (see FAQ)

  trace.phaseSync('parse config', parseBundledConfig);
  await trace.phase('firebase', () => Firebase.initializeApp());
  await trace.parallel({
    'hive': () => Hive.initFlutter(),
    'prefs': () => SharedPreferences.getInstance(),
  }, name: 'storage');
  await trace.phase('session', restoreSession, dependsOnPrevious: true);
  trace.mark('before runApp');

  unawaited(trace.deferred('ads', () => MobileAds.instance.initialize()));

  trace.runApp(const StartupTracerBanner(child: MyApp()));
  // same as: runApp(StartupTracerScope(tracer: trace, child: ...))
}

// In the first real screen, once its data is on screen:
StartupTracer.of(context).markInteractive('home');
```

### 🧾 What the report looks like

This is a real report from `example/` on the iOS simulator (debug, so the numbers are slower than
in reality):

```text
== Startup trace (debug) - total 1154 ms ==
process start -> main       : 1625 ms (ios:sysctl(KERN_PROC_PID).p_starttime)
main -> runApp              : 708 ms
main -> first frame         : 1043 ms (rasterized)
main -> interactive         : 1154 ms ('home')
process start -> interactive: 2779 ms

phase                           start     ms |0                                1389 ms|
parse bundled config               46     40 | ##                                     | sync
crash reporting SDK                86    228 |  ########                              |
feature flags                     315     93 |         ###                            |
remote strings                    407    113 |           ####                         |
[parallel] storage                520    155 |              ======                    | wall 155 / sum 269 ms
  database                        522    153 |               #####                    |
  preferences                     522     43 |               ##                       |
  secure storage                  522     73 |               ###                      |
session                           675     32 |                   ##                   |
* before runApp                   708        |                    |                   |
> runApp                          708        |                    |                   |
> first frame built              1036        |                             |          |
> first frame rasterized         1043        |                              |         |
(deferred) ads SDK               1087    302 |                               ~~~~~~~~~|
(deferred) analytics             1087    122 |                               ~~~~     |
> interactive: home              1154        |                                 |      |
legend: # phase  = parallel group  ~ deferred  | instant  * mark  > milestone

Advice:
  [!] Measured in debug mode (JIT, asserts, no AOT): numbers are several times slower than what users see. Measure with --profile or --release.
  [!] 1625 ms passed between the process starting and Dart main. Look at native work before the engine runs: ...
  [!] 'crash reporting SDK' took 228 ms on the critical path. If the first screen does not need it, consider deferring it with deferred('crash reporting SDK', ...) or initialising it lazily on first use.
  [!] 'crash reporting SDK', 'feature flags', 'remote strings' ran one after another (434 ms in total). If they do not depend on each other, run them with parallel({...}): best case about 228 ms, saving up to 206 ms. ...
```

## 🧭 Advice

| Rule | When it fires | Default |
|---|---|---|
| `debugMode` | The report was produced in debug | Always |
| `slowCriticalPhase` | A phase before `runApp` (or a task inside `parallel`) took a long time → "defer it" | ≥ 100 ms |
| `serialPhases` | Async phases one after another, none of which says `dependsOnPrevious` → "run them `parallel`", with the expected saving | Sum ≥ 150 ms, and each ≥ 20 ms |
| `heavyFirstBuild` | A long time from `runApp` to the first frame | > 500 ms |
| `slowNativeStart` | A long time from process start to `main` | ≥ 1000 ms |
| `prewarmed` | iOS said the process was pre-warmed, or the gap is ≥ 10 seconds → not counted in the total | — |
| `failedPhase` | A phase threw an exception | — |

All the thresholds can be changed through `StartupAdviceConfig`. If a phase really does need the one
before it, pass `dependsOnPrevious: true` and the parallel rule won't suggest it.

## 📤 Where to send the report

- `printReport` (on by default outside release) prints the report to the console as soon as it is done.
- `onReport` is called once with the final report: send `report.toJson()` to Crashlytics,
  analytics or your logs.
- `StartupTracer.history` holds the last 5 reports (`historyLimit`) **in memory only**. Nothing is
  written to disk; persisting is up to you, from `onReport`.
- `trace.report()` can be called at any time to get a snapshot up to that moment.
- `trace.completed` (a `ValueListenable`) if you want to build UI on top of the report.

## ✅ When the report completes

When all of the following have happened: the first frame was built, all deferred tasks finished,
the native start time was read (or found to be unknown), and, if `waitForInteractive: true`,
`markInteractive` was also called.
Deferred tasks start as soon as the engine reports that the first frame was rasterized; if it
doesn't report it (tests, headless), they start after `deferredFallback` (2 seconds by default)
from the first build.

## 🧪 In tests

- `StartupTracer.start(clock: myFakeClock)`: the `TracerClock` is injectable, so you can test the
  timings exactly.
- In widget tests pass `processStartReader: () async => null`: the real platform channel replies
  outside the fake time of `testWidgets`, and the report would never complete.
- `StartupTracer.debugReset()` clears `current` and `history` between tests.

## ❓ FAQ

**Why are the numbers so high in debug?** Debug runs JIT and asserts, without AOT, so it can be two
or three times slower. Measure with `flutter run --profile` or `--release`; the report itself warns
you.

**Why can't I call `ensureInitialized()` inside a `phase`?** A `phase` runs the code in a new zone so
it knows what is inside what (that's what makes nesting work even with `await`). Flutter warns if
the binding is created in one zone and `runApp` runs in another. Call it outside any phase, or
inside `phaseSync` (which doesn't create a zone).

**"process start → main" is huge on iOS?** iOS 15+ can launch the process before the user taps the
icon (pre-warming). If the OS says so, or the gap is more than 10 seconds, the report marks it
"not counted" and leaves it out of the total.

**Does the package slow down startup itself?** Practically not: each phase is two stopwatch reads
and a few objects. The native call happens once, **after** the first frame, not during launch.

**Can I use it in release?** Yes. Printing and the banner are off by default in release, but the
measurement and `onReport` keep working, so you can collect real numbers from users.

**I don't use `trace.runApp`?** Just wrap the app in `StartupTracerScope(tracer: trace, child: ...)`.
And if you won't use the scope at all, call `markRunApp()`, `markFirstFrameBuilt()` and
`releaseDeferred()` yourself.

## ⚖️ Limitations

- t0 is the `StartupTracer.start()` line. Anything before `main` (engine loading, native init)
  only shows up as a single "process start → main" number, without details.
- The process start time is computed with the wall clock, so if the clock is adjusted at that same
  moment the number will be wrong. On Android before API 33 it starts from the fork, not from the
  launch request.
- "first frame rasterized" needs the engine to send `FrameTiming`. In tests and headless it isn't
  available, and the report says "built".
- The `parallel` advice is a guess: the package only knows what depends on what from
  `dependsOnPrevious`.
- `deferred` starts after the first frame, but if its work is heavy on the UI isolate it will still
  compete with the frames that follow. Split it up or make it lazy.
- `history` is in memory only, and a hot restart clears it.
- There is no native start on web/desktop (it is reported as unknown).
- If `waitForInteractive: true` and nobody calls `markInteractive`, the report won't complete (and
  `report()` still works).

## 🛠 API at a glance

| API | What it does |
|---|---|
| `StartupTracer.start({...})` | Starts tracing; options: `waitForInteractive`, `onReport`, `printReport`, `printer`, `timelineEvents`, `adviceConfig`, `deferredFallback`, `clock`, `processStartReader` |
| `phase(name, body, {dependsOnPrevious})` | Measures async (or sync) work in a child zone; nests |
| `phaseSync(name, body)` | Measures synchronous work in the caller's zone |
| `parallel({name: body}, {name})` | Runs tasks concurrently; records wall time vs sum; returns results by name |
| `deferred(name, body)` | Runs after the first frame; returns a future of the task |
| `mark(name)` / `markInteractive(name)` | Instants on the timeline; the first `markInteractive` is the "interactive" milestone |
| `runApp(app)` | `markRunApp()` + Flutter `runApp` wrapped in `StartupTracerScope` |
| `StartupTracer.of(context)` / `maybeOf` / `current` | Find the tracer |
| `report()` / `completed` / `history` | Snapshot, final report notifier, last N reports in memory |
| `StartupReport` | `toPrettyString()`, `toMarkdown()`, `toJson()`, `advice`, `total`, `processStartToMain`, ... |
| `StartupTracerScope` | Captures `runApp`, first frame built and rasterized |
| `StartupTracerBanner` | On-screen total for 5 s (debug/profile by default) |

## 🏗 Project structure

| Path | Role |
|---|---|
| `lib/src/tracer.dart` | `StartupTracer`: spans, zones for nesting, deferred queue, completion |
| `lib/src/scope.dart` | `StartupTracerScope`: `runApp`, post-frame and `FrameTiming` capture |
| `lib/src/report.dart` | `StartupReport`: totals, JSON |
| `lib/src/waterfall.dart` | ASCII waterfall, console and Markdown output |
| `lib/src/advice.dart` | Advice rules and thresholds |
| `lib/src/native.dart` | Method channel to the native process-start reader |
| `lib/src/banner.dart` | `StartupTracerBanner` |
| `android/.../FlutterStartupTracerPlugin.kt` | `Process.getStart*ElapsedRealtime` → epoch micros |
| `ios/.../FlutterStartupTracerPlugin.swift` | `sysctl(KERN_PROC_PID)` → epoch micros, `ActivePrewarm` |
| `example/` | App with deliberately slow phases |

## 🚀 Development

```bash
flutter pub get
flutter analyze
flutter test
cd example && flutter test && flutter run --profile
```

## 📄 License

[MIT](LICENSE)

## 👤 Author

**Youssef Belal Zakaria** · [GitHub @youssef336](https://github.com/youssef336)

⭐ If you like this project, give it a star!
