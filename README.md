<h1 align="center">Flutter Startup Tracer</h1>

<p align="center">
  Measure your Flutter app's startup from process start to "the user can actually use it", see every phase on a waterfall, and get told what to fix.
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Flutter-plugin-02569B?style=for-the-badge&logo=flutter&logoColor=white" alt="Flutter">
  <img src="https://img.shields.io/badge/Dart-3.5%2B-0175C2?style=for-the-badge&logo=dart&logoColor=white" alt="Dart">
  <img src="https://img.shields.io/badge/Android-Kotlin-7F52FF?style=for-the-badge&logo=kotlin&logoColor=white" alt="Kotlin">
  <img src="https://img.shields.io/badge/iOS-Swift-F05138?style=for-the-badge&logo=swift&logoColor=white" alt="Swift">
  <img src="https://img.shields.io/badge/Dependencies-zero-2ea44f?style=for-the-badge" alt="Zero dependencies">
  <img src="https://img.shields.io/badge/License-MIT-blue?style=for-the-badge" alt="MIT">
</p>

> **English summary.** `flutter_startup_tracer` measures and explains app startup for any
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

<div dir="rtl">

بتحط سطر واحد في أول `main`، وتلف الـ init بتاعك في `phase` و `parallel`، والباكدج يقولك
الـ app بتاعك بياخد وقته فين من ساعة ما الـ OS بدأ الـ process لحد ما المستخدم يقدر يستخدم
أول شاشة، وإيه اللي تأجله أو تشغّله بالتوازي عشان يفتح أسرع.

## ✨ بيعمل إيه

- ⏱ **بيقيس كل حاجة من أول `main`**: كل `phase` (sync أو async)، والمتداخل جوه بعض،
  والـ `parallel` بيطلعلك فيه الـ **wall time** (اللي استنيته فعلًا) جنب **مجموع** المهام
  (اللي كنت هتستناه لو شغلتهم ورا بعض).
- 📱 **وقت بداية الـ process من الـ native**: على Android من
  `Process.getStartRequestedElapsedRealtime` (أو `getStartElapsedRealtime` قبل API 33)،
  وعلى iOS من `sysctl(KERN_PROC_PID)`، ومعاه كشف الـ **pre-warming** بتاع iOS. على
  web/desktop وفي التستات بيكتب «unknown» ومبيقعش.
- 🖼 **أول frame**: `StartupTracerScope` بيسجل `runApp`، وإمتى أول frame اتبنى، وإمتى الـ engine
  رسمه فعلًا (`FrameTiming.rasterFinishWallTime`)، فمش بتقيس «الكود خلص» وخلاص، بتقيس «الشاشة
  ظهرت».
- ✅ **«المستخدم يقدر يستخدمه»**: `markInteractive('home')` من أول شاشة حقيقية بعد ما الداتا
  بتاعتها توصل.
- 💤 **`deferred`**: الحاجات اللي مش لازمة لأول شاشة (إعلانات، analytics…) بتتشغل بعد أول frame
  وبتتقاس لوحدها بره الـ critical path.
- 📊 **التقرير**: في الـ console بـ ASCII waterfall، أو `toMarkdown()` تحطه في PR، أو `toJson()`
  تبعته لأي backend.
- 🧭 **نصايح**: بيقولك تأجل إيه، وإيه اللي ممكن يبقى `parallel`، ولو أول build تقيل، ولو الـ
  native start بطيء، ولو انت بتقيس في debug أصلًا.
- 🔬 **DevTools**: كل phase بتطلع في الـ Performance view كـ timeline events.
- 🏷 **Banner** صغير فوق الـ app بيعرض الرقم 5 ثواني (debug/profile بس).

## 📦 التثبيت

لسه مش على pub.dev، فبتاخده من GitHub:

```yaml
dependencies:
  flutter_startup_tracer:
    git:
      url: https://github.com/youssef336/flutter_startup_tracer.git
      ref: v0.1.0
```

بعدها `flutter pub get`. مفيش أي setup native: الـ plugin بيتسجل لوحده على Android و iOS.

## 🚀 الاستخدام

</div>

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

<div dir="rtl">

### 🧾 شكل التقرير

ده تقرير حقيقي من الـ `example/` على iOS simulator (debug، فالأرقام أبطأ من الحقيقة):

</div>

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

<div dir="rtl">

## 🧭 النصايح

| القاعدة | بتشتغل إمتى | الافتراضي |
|---|---|---|
| `debugMode` | التقرير اتعمل في debug | دايمًا |
| `slowCriticalPhase` | phase قبل `runApp` (أو مهمة جوه `parallel`) خدت وقت كبير ← «أجّلها» | ≥ 100 ms |
| `serialPhases` | phases async ورا بعض ومحدش فيهم قال `dependsOnPrevious` ← «شغلهم `parallel`» ومعاها التوفير المتوقع | المجموع ≥ 150 ms، وكل واحدة ≥ 20 ms |
| `heavyFirstBuild` | من `runApp` لأول frame وقت كبير | > 500 ms |
| `slowNativeStart` | من بداية الـ process لـ `main` كبير | ≥ 1000 ms |
| `prewarmed` | iOS قال إن الـ process كان pre-warmed، أو الفرق ≥ 10 ثواني ← مبيتحسبش في الإجمالي | — |
| `failedPhase` | phase رمت exception | — |

