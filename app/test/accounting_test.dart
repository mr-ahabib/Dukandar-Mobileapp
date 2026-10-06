import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:dukandar/core/database/app_database.dart';
import 'package:dukandar/core/utils/pdf_kit.dart';
import 'package:dukandar/core/utils/statement_pdf.dart';
import 'package:dukandar/models/cash_memo.dart';
import 'package:dukandar/models/customer.dart';
import 'package:dukandar/models/product.dart';
import 'package:dukandar/models/transaction_item.dart';
import 'package:dukandar/providers/billing_provider.dart';
import 'package:dukandar/providers/cash_drawer_provider.dart';
import 'package:dukandar/providers/ledger_provider.dart';

/// Money-path tests against a real (in-memory) SQLite database.
/// Definitions: lib/core/utils/money_rules.md
void main() {
  final db = AppDatabase.instance;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    AppDatabase.useInMemory = true;
  });

  // Fresh DB per test.
  setUp(() async => db.close());
  tearDownAll(() async => db.close());

  Future<Customer> addCustomer({String id = 'c1', ContactType type = ContactType.customer, double opening = 0}) async {
    final ledger = LedgerProvider();
    return ledger.addContact(id: id, name: 'কামাল', phone: '017', type: type, openingBalance: opening);
  }

  Future<TransactionItem> tx(Customer c, TransactionType t, double amount, {DateTime? date, String note = ''}) {
    return LedgerProvider().recordTransaction(customer: c, type: t, amount: amount, note: note, date: date ?? DateTime.now());
  }

  Future<double> balance(String id) async => (await db.getCustomer(id))!.currentBalance;

  group('a) memo arithmetic', () {
    CashMemo memo({double discount = 0, required double paid}) => CashMemo(
          id: 'm',
          memoNumber: '#MEMO-1001',
          customerName: 'x',
          customerPhone: '',
          items: [MemoItem(name: 'চাল', quantity: 10, unitPrice: 70), MemoItem(name: 'তেল', quantity: 2, unitPrice: 150)],
          discount: discount,
          paidAmount: paid,
          date: DateTime.now(),
        );

    test('subtotal, discount, grand total, partial due', () {
      final m = memo(paid: 300);
      expect(m.subtotal, 1000);
      expect(m.grandTotal, 1000);
      expect(m.dueAmount, 700);
      expect(m.cashReceived, 300);
      expect(m.changeAmount, 0);
      expect(m.isFullyPaid, isFalse);
      final d = memo(discount: 50, paid: 300);
      expect(d.grandTotal, 950);
      expect(d.dueAmount, 650);
    });

    test('পুরো টাকা → due 0; overpaid → due 0, change shown, cash kept = total', () {
      final full = memo(paid: 1000);
      expect(full.dueAmount, 0);
      expect(full.isFullyPaid, isTrue);
      final over = memo(paid: 1200);
      expect(over.dueAmount, 0, reason: 'never negative');
      expect(over.changeAmount, 200);
      expect(over.cashReceived, 1000);
    });

    test('createMemo validates inputs: discount ≤ subtotal, paid ≤ total, sequential numbers', () async {
      final billing = BillingProvider();
      final m1 = await billing.createMemo(
        customerName: '',
        customerPhone: '',
        items: [MemoItem(name: 'a', quantity: 1, unitPrice: 500)],
        discount: 900, // more than subtotal
        paidAmount: 10000, // more than total
      );
      expect(m1.discount, 500);
      expect(m1.grandTotal, 0);
      expect(m1.paidAmount, 0);
      expect(m1.customerName, 'সাধারণ ক্রেতা');
      expect(m1.memoNumber, '#MEMO-1001');
      final m2 = await billing.createMemo(
          customerName: 'র', customerPhone: '', items: [MemoItem(name: 'b', quantity: 2, unitPrice: 100)], discount: 0, paidAmount: 250);
      expect(m2.memoNumber, '#MEMO-1002');
      expect(m2.paidAmount, 200, reason: 'clamped to grand total');
      await billing.deleteMemo(m1);
      final m3 = await billing.createMemo(
          customerName: '', customerPhone: '', items: [MemoItem(name: 'c', quantity: 1, unitPrice: 1)], discount: 0, paidAmount: 1);
      expect(m3.memoNumber, '#MEMO-1003', reason: 'deleting never reuses a number');
      expect(() => billing.createMemo(customerName: '', customerPhone: '', items: [], discount: 0, paidAmount: 0), throwsArgumentError);
    });
  });

  group('b) memo → ledger', () {
    test('only the due is posted, linked by memo_id; balance = due', () async {
      final c = await addCustomer();
      final memo = await BillingProvider().createMemo(
        customerName: c.name,
        customerPhone: c.phone,
        customerId: c.id,
        items: [MemoItem(name: 'চাল', quantity: 10, unitPrice: 100)],
        discount: 0,
        paidAmount: 300,
        pushDueToLedger: true,
      );
      expect(memo.dueAmount, 700);
      final txs = await db.getTransactions(c.id);
      expect(txs.length, 1);
      expect(txs.single.type, TransactionType.gave);
      expect(txs.single.amount, 700);
      expect(txs.single.memoId, memo.id);
      expect(await balance(c.id), 700);
      // No `got` row for the paid part → collections stay 0.
      expect(await db.getCollectionsForDay(DateTime.now()), 0);
    });

    test('fully paid memo posts nothing; unticked checkbox posts nothing', () async {
      final c = await addCustomer();
      await BillingProvider().createMemo(
          customerName: c.name, customerPhone: '', customerId: c.id,
          items: [MemoItem(name: 'a', quantity: 1, unitPrice: 500)], discount: 0, paidAmount: 500, pushDueToLedger: true);
      await BillingProvider().createMemo(
          customerName: c.name, customerPhone: '', customerId: c.id,
          items: [MemoItem(name: 'a', quantity: 1, unitPrice: 500)], discount: 0, paidAmount: 0, pushDueToLedger: false);
      expect(await db.getTransactions(c.id), isEmpty);
      expect(await balance(c.id), 0);
    });

    test('deleting the memo reverses the ledger entry, recomputes balance, restores stock', () async {
      final c = await addCustomer(opening: 1000);
      await db.insertProduct(Product(id: 'p1', name: 'চাল', salePrice: 100, stock: 50, updatedAt: DateTime.now()));
      final billing = BillingProvider();
      final memo = await billing.createMemo(
        customerName: c.name, customerPhone: '', customerId: c.id,
        items: [MemoItem(name: 'চাল', quantity: 5, unitPrice: 100, productId: 'p1')],
        discount: 0, paidAmount: 100, pushDueToLedger: true,
      );
      expect(await balance(c.id), 1400);
      expect((await db.getProducts()).single.stock, 45);
      await billing.deleteMemo(memo);
      expect(await balance(c.id), 1000, reason: 'back to the opening balance');
      expect((await db.getTransactions(c.id)).where((t) => t.memoId != null), isEmpty);
      expect((await db.getProducts()).single.stock, 50);
      expect(await db.getMemoCount(), 0);
    });
  });

  group('c) ledger partial payments / advance', () {
    test('owes 1000, pays 400 → 600; pays 700 → −100 (advance)', () async {
      final c = await addCustomer();
      await tx(c, TransactionType.gave, 1000);
      await tx(c, TransactionType.got, 400);
      expect(await balance(c.id), 600);
      await tx(c, TransactionType.got, 700);
      expect(await balance(c.id), -100, reason: 'advance is kept as a negative balance, not clamped');

      final ledger = LedgerProvider();
      await ledger.loadData();
      expect(ledger.totalReceivables, 0, reason: 'negatives never sum into মোট পাওনা');
      expect(ledger.totalCustomerAdvances, 100);
      expect(ledger.dueCustomerCount, 0);
      expect(await db.getOverdueCustomers(days: 0), isEmpty);
    });

    test('supplier: got (goods on credit) raises payable, gave (we paid) lowers it', () async {
      final s = await addCustomer(id: 's1', type: ContactType.supplier);
      await tx(s, TransactionType.got, 5000);
      await tx(s, TransactionType.gave, 2000);
      expect(await balance(s.id), 3000);
      final ledger = LedgerProvider();
      await ledger.loadData();
      expect(ledger.totalPayables, 3000);
      expect(ledger.totalReceivables, 0);
    });

    test('overdue list only has positive balances older than the window', () async {
      final old = await addCustomer(id: 'old');
      await tx(old, TransactionType.gave, 500, date: DateTime.now().subtract(const Duration(days: 10)));
      final fresh = await addCustomer(id: 'fresh');
      await tx(fresh, TransactionType.gave, 500);
      final settled = await addCustomer(id: 'settled');
      await tx(settled, TransactionType.gave, 500, date: DateTime.now().subtract(const Duration(days: 20)));
      await tx(settled, TransactionType.got, 500, date: DateTime.now().subtract(const Duration(days: 15)));
      final overdue = await db.getOverdueCustomers(days: 7);
      expect(overdue.map((c) => c.id), ['old']);
    });
  });

  group('d) balance is always recomputed from transactions', () {
    test('opening balance is a transaction; update/delete recompute; profile edit cannot clobber', () async {
      final c = await addCustomer(opening: 250);
      final txs = await db.getTransactions(c.id);
      expect(txs.single.amount, 250);
      expect(await balance(c.id), 250);

      final ledger = LedgerProvider();
      await ledger.updateTransaction(txs.single.copyWith(amount: 400));
      expect(await balance(c.id), 400);

      // Stale object with the old balance must not overwrite the ledger.
      await ledger.updateContact(c.copyWith(name: 'নতুন নাম'));
      expect(await balance(c.id), 400);
      expect((await db.getCustomer(c.id))!.name, 'নতুন নাম');

      await ledger.deleteTransaction(txs.single);
      expect(await balance(c.id), 0);
    });

    test('negative opening balance = advance', () async {
      final c = await addCustomer(opening: -300);
      expect(await balance(c.id), -300);
      expect((await db.getTransactions(c.id)).single.type, TransactionType.got);
    });

    test('floating point dust is rounded away', () async {
      final c = await addCustomer();
      await tx(c, TransactionType.gave, 0.1);
      await tx(c, TransactionType.gave, 0.2);
      await tx(c, TransactionType.got, 0.3);
      expect(await balance(c.id), 0);
    });
  });

  group('e) today\'s figures', () {
    test('sales / cash sales / collections / supplier payments / net cash', () async {
      final c = await addCustomer();
      final s = await addCustomer(id: 's1', type: ContactType.supplier);
      final billing = BillingProvider();
      // Memo 1: 1000 total, 300 paid, due pushed to ledger.
      await billing.createMemo(
          customerName: c.name, customerPhone: '', customerId: c.id,
          items: [MemoItem(name: 'a', quantity: 10, unitPrice: 100)], discount: 0, paidAmount: 300, pushDueToLedger: true);
      // Memo 2: walk-in, 500 total, overpaid 600 → cash 500.
      await billing.createMemo(
          customerName: '', customerPhone: '', items: [MemoItem(name: 'b', quantity: 5, unitPrice: 100)], discount: 0, paidAmount: 600);
      // Customer pays 200 of the old due; we pay supplier 150; expense 50.
      await tx(c, TransactionType.got, 200);
      await tx(s, TransactionType.got, 1000);
      await tx(s, TransactionType.gave, 150);
      final cash = CashDrawerProvider();
      await cash.addExpense(title: 'চা', category: 'নাস্তা/চা', amount: 50);
      await cash.loadExpenses();

      expect(cash.totalSales, 1500, reason: 'আজ বিক্রি = Σ grand total');
      expect(cash.cashSales, 800, reason: 'নগদ বিক্রি = Σ paid (clamped), 300 + 500');
      expect(cash.creditSales, 700);
      expect(cash.collections, 200, reason: 'only ledger got from customers; memo cash is not a got row');
      expect(cash.supplierPayments, 150);
      expect(cash.totalExpense, 50);
      expect(cash.netCash, 800 + 200 - 50 - 150);

      final start = DateTime.now();
      final day0 = DateTime(start.year, start.month, start.day);
      expect(await db.getSalesForDay(day0), 1500);
      expect(await db.getCashSalesBetween(day0, day0.add(const Duration(days: 1))), 800);
      await billing.loadMemos();
      expect(billing.todaySales, 1500);
      expect(billing.todayCount, 2);
      expect(await balance(c.id), 500);
    });
  });

  group('e2) আজকের নগদ sign check (coordinator scenario)', () {
    test('memo paid 2000, collection 200, expense 770 → +1430; supplier gave 2000 → −570', () async {
      final c = await addCustomer();
      await BillingProvider().createMemo(
          customerName: c.name, customerPhone: '', customerId: c.id,
          items: [MemoItem(name: 'a', quantity: 1, unitPrice: 2500)], discount: 0, paidAmount: 2000, pushDueToLedger: true);
      await tx(c, TransactionType.got, 200);
      final cash = CashDrawerProvider();
      await cash.addExpense(title: 'x', category: 'অন্যান্য', amount: 770);
      await cash.loadExpenses();
      expect(cash.cashSales, 2000);
      expect(cash.collections, 200);
      expect(cash.totalExpense, 770);
      expect(cash.supplierPayments, 0);
      expect(cash.netCash, 1430, reason: 'cash in is positive, only expenses/supplier payments subtract');

      // Paying a supplier is the only other outflow; a customer `gave` (credit) never touches cash.
      final s = await addCustomer(id: 's', type: ContactType.supplier);
      await tx(s, TransactionType.gave, 2000);
      await tx(c, TransactionType.gave, 5000);
      await cash.loadExpenses();
      expect(cash.supplierPayments, 2000);
      expect(cash.netCash, 1430 - 2000);
      // Memo cash is counted once: no `got` row was created for the 2000.
      expect((await db.getTransactions(c.id)).where((t) => t.type == TransactionType.got).length, 1);
    });
  });

  group('f) statement running balance', () {
    test('matches ledger order and final balance (customer and supplier)', () async {
      final c = await addCustomer();
      final d0 = DateTime(2026, 1, 1);
      await tx(c, TransactionType.gave, 1000, date: d0);
      await tx(c, TransactionType.got, 400, date: d0.add(const Duration(days: 1)));
      await tx(c, TransactionType.gave, 250, date: d0.add(const Duration(days: 2)));
      await tx(c, TransactionType.got, 900, date: d0.add(const Duration(days: 3)));
      final cust = (await db.getCustomer(c.id))!;
      final rows = buildStatementRows(cust, await db.getTransactions(c.id)); // DB returns DESC; helper re-sorts
      expect(rows.map((r) => r.running).toList(), [1000, 600, 850, -50]);
      expect(rows.last.running, cust.currentBalance);
      expect(rows.map((r) => r.tx.date).toList(), rows.map((r) => r.tx.date).toList()..sort());

      final s = await addCustomer(id: 's', type: ContactType.supplier);
      await tx(s, TransactionType.got, 5000, date: d0);
      await tx(s, TransactionType.gave, 2000, date: d0.add(const Duration(days: 1)));
      final sup = (await db.getCustomer(s.id))!;
      final srows = buildStatementRows(sup, await db.getTransactions(s.id));
      expect(srows.map((r) => r.running).toList(), [5000, 3000]);
      expect(srows.last.running, sup.currentBalance);
    });

    test('PdfKit number formatting', () {
      expect(PdfKit.grouped(1234567), '12,34,567');
      expect(PdfKit.grouped(999), '999');
      expect(PdfKit.grouped(1000), '1,000');
      expect(PdfKit.grouped(72.5), '72.5');
      expect(PdfKit.grouped(-100), '-100');
      expect(PdfKit.toBangla('2026-10-04'), '২০২৬-১০-০৪');
    });
  });

  group('g) monthly flows', () {
    test('collected / credited / sales / expenses follow the same definitions', () async {
      final c = await addCustomer();
      final s = await addCustomer(id: 's', type: ContactType.supplier);
      final billing = BillingProvider();
      await billing.createMemo(
          customerName: c.name, customerPhone: '', customerId: c.id,
          items: [MemoItem(name: 'a', quantity: 1, unitPrice: 1000)], discount: 100, paidAmount: 400, pushDueToLedger: true);
      await tx(c, TransactionType.got, 150);
      await tx(s, TransactionType.got, 999); // supplier rows never count as customer flows
      await tx(s, TransactionType.gave, 10);
      await CashDrawerProvider().addExpense(title: 'x', category: 'অন্যান্য', amount: 80);

      final flows = await db.getMonthlyFlows(months: 2);
      expect(flows.length, 2);
      final now = flows.last;
      expect(now.month.month, DateTime.now().month);
      expect(now.sales, 900);
      expect(now.credited, 500, reason: 'memo due posted to the ledger counts as new credit');
      expect(now.collected, 150);
      expect(now.expenses, 80);
      expect(flows.first.sales, 0);
    });
  });

  group('h) legacy balance migration', () {
    test('stored balance without transactions is preserved; partial payment reduces it', () async {
      final c = Customer(
        id: 'legacy_1',
        name: 'সাইফুল',
        phone: '01800000000',
        type: ContactType.customer,
        currentBalance: 1400, // written directly by an old app version, no transactions
        updatedAt: DateTime.now(),
      );
      await db.insertCustomer(c);
      await db.reconcileLegacyBalances();
      expect(await db.recomputeBalance('legacy_1'), 1400);

      await db.insertTransaction(TransactionItem(
        id: 'pay_1',
        customerId: 'legacy_1',
        type: TransactionType.got,
        amount: 400,
        date: DateTime.now(),
      ));
      expect(await db.recomputeBalance('legacy_1'), 1000);
      // Running it again must not add another adjustment.
      await db.reconcileLegacyBalances();
      expect(await db.recomputeBalance('legacy_1'), 1000);
    });
  });
}
