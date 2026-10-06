import 'package:shared_preferences/shared_preferences.dart';

import '../../models/cash_memo.dart';
import '../../models/customer.dart';
import '../../models/daily_expense.dart';
import '../../models/product.dart';
import '../../models/transaction_item.dart';
import '../app_config.dart';
import '../database/app_database.dart';

/// Demo build support (`--dart-define=DUKANDAR_DEMO=true`).
///
/// In demo mode the app never talks to the server: the shop is a fixed demo
/// account, the licence is always active, tamper checks are skipped and the
/// local database is seeded once with realistic sample data.
class DemoMode {
  DemoMode._();

  static bool get enabled => AppConfig.isDemo;

  static const Map<String, dynamic> shop = {
    'id': 'demo-shop',
    'shop_name': 'বিসমিল্লাহ জেনারেল স্টোর',
    'owner_name': 'হাবিবুর রহমান',
    'phone': '01711223344',
    'address': 'দোকান নং ৪, বাজার রোড, ঢাকা',
    'plan': {'id': 'demo', 'name': 'স্ট্যান্ডার্ড', 'price_bdt': 300, 'period_days': 30},
  };

  static Map<String, dynamic> license() {
    final now = DateTime.now().toUtc();
    final paidUntil = now.add(const Duration(days: 23));
    return {
      'status': 'active',
      'plan_name': 'স্ট্যান্ডার্ড',
      'price_bdt': 300,
      'paid_until': paidUntil.toIso8601String(),
      'next_due_at': paidUntil.toIso8601String(),
      'days_left': 23,
      'grace_days': AppConfig.graceDays,
      'message_bn': 'ডেমো অ্যাকাউন্ট — সাবস্ক্রিপশন সক্রিয়।',
      'server_time': now.toIso8601String(),
      'device_locked': false,
      'features': ['ledger', 'billing', 'cash_drawer', 'reports', 'backup', 'drive'],
      'payment_info': {
        'bkash': '01700000000',
        'nagad': '01800000000',
        'instructions_bn': 'বিকাশ/নগদে Send Money করে ট্রানজেকশন আইডি অ্যাপে জমা দিন।',
        'support_phone': AppConfig.supportPhone,
      },
    };
  }

  /// Non-demo builds: if a demo build previously seeded this install (same
  /// package id), wipe that sample data so a real shopkeeper starts clean.
  static Future<void> purgeLeftovers() async {
    if (enabled) return;
    final prefs = await SharedPreferences.getInstance();
    if (!(prefs.getBool('demo_seeded_v1') ?? false)) return;
    final db = await AppDatabase.instance.database;
    await db.transaction((txn) async {
      for (final t in ['transactions', 'cash_memos', 'expenses', 'products', 'customers']) {
        await txn.delete(t);
      }
    });
    for (final k in ['shop_name', 'owner_name', 'phone', 'address', 'bkash_number', 'demo_seeded_v1']) {
      await prefs.remove(k);
    }
  }

  /// Seeds the local database once (idempotent via a preference flag).
  static Future<void> ensureSeeded() async {
    if (!enabled) return;
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool('demo_seeded_v1') ?? false) return;

    final db = AppDatabase.instance;
    final now = DateTime.now();
    DateTime ago(int days, [int hours = 0]) => now.subtract(Duration(days: days, hours: hours));

    // Shop profile for memos / settings.
    await prefs.setString('shop_name', shop['shop_name'] as String);
    await prefs.setString('owner_name', shop['owner_name'] as String);
    await prefs.setString('phone', shop['phone'] as String);
    await prefs.setString('address', shop['address'] as String);
    await prefs.setString('bkash_number', shop['phone'] as String);

    // Customers (opening balances are transactions, so recompute stays exact).
    final customers = <Customer, List<TransactionItem>>{};
    Customer c(String id, String name, String phone, String address, [ContactType type = ContactType.customer]) =>
        Customer(id: id, name: name, phone: phone, address: address, type: type, updatedAt: now);
    TransactionItem t(String id, String cid, TransactionType type, double amt, String note, DateTime d) =>
        TransactionItem(id: id, customerId: cid, type: type, amount: amt, note: note, date: d);

    final kamal = c('demo_c1', 'কামাল হোসেন', '01712345678', 'মেইন রোড, ঢাকা');
    customers[kamal] = [
      t('demo_t1', kamal.id, TransactionType.gave, 2500, 'মিনিকেট চাল ২৫ কেজি ও সয়াবিন তেল', ago(12)),
      t('demo_t2', kamal.id, TransactionType.got, 1000, 'বিকাশে নগদ জমা', ago(9)),
      t('demo_t3', kamal.id, TransactionType.gave, 1750, 'চিনি ও মসলা বাকি', ago(3)),
    ];
    final saiful = c('demo_c2', 'সাইফুল ইসলাম', '01898765432', 'বাজার গলি');
    customers[saiful] = [
      t('demo_t4', saiful.id, TransactionType.gave, 1400, 'ডাল, আটা ও ডিম', ago(15)),
      t('demo_t5', saiful.id, TransactionType.got, 400, 'নগদ জমা', ago(6)),
    ];
    final rina = c('demo_c3', 'রিনা বেগম', '01911223344', 'বাসা নং ১২');
    customers[rina] = [
      t('demo_t6', rina.id, TransactionType.gave, 860, 'সাবান, শ্যাম্পু, বিস্কুট', ago(8)),
    ];
    final rafiq = c('demo_c4', 'রফিকুল আলম', '01611002299', 'স্কুল রোড');
    customers[rafiq] = [
      t('demo_t7', rafiq.id, TransactionType.gave, 500, 'চা পাতা ও দুধ', ago(20)),
      t('demo_t8', rafiq.id, TransactionType.got, 500, 'পুরো টাকা পরিশোধ', ago(10)),
    ];
    final jamal = c('demo_c5', 'জামাল উদ্দিন', '01755667788', 'কলোনি গেট');
    customers[jamal] = [
      t('demo_t9', jamal.id, TransactionType.gave, 3200, 'মাসের বাজার', ago(1)),
    ];
    final supplier1 = c('demo_s1', 'মেসার্স বিসমিল্লাহ ট্রেডার্স', '01755443322', 'কাওরান বাজার', ContactType.supplier);
    customers[supplier1] = [
      t('demo_t10', supplier1.id, TransactionType.got, 18500, 'চাল ১০ বস্তা', ago(14)),
      t('demo_t11', supplier1.id, TransactionType.gave, 8000, 'নগদ পরিশোধ', ago(7)),
    ];
    final supplier2 = c('demo_s2', 'সোবহান ফুড ডিস্ট্রিবিউশন', '01611002200', 'চকবাজার', ContactType.supplier);
    customers[supplier2] = [
      t('demo_t12', supplier2.id, TransactionType.got, 4800, 'তেল ও চিনি', ago(5)),
    ];
    for (final entry in customers.entries) {
      await db.insertCustomer(entry.key);
      for (final tx in entry.value) {
        await db.insertTransaction(tx);
      }
      await db.recomputeBalance(entry.key.id);
    }

