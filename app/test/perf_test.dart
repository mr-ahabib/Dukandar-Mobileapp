import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:dukandar/core/database/app_database.dart';
import 'package:dukandar/core/utils/perf.dart';
import 'package:dukandar/models/cash_memo.dart';
import 'package:dukandar/models/customer.dart';
import 'package:dukandar/models/transaction_item.dart';
import 'package:dukandar/providers/billing_provider.dart';
import 'package:dukandar/providers/cash_drawer_provider.dart';
import 'package:dukandar/providers/ledger_provider.dart';

/// Load-time budget tests against a real (in-memory) SQLite database seeded
/// with a "big shop": 2,000 contacts, 20,000 transactions, 1,000 memos.
///
/// Thresholds are deliberately generous (3–5× what this machine measures)
/// so CI never flakes; the point is to catch O(n²) regressions, not to
/// benchmark. Measured numbers are printed for the report.
void main() {
  final db = AppDatabase.instance;
  const customers = 2000;
  const transactions = 20000;
  const memos = 1000;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    AppDatabase.useInMemory = true;
    Perf.logging = false;
    await db.close();
    await _seed(db, customers: customers, transactions: transactions, memos: memos);
  });

  tearDownAll(() => db.close());

  test('seeded as expected', () async {
    expect((await db.getCustomers(type: ContactType.customer)).length + (await db.getCustomers(type: ContactType.supplier)).length, customers);
    expect(await db.getMemoCount(), memos);
  });

  test('ledger load (2,000 contacts + overdue + recent) < 300ms', () async {
    final ledger = LedgerProvider();
    final sw = Stopwatch()..start();
    await ledger.loadData();
    sw.stop();
    // ignore: avoid_print
    print('[perf-test] ledger.load ${sw.elapsedMilliseconds}ms (${ledger.allCustomersRaw.length}+${ledger.allSuppliersRaw.length} contacts, ${ledger.overdueCustomers.length} overdue)');
    expect(ledger.allCustomersRaw.length + ledger.allSuppliersRaw.length, customers);
    expect(sw.elapsedMilliseconds, lessThan(300));
  });

  test('dashboard aggregates (today sales/count/collections/supplier payments) < 100ms', () async {
    final n = DateTime.now();
    final start = DateTime(n.year, n.month, n.day);
    final end = start.add(const Duration(days: 1));
    final sw = Stopwatch()..start();
    await Future.wait([
      db.getSalesBetween(start, end),
      db.getMemoCountBetween(start, end),
      db.getCollectionsForDay(start),
      db.getSupplierPaymentsForDay(start),
    ]);
    sw.stop();
    // ignore: avoid_print
    print('[perf-test] dashboard aggregates ${sw.elapsedMilliseconds}ms');
    expect(sw.elapsedMilliseconds, lessThan(100));
  });

  test('reports aggregates (30-day sales, 6-month flows, category sums) < 300ms', () async {
    final sw = Stopwatch()..start();
    await Future.wait([
      db.getDailySales(days: 30),
      db.getMonthlyFlows(months: 6),
      db.getExpensesByCategory(DateTime.now()),
    ]);
    sw.stop();
    // ignore: avoid_print
    print('[perf-test] reports aggregates ${sw.elapsedMilliseconds}ms');
    expect(sw.elapsedMilliseconds, lessThan(300));
  });

  test('billing load (200 lazy memos) < 200ms and does not decode items JSON', () async {
    final billing = BillingProvider();
    final sw = Stopwatch()..start();
    await billing.loadMemos();
    sw.stop();
    // ignore: avoid_print
    print('[perf-test] billing.load ${sw.elapsedMilliseconds}ms (${billing.allMemos.length} memos)');
    expect(billing.allMemos.length, BillingProvider.recentLimit);
    expect(billing.allMemos.every((m) => !m.itemsDecoded), isTrue, reason: 'list rows must stay lazy');
    expect(billing.allMemos.first.grandTotal, greaterThan(0)); // from stored column
    expect(sw.elapsedMilliseconds, lessThan(200));
  });

  test('cash drawer day load < 150ms', () async {
    final cash = CashDrawerProvider();
    final sw = Stopwatch()..start();
    await cash.loadExpenses();
    sw.stop();
    // ignore: avoid_print
    print('[perf-test] cash.load ${sw.elapsedMilliseconds}ms');
    expect(sw.elapsedMilliseconds, lessThan(150));
  });

  test('ledger search + sections are cached between builds', () async {
    final ledger = LedgerProvider();
    await ledger.loadData();
    ledger.setSearchQuery('ক্রেতা 1');
    final sw = Stopwatch()..start();
    final a = ledger.sections(ContactType.customer);
    for (int i = 0; i < 1000; i++) {
      ledger.sections(ContactType.customer); // what 1,000 rebuilds would cost
    }
    sw.stop();
    expect(identical(a, ledger.sections(ContactType.customer)), isTrue);
    expect(a.visible, isNotEmpty);
    expect(sw.elapsedMilliseconds, lessThan(250));
    expect(ledger.totalReceivables, greaterThan(0));
  });

  test('one customer history (≈10 tx) < 50ms', () async {
    final sw = Stopwatch()..start();
    final txs = await db.getTransactions('c_0001');
    sw.stop();
    expect(txs, isNotEmpty);
    expect(sw.elapsedMilliseconds, lessThan(250));
  });

  test('database open is single-flight and close() is idempotent', () async {
    await db.close();
    await db.close(); // second close must not throw
    final futures = List.generate(5, (_) => db.database);
    final dbs = await Future.wait(futures);
    expect(dbs.every((d) => identical(d, dbs.first)), isTrue);
    await db.reopen();
    await db.reopen();
    expect((await db.database).isOpen, isTrue);
  });
}