كل الأرقام بتتغير من `StartupAdviceConfig`. لو phase محتاجة اللي قبلها فعلًا، ابعت
`dependsOnPrevious: true` والقاعدة بتاعة الـ parallel مش هتقترحها.

## 📤 تودّي التقرير فين

- `printReport` (شغال افتراضيًا بره release) بيطبع التقرير في الـ console أول ما يخلص.
- `onReport` بيتنده مرة واحدة بالتقرير النهائي: ابعت `report.toJson()` لـ Crashlytics أو
  analytics أو الـ logs بتاعتك.
- `StartupTracer.history` فيه آخر 5 تقارير (`historyLimit`) **في الميموري بس**. مفيش حاجة بتتكتب
  على الديسك؛ الحفظ عليك من `onReport`.
- `trace.report()` تقدر تناديه في أي وقت وتاخد snapshot لحد اللحظة دي.
- `trace.completed` (`ValueListenable`) لو عايز تبني UI على التقرير.

## ✅ التقرير بيخلص إمتى

لما يحصل كل ده: أول frame اتبنى، والـ deferred كلهم خلصوا، ووقت الـ native start اتقرا (أو
اتعرف إنه unknown)، ولو `waitForInteractive: true` لازم كمان `markInteractive` يتنده.
الـ deferred بيبدأ أول ما الـ engine يبلّغ إن أول frame اترسم؛ ولو مبلّغش (تستات، headless)
بيبدأ بعد `deferredFallback` (ثانيتين افتراضيًا) من أول build.

## 🧪 في التستات

- `StartupTracer.start(clock: myFakeClock)`: الـ `TracerClock` بيتحقن، فتقدر تتست الأوقات بالظبط.
- في الـ widget tests ابعت `processStartReader: () async => null`: الـ platform channel الحقيقي
  بيرد بره الـ fake time بتاع `testWidgets` والتقرير مش هيخلص.
- `StartupTracer.debugReset()` بينضف `current` و `history` بين التستات.

## ❓ أسئلة متكررة

**ليه الأرقام في debug عالية كده؟** debug بيشغل JIT و asserts ومن غير AOT، فممكن يبقى أبطأ
مرتين أو تلاتة. قيس بـ `flutter run --profile` أو `--release`، والتقرير نفسه بيحذرك.

**ليه مينفعش أنده `ensureInitialized()` جوه `phase`؟** الـ `phase` بتشغل الكود في zone جديدة
عشان تعرف مين جوه مين (ده اللي بيخلي الـ nesting يشتغل حتى مع `await`). Flutter بيحذر لو الـ
binding اتعمل في zone و `runApp` في zone تانية. نادِيه بره أي phase، أو جوه `phaseSync`
(دي مبتعملش zone).

**«process start → main» كبير جدًا على iOS؟** iOS 15+ ممكن يشغل الـ process قبل ما المستخدم
يدوس على الأيقونة (pre-warming). لو الـ OS قال كده، أو الفرق أكبر من 10 ثواني، التقرير
بيكتبه «not counted» ومبيدخلوش في الإجمالي.

**الباكدج بيبطّأ الـ startup نفسه؟** لأ تقريبًا: كل phase = قراءة stopwatch مرتين وكام object.
الـ native call بيحصل مرة واحدة **بعد** أول frame، مش وقت الإقلاع.

**ينفع أستخدمه في release؟** آه. الطباعة والـ banner مقفولين افتراضيًا في release، بس القياس و
`onReport` شغالين، فتقدر تجمع أرقام حقيقية من المستخدمين.

**مش بستخدم `trace.runApp`؟** لف الـ app بـ `StartupTracerScope(tracer: trace, child: ...)`
وخلاص. ولو مش هتستخدم الـ scope خالص، نادِ `markRunApp()` و `markFirstFrameBuilt()` و
`releaseDeferred()` بنفسك.

## ⚖️ الحدود

- الـ t0 هو سطر `StartupTracer.start()`. أي حاجة قبل `main` (تحميل الـ engine، الـ native init)
  بتظهر بس كرقم واحد «process start → main»، ومن غير تفاصيل.
- وقت بداية الـ process بيتحسب بالـ wall clock، فلو الساعة اتظبطت في نفس اللحظة الرقم هيبوظ.
  على Android قبل API 33 بيبدأ من الـ fork مش من طلب الفتح.
- «first frame rasterized» محتاج الـ engine يبعت `FrameTiming`. في التستات و headless مش
  موجود، والتقرير بيقول «built».
- نصيحة الـ `parallel` تخمين: الباكدج ميعرفش مين معتمد على مين غير من `dependsOnPrevious`.
- الـ `deferred` بيبدأ بعد أول frame، بس لو شغله تقيل على الـ UI isolate هيفضل ينافس الـ
  frames اللي بعده. قسّمه أو خليه lazy.
- الـ `history` في الميموري بس، و hot restart بيمسحه.
- مفيش native start على web/desktop (بيتكتب unknown).
- لو `waitForInteractive: true` ومحدش نده `markInteractive`، التقرير مش هيخلص (و`report()`
  لسه شغال).

</div>

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
