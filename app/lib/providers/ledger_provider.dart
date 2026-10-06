import 'package:flutter/material.dart';
import '../core/database/app_database.dart';
import '../core/utils/perf.dart';
import '../core/utils/photo_helper.dart';
import '../models/customer.dart';
import '../models/transaction_item.dart';

/// The ledger list split the way the খাতা screen shows it. Built once per
/// data/filter change (not per frame) by [LedgerProvider.sections].
class LedgerSections {
  final List<Customer> visible; // after search + filter
  final List<Customer> due; // balance > 0, sorted
  final List<Customer> advance; // balance < 0, sorted
  final List<Customer> settled; // balance == 0, sorted
  const LedgerSections({required this.visible, required this.due, required this.advance, required this.settled});
  static const empty = LedgerSections(visible: [], due: [], advance: [], settled: []);
}

class LedgerProvider extends ChangeNotifier {
  final AppDatabase _db = AppDatabase.instance;

  List<Customer> _customers = [];
  List<Customer> _suppliers = [];
  List<Customer> _overdue = [];
  List<TransactionItem> _recent = [];
  Map<String, Customer> _byId = const {};
  bool _isLoading = false;
  bool _loadedOnce = false;
  String _searchQuery = '';
  String _selectedFilter = 'all'; // 'all', 'due', 'zero'

  // ---- cached aggregates (recomputed in _onDataChanged, never in build) ----
  double _totalReceivables = 0;
  double _totalPayables = 0;
  double _totalCustomerAdvances = 0;
  int _dueCustomerCount = 0;
  int _dueSupplierCount = 0;
  int _settledCustomers = 0;
  int _settledSuppliers = 0;
  final Map<ContactType, LedgerSections> _sections = {};

  List<Customer> get customers => sections(ContactType.customer).visible;
  List<Customer> get suppliers => sections(ContactType.supplier).visible;
  List<Customer> get allCustomersRaw => _customers;
  List<Customer> get allSuppliersRaw => _suppliers;

  /// যাদের কাছে ৭ দিনের বেশি বাকি
  List<Customer> get overdueCustomers => _overdue;
  List<TransactionItem> get recentTransactions => _recent;
  bool get isLoading => _isLoading;
  bool get loadedOnce => _loadedOnce;
  String get searchQuery => _searchQuery;
  String get selectedFilter => _selectedFilter;

  double get totalReceivables => _totalReceivables;
  double get totalPayables => _totalPayables;
  int get dueCustomerCount => _dueCustomerCount;
  int get dueSupplierCount => _dueSupplierCount;
  int settledCount(ContactType t) => t == ContactType.customer ? _settledCustomers : _settledSuppliers;
  int activeCount(ContactType t) =>
      (t == ContactType.customer ? _customers.length - _settledCustomers : _suppliers.length - _settledSuppliers);

  /// Customers who have paid more than they owe (negative balance).
  double get totalCustomerAdvances => _totalCustomerAdvances;

  /// Constructor is intentionally empty: loading is kicked off by
  /// `AppBootstrap` after the first frame (all providers in parallel).
  LedgerProvider();

  Customer? byId(String id) => _byId[id];

  /// Sorted / partitioned list for one tab. Cached until data, search or
  /// filter changes, so a rebuild of the screen is O(1) here.
  LedgerSections sections(ContactType type) => _sections[type] ??= _buildSections(type);

  /// Idempotent first load (safe to call from several screens).
  Future<void> ensureLoaded() => _loadedOnce || _isLoading ? Future.value() : loadData();

  Future<void> loadData() async {
    _isLoading = true;
    notifyListeners();
    final t = Perf.start('ledger.load');
    try {
      final results = await Future.wait([
        _db.getCustomers(type: ContactType.customer),
        _db.getCustomers(type: ContactType.supplier),
        _db.getOverdueCustomers(days: 7),
        _db.getRecentTransactions(limit: 20),
      ]);
      _customers = results[0] as List<Customer>;
      _suppliers = results[1] as List<Customer>;
      _overdue = results[2] as List<Customer>;
      _recent = results[3] as List<TransactionItem>;
      _onDataChanged();
      t.stop('${_customers.length + _suppliers.length} contacts');
    } catch (e) {
      debugPrint('Error loading ledger: $e');
    } finally {
      _isLoading = false;
      _loadedOnce = true;
      notifyListeners();
    }
  }

