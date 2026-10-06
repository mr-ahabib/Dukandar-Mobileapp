import 'dart:async';

import 'package:flutter/foundation.dart';

import '../providers/billing_provider.dart';
import '../providers/cash_drawer_provider.dart';
import '../providers/ledger_provider.dart';
import '../providers/products_provider.dart';
import 'database/app_database.dart';
import 'utils/perf.dart';

/// Single place that starts the data layer AFTER the first frame.
///
/// * Opens sqflite once (migrations run exactly once, single-flight).
/// * Then loads every provider concurrently — the DB open is shared and the
///   four read paths overlap instead of each provider opening/querying
///   serially from its constructor.
/// * Idempotent: screens may call [run] again (pull-to-refresh uses the
///   providers directly); only the first call does the warm-up.
class AppBootstrap {
  AppBootstrap._();

  static Future<void>? _running;
  static bool _done = false;
  static bool get isDone => _done;

  static Future<void> run({
    required LedgerProvider ledger,
    required BillingProvider billing,
    required CashDrawerProvider cash,
    ProductsProvider? products,
  }) {
    if (_done) return Future.value();
    return _running ??= _run(ledger, billing, cash, products ?? ProductsProvider.instance);
  }

  static Future<void> _run(
    LedgerProvider ledger,
    BillingProvider billing,
    CashDrawerProvider cash,
    ProductsProvider products,
  ) async {
    Perf.mark('bootstrap.start');
    final t = Perf.start('bootstrap.total');
    try {
      // Warm the connection first so the parallel loads below never race
      // the schema migration (they would all wait on the same future anyway).
      await AppDatabase.instance.database;
      await Future.wait<void>([
        ledger.ensureLoaded(),
        billing.ensureLoaded(),
        cash.ensureLoaded(),
        products.ensureLoaded(),
      ]);
    } catch (e, st) {
      debugPrint('AppBootstrap failed: $e\n$st');
    } finally {
      _done = true;
      _running = null;
      t.stop();
    }
  }

  /// Test / restore helper: allows [run] to do the warm-up again.
  @visibleForTesting
  static void reset() {
    _done = false;
    _running = null;
  }
}
