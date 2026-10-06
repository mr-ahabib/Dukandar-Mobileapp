import 'package:flutter/material.dart';
import '../core/database/app_database.dart';
import '../models/cash_memo.dart';
import '../core/utils/perf.dart';
import '../models/daily_expense.dart';

class ExpenseCategory {
  final String name;
  final IconData icon;
  final Color color;
  const ExpenseCategory(this.name, this.icon, this.color);
}

class CashDrawerProvider extends ChangeNotifier {
  final AppDatabase _db = AppDatabase.instance;

  static const List<ExpenseCategory> categories = [
    ExpenseCategory('দোকান ভাড়া', Icons.home_work_rounded, Color(0xFF166534)),
    ExpenseCategory('কারেন্ট বিল', Icons.bolt_rounded, Color(0xFFB45309)),
    ExpenseCategory('নাস্তা/চা', Icons.emoji_food_beverage_rounded, Color(0xFFDC2626)),
    ExpenseCategory('স্টাফ বেতন', Icons.badge_rounded, Color(0xFF0F766E)),
    ExpenseCategory('মাল কেনা', Icons.local_shipping_rounded, Color(0xFF059669)),
    ExpenseCategory('যাতায়াত', Icons.directions_bike_rounded, Color(0xFF4D7C0F)),
    ExpenseCategory('মোবাইল/নেট', Icons.phone_android_rounded, Color(0xFF0369A1)),
    ExpenseCategory('অন্যান্য', Icons.more_horiz_rounded, Color(0xFF64748B)),
  ];

  static ExpenseCategory categoryOf(String name) =>
      categories.firstWhere((c) => c.name == name, orElse: () => categories.last);

  List<DailyExpense> _expenses = [];
  List<CashMemo> _memos = [];
  double _collections = 0;
  double _supplierPayments = 0;
  bool _isLoading = false;
  bool _loadedOnce = false;
  DateTime _selectedDay = DateTime.now();

  // Cached day aggregates — recomputed once per data change, not per build.
  double _totalExpense = 0;
  double _totalSales = 0;
  double _cashSales = 0;
  double _creditSales = 0;

  void _recompute() {
    double exp = 0, sales = 0, cash = 0, credit = 0;
    for (final e in _expenses) {
      exp += e.amount;
    }
    for (final m in _memos) {
      sales += m.grandTotal;
      cash += m.cashReceived;
      credit += m.dueAmount;
    }
    _totalExpense = exp;
    _totalSales = sales;
    _cashSales = cash;
    _creditSales = credit;
  }

  List<DailyExpense> get expenses => _expenses;
  List<CashMemo> get memos => _memos;
  bool get isLoading => _isLoading;
  bool get loadedOnce => _loadedOnce;
  DateTime get selectedDay => _selectedDay;
  bool get isToday {
    final n = DateTime.now();
    return n.year == _selectedDay.year && n.month == _selectedDay.month && n.day == _selectedDay.day;
  }

  // Day figures (see money_rules.md):
  /// খরচ — sum of expenses written for the day.
  double get totalExpense => _totalExpense;
  /// বিক্রি — Σ grand total of the day's memos (cash + credit).
  double get totalSales => _totalSales;
  /// নগদ বিক্রি — Σ min(paid, grand total). Change given back is not revenue.
  double get cashSales => _cashSales;
  /// বাকিতে বিক্রি — Σ due of the day's memos.
  double get creditSales => _creditSales;
  /// বাকি আদায় — ledger `got` rows on customers (memo cash never creates one).
  double get collections => _collections;
  /// মহাজনকে দেওয়া — ledger `gave` rows on suppliers.
  double get supplierPayments => _supplierPayments;

  /// আজকের নগদ = নগদ বিক্রি + বাকি আদায় − খরচ − মহাজনকে দেওয়া
  double get netCash => cashSales + _collections - totalExpense - _supplierPayments;

  /// Backwards-compatible name used by older code.
  double get todayTotalExpense => totalExpense;

  /// Loading is started by `AppBootstrap` after the first frame.
  CashDrawerProvider();

  Future<void> ensureLoaded() => _loadedOnce || _isLoading ? Future.value() : loadExpenses();

  Future<void> setDay(DateTime day) async {
    _selectedDay = day;
    await loadExpenses();
  }

  Future<void> loadExpenses() async {
    _isLoading = true;
    notifyListeners();
    final t = Perf.start('cash.load');
    try {
      final start = DateTime(_selectedDay.year, _selectedDay.month, _selectedDay.day);
      final end = start.add(const Duration(days: 1));
      final results = await Future.wait<Object>([
        _db.getExpenses(from: start, to: end),
        _db.getCashMemos(from: start, to: end),
        _db.getCollectionsForDay(start),
        _db.getSupplierPaymentsForDay(start),
      ]);
      _expenses = results[0] as List<DailyExpense>;
      _memos = results[1] as List<CashMemo>;
      _collections = results[2] as double;
      _supplierPayments = results[3] as double;
      _recompute();
      t.stop('${_expenses.length} expenses, ${_memos.length} memos');
    } catch (e) {
      debugPrint('Error loading cash drawer: $e');
    } finally {
      _isLoading = false;
      _loadedOnce = true;
      notifyListeners();
    }
  }

  Future<void> addExpense({
    required String title,
    required String category,
    required double amount,
    DateTime? date,
  }) async {
    final when = date ?? (isToday ? DateTime.now() : _selectedDay);
    final expense = DailyExpense(
      id: 'exp_${DateTime.now().millisecondsSinceEpoch}',
      title: title.trim().isEmpty ? category : title.trim(),
      category: category,
      amount: amount,
      date: when,
    );
    await _db.insertExpense(expense);
    final d = DateTime(when.year, when.month, when.day);
    final sel = DateTime(_selectedDay.year, _selectedDay.month, _selectedDay.day);
    if (d == sel) {
      _expenses = [expense, ..._expenses];
      _totalExpense += expense.amount;
      notifyListeners();
    }
  }

  Future<void> deleteExpense(String id) async {
    await _db.deleteExpense(id);
    _expenses = _expenses.where((e) => e.id != id).toList();
    _recompute();
    notifyListeners();
  }

  /// Called by BillingProvider consumers after a memo is created so the
  /// drawer reflects today's sale without a full reload.
  void onMemoCreated(CashMemo memo) {
    if (!isToday) return;
    _memos = [memo, ..._memos];
    _totalSales += memo.grandTotal;
    _cashSales += memo.cashReceived;
    _creditSales += memo.dueAmount;
    notifyListeners();
  }

  /// Mirror of [onMemoCreated] for deletions.
  void onMemoDeleted(CashMemo memo) {
    final before = _memos.length;
    _memos = _memos.where((m) => m.id != memo.id).toList();
    if (_memos.length != before) {
      _recompute();
      notifyListeners();
    }
  }
}
