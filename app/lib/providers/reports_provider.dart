import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../core/database/app_database.dart';
import '../core/utils/pdf_kit.dart';
import '../core/utils/perf.dart';

/// Monthly/daily aggregates for the reports screen. Singleton (see ProductsProvider).
class ReportsProvider extends ChangeNotifier {
  static final ReportsProvider instance = ReportsProvider._();
  ReportsProvider._();

  final AppDatabase _db = AppDatabase.instance;

  List<DayAmount> dailySales = const [];
  List<MonthFlow> monthlyFlows = const [];
  Map<String, double> expensesByCategory = const {};
  DateTime selectedMonth = DateTime(DateTime.now().year, DateTime.now().month, 1);
  bool isLoading = false;
  bool _loadedOnce = false;
  bool get loadedOnce => _loadedOnce;

  double _last30Sales = 0;
  double _selectedMonthExpenses = 0;
  double get last30Sales => _last30Sales;
  double get selectedMonthExpenses => _selectedMonthExpenses;

  MonthFlow? get selectedFlow {
    for (final f in monthlyFlows) {
      if (f.month.year == selectedMonth.year && f.month.month == selectedMonth.month) return f;
    }
    return null;
  }

  Future<void> load() async {
    isLoading = true;
    notifyListeners();
    final t = Perf.start('reports.load');
    try {
      final results = await Future.wait<Object>([
        _db.getDailySales(days: 30),
        _db.getMonthlyFlows(months: 6),
        _db.getExpensesByCategory(selectedMonth),
      ]);
      dailySales = results[0] as List<DayAmount>;
      monthlyFlows = results[1] as List<MonthFlow>;
      expensesByCategory = results[2] as Map<String, double>;
      _last30Sales = dailySales.fold(0.0, (s, d) => s + d.amount);
      _selectedMonthExpenses = expensesByCategory.values.fold(0.0, (s, v) => s + v);
      t.stop();
    } catch (e) {
      debugPrint('Reports load error: $e');
    } finally {
      isLoading = false;
      _loadedOnce = true;
      notifyListeners();
    }
  }

  Future<void> setMonth(DateTime month) async {
    selectedMonth = DateTime(month.year, month.month, 1);
    await load();
  }

  static const List<String> bnMonths = [
    'জানুয়ারি', 'ফেব্রুয়ারি', 'মার্চ', 'এপ্রিল', 'মে', 'জুন',
    'জুলাই', 'আগস্ট', 'সেপ্টেম্বর', 'অক্টোবর', 'নভেম্বর', 'ডিসেম্বর',
  ];
  static const List<String> bnMonthsShort = [
    'জানু', 'ফেব্রু', 'মার্চ', 'এপ্রি', 'মে', 'জুন', 'জুলা', 'আগ', 'সেপ্ট', 'অক্টো', 'নভে', 'ডিসে',
  ];

  static String monthLabel(DateTime m) => '${bnMonths[m.month - 1]} ${m.year}';

  /// Monthly summary PDF (A4): summary table, 6-month flow table, expense
  /// breakdown, current receivables / payables.
  Future<Uint8List> buildMonthlyPdf({
    required PdfBranding branding,
    required double receivables,
    required double payables,
  }) async {
    final k = await PdfKit.load(branding);
    final flow = selectedFlow;
    final sales = flow?.sales ?? 0;
    final collected = flow?.collected ?? 0;
    final credited = flow?.credited ?? 0;
    final expenses = flow?.expenses ?? 0;
    final expTotal = selectedMonthExpenses;

    final pdf = pw.Document(title: 'মাসিক হিসাব ${monthLabel(selectedMonth)}', author: branding.shopName);
    pdf.addPage(pw.MultiPage(
      theme: k.theme,
      pageFormat: PdfPageFormat.a4,
      margin: PdfKit.margin,
      footer: (ctx) => k.footer(ctx, text: branding.footer),
      build: (ctx) => [
        k.headerBand(docTitle: 'মাসিক হিসাব'),
        pw.SizedBox(height: 12),
        k.metaBlock(
          leftTitle: 'মাস',
          left: [pw.Text(k.digits(monthLabel(selectedMonth)), style: k.ts(12, bold: true))],
          rightTitle: 'তৈরি',
          right: [k.kv('তারিখ', k.date(DateTime.now()))],
        ),
        k.sectionTitle('এই মাসের সারসংক্ষেপ'),
        k.table(
          headers: const ['খাত', 'ব্যাখ্যা', 'টাকা'],
          flex: const [2.2, 4.2, 1.8],
          alignRight: const [false, false, true],
          rows: [
            ['মোট বিক্রি', 'মেমোর সর্বমোট (নগদ + বাকি)', k.money(sales)],
            ['বাকি আদায়', 'খরিদ্দারদের কাছ থেকে জমা পাওয়া', k.money(collected)],
            ['নতুন বাকি', 'খরিদ্দারদের বাকিতে দেওয়া', k.money(credited)],
            ['মোট খরচ', 'ক্যাশ বাক্সে লেখা খরচ', k.money(expenses)],
          ],
          cellColors: [
            [null, null, null],
            [null, null, PdfKit.emerald],
            [null, null, PdfKit.coral],
            [null, null, PdfKit.coral],
          ],
        ),
        pw.SizedBox(height: 10),
        k.totalsBox([
          TotalLine('বর্তমান মোট পাওনা (খরিদ্দার)', k.money(receivables), color: PdfKit.coral),
          TotalLine('বর্তমান মোট দেনা (মহাজন)', k.money(payables)),
          TotalLine('নিট', k.money((receivables - payables).abs()), strong: true, highlight: true,
              color: receivables - payables >= 0 ? PdfKit.emerald : PdfKit.coral),
        ], width: 270),
        if (monthlyFlows.isNotEmpty) ...[
          k.sectionTitle('শেষ ${k.digits('${monthlyFlows.length}')} মাস'),
          k.table(
            headers: const ['মাস', 'বিক্রি', 'আদায়', 'নতুন বাকি', 'খরচ'],
            flex: const [2.2, 1.7, 1.7, 1.7, 1.7],
            alignRight: const [false, true, true, true, true],
            rows: [
              for (final f in monthlyFlows)
                [k.digits(monthLabel(f.month)), k.num(f.sales), k.num(f.collected), k.num(f.credited), k.num(f.expenses)],
            ],
          ),
        ],
        k.sectionTitle('খরচের খাত'),
        if (expensesByCategory.isEmpty)
          pw.Text('এই মাসে কোনো খরচ লেখা হয়নি', style: k.ts(10, color: PdfKit.muted))
        else
          k.table(
            headers: const ['খাত', 'অংশ', 'টাকা'],
            flex: const [4, 1.5, 2],
            alignRight: const [false, true, true],
            rows: [
              for (final e in expensesByCategory.entries)
                [e.key, '${k.digits((expTotal <= 0 ? 0 : (e.value / expTotal * 100)).round().toString())}%', k.money(e.value)],
              ['মোট', '', k.money(expTotal)],
            ],
            cellColors: [
              for (final _ in expensesByCategory.entries) [null, null, null],
              [PdfKit.ink, null, PdfKit.coral],
            ],
          ),
      ],
    ));
    return pdf.save();
  }

  Future<void> shareMonthlyPdf({
    required PdfBranding branding,
    required double receivables,
    required double payables,
  }) async {
    final bytes = await buildMonthlyPdf(branding: branding, receivables: receivables, payables: payables);
    await Printing.sharePdf(bytes: bytes, filename: 'report_${selectedMonth.year}_${selectedMonth.month}.pdf');
  }
}
