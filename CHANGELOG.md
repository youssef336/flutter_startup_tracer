## 0.1.0

* First release.
* `StartupTracer.start()` records Dart `main` as t0; `phase`, `phaseSync`, `parallel`
  (wall time vs sum) and nested phases via zones.
* `StartupTracerScope` / `trace.runApp()` capture `runApp`, first frame built and first
  frame rasterized (engine `FrameTiming`), and start `deferred` tasks after it.
* `markInteractive()` and `mark()` for app-defined milestones.
* Optional native process-start time: Android `Process.getStart(Requested)ElapsedRealtime`,
  iOS `sysctl(KERN_PROC_PID)` with pre-warm detection. Unknown elsewhere.
* `dart:developer` timeline events for DevTools.
* Reports as console text with an ASCII waterfall, Markdown and JSON, plus advice: slow
  critical phases, serial phases that could run in parallel, heavy first build, slow
  native start, pre-warming, failed phases and debug-mode measurements.
* `StartupTracerBanner` overlay, `onReport` callback and in-memory `history`.
