import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import '../../models/customer.dart';
import '../../models/transaction_item.dart';
import '../../models/cash_memo.dart';
import '../../models/daily_expense.dart';
import '../../models/product.dart';
import '../utils/perf.dart';

/// Aggregated point used by the reports screens.
class DayAmount {
  final DateTime day;
  final double amount;
  const DayAmount(this.day, this.amount);
}

class MonthFlow {
  final DateTime month; // first day of month
  final double collected; // টাকা পেলাম (customers)
  final double credited; // বাকি দিলাম (customers)
  final double sales; // memo grand totals
  final double expenses;
  const MonthFlow({
    required this.month,
    required this.collected,
    required this.credited,
    required this.sales,
    required this.expenses,
  });
}

/// Single source of truth for all money (see lib/core/utils/money_rules.md).
///
/// * A contact's `current_balance` is always *derived* from its transactions
///   (opening balance included) via [recomputeBalance]; nothing else writes it.
/// * A memo's cash is `MIN(paid_amount, grand_total)`; only its due is posted
///   to the ledger (as a `gave` row carrying `memo_id`), so memo cash and
///   ledger collections never double count.
class AppDatabase {
  static final AppDatabase instance = AppDatabase._init();
  static Database? _database;
  static Future<Database>? _opening;
  static const int schemaVersion = 5;
  static const String dbFileName = 'dukandar.db';

  /// Tests set this (with `databaseFactory = databaseFactoryFfi`) to get a
  /// fresh in-memory database; [close] then [database] starts over.
  @visibleForTesting
  static bool useInMemory = false;

  AppDatabase._init();

  /// Opens the database once (single-flight: concurrent first callers share
  /// the same open future, so migrations run exactly once). If the handle was
  /// closed behind our back (backup/restore) it is transparently re-opened.
  Future<Database> get database {
    final db = _database;
    if (db != null && db.isOpen) return Future.value(db);
    return _opening ??= _open();
  }

  Future<Database> _open() async {
    try {
      final db = await _initDB(dbFileName);
      _database = db;
      return db;
    } finally {
      _opening = null;
    }
  }

  Future<String> get databasePath async => p.join(await getDatabasesPath(), dbFileName);

  Future<Database> _initDB(String filePath) async {
    final t = Perf.start('db.open');
    final path = useInMemory ? inMemoryDatabasePath : p.join(await getDatabasesPath(), filePath);
    final db = await openDatabase(
      path,
      version: schemaVersion,
      onConfigure: _configure,
      onCreate: _createDB,
      onUpgrade: _upgradeDB,
    );
    t.stop(useInMemory ? 'memory' : 'file');
    return db;
  }

  /// Connection pragmas. WAL lets the UI read while a write commits and
  /// `synchronous=NORMAL` skips the per-commit fsync of the main file (safe
  /// with WAL: a power cut can lose the last transactions, never corrupt).
  Future<void> _configure(Database db) async {
    try {
      await db.execute('PRAGMA foreign_keys = ON');
    } catch (_) {}
    if (useInMemory) return;
    try {
      await db.rawQuery('PRAGMA journal_mode = WAL');
    } catch (e) {
      debugPrint('WAL not available: $e');
    }
    try {
      await db.execute('PRAGMA synchronous = NORMAL');
    } catch (_) {}
  }

  /// Flushes the WAL into the main file so a plain file copy is complete.
  Future<void> checkpoint() async {
    final db = _database;
    if (db == null || !db.isOpen) return;
    try {
      await db.rawQuery('PRAGMA wal_checkpoint(TRUNCATE)');
    } catch (_) {}
  }

  /// Closes the DB handle. Required before a backup restore overwrites the
  /// file. Safe to call twice or while an open is in flight.
  Future<void> close() async {
    if (_opening != null) {
      try {
        await _opening;
      } catch (_) {}
    }
    final db = _database;
    _database = null;
    if (db != null && db.isOpen) {
      try {
        await db.close();
      } catch (_) {}
    }
  }

  /// Re-opens after a restore (runs migrations if the restored file is older).
  Future<void> reopen() async {
    await close();
    await database;
  }