  void setSearchQuery(String query) {
    final q = query.trim().toLowerCase();
    if (q == _searchQuery) return;
    _searchQuery = q;
    _sections.clear();
    notifyListeners();
  }

  void setFilter(String filter) {
    if (filter == _selectedFilter) return;
    _selectedFilter = filter;
    _sections.clear();
    notifyListeners();
  }

  // ------------------------------------------------------------- internals

  /// Recomputes every derived value once. Called after each data mutation.
  void _onDataChanged() {
    double rec = 0, pay = 0, adv = 0;
    int dueC = 0, dueS = 0, setC = 0, setS = 0;
    final index = <String, Customer>{};
    for (final c in _customers) {
      index[c.id] = c;
      final b = c.currentBalance;
      if (b > 0) {
        rec += b;
        dueC++;
      } else if (b < 0) {
        adv -= b;
      } else {
        setC++;
      }
    }
    for (final s in _suppliers) {
      index[s.id] = s;
      final b = s.currentBalance;
      if (b > 0) {
        pay += b;
        dueS++;
      } else if (b == 0) {
        setS++;
      }
    }
    _totalReceivables = rec;
    _totalPayables = pay;
    _totalCustomerAdvances = adv;
    _dueCustomerCount = dueC;
    _dueSupplierCount = dueS;
    _settledCustomers = setC;
    _settledSuppliers = setS;
    _byId = index;
    _sections.clear();
  }

  LedgerSections _buildSections(ContactType type) {
    final source = type == ContactType.customer ? _customers : _suppliers;
    final q = _searchQuery;
    final visible = <Customer>[];
    for (final item in source) {
      if (q.isNotEmpty && !item.searchKey.contains(q)) continue;
      final b = item.currentBalance;
      final ok = switch (_selectedFilter) {
        'due' => b > 0,
        'zero' => b == 0, // হিসাব মিটে গেছে / ইতিহাস
        _ => b != 0, // main খাতা: paid-off contacts are hidden
      };
      if (ok) visible.add(item);
    }
    // Sort: due first (desc), then by updated.
    final sorted = [...visible]..sort((a, b) {
        if ((a.currentBalance > 0) != (b.currentBalance > 0)) return a.currentBalance > 0 ? -1 : 1;
        return b.updatedAt.compareTo(a.updatedAt);
      });
    final due = <Customer>[], advance = <Customer>[], settled = <Customer>[];
    for (final c in sorted) {
      if (c.currentBalance > 0) {
        due.add(c);
      } else if (c.currentBalance < 0) {
        advance.add(c);
      } else {
        settled.add(c);
      }
    }
    return LedgerSections(visible: visible, due: due, advance: advance, settled: settled);
  }

  // --------------------------------------------------------------- writes

  Future<Customer> addContact({
    required String name,
    required String phone,
    String address = '',
    String note = '',
    String? photoPath,
    required ContactType type,
    double openingBalance = 0.0,
    String? id,
  }) async {
    final newId = id ?? 'contact_${DateTime.now().millisecondsSinceEpoch}';
    final customer = Customer(
      id: newId,
      name: name.trim(),
      phone: phone.trim(),
      address: address.trim(),
      note: note.trim(),
      photoPath: photoPath,
      type: type,
      currentBalance: openingBalance,
      updatedAt: DateTime.now(),
    );
    // The opening balance is itself a transaction so the balance stays a pure
    // function of the log. Positive = they owe (customer) / we owe (supplier);
    // negative = advance already paid.
    TransactionItem? opening;
    if (openingBalance != 0 && !openingBalance.isNaN) {
      final owes = openingBalance > 0;
      final debitType = type == ContactType.customer ? TransactionType.gave : TransactionType.got;
      final creditType = type == ContactType.customer ? TransactionType.got : TransactionType.gave;
      opening = TransactionItem(
        id: 'tx_init_$newId',
        customerId: newId,
        type: owes ? debitType : creditType,
        amount: openingBalance.abs(),
        note: owes ? 'পূর্বের প্রারম্ভিক বাকি' : 'পূর্বের অগ্রিম জমা',
        date: DateTime.now(),
      );
    }
    final stored = await _db.createContact(customer, opening: opening);
    await _refreshContact(newId, fresh: stored);
    return stored;
  }

