import 'package:flutter/foundation.dart';

/// Tiny debug-only stopwatch logger for DB / provider load timings.
///
/// Usage:
/// ```dart
/// final t = Perf.start('ledger.load');
/// ... await work ...
/// t.stop(); // prints "[perf] ledger.load 12ms" in debug builds only
/// ```
///
/// Every stop() is also recorded in [Perf.last] (label → ms) so tests can
/// assert on measured durations without parsing log output.
class Perf {
  Perf._(this.label) : _sw = Stopwatch()..start();
  final String label;
  final Stopwatch _sw;

  /// Process start reference used by [sinceStart].
  static final Stopwatch _appClock = Stopwatch()..start();

  /// Last measured duration per label (ms). Always recorded, even in release,
  /// because it is just a map write; printing is debug-only.
  static final Map<String, int> last = <String, int>{};

  /// Set to false to silence console output (tests).
  static bool logging = kDebugMode;

  static Perf start(String label) => Perf._(label);

  /// Milliseconds since the Dart isolate started (first `Perf` use).
  static int get sinceStart => _appClock.elapsedMilliseconds;

  /// One-off marker: "[perf] first-frame @ 412ms".
  static void mark(String label) {
    if (!logging) return;
    debugPrint('[perf] $label @ ${sinceStart}ms');
  }

  int stop([String? extra]) {
    _sw.stop();
    final ms = _sw.elapsedMilliseconds;
    last[label] = ms;
    if (logging) {
      debugPrint('[perf] $label ${ms}ms${extra == null ? '' : ' · $extra'}');
    }
    return ms;
  }

  /// Times an async block.
  static Future<T> time<T>(String label, Future<T> Function() body) async {
    final t = Perf.start(label);
    try {
      return await body();
    } finally {
      t.stop();
    }
  }
}