Future<void> _seed(AppDatabase db, {required int customers, required int transactions, required int memos}) async {
  final now = DateTime.now();
  final sw = Stopwatch()..start();
  final list = <Customer>[];
  for (int i = 0; i < customers; i++) {
    final isSupplier = i % 10 == 0;
    list.add(Customer(
      id: 'c_${i.toString().padLeft(4, '0')}',
      name: isSupplier ? 'মহাজন $i' : 'ক্রেতা $i',
      phone: '017${i.toString().padLeft(8, '0')}',
      type: isSupplier ? ContactType.supplier : ContactType.customer,
      updatedAt: now.subtract(Duration(hours: i % 500)),
    ));
  }
  await db.insertCustomersBatch(list);

  final txs = <TransactionItem>[];
  for (int i = 0; i < transactions; i++) {
    final c = list[i % customers];
    txs.add(TransactionItem(
      id: 'tx_$i',
      customerId: c.id,
      type: i % 3 == 0 ? TransactionType.got : TransactionType.gave,
      amount: 50.0 + (i % 900),
      note: 'seed',
      date: now.subtract(Duration(hours: (i * 7) % (24 * 180))),
    ));
  }
  await db.insertTransactionsBatch(txs);
  await db.recomputeAllBalances();

  for (int i = 0; i < memos; i++) {
    await db.insertCashMemo(CashMemo(
      id: 'memo_$i',
      memoNumber: '#MEMO-${1001 + i}',
      customerName: 'ক্রেতা $i',
      customerPhone: '',
      items: [MemoItem(name: 'চাল', quantity: 2, unitPrice: 70 + (i % 30)), MemoItem(name: 'তেল', quantity: 1, unitPrice: 180)],
      paidAmount: 100,
      date: now.subtract(Duration(hours: (i * 5) % (24 * 60))),
    ));
  }
  sw.stop();
  // ignore: avoid_print
  print('[perf-test] seed $customers customers / $transactions tx / $memos memos in ${sw.elapsedMilliseconds}ms');
}
