/// Measure and explain Flutter app startup: process start, phases in `main`,
/// first frame, interactive, and deferred work, with a waterfall and advice.
library;

export 'src/advice.dart'
    show StartupAdvice, StartupAdviceCode, StartupAdviceConfig, StartupAdviceSeverity;
export 'src/banner.dart' show StartupTracerBanner;
export 'src/clock.dart' show StopwatchTracerClock, TracerClock;
export 'src/model.dart' show ProcessStartInfo, StartupMark, StartupSpan, StartupSpanKind;
export 'src/native.dart' show ProcessStartReader, readNativeProcessStart;
export 'src/report.dart' show StartupReport;
export 'src/scope.dart' show StartupTracerScope;
export 'src/tracer.dart' show StartupReportCallback, StartupTracer;
