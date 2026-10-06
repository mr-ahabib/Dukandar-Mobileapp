import 'package:flutter_test/flutter_test.dart';
import 'package:dukandar/core/utils/currency_formatter.dart';
import 'package:dukandar/models/cash_memo.dart';
import 'package:dukandar/models/customer.dart';
import 'package:dukandar/models/product.dart';
import 'package:dukandar/models/transaction_item.dart';
import 'package:dukandar/core/utils/voice_parser.dart';

void main() {
  group('CurrencyFormatter', () {
    test('formats positive amounts correctly', () {
      expect(CurrencyFormatter.format(1250), '৳ 1,250');
      expect(CurrencyFormatter.format(50000), '৳ 50,000');
    });
    test('formats zero correctly', () => expect(CurrencyFormatter.format(0), '৳ 0'));
    test('formats negative amounts correctly', () => expect(CurrencyFormatter.format(-500), '-৳ 500'));
    test('compact formatting works', () {
      expect(CurrencyFormatter.formatCompact(45000), '৳ 45.0K');
      expect(CurrencyFormatter.formatCompact(250000), '৳ 2.5L');
    });
  });

  group('CashMemo math', () {
    test('calculates subtotal, grand total, and due correctly', () {
      final memo = CashMemo(
        id: 'test_1',
        memoNumber: '#MEMO-1',
        customerName: 'করিম',
        customerPhone: '01700000000',
        items: [MemoItem(name: 'চাল', quantity: 2, unitPrice: 70), MemoItem(name: 'ডাল', quantity: 1, unitPrice: 120)],
        discount: 20,
        paidAmount: 200,
        date: DateTime.now(),
      );
      expect(memo.subtotal, 260.0);
      expect(memo.grandTotal, 240.0);
      expect(memo.dueAmount, 40.0);
      expect(memo.isFullyPaid, isFalse);
    });

    test('round-trips customer_id and product_id through maps', () {
      final memo = CashMemo(
        id: 'm',
        memoNumber: '#MEMO-2',
        customerName: 'রহিম',
        customerPhone: '',
        customerId: 'c_1',
        items: [MemoItem(name: 'তেল', quantity: 5, unitPrice: 180, productId: 'p_1')],
        paidAmount: 900,
        date: DateTime(2026, 10, 4),
      );
      final back = CashMemo.fromMap(memo.toMap());
      expect(back.customerId, 'c_1');
      expect(back.items.first.productId, 'p_1');
      expect(back.dueAmount, 0.0);
    });
  });

  group('Models', () {
    test('Customer map round trip incl. photo & note', () {
      final c = Customer(
        id: 'c_test',
        name: 'শফিক হাসান',
        phone: '01912345678',
        address: 'ঢাকা',
        type: ContactType.customer,
        currentBalance: 1500.0,
        updatedAt: DateTime(2026, 10, 4),
        photoPath: '/tmp/photos/c_test.jpg',
        note: 'শুক্রবারে টাকা দেয়',
      );
      final back = Customer.fromMap(c.toMap());
      expect(back.id, c.id);
      expect(back.photoPath, c.photoPath);
      expect(back.note, c.note);
      expect(back.copyWith(clearPhoto: true).photoPath, isNull);
    });

    test('TransactionItem keeps memo & photo links', () {
      final t = TransactionItem(id: 't', customerId: 'c', type: TransactionType.gave, amount: 10, date: DateTime(2026), memoId: 'm1', photoPath: 'x.jpg');
      final back = TransactionItem.fromMap(t.toMap());
      expect(back.memoId, 'm1');
      expect(back.photoPath, 'x.jpg');
    });

    test('Product low stock flag', () {
      final p = Product(id: 'p', name: 'চাল', salePrice: 72, stock: 4, lowStockAlert: 5, updatedAt: DateTime(2026));
      expect(p.isLowStock, isTrue);
      expect(p.copyWith(stock: 50).isLowStock, isFalse);
      expect(Product.fromMap(p.toMap()).unit, 'পিস');
    });
  });

  group('VoiceParser numbers', () {
    test('Bangla digits and number words', () {
      expect(VoiceParser.normalizeNumbers('৮০ টাকা'), '80 টাকা');
      expect(VoiceParser.normalizeNumbers('দেড়শ টাকা'), '150 টাকা');
      expect(VoiceParser.normalizeNumbers('আড়াইশ'), '250');
      expect(VoiceParser.normalizeNumbers('সাড়ে তিনশ টাকা'), '350 টাকা');
      expect(VoiceParser.normalizeNumbers('দুই হাজার পাঁচশ'), '2500');
      expect(VoiceParser.normalizeNumbers('পাঁচ হাজার'), '5000');
      expect(VoiceParser.normalizeNumbers('এক লাখ'), '100000');
      expect(VoiceParser.normalizeNumbers('সাড়ে পাঁচ কেজি'), '5.5 কেজি');
      expect(VoiceParser.normalizeNumbers('পঁচিশ কেজি'), '25 কেজি');
    });
  });

  group('VoiceParser memo items', () {
    test('parses Bengali quantity, unit, name, and price', () {
      final res = VoiceParser.parse('১ কেজি চিনি ৮০ টাকা');
      expect(res.quantity, 1.0);
      expect(res.unitPrice, 80.0);
      expect(res.unit, 'কেজি');
      expect(res.itemName.contains('চিনি'), isTrue);
    });
    test('parses rice 25kg 70 taka', () {
      final res = VoiceParser.parse('মিনিকেট চাল ২৫ কেজি ৭০ টাকা');
      expect(res.quantity, 25.0);
      expect(res.unitPrice, 70.0);
      expect(res.itemName.contains('মিনিকেট চাল'), isTrue);
    });
    test('parses soap 2 pcs 50 taka', () {
      final res = VoiceParser.parse('২ টা লাক্স সাবান ৫০ টাকা');
      expect(res.quantity, 2.0);
      expect(res.unitPrice, 50.0);
      expect(res.unit, 'পিস');
      expect(res.itemName.contains('লাক্স সাবান'), isTrue);
    });
    test('eggs 10 pcs at 12 each (price after unit)', () {
      final res = VoiceParser.parse('ডিম ১০ টা ১২ টাকা করে');
      expect(res.quantity, 10.0);
      expect(res.unitPrice, 12.0);
      expect(res.total, 120.0);
    });
    test('number words: দেড় কেজি পেঁয়াজ একশ টাকা', () {
      final res = VoiceParser.parse('দেড় কেজি পেঁয়াজ একশ টাকা');
      expect(res.quantity, 1.5);
      expect(res.unitPrice, 100.0);
    });
  });

  group('VoiceParser ledger', () {
    test('কামালকে ৫০০ টাকা বাকি দিলাম', () {
      final r = VoiceParser.parseLedger('কামালকে ৫০০ টাকা বাকি দিলাম');
      expect(r.customerName, 'কামাল');
      expect(r.intent, VoiceIntent.gave);
      expect(r.amount, 500);
    });
    test('রহিম ২০০ টাকা জমা দিলো', () {
      final r = VoiceParser.parseLedger('রহিম ২০০ টাকা জমা দিলো');
      expect(r.customerName, 'রহিম');
      expect(r.intent, VoiceIntent.got);
      expect(r.amount, 200);
    });
    test('দেড়শ টাকা পেলাম সাইফুলের কাছ থেকে', () {
      final r = VoiceParser.parseLedger('দেড়শ টাকা পেলাম সাইফুলের কাছ থেকে');
      expect(r.intent, VoiceIntent.got);
      expect(r.amount, 150);
      expect(r.customerName, 'সাইফুল');
    });
    test('note keeps the items', () {
      final r = VoiceParser.parseLedger('করিমকে চাল তেল ৭০০ টাকা বাকি দিলাম');
      expect(r.note.contains('চাল'), isTrue);
      expect(r.note.contains('তেল'), isTrue);
      expect(r.note.contains('700'), isFalse);
    });
  });

  group('VoiceParser expense / contact / product', () {
    test('expense: বিদ্যুৎ বিল ৬৫০ টাকা', () {
      final r = VoiceParser.parseExpense('বিদ্যুৎ বিল ৬৫০ টাকা');
      expect(r.amount, 650);
      expect(r.category, 'কারেন্ট বিল');
    });
    test('expense: চা নাস্তা একশ বিশ টাকা', () {
      final r = VoiceParser.parseExpense('চা নাস্তা একশ বিশ টাকা');
      expect(r.amount, 120);
      expect(r.category, 'নাস্তা/চা');
    });
    test('contact: name + phone digits', () {
      final r = VoiceParser.parseContact('কামাল হোসেন ০১৭১২৩৪৫৬৭৮');
      expect(r.name, 'কামাল হোসেন');
      expect(r.phone, '01712345678');
    });
    test('contact: spaced phone digits', () {
      final r = VoiceParser.parseContact('রহিম 017 1234 5678');
      expect(r.phone, '01712345678');
      expect(r.name, 'রহিম');
    });
    test('product: মিনিকেট চাল কেজি ৭২ টাকা স্টক ৫০', () {
      final r = VoiceParser.parseProduct('মিনিকেট চাল কেজি ৭২ টাকা স্টক ৫০');
      expect(r.name, 'মিনিকেট চাল');
      expect(r.unit, 'কেজি');
      expect(r.price, 72);
      expect(r.stock, 50);
    });
  });
}
