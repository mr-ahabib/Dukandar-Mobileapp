import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../core/database/app_database.dart';
import '../core/utils/pdf_kit.dart';
import '../core/utils/perf.dart';
import '../models/cash_memo.dart';

/// Shop identity printed on memos.
class MemoBranding {
  final String shopName;
  final String shopPhone;
  final String shopAddress;
  final String footer;
  final String? logoPath;
  final bool banglaDigits;
  const MemoBranding({
    required this.shopName,
    required this.shopPhone,
    required this.shopAddress,
    this.footer = '',
    this.logoPath,
    this.banglaDigits = false,
  });

  PdfBranding toPdf() => PdfBranding(
        shopName: shopName,
        shopPhone: shopPhone,
        shopAddress: shopAddress,
        footer: footer,
        logoPath: logoPath,
        banglaDigits: banglaDigits,
      );
}

/// Memos grouped under a day label ("আজ", "গতকাল", …) in list order.
class MemoGroup {
  final String label;
  final List<CashMemo> memos;
  const MemoGroup(this.label, this.memos);
}

class BillingProvider extends ChangeNotifier {
  final AppDatabase _db = AppDatabase.instance;
  List<CashMemo> _memos = [];
  bool _isLoading = false;
  bool _loadedOnce = false;
  String _query = '';
  double _todaySales = 0;
  int _todayCount = 0;

  // Cached views, invalidated on data / query change (never built in build()).
  List<CashMemo>? _filtered;
  List<MemoGroup>? _groups;

  /// Most recent memos kept in memory (older ones stay in the DB).
  static const int recentLimit = 200;

  List<CashMemo> get memos => _filtered ??= _filter();

  /// Visible memos grouped by a day label (e.g. `relativeTimeBn`). Cached
  /// until the data or query changes so build() does no grouping work.
  List<MemoGroup> grouped(String Function(DateTime) label) => _groups ??= _group(memos, label);

  List<CashMemo> get allMemos => _memos;
  bool get isLoading => _isLoading;
  bool get loadedOnce => _loadedOnce;
  String get query => _query;

  List<CashMemo> _filter() {
    final q = _query;
    if (q.isEmpty) return _memos;
    return [
      for (final m in _memos)
        if (m.searchKey.contains(q) || m.customerPhone.contains(q)) m,
    ];
  }

  static List<MemoGroup> _group(List<CashMemo> list, String Function(DateTime) label) {
    final out = <MemoGroup>[];
    String? last;
    for (final m in list) {
      final key = label(m.date);
      if (key != last || out.isEmpty) {
        out.add(MemoGroup(key, []));
        last = key;
      }
      out.last.memos.add(m);
    }
    return out;
  }

  void _invalidate() {
    _filtered = null;
    _groups = null;
  }

  bool _isToday(DateTime d) {
    final n = DateTime.now();
    return d.year == n.year && d.month == n.month && d.day == n.day;
  }

  double get todaySales => _todaySales;
  int get todayCount => _todayCount;

  /// Loading is started by `AppBootstrap` after the first frame.
  BillingProvider();

  void setQuery(String q) {
    final norm = q.trim().toLowerCase();
    if (norm == _query) return;
    _query = norm;
    _invalidate();
    notifyListeners();
  }

  Future<void> ensureLoaded() => _loadedOnce || _isLoading ? Future.value() : loadMemos();

  Future<void> loadMemos() async {
    _isLoading = true;
    notifyListeners();
    final t = Perf.start('billing.load');
    try {
      final n = DateTime.now();
      final start = DateTime(n.year, n.month, n.day);
      final end = start.add(const Duration(days: 1));
      final results = await Future.wait<Object>([
        _db.getCashMemos(limit: recentLimit),
        _db.getSalesBetween(start, end),
        _db.getMemoCountBetween(start, end),
      ]);
      _memos = results[0] as List<CashMemo>;
      _todaySales = results[1] as double;
      _todayCount = results[2] as int;
      _invalidate();
      t.stop('${_memos.length} memos');
    } catch (e) {
      debugPrint('Error loading memos: $e');
    } finally {
      _isLoading = false;
      _loadedOnce = true;
      notifyListeners();
    }
  }

  /// Creates a memo. When [customerId] is given and [pushDueToLedger] is true,
  /// ONLY the unpaid amount (grand total − paid) is written to the ledger as a
  /// `gave` (বাকি) transaction linked by `memo_id`; the paid part never
  /// creates a ledger row, so it is not double counted with collections.
  /// Inputs are validated: discount is clamped to the subtotal and paid to
  /// the grand total (any excess is change handed back, not revenue).
  /// Stock is decremented for items linked to a product (inside the DB layer).
  Future<CashMemo> createMemo({
    required String customerName,
    required String customerPhone,
    String? customerId,
    required List<MemoItem> items,
    required double discount,
    required double paidAmount,
    bool pushDueToLedger = false,
    DateTime? date,
  }) async {
    if (items.isEmpty) throw ArgumentError('memo needs at least one item');
    final subtotal = items.fold(0.0, (s, i) => s + i.total);
    final safeDiscount = discount.isNaN ? 0.0 : discount.clamp(0.0, subtotal).toDouble();
    final grandTotal = subtotal - safeDiscount;
    final safePaid = paidAmount.isNaN ? 0.0 : paidAmount.clamp(0.0, grandTotal).toDouble();

    final memoNumber = await _db.nextMemoNumber();
    final memo = CashMemo(
      id: 'memo_${DateTime.now().microsecondsSinceEpoch}',
      memoNumber: memoNumber,
      customerName: customerName.trim().isEmpty ? 'সাধারণ ক্রেতা' : customerName.trim(),
      customerPhone: customerPhone.trim(),
      customerId: customerId,
      items: items,
      discount: safeDiscount,
      paidAmount: safePaid,
      date: date ?? DateTime.now(),
    );

    await _db.insertCashMemo(memo, postDueToLedger: pushDueToLedger && customerId != null);

    _memos.insert(0, memo);
    if (_memos.length > recentLimit) _memos.removeLast();
    if (_isToday(memo.date)) {
      _todaySales += memo.grandTotal;
      _todayCount += 1;
    }
    _invalidate();
    notifyListeners();
    return memo;
  }