  // ---------------------------------------------------------------- schema
  Future<void> _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE customers (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        phone TEXT,
        address TEXT,
        type TEXT NOT NULL,
        current_balance REAL NOT NULL,
        updated_at TEXT NOT NULL,
        photo_path TEXT,
        note TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE transactions (
        id TEXT PRIMARY KEY,
        customer_id TEXT NOT NULL,
        type TEXT NOT NULL,
        amount REAL NOT NULL,
        note TEXT,
        date TEXT NOT NULL,
        memo_id TEXT,
        photo_path TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE cash_memos (
        id TEXT PRIMARY KEY,
        memo_number TEXT NOT NULL,
        customer_name TEXT,
        customer_phone TEXT,
        customer_id TEXT,
        items_json TEXT NOT NULL,
        discount REAL NOT NULL,
        paid_amount REAL NOT NULL,
        date TEXT NOT NULL,
        grand_total REAL NOT NULL DEFAULT 0
      )
    ''');
    await db.execute('''
      CREATE TABLE expenses (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        category TEXT NOT NULL,
        amount REAL NOT NULL,
        date TEXT NOT NULL
      )
    ''');
    await _createProductsTable(db);
    await _createIndexes(db);
  }

  Future<void> _createProductsTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS products (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        unit TEXT,
        sale_price REAL NOT NULL,
        buy_price REAL,
        stock REAL NOT NULL DEFAULT 0,
        low_stock_alert REAL NOT NULL DEFAULT 0,
        updated_at TEXT NOT NULL
      )
    ''');
  }

  Future<void> _createIndexes(Database db) async {
    await db.execute('CREATE INDEX IF NOT EXISTS idx_tx_customer ON transactions(customer_id)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_tx_date ON transactions(date)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_memo_date ON cash_memos(date)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_exp_date ON expenses(date)');
    await _createIndexesV3(db);
  }

  /// v3: composite / covering indexes for the hot queries.
  Future<void> _createIndexesV3(Database db) async {
    await db.execute('CREATE INDEX IF NOT EXISTS idx_tx_customer_date ON transactions(customer_id, date)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_memo_customer ON cash_memos(customer_id)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_cust_type_balance ON customers(type, current_balance)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_products_name ON products(name)');
    await _createIndexesV5(db);
  }

  /// v5: indexes for the remaining hot WHERE/ORDER BY shapes.
  ///  * (customer_id, type, date) — overdue check `MAX(date) WHERE type='got'`
  ///    per customer and the per-type SUM in recomputeBalance.
  ///  * (type, date) — day / month sums filtered by tx type.
  ///  * customers(type, updated_at) — the ledger list `WHERE type ORDER BY updated_at DESC`.
  Future<void> _createIndexesV5(Database db) async {
    await db.execute('CREATE INDEX IF NOT EXISTS idx_tx_customer_type_date ON transactions(customer_id, type, date)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_tx_type_date ON transactions(type, date)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_cust_type_updated ON customers(type, updated_at)');
  }

  Future<void> _upgradeDB(Database db, int oldVersion, int newVersion) async {
    final t = Perf.start('db.migrate');
    // Each step is guarded: a failure in one (e.g. an index that already
    // exists under another name) must not leave the app unable to open its
    // own data. Steps are idempotent (IF NOT EXISTS / column checks).
    await _step('v2', () => _upgradeToV2(db), skip: oldVersion >= 2);
    await _step('v3', () => _upgradeToV3(db), skip: oldVersion >= 3);
    await _step('v4', () => _reconcileLegacyBalances(db), skip: oldVersion >= 4);
    await _step('v5', () => _createIndexesV5(db), skip: oldVersion >= 5);
    t.stop('$oldVersion → $newVersion');
  }

  Future<void> _step(String name, Future<void> Function() body, {required bool skip}) async {
    if (skip) return;
    try {
      await body();
    } catch (e) {
      debugPrint('Migration $name failed (continuing): $e');
    }
  }

  Future<void> _upgradeToV2(Database db) async {
    {
      await _addColumnIfMissing(db, 'customers', 'photo_path', 'TEXT');
      await _addColumnIfMissing(db, 'customers', 'note', 'TEXT');
      await _addColumnIfMissing(db, 'cash_memos', 'customer_id', 'TEXT');
      await _addColumnIfMissing(db, 'transactions', 'memo_id', 'TEXT');
      await _addColumnIfMissing(db, 'transactions', 'photo_path', 'TEXT');
      await _createProductsTable(db);
      await _createIndexes(db);
    }
  }