  /// Replaces one contact in the in-memory lists and refreshes only the
  /// cheap derived queries (overdue + recent). One notify per operation.
  Future<void> refreshContact(String id) => _refreshContact(id);

  Future<void> _refreshContact(String id, {Customer? fresh}) async {
    final results = await Future.wait<Object?>([
      fresh != null ? Future.value(fresh) : _db.getCustomer(id),
      _db.getOverdueCustomers(days: 7),
      _db.getRecentTransactions(limit: 20),
    ]);
    final updated = results[0] as Customer?;
    _customers = _customers.where((c) => c.id != id).toList();
    _suppliers = _suppliers.where((c) => c.id != id).toList();
    if (updated != null) {
      (updated.isCustomer ? _customers : _suppliers).insert(0, updated);
    }
    _overdue = results[1] as List<Customer>;
    _recent = results[2] as List<TransactionItem>;
    _onDataChanged();
    notifyListeners();
  }

  /// Profile edit. The balance is re-read from the DB (never taken from the
  /// possibly stale [customer] object) so an edit can't clobber the ledger.
  Future<void> updateContact(Customer customer) async {
    final updated = customer.copyWith(updatedAt: DateTime.now());
    await _db.updateCustomer(updated);
    await _refreshContact(updated.id);
  }

  Future<void> deleteContact(Customer customer) async {
    await PhotoHelper.delete(customer.photoPath);
    await _db.deleteCustomer(customer.id);
    // New list instances so `context.select` on these lists sees the change.
    _customers = _customers.where((c) => c.id != customer.id).toList();
    _suppliers = _suppliers.where((c) => c.id != customer.id).toList();
    _overdue = _overdue.where((c) => c.id != customer.id).toList();
    _recent = _recent.where((t) => t.customerId != customer.id).toList();
    _onDataChanged();
    notifyListeners();
  }

  Future<TransactionItem> recordTransaction({
    required Customer customer,
    required TransactionType type,
    required double amount,
    required String note,
    required DateTime date,
    String? photoPath,
    String? memoId,
  }) async {
    final tx = TransactionItem(
      id: 'tx_${DateTime.now().millisecondsSinceEpoch}',
      customerId: customer.id,
      type: type,
      amount: amount,
      note: note.trim().isEmpty ? (type == TransactionType.gave ? 'বাকি' : 'জমা') : note.trim(),
      date: date,
      photoPath: photoPath,
      memoId: memoId,
    );
    // Insert + recompute happen in one SQLite transaction.
    final fresh = await _db.recordTransaction(tx);
    await _refreshContact(customer.id, fresh: fresh);
    return tx;
  }

  Future<void> updateTransaction(TransactionItem tx) async {
    await _db.updateTransaction(tx); // recomputes inside the DB transaction
    await _refreshContact(tx.customerId);
  }

  Future<void> deleteTransaction(TransactionItem tx) async {
    await PhotoHelper.delete(tx.photoPath);
    await _db.deleteTransaction(tx.id); // recomputes inside the DB transaction
    await _refreshContact(tx.customerId);
  }

  Future<List<TransactionItem>> getCustomerTransactions(String customerId, {int? limit, int? offset}) =>
      _db.getTransactions(customerId, limit: limit, offset: offset);
}
