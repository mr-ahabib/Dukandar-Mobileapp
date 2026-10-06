import 'package:flutter/foundation.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../../models/customer.dart';
import '../../models/transaction_item.dart';
import 'pdf_kit.dart';

/// One statement line with its running balance (pure data; tested).
class StatementRow {
  final TransactionItem tx;
  final bool isDebit; // increases what the contact owes
  final double running;
  const StatementRow({required this.tx, required this.isDebit, required this.running});
}

/// Builds the rows oldest → newest. The running balance follows the ledger
/// convention (customer: gave − got, supplier: got − gave), so the last
/// value equals `recomputeBalance` for the same transactions.
List<StatementRow> buildStatementRows(Customer customer, List<TransactionItem> transactions) {
  final isCustomer = customer.type == ContactType.customer;
  final sorted = [...transactions]..sort((a, b) {
      final c = a.date.compareTo(b.date);
      return c != 0 ? c : a.id.compareTo(b.id);
    });
  double running = 0;
  final out = <StatementRow>[];
  for (final t in sorted) {
    final isDebit = isCustomer ? t.type == TransactionType.gave : t.type == TransactionType.got;
    running += isDebit ? t.amount : -t.amount;
    running = (running * 100).roundToDouble() / 100;
    out.add(StatementRow(tx: t, isDebit: isDebit, running: running));
  }
  return out;
}

/// Customer / supplier account statement (হিসাব বিবরণী) as an A4 PDF.
class StatementPdf {
  StatementPdf._();

  static Future<Uint8List> build({
    required Customer customer,
    required List<TransactionItem> transactions,
    required PdfBranding branding,
  }) async {
    final k = await PdfKit.load(branding);
    final isCustomer = customer.type == ContactType.customer;
    final rows = buildStatementRows(customer, transactions);
    final balance = rows.isEmpty ? customer.currentBalance : rows.last.running;

    double debitTotal = 0, creditTotal = 0;
    for (final r in rows) {
      if (r.isDebit) {
        debitTotal += r.tx.amount;
      } else {
        creditTotal += r.tx.amount;
      }
    }

    String runningLabel(double v) => v < 0 ? '${k.money(-v)} (অগ্রিম)' : k.money(v);
    final balanceLabel = balance > 0
        ? (isCustomer ? 'মোট বাকি (পাবেন)' : 'মোট দেনা (দেবেন)')
        : balance < 0
            ? (isCustomer ? 'অগ্রিম জমা আছে' : 'অগ্রিম দেওয়া আছে')
            : 'হিসাব পরিষ্কার';
    final balanceColor = balance > 0 ? PdfKit.coral : (balance < 0 ? PdfKit.emerald : PdfKit.muted);

    final debitHead = isCustomer ? 'বাকি দিলাম' : 'মাল পেলাম';
    final creditHead = isCustomer ? 'জমা পেলাম' : 'টাকা দিলাম';

    final pdf = pw.Document(title: 'হিসাব বিবরণী — ${customer.name}', author: branding.shopName);
    pdf.addPage(pw.MultiPage(
      theme: k.theme,
      pageFormat: PdfPageFormat.a4,
      margin: PdfKit.margin,
      footer: (ctx) => k.footer(ctx, text: branding.footer),
      build: (ctx) => [
        k.headerBand(docTitle: 'হিসাব বিবরণী'),
        pw.SizedBox(height: 12),
        k.metaBlock(
          leftTitle: isCustomer ? 'খরিদ্দার' : 'মহাজন',
          left: [
            pw.Text(customer.name, style: k.ts(12, bold: true)),
            if (customer.phone.isNotEmpty) pw.Text(k.digits(customer.phone), style: k.ts(9, color: PdfKit.muted)),
            if (customer.address.isNotEmpty) pw.Text(customer.address, style: k.ts(9, color: PdfKit.muted)),
          ],
          rightTitle: 'বিবরণী',
          right: [
            k.kv('তারিখ', k.date(DateTime.now())),
            k.kv('লেনদেন', '${k.digits('${rows.length}')} টি'),
            if (rows.isNotEmpty) k.kv('সময়কাল', '${k.date(rows.first.tx.date)} – ${k.date(rows.last.tx.date)}'),
          ],
        ),
        pw.SizedBox(height: 12),
        // Balance banner
        pw.Container(
          padding: const pw.EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: pw.BoxDecoration(
            color: balance > 0 ? PdfKit.coralSoft : PdfKit.mint,
            borderRadius: pw.BorderRadius.circular(8),
          ),
          child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
            pw.Text(balanceLabel, style: k.ts(11, bold: true)),
            pw.Text(k.money(balance.abs()), style: k.ts(15, bold: true, color: balanceColor)),
          ]),
        ),
        pw.SizedBox(height: 12),
        if (rows.isEmpty)
          pw.Padding(
            padding: const pw.EdgeInsets.all(20),
            child: pw.Center(child: pw.Text('এখনো কোনো লেনদেন নেই', style: k.ts(10, color: PdfKit.muted))),
          )
        else
          k.table(
            headers: ['তারিখ', 'বিবরণ', debitHead, creditHead, 'ব্যালেন্স'],
            flex: const [1.4, 3.6, 1.6, 1.6, 2.0],
            alignRight: const [false, false, true, true, true],
            rows: [
              for (final r in rows)
                [
                  k.date(r.tx.date),
                  r.tx.note.isEmpty ? (r.isDebit ? debitHead : creditHead) : r.tx.note,
                  r.isDebit ? k.num(r.tx.amount) : '',
                  r.isDebit ? '' : k.num(r.tx.amount),
                  runningLabel(r.running),
                ],
            ],
            cellColors: [
              for (final r in rows) [null, null, r.isDebit ? PdfKit.coral : null, r.isDebit ? null : PdfKit.emerald, null],
            ],
          ),
        pw.SizedBox(height: 14),
        k.totalsBox([
          TotalLine('মোট $debitHead', k.money(debitTotal), color: PdfKit.coral),
          TotalLine('মোট $creditHead', k.money(creditTotal), color: PdfKit.emerald),
          TotalLine(balanceLabel, k.money(balance.abs()), strong: true, highlight: true, color: balanceColor),
        ], width: 250),
      ],
    ));
    return pdf.save();
  }

  static Future<void> share({
    required Customer customer,
    required List<TransactionItem> transactions,
    required PdfBranding branding,
  }) async {
    final bytes = await build(customer: customer, transactions: transactions, branding: branding);
    final safe = customer.name.replaceAll(RegExp(r'[^\wঀ-৿]+'), '_');
    await Printing.sharePdf(bytes: bytes, filename: 'statement_$safe.pdf');
  }
}