  Future<void> _upgradeToV3(Database db) async {
    {
      // Stored grand_total lets reports/dashboard SUM in SQL instead of
      // decoding every memo's items_json in Dart.
      await _addColumnIfMissing(db, 'cash_memos', 'grand_total', 'REAL NOT NULL DEFAULT 0');
      final rows = await db.query('cash_memos', columns: ['id', 'items_json', 'discount']);
      final batch = db.batch();
      for (final r in rows) {
        double subtotal = 0;
        try {
          for (final item in jsonDecode(r['items_json'] as String) as List<dynamic>) {
            final m = item as Map<String, dynamic>;
            subtotal += ((m['quantity'] as num?)?.toDouble() ?? 1) * ((m['unit_price'] as num?)?.toDouble() ?? 0);
          }
        } catch (_) {}
        final total = subtotal - ((r['discount'] as num?)?.toDouble() ?? 0);
        batch.update('cash_memos', {'grand_total': total > 0 ? total : 0}, where: 'id = ?', whereArgs: [r['id']]);
      }
      await batch.commit(noResult: true);
      await _createIndexesV3(db);
    }
  }

  /// v4: balances are now derived from transactions only. Older versions kept
  /// `current_balance` as a counter that could differ from Σ transactions
  /// (e.g. an opening balance written directly to the row). For every contact
  /// whose stored balance differs from the transaction sum, insert one
  /// adjustment transaction so the balance the shopkeeper saw is preserved.
  /// Test/support entry point for the v4 reconciliation.
  Future<void> reconcileLegacyBalances() async => _reconcileLegacyBalances(await database);

  Future<void> _reconcileLegacyBalances(Database db) async {
    final customers = await db.query('customers', columns: ['id', 'type', 'current_balance']);
    final batch = db.batch();
    final now = DateTime.now();
    for (final c in customers) {
      final id = c['id'] as String;
      final isCustomer = c['type'] != 'supplier';
      final stored = ((c['current_balance'] as num?)?.toDouble() ?? 0);
      final rows = await db.rawQuery(
        'SELECT type, SUM(amount) AS total FROM transactions WHERE customer_id = ? GROUP BY type',
        [id],
      );
      double gave = 0, got = 0;
      for (final r in rows) {
        final total = (r['total'] as num?)?.toDouble() ?? 0;
        if (r['type'] == 'gave') gave = total;
        if (r['type'] == 'got') got = total;
      }
      final derived = isCustomer ? gave - got : got - gave;
      final diff = ((stored - derived) * 100).roundToDouble() / 100;
      if (diff.abs() < 0.005) continue;
      // Positive diff: they owe more than the ledger says → add to the "owing" side.
      final owingType = isCustomer ? 'gave' : 'got';
      final payingType = isCustomer ? 'got' : 'gave';
      batch.insert('transactions', {
        'id': 'tx_adj_${id}_${now.millisecondsSinceEpoch}',
        'customer_id': id,
        'type': diff > 0 ? owingType : payingType,
        'amount': diff.abs(),
        'note': 'পূর্বের হিসাব (সমন্বয়)',
        'date': now.subtract(const Duration(seconds: 1)).toIso8601String(),
      });
    }
    await batch.commit(noResult: true);
  }

  Future<void> _addColumnIfMissing(Database db, String table, String column, String type) async {
    final info = await db.rawQuery('PRAGMA table_info($table)');
    if (!info.any((row) => row['name'] == column)) {
      await db.execute('ALTER TABLE $table ADD COLUMN $column $type');
    }
  }

  // ------------------------------------------------------------- customers
  Future<List<Customer>> getCustomers({ContactType? type}) async {
    final db = await database;
    final maps = await db.query('customers',
        where: type != null ? 'type = ?' : null,
        whereArgs: type != null ? [type.name] : null,
        orderBy: 'updated_at DESC');
    return maps.map(Customer.fromMap).toList();
  }

  Future<Customer?> getCustomer(String id) async => _getCustomerIn(await database, id);

  /// Batch insert in one transaction (restore / import / seeding paths).
  Future<void> insertCustomersBatch(List<Customer> customers) async {
    if (customers.isEmpty) return;
    final db = await database;
    final batch = db.batch();
    for (final c in customers) {
      batch.insert('customers', c.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  /// Recomputes every contact's balance with two set-based statements
  /// (no per-customer round trips). Used after bulk imports.
  Future<void> recomputeAllBalances() async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.rawUpdate('''
        UPDATE customers SET current_balance = ROUND(COALESCE((
          SELECT SUM(CASE WHEN t.type = 'gave' THEN t.amount ELSE -t.amount END)
          FROM transactions t WHERE t.customer_id = customers.id), 0), 2)
        WHERE type != 'supplier'
      ''');
      await txn.rawUpdate('''
        UPDATE customers SET current_balance = ROUND(COALESCE((
          SELECT SUM(CASE WHEN t.type = 'got' THEN t.amount ELSE -t.amount END)
          FROM transactions t WHERE t.customer_id = customers.id), 0), 2)
        WHERE type = 'supplier'
      ''');
    });
  }

