/// Simulates I/O (a plugin call, a network request) that takes [ms].
Future<void> fakeIo(int ms) => Future<void>.delayed(Duration(milliseconds: ms));

/// Simulates CPU-bound work that blocks the isolate for [ms].
void busyWait(int ms) {
  final Stopwatch stopwatch = Stopwatch()..start();
  while (stopwatch.elapsedMilliseconds < ms) {}
}
