# flutter_startup_tracer example

A small app with deliberately slow startup work (a slow "SDK" init, two serial
phases that could run in parallel, a parallel group, a deferred task and a home
screen that loads data before it is interactive), so the report has something to
say.

```bash
flutter run --profile     # measure in profile mode, not debug
```

The report is printed to the console when startup completes, shown in a banner
for five seconds, and rendered on the home screen.