  Future<void> deleteMemo(CashMemo memo) async {
    await _db.deleteCashMemo(memo.id);
    _memos.removeWhere((m) => m.id == memo.id);
    if (_isToday(memo.date)) {
      _todaySales = (_todaySales - memo.grandTotal).clamp(0, double.infinity);
      _todayCount = _todayCount > 0 ? _todayCount - 1 : 0;
    }
    _invalidate();
    notifyListeners();
  }

  // ------------------------------------------------------------------ PDF
  /// A5 invoice: header band, meta block, zebra items table, totals box with
  /// the due highlighted, footer with page numbers (multi-page safe).
  Future<Uint8List> generatePdfBytes(CashMemo memo, PdfBranding branding) async {
    final k = await PdfKit.load(branding);
    final hasDue = memo.dueAmount > 0;

    final pdf = pw.Document(title: 'ক্যাশ মেমো ${memo.memoNumber}', author: branding.shopName);
    pdf.addPage(pw.MultiPage(
      theme: k.theme,
      pageFormat: PdfPageFormat.a5,
      margin: const pw.EdgeInsets.fromLTRB(22, 20, 22, 22),
      footer: (ctx) => k.footer(ctx, text: branding.footer.isNotEmpty ? branding.footer : 'ধন্যবাদ! আবার আসবেন।'),
      build: (ctx) => [
        k.headerBand(docTitle: 'ক্যাশ মেমো', compact: true),
        pw.SizedBox(height: 10),
        k.metaBlock(
          leftTitle: 'ক্রেতা',
          left: [
            pw.Text(memo.customerName, style: k.ts(11, bold: true)),
            if (memo.customerPhone.isNotEmpty) pw.Text(k.digits(memo.customerPhone), style: k.ts(8.5, color: PdfKit.muted)),
          ],
          rightTitle: 'মেমো',
          right: [
            k.kv('নং', k.digits(memo.memoNumber), bold: true, size: 8.5),
            k.kv('তারিখ', k.date(memo.date), size: 8.5),
            k.kv('অবস্থা', hasDue ? 'বাকি আছে' : 'পরিশোধিত', color: hasDue ? PdfKit.coral : PdfKit.emerald, bold: true, size: 8.5),
          ],
        ),
        pw.SizedBox(height: 10),
        k.table(
          headers: const ['#', 'পণ্য', 'পরিমাণ', 'দর', 'মোট'],
          flex: const [0.5, 3.6, 1.3, 1.4, 1.7],
          alignRight: const [false, false, true, true, true],
          fontSize: 9,
          rows: [
            for (int i = 0; i < memo.items.length; i++)
              [
                k.digits('${i + 1}'),
                memo.items[i].name,
                k.num(memo.items[i].quantity),
                k.num(memo.items[i].unitPrice),
                k.num(memo.items[i].total),
              ],
          ],
        ),
        pw.SizedBox(height: 10),
        k.totalsBox([
          TotalLine('উপমোট', k.money(memo.subtotal)),
          if (memo.discount > 0) TotalLine('ডিসকাউন্ট', '− ${k.money(memo.discount)}'),
          TotalLine('সর্বমোট', k.money(memo.grandTotal), strong: true),
          TotalLine('নগদ জমা', k.money(memo.cashReceived), color: PdfKit.emerald),
          if (memo.changeAmount > 0) TotalLine('ফেরত', k.money(memo.changeAmount)),
          TotalLine(hasDue ? 'বাকি' : 'বাকি নেই', k.money(memo.dueAmount), strong: true, highlight: true, color: hasDue ? PdfKit.coral : PdfKit.emerald),
        ], width: 200),
        pw.SizedBox(height: 14),
        pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
          _signature(k, 'ক্রেতার স্বাক্ষর'),
          _signature(k, 'বিক্রেতার স্বাক্ষর'),
        ]),
      ],
    ));
    return pdf.save();
  }

  pw.Widget _signature(PdfKit k, String label) => pw.Column(children: [
        pw.Container(width: 110, height: 0.8, color: PdfKit.muted),
        pw.SizedBox(height: 3),
        pw.Text(label, style: k.ts(8, color: PdfKit.muted)),
      ]);

  Future<Uint8List> _bytes(CashMemo memo, MemoBranding b) => generatePdfBytes(memo, b.toPdf());

  Future<void> printMemo(CashMemo memo, MemoBranding b) async {
    final bytes = await _bytes(memo, b);
    await Printing.layoutPdf(onLayout: (_) async => bytes);
  }

  Future<void> shareMemo(CashMemo memo, MemoBranding b) async {
    final bytes = await _bytes(memo, b);
    await Printing.sharePdf(bytes: bytes, filename: '${memo.memoNumber.replaceAll('#', '')}.pdf');
  }
}