  Future<List<Customer>> searchCustomers(String query, {ContactType? type}) async {
    final db = await database;
    final q = '%${query.trim()}%';
    final where = StringBuffer('(name LIKE ? OR phone LIKE ?)');
    final args = <Object?>[q, q];
    if (type != null) {
      where.write(' AND type = ?');
      args.add(type.name);
    }
    final maps = await db.query('customers',
        where: where.toString(), whereArgs: args, orderBy: 'name ASC', limit: 50);
    return maps.map(Customer.fromMap).toList();
  }

  Future<void> insertCustomer(Customer customer) async {
    final db = await database;
    await db.insert('customers', customer.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// Updates profile fields only. `current_balance` is derived from the
  /// transaction log and is never overwritten by a (possibly stale) object.
  Future<void> updateCustomer(Customer customer) async {
    final db = await database;
    final map = customer.toMap()..remove('current_balance');
    await db.update('customers', map, where: 'id = ?', whereArgs: [customer.id]);
  }

  Future<void> updateCustomerBalance(String customerId, double newBalance) async {
    final db = await database;
    await db.update(
      'customers',
      {'current_balance': newBalance, 'updated_at': DateTime.now().toIso8601String()},
      where: 'id = ?',
      whereArgs: [customerId],
    );
  }

  /// Deletes the customer and all of their transactions.
  Future<void> deleteCustomer(String customerId) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('transactions', where: 'customer_id = ?', whereArgs: [customerId]);
      await txn.update('cash_memos', {'customer_id': null},
          where: 'customer_id = ?', whereArgs: [customerId]);
      await txn.delete('customers', where: 'id = ?', whereArgs: [customerId]);
    });
  }

  /// Recomputes the balance from the transaction log (single source of truth).
  /// Customer: gave (+) / got (−)  → positive = customer owes the shop,
  ///                                  negative = advance / জমা বেশি.
  /// Supplier: got (+) / gave (−)  → positive = shop owes the supplier.
  Future<double> recomputeBalance(String customerId) async {
    final db = await database;
    return _recomputeBalanceIn(db, customerId);
  }

  Future<double> _recomputeBalanceIn(DatabaseExecutor db, String customerId) async {
    final cRows = await db.query('customers', columns: ['type'], where: 'id = ?', whereArgs: [customerId], limit: 1);
    if (cRows.isEmpty) return 0;
    final isCustomer = cRows.first['type'] != 'supplier';
    final rows = await db.rawQuery(
      'SELECT type, SUM(amount) AS total FROM transactions WHERE customer_id = ? GROUP BY type',
      [customerId],
    );
    double gave = 0, got = 0;
    for (final r in rows) {
      final total = (r['total'] as num?)?.toDouble() ?? 0;
      if (r['type'] == 'gave') gave = total;
      if (r['type'] == 'got') got = total;
    }
    final raw = isCustomer ? gave - got : got - gave;
    // Kill floating-point dust (e.g. 0.30000000000000004) so "settled" is exact.
    final balance = (raw * 100).roundToDouble() / 100;
    await db.update(
      'customers',
      {'current_balance': balance, 'updated_at': DateTime.now().toIso8601String()},
      where: 'id = ?',
      whereArgs: [customerId],
    );
    return balance;
  }

  /// Customers with a positive balance whose last payment is older than [days]
  /// days (or who never paid and whose first credit is older than [days]).
  Future<List<Customer>> getOverdueCustomers({int days = 7}) async {
    final db = await database;
    final cutoff = DateTime.now().subtract(Duration(days: days)).toIso8601String();
    final rows = await db.rawQuery('''
      SELECT c.* FROM customers c
      WHERE c.type = 'customer' AND c.current_balance > 0
        AND COALESCE(
              (SELECT MAX(t.date) FROM transactions t WHERE t.customer_id = c.id AND t.type = 'got'),
              (SELECT MIN(t.date) FROM transactions t WHERE t.customer_id = c.id),
              c.updated_at
            ) < ?
      ORDER BY c.current_balance DESC
    ''', [cutoff]);
    return rows.map(Customer.fromMap).toList();
  }

  // ---------------------------------------------------------- transactions
  /// Transactions of one contact, newest first. [limit]/[offset] allow the
  /// detail screen to page through very long histories.
  Future<List<TransactionItem>> getTransactions(String customerId, {int? limit, int? offset}) async {
    final db = await database;
    final maps = await db.query('transactions',
        where: 'customer_id = ?', whereArgs: [customerId], orderBy: 'date DESC', limit: limit, offset: offset);
    return maps.map(TransactionItem.fromMap).toList();
  }

  Future<int> getTransactionCount(String customerId) async {
    final db = await database;
    return Sqflite.firstIntValue(await db.rawQuery(
          'SELECT COUNT(*) FROM transactions WHERE customer_id = ?',
          [customerId],
        )) ??
        0;
  }

  Future<List<TransactionItem>> getRecentTransactions({int limit = 10}) async {
    final db = await database;
    final maps = await db.query('transactions', orderBy: 'date DESC', limit: limit);
    return maps.map(TransactionItem.fromMap).toList();
  }

  Future<void> insertTransaction(TransactionItem tx) async {
    final db = await database;
    await db.insert('transactions', tx.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// Insert + balance recompute in ONE SQLite transaction (one fsync, and no
  /// window where the row exists but the balance is stale). Returns the
  /// refreshed contact.
  Future<Customer?> recordTransaction(TransactionItem tx) async {
    final db = await database;
    return db.transaction((txn) async {
      await txn.insert('transactions', tx.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
      await _recomputeBalanceIn(txn, tx.customerId);
      return _getCustomerIn(txn, tx.customerId);
    });
  }

  Future<void> updateTransaction(TransactionItem tx) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.update('transactions', tx.toMap(), where: 'id = ?', whereArgs: [tx.id]);
      await _recomputeBalanceIn(txn, tx.customerId);
    });
  }

  /// Deletes a transaction and recomputes the owner's balance (atomic).
  Future<void> deleteTransaction(String txId) async {
    final db = await database;
    await db.transaction((txn) async {
      final rows = await txn.query('transactions', columns: ['customer_id'], where: 'id = ?', whereArgs: [txId], limit: 1);
      if (rows.isEmpty) return;
      final customerId = rows.first['customer_id'] as String;
      await txn.delete('transactions', where: 'id = ?', whereArgs: [txId]);
      await _recomputeBalanceIn(txn, customerId);
    });
  }

  /// Creates a contact with an optional opening-balance transaction and the
  /// derived balance, all in one transaction. Returns the stored row.
  Future<Customer> createContact(Customer customer, {TransactionItem? opening}) async {
    final db = await database;
    return db.transaction((txn) async {
      await txn.insert('customers', customer.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
      if (opening != null) {
        await txn.insert('transactions', opening.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
      }
      await _recomputeBalanceIn(txn, customer.id);
      return (await _getCustomerIn(txn, customer.id)) ?? customer;
    });
  }

  Future<Customer?> _getCustomerIn(DatabaseExecutor db, String id) async {
    final maps = await db.query('customers', where: 'id = ?', whereArgs: [id], limit: 1);
    return maps.isEmpty ? null : Customer.fromMap(maps.first);
  }

  /// Sum of customer payments ("got", বাকি আদায়) for a given day.
  Future<double> getCollectionsForDay(DateTime day) =>
      _sumTxForDay(day, contactType: 'customer', txType: 'got');

  /// Sum of cash paid to suppliers ("gave" on a supplier) for a given day.
  Future<double> getSupplierPaymentsForDay(DateTime day) =>
      _sumTxForDay(day, contactType: 'supplier', txType: 'gave');

  Future<double> _sumTxForDay(DateTime day, {required String contactType, required String txType}) async {
    final db = await database;
    final start = DateTime(day.year, day.month, day.day).toIso8601String();
    final end = DateTime(day.year, day.month, day.day + 1).toIso8601String();
    final rows = await db.rawQuery('''
      SELECT SUM(t.amount) AS total FROM transactions t
      JOIN customers c ON c.id = t.customer_id
      WHERE c.type = ? AND t.type = ? AND t.date >= ? AND t.date < ?
    ''', [contactType, txType, start, end]);
    return (rows.first['total'] as num?)?.toDouble() ?? 0;
  }

  // ------------------------------------------------------------ cash memos
  /// Rows become lazy memos: `items_json` is decoded only when `.items` is
  /// first read (detail / PDF), list totals come from the stored column.
  CashMemo _memoFromRow(Map<String, Object?> e) {
    return CashMemo.lazy(
      id: e['id']?.toString() ?? '',
      memoNumber: e['memo_number']?.toString() ?? '',
      customerName: e['customer_name'] as String? ?? 'সাধারণ ক্রেতা',
      customerPhone: e['customer_phone'] as String? ?? '',
      customerId: e['customer_id'] as String?,
      itemsJson: e['items_json'] as String? ?? '',
      grandTotal: (e['grand_total'] as num?)?.toDouble() ?? 0.0,
      discount: (e['discount'] as num?)?.toDouble() ?? 0.0,
      paidAmount: (e['paid_amount'] as num?)?.toDouble() ?? 0.0,
      date: DateTime.tryParse(e['date'] as String? ?? '') ?? DateTime.now(),
    );
  }

  Map<String, Object?> _memoToRow(CashMemo memo) => {
        'id': memo.id,
        'memo_number': memo.memoNumber,
        'customer_name': memo.customerName,
        'customer_phone': memo.customerPhone,
        'customer_id': memo.customerId,
        'items_json': memo.itemsJson,
        'discount': memo.discount,
        'paid_amount': memo.paidAmount,
        'date': memo.date.toIso8601String(),
        'grand_total': memo.grandTotal,
      };

  Future<List<CashMemo>> getCashMemos({DateTime? from, DateTime? to, int? limit}) async {
    final db = await database;
    String? where;
    List<Object?>? args;
    if (from != null && to != null) {
      where = 'date >= ? AND date < ?';
      args = [from.toIso8601String(), to.toIso8601String()];
    }
    final maps = await db.query('cash_memos', where: where, whereArgs: args, orderBy: 'date DESC', limit: limit);
    return maps.map(_memoFromRow).toList();
  }

  /// SUM(grand_total) over a date range — no JSON decoding. ("বিক্রি")
  Future<double> getSalesBetween(DateTime from, DateTime to) async {
    final db = await database;
    final rows = await db.rawQuery(
      'SELECT SUM(grand_total) AS total FROM cash_memos WHERE date >= ? AND date < ?',
      [from.toIso8601String(), to.toIso8601String()],
    );
    return (rows.first['total'] as num?)?.toDouble() ?? 0;
  }

  /// SUM(MIN(paid, grand_total)) over a date range — cash actually kept from
  /// memos ("নগদ বিক্রি"). Over-payment (change returned) is not revenue.
  Future<double> getCashSalesBetween(DateTime from, DateTime to) async {
    final db = await database;
    final rows = await db.rawQuery(
      'SELECT SUM(MIN(paid_amount, grand_total)) AS total FROM cash_memos WHERE date >= ? AND date < ?',
      [from.toIso8601String(), to.toIso8601String()],
    );
    return (rows.first['total'] as num?)?.toDouble() ?? 0;
  }

  /// Next sequential memo number. Uses the highest existing number (not the
  /// row count) so deleting a memo can never produce a duplicate.
  Future<String> nextMemoNumber() async {
    final db = await database;
    final rows = await db.rawQuery(
      "SELECT MAX(CAST(substr(memo_number, 7) AS INTEGER)) AS n FROM cash_memos WHERE memo_number LIKE '#MEMO-%'",
    );
    final last = (rows.first['n'] as num?)?.toInt() ?? 1000;
    return '#MEMO-${(last < 1000 ? 1000 : last) + 1}';
  }

  Future<int> getMemoCountBetween(DateTime from, DateTime to) async {
    final db = await database;
    return Sqflite.firstIntValue(await db.rawQuery(
          'SELECT COUNT(*) FROM cash_memos WHERE date >= ? AND date < ?',
          [from.toIso8601String(), to.toIso8601String()],
        )) ??
        0;
  }

  Future<List<CashMemo>> getMemosForCustomer(String customerId) async {
    final db = await database;
    final maps = await db.query('cash_memos',
        where: 'customer_id = ?', whereArgs: [customerId], orderBy: 'date DESC');
    return maps.map(_memoFromRow).toList();
  }

  Future<int> getMemoCount() async {
    final db = await database;
    return Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM cash_memos')) ?? 0;
  }

  /// Inserts a memo, decrements stock for any item linked to a product and,
  /// when [postDueToLedger] is set and the memo has a customer, writes ONLY
  /// the due (grand total − paid) to the ledger as a `gave` row tagged with
  /// `memo_id`. The customer's balance is recomputed from the log. All of it
  /// happens in one SQLite transaction.
  Future<void> insertCashMemo(CashMemo memo, {bool postDueToLedger = false}) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.insert('cash_memos', _memoToRow(memo), conflictAlgorithm: ConflictAlgorithm.replace);
      for (final item in memo.items) {
        if (item.productId != null) {
          await txn.rawUpdate(
            'UPDATE products SET stock = stock - ?, updated_at = ? WHERE id = ?',
            [item.quantity, DateTime.now().toIso8601String(), item.productId],
          );
        }
      }
      final customerId = memo.customerId;
      if (postDueToLedger && customerId != null && memo.dueAmount > 0) {
        await txn.insert(
          'transactions',
          TransactionItem(
            id: 'tx_memo_${memo.id}',
            customerId: customerId,
            type: TransactionType.gave,
            amount: memo.dueAmount,
            note: 'মেমো ${memo.memoNumber} এর বাকি',
            date: memo.date,
            memoId: memo.id,
          ).toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        await _recomputeBalanceIn(txn, customerId);
      }
    });
  }

  /// Deletes a memo and reverses its side effects: the linked ledger row(s)
  /// are removed (balance recomputed) and stock is restored.
  Future<void> deleteCashMemo(String memoId) async {
    final db = await database;
    await db.transaction((txn) async {
      final rows = await txn.query('cash_memos', where: 'id = ?', whereArgs: [memoId], limit: 1);
      if (rows.isEmpty) return;
      final memo = _memoFromRow(rows.first);
      for (final item in memo.items) {
        if (item.productId != null) {
          await txn.rawUpdate(
            'UPDATE products SET stock = stock + ?, updated_at = ? WHERE id = ?',
            [item.quantity, DateTime.now().toIso8601String(), item.productId],
          );
        }
      }
      final linked = await txn.query('transactions', columns: ['customer_id'], where: 'memo_id = ?', whereArgs: [memoId]);
      await txn.delete('transactions', where: 'memo_id = ?', whereArgs: [memoId]);
      await txn.delete('cash_memos', where: 'id = ?', whereArgs: [memoId]);
      for (final id in linked.map((r) => r['customer_id'] as String).toSet()) {
        await _recomputeBalanceIn(txn, id);
      }
    });
  }

  Future<double> getSalesForDay(DateTime day) async {
    final start = DateTime(day.year, day.month, day.day);
    return getSalesBetween(start, start.add(const Duration(days: 1)));
  }

  // -------------------------------------------------------------- expenses
  Future<List<DailyExpense>> getExpenses({DateTime? from, DateTime? to}) async {
    final db = await database;
    String? where;
    List<Object?>? args;
    if (from != null && to != null) {
      where = 'date >= ? AND date < ?';
      args = [from.toIso8601String(), to.toIso8601String()];
    }
    final maps = await db.query('expenses', where: where, whereArgs: args, orderBy: 'date DESC');
    return maps.map(DailyExpense.fromMap).toList();
  }

  Future<void> insertExpense(DailyExpense expense) async {
    final db = await database;
    await db.insert('expenses', expense.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> deleteExpense(String id) async {
    final db = await database;
    await db.delete('expenses', where: 'id = ?', whereArgs: [id]);
  }

  // -------------------------------------------------------------- products
  Future<List<Product>> getProducts() async {
    final db = await database;
    final maps = await db.query('products', orderBy: 'name COLLATE NOCASE ASC');
    return maps.map(Product.fromMap).toList();
  }

  Future<List<Product>> searchProducts(String query) async {
    final db = await database;
    final maps = await db.query('products',
        where: 'name LIKE ?', whereArgs: ['%${query.trim()}%'], orderBy: 'name ASC', limit: 50);
    return maps.map(Product.fromMap).toList();
  }

  Future<void> insertProduct(Product product) async {
    final db = await database;
    await db.insert('products', product.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> updateProduct(Product product) async {
    final db = await database;
    await db.update('products', product.toMap(), where: 'id = ?', whereArgs: [product.id]);
  }

  Future<void> deleteProduct(String id) async {
    final db = await database;
    await db.delete('products', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> adjustStock(String productId, double delta) async {
    final db = await database;
    await db.rawUpdate('UPDATE products SET stock = stock + ?, updated_at = ? WHERE id = ?',
        [delta, DateTime.now().toIso8601String(), productId]);
  }

  // ------------------------------------------------------------ aggregates
  /// Sales (memo grand totals) per day for the last [days] days, oldest first.
  Future<List<DayAmount>> getDailySales({int days = 30}) async {
    final db = await database;
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day).subtract(Duration(days: days - 1));
    final rows = await db.rawQuery('''
      SELECT substr(date, 1, 10) AS d, SUM(grand_total) AS total FROM cash_memos
      WHERE date >= ? GROUP BY d
    ''', [start.toIso8601String()]);
    final buckets = <String, double>{
      for (final r in rows) (r['d'] as String): (r['total'] as num?)?.toDouble() ?? 0,
    };
    String key(DateTime d) =>
        '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    return List.generate(days, (i) {
      final day = start.add(Duration(days: i));
      return DayAmount(day, buckets[key(day)] ?? 0);
    });
  }

  /// Collections vs new credit (customers only), sales & expenses per month.
  Future<List<MonthFlow>> getMonthlyFlows({int months = 6}) async {
    final db = await database;
    final now = DateTime.now();
    final startMonth = DateTime(now.year, now.month - (months - 1), 1);
    final startIso = startMonth.toIso8601String();

    final txRows = await db.rawQuery('''
      SELECT substr(t.date, 1, 7) AS ym, t.type, SUM(t.amount) AS total
      FROM transactions t JOIN customers c ON c.id = t.customer_id
      WHERE c.type = 'customer' AND t.date >= ?
      GROUP BY ym, t.type
    ''', [startIso]);
    final expRows = await db.rawQuery('''
      SELECT substr(date, 1, 7) AS ym, SUM(amount) AS total FROM expenses
      WHERE date >= ? GROUP BY ym
    ''', [startIso]);
    final memoRows = await db.rawQuery('''
      SELECT substr(date, 1, 7) AS ym, SUM(grand_total) AS total FROM cash_memos
      WHERE date >= ? GROUP BY ym
    ''', [startIso]);

    String ymOf(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}';
    final result = <MonthFlow>[];
    for (int i = 0; i < months; i++) {
      final m = DateTime(startMonth.year, startMonth.month + i, 1);
      final ym = ymOf(m);
      double collected = 0, credited = 0, expenses = 0, sales = 0;
      for (final r in txRows) {
        if (r['ym'] != ym) continue;
        final total = (r['total'] as num?)?.toDouble() ?? 0;
        if (r['type'] == 'got') collected = total;
        if (r['type'] == 'gave') credited = total;
      }
      for (final r in expRows) {
        if (r['ym'] == ym) expenses = (r['total'] as num?)?.toDouble() ?? 0;
      }
      for (final r in memoRows) {
        if (r['ym'] == ym) sales = (r['total'] as num?)?.toDouble() ?? 0;
      }
      result.add(MonthFlow(month: m, collected: collected, credited: credited, sales: sales, expenses: expenses));
    }
    return result;
  }

  /// Expense totals grouped by category within a month.
  Future<Map<String, double>> getExpensesByCategory(DateTime month) async {
    final db = await database;
    final start = DateTime(month.year, month.month, 1).toIso8601String();
    final end = DateTime(month.year, month.month + 1, 1).toIso8601String();
    final rows = await db.rawQuery('''
      SELECT category, SUM(amount) AS total FROM expenses
      WHERE date >= ? AND date < ? GROUP BY category ORDER BY total DESC
    ''', [start, end]);
    return {
      for (final r in rows) (r['category'] as String? ?? 'অন্যান্য'): (r['total'] as num?)?.toDouble() ?? 0
    };
  }

  /// Batch insert in one transaction (restore / import paths).
  Future<void> insertTransactionsBatch(List<TransactionItem> txs) async {
    if (txs.isEmpty) return;
    final db = await database;
    final batch = db.batch();
    for (final t in txs) {
      batch.insert('transactions', t.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  // ------------------------------------------- optional demo data (unused)
  /// Not called automatically – a real shop starts empty.
  Future<void> seedDemoData() async {
    final now = DateTime.now();
    final c1 = Customer(
      id: 'demo_c_1',
      name: 'কামাল হোসেন',
      phone: '01712345678',
      address: 'মেইন রোড',
      type: ContactType.customer,
      currentBalance: 1500,
      updatedAt: now.subtract(const Duration(days: 9)),
    );
    await insertCustomer(c1);
    await insertTransaction(TransactionItem(
      id: 'demo_t_1',
      customerId: c1.id,
      type: TransactionType.gave,
      amount: 1500,
      note: 'চাল ও তেল বাকি',
      date: now.subtract(const Duration(days: 9)),
    ));
    await insertProduct(Product(
      id: 'demo_p_1',
      name: 'মিনিকেট চাল',
      unit: 'কেজি',
      salePrice: 72,
      buyPrice: 66,
      stock: 50,
      lowStockAlert: 10,
      updatedAt: now,
    ));
    debugPrint('Demo data seeded');
  }
}