    // Products
    final products = [
      Product(id: 'demo_p1', name: 'মিনিকেট চাল', unit: 'কেজি', salePrice: 72, buyPrice: 66, stock: 180, lowStockAlert: 40, updatedAt: now),
      Product(id: 'demo_p2', name: 'সয়াবিন তেল', unit: 'লিটার', salePrice: 175, buyPrice: 163, stock: 36, lowStockAlert: 12, updatedAt: now),
      Product(id: 'demo_p3', name: 'চিনি', unit: 'কেজি', salePrice: 130, buyPrice: 122, stock: 8, lowStockAlert: 10, updatedAt: now),
      Product(id: 'demo_p4', name: 'মসুর ডাল', unit: 'কেজি', salePrice: 140, buyPrice: 128, stock: 25, lowStockAlert: 10, updatedAt: now),
      Product(id: 'demo_p5', name: 'ডিম', unit: 'হালি', salePrice: 52, buyPrice: 46, stock: 60, lowStockAlert: 20, updatedAt: now),
      Product(id: 'demo_p6', name: 'লাক্স সাবান', unit: 'পিস', salePrice: 65, buyPrice: 58, stock: 40, lowStockAlert: 10, updatedAt: now),
    ];
    for (final p in products) {
      await db.insertProduct(p);
    }

    // Memos (today + recent days) — stock is decremented by insertCashMemo.
    final memos = [
      CashMemo(
        id: 'demo_m1',
        memoNumber: '#MEMO-1001',
        customerName: 'কামাল হোসেন',
        customerPhone: '01712345678',
        customerId: kamal.id,
        items: [
          MemoItem(name: 'মিনিকেট চাল', quantity: 25, unitPrice: 72, productId: 'demo_p1'),
          MemoItem(name: 'সয়াবিন তেল', quantity: 5, unitPrice: 175, productId: 'demo_p2'),
        ],
        discount: 25,
        paidAmount: 2650,
        date: ago(0, 5),
      ),
      CashMemo(
        id: 'demo_m2',
        memoNumber: '#MEMO-1002',
        customerName: 'সাধারণ ক্রেতা',
        customerPhone: '',
        items: [
          MemoItem(name: 'ডিম', quantity: 2, unitPrice: 52, productId: 'demo_p5'),
          MemoItem(name: 'চিনি', quantity: 1, unitPrice: 130, productId: 'demo_p3'),
        ],
        paidAmount: 234,
        date: ago(0, 2),
      ),
      CashMemo(
        id: 'demo_m3',
        memoNumber: '#MEMO-1003',
        customerName: 'রিনা বেগম',
        customerPhone: '01911223344',
        customerId: rina.id,
        items: [
          MemoItem(name: 'মসুর ডাল', quantity: 2, unitPrice: 140, productId: 'demo_p4'),
          MemoItem(name: 'লাক্স সাবান', quantity: 3, unitPrice: 65, productId: 'demo_p6'),
        ],
        paidAmount: 475,
        date: ago(1, 3),
      ),
      CashMemo(
        id: 'demo_m4',
        memoNumber: '#MEMO-1004',
        customerName: 'সাধারণ ক্রেতা',
        customerPhone: '',
        items: [MemoItem(name: 'সয়াবিন তেল', quantity: 2, unitPrice: 175, productId: 'demo_p2')],
        paidAmount: 350,
        date: ago(2, 6),
      ),
    ];
    for (final m in memos) {
      await db.insertCashMemo(m);
    }

    // Expenses
    final expenses = [
      DailyExpense(id: 'demo_e1', title: 'দোকানের বিদ্যুৎ বিল', category: 'কারেন্ট বিল', amount: 650, date: ago(0, 6)),
      DailyExpense(id: 'demo_e2', title: 'স্টাফ সকালের নাস্তা', category: 'নাস্তা/চা', amount: 120, date: ago(0, 1)),
      DailyExpense(id: 'demo_e3', title: 'ভ্যান ভাড়া (মাল আনা)', category: 'অন্যান্য', amount: 300, date: ago(1, 4)),
      DailyExpense(id: 'demo_e4', title: 'দোকান ভাড়া', category: 'দোকান ভাড়া', amount: 8000, date: ago(3)),
    ];
    for (final e in expenses) {
      await db.insertExpense(e);
    }

    await prefs.setBool('demo_seeded_v1', true);
  }
}
