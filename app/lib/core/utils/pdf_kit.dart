import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// Shop identity + formatting options shared by every PDF.
class PdfBranding {
  final String shopName;
  final String shopPhone;
  final String shopAddress;
  final String footer;
  final String? logoPath;
  final bool banglaDigits;
  const PdfBranding({
    required this.shopName,
    this.shopPhone = '',
    this.shopAddress = '',
    this.footer = '',
    this.logoPath,
    this.banglaDigits = false,
  });
}

/// One visual system for the memo, statement and monthly report:
/// green header band, document title block, zebra table with right-aligned
/// numbers, totals box with the due highlighted, footer with page numbers.
class PdfKit {
  PdfKit._(this.theme, this.logo, this.b);

  final pw.ThemeData theme;
  final pw.ImageProvider? logo;
  final PdfBranding b;

  // Palette mirrors AppTheme.
  static final navy = PdfColor.fromHex('#14532D');
  static final indigo = PdfColor.fromHex('#166534');
  static final mint = PdfColor.fromHex('#ECFDF5');
  static final sand = PdfColor.fromHex('#F1F5F2');
  static final hairline = PdfColor.fromHex('#E5EBE7');
  static final ink = PdfColor.fromHex('#0F1F17');
  static final muted = PdfColor.fromHex('#5B6B62');
  static final emerald = PdfColor.fromHex('#059669');
  static final coral = PdfColor.fromHex('#DC2626');
  static final coralSoft = PdfColor.fromHex('#FEF2F2');

  static const margin = pw.EdgeInsets.fromLTRB(28, 26, 28, 30);

  /// The two Bengali TTFs (~500 KB) are parsed once per process and reused
  /// by every memo / statement / report instead of on each PDF.
  static Future<pw.ThemeData>? _themeFuture;

  static Future<pw.ThemeData> _loadTheme() async {
    try {
      // Bundled fonts: identical to the app UI and fully offline.
      final bytes = await Future.wait([
        rootBundle.load('assets/fonts/NotoSansBengali-Regular.ttf'),
        rootBundle.load('assets/fonts/NotoSansBengali-Bold.ttf'),
      ]);
      final regular = pw.Font.ttf(bytes[0]);
      final bold = pw.Font.ttf(bytes[1]);
      return pw.ThemeData.withFont(base: regular, bold: bold, italic: regular, boldItalic: bold);
    } catch (e) {
      debugPrint('PDF font load error: $e');
      _themeFuture = null; // retry next time rather than caching the fallback
      return pw.ThemeData.base();
    }
  }

  /// Logo bytes cached by path + mtime so repeated prints don't re-read it.
  static String? _logoKey;
  static pw.ImageProvider? _logoCached;

  static Future<PdfKit> load(PdfBranding b) async {
    final theme = await (_themeFuture ??= _loadTheme());
    pw.ImageProvider? logo;
    final path = b.logoPath;
    if (path != null && path.isNotEmpty) {
      try {
        final f = File(path);
        if (await f.exists()) {
          final key = '$path@${(await f.lastModified()).millisecondsSinceEpoch}';
          if (_logoKey != key) {
            _logoCached = pw.MemoryImage(await f.readAsBytes());
            _logoKey = key;
          }
          logo = _logoCached;
        }
      } catch (_) {}
    }
    return PdfKit._(theme, logo, b);
  }

  // ------------------------------------------------------------ formatting
  static const _bn = ['০', '১', '২', '৩', '৪', '৫', '৬', '৭', '৮', '৯'];

  /// Converts ASCII digits to Bangla digits.
  static String toBangla(String s) {
    final sb = StringBuffer();
    for (final r in s.runes) {
      if (r >= 0x30 && r <= 0x39) {
        sb.write(_bn[r - 0x30]);
      } else {
        sb.writeCharCode(r);
      }
    }
    return sb.toString();
  }

  /// Plain number: integers without decimals, otherwise up to 2 decimals.
  static String plainNumber(double v) {
    final r = (v * 100).roundToDouble() / 100;
    final s = r == r.roundToDouble() ? r.toStringAsFixed(0) : r.toStringAsFixed(2).replaceFirst(RegExp(r'0+$'), '');
    return s;
  }

  /// 12,34,567 style grouping (Bangladeshi lakh grouping).
  static String grouped(double v) {
    final neg = v < 0;
    final s = plainNumber(v.abs());
    final parts = s.split('.');
    var intPart = parts[0];
    if (intPart.length > 3) {
      final last3 = intPart.substring(intPart.length - 3);
      var rest = intPart.substring(0, intPart.length - 3);
      final buf = <String>[];
      while (rest.length > 2) {
        buf.insert(0, rest.substring(rest.length - 2));
        rest = rest.substring(0, rest.length - 2);
      }
      if (rest.isNotEmpty) buf.insert(0, rest);
      intPart = '${buf.join(',')},$last3';
    }
    final out = parts.length > 1 ? '$intPart.${parts[1]}' : intPart;
    return neg ? '-$out' : out;
  }

  String digits(String s) => b.banglaDigits ? toBangla(s) : s;
  String num(double v) => digits(grouped(v));
  String money(double v) => '৳ ${num(v)}';
  String date(DateTime d) => digits('${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}');

  // --------------------------------------------------------------- widgets
  pw.TextStyle ts(double size, {bool bold = false, PdfColor? color}) =>
      pw.TextStyle(fontSize: size, fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal, color: color ?? ink);

  /// Green band: logo, shop name, address, phone; document title on the right.
  pw.Widget headerBand({required String docTitle, bool compact = false}) {
    final nameSize = compact ? 15.0 : 18.0;
    return pw.Container(
      padding: pw.EdgeInsets.symmetric(horizontal: compact ? 14 : 18, vertical: compact ? 12 : 16),
      decoration: pw.BoxDecoration(color: navy, borderRadius: pw.BorderRadius.circular(10)),
      child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.center, children: [
        if (logo != null) ...[
          pw.Container(
            width: compact ? 38 : 46,
            height: compact ? 38 : 46,
            decoration: pw.BoxDecoration(color: PdfColors.white, borderRadius: pw.BorderRadius.circular(8)),
            padding: const pw.EdgeInsets.all(3),
            child: pw.Image(logo!, fit: pw.BoxFit.contain),
          ),
          pw.SizedBox(width: 10),
        ],
        pw.Expanded(
          child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Text(b.shopName, style: ts(nameSize, bold: true, color: PdfColors.white)),
            if (b.shopAddress.isNotEmpty) pw.Text(b.shopAddress, style: ts(8.5, color: PdfColor.fromHex('#C8E6D3'))),
            if (b.shopPhone.isNotEmpty) pw.Text('ফোন: ${digits(b.shopPhone)}', style: ts(8.5, color: PdfColor.fromHex('#C8E6D3'))),
          ]),
        ),
        pw.Container(
          padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: pw.BoxDecoration(
            color: PdfColors.white,
            borderRadius: pw.BorderRadius.circular(6),
          ),
          child: pw.Text(docTitle, style: ts(compact ? 10 : 11, bold: true, color: navy)),
        ),
      ]),
    );
  }

  /// Small "label / value" pair used in meta blocks.
  pw.Widget kv(String k, String v, {bool bold = false, PdfColor? color, double size = 9.5}) =>
      pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 1.5),
        child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.SizedBox(width: 56, child: pw.Text(k, style: ts(size, color: muted))),
          pw.Expanded(child: pw.Text(v, style: ts(size, bold: bold, color: color))),
        ]),
      );

  /// Two-column meta block (customer on the left, document info on the right).
  pw.Widget metaBlock({required List<pw.Widget> left, required List<pw.Widget> right, String? leftTitle, String? rightTitle}) {
    pw.Widget col(String? title, List<pw.Widget> rows) => pw.Expanded(
          child: pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: pw.BoxDecoration(
              color: sand,
              borderRadius: pw.BorderRadius.circular(8),
            ),
            child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              if (title != null) ...[
                pw.Text(title, style: ts(8, bold: true, color: muted)),
                pw.SizedBox(height: 4),
              ],
              ...rows,
            ]),
          ),
        );
    return pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
      col(leftTitle, left),
      pw.SizedBox(width: 10),
      col(rightTitle, right),
    ]);
  }

  /// Zebra table. [aligns] true = right-aligned (numbers).
  pw.Widget table({
    required List<String> headers,
    required List<List<String>> rows,
    required List<double> flex,
    required List<bool> alignRight,
    List<List<PdfColor?>>? cellColors,
    double fontSize = 9.5,
  }) {
    pw.Widget cell(String s, {bool head = false, bool right = false, PdfColor? color, bool bold = false}) => pw.Padding(
          padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: pw.Text(
            s,
            textAlign: right ? pw.TextAlign.right : pw.TextAlign.left,
            style: ts(head ? fontSize - 0.5 : fontSize, bold: head || bold, color: head ? muted : (color ?? ink)),
          ),
        );
    return pw.Table(
      columnWidths: {for (int i = 0; i < flex.length; i++) i: pw.FlexColumnWidth(flex[i])},
      border: pw.TableBorder(
        bottom: pw.BorderSide(color: hairline, width: 0.8),
        horizontalInside: pw.BorderSide(color: hairline, width: 0.5),
      ),
      children: [
        pw.TableRow(
          decoration: pw.BoxDecoration(color: mint, borderRadius: const pw.BorderRadius.vertical(top: pw.Radius.circular(6))),
          children: [for (int i = 0; i < headers.length; i++) cell(headers[i], head: true, right: alignRight[i])],
        ),
        for (int r = 0; r < rows.length; r++)
          pw.TableRow(
            decoration: pw.BoxDecoration(color: r.isOdd ? sand : PdfColors.white),
            children: [
              for (int i = 0; i < rows[r].length; i++)
                cell(rows[r][i], right: alignRight[i], color: cellColors?[r][i], bold: cellColors?[r][i] != null),
            ],
          ),
      ],
    );
  }

  /// Totals box, right-aligned; the row flagged `highlight` gets a tinted band.
  pw.Widget totalsBox(List<TotalLine> lines, {double width = 230}) {
    return pw.Align(
      alignment: pw.Alignment.centerRight,
      child: pw.Container(
        width: width,
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: hairline, width: 0.8),
          borderRadius: pw.BorderRadius.circular(8),
        ),
        child: pw.ClipRRect(
          horizontalRadius: 8,
          verticalRadius: 8,
          child: pw.Column(children: [
            for (final l in lines)
              pw.Container(
                padding: pw.EdgeInsets.symmetric(horizontal: 12, vertical: l.strong ? 8 : 5),
                color: l.highlight ? (l.color == coral ? coralSoft : mint) : (l.strong ? sand : PdfColors.white),
                child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
                  pw.Text(l.label, style: ts(l.strong ? 11 : 9.5, bold: l.strong, color: l.strong ? ink : muted)),
                  pw.Text(l.value, style: ts(l.strong ? 12.5 : 10, bold: true, color: l.color ?? ink)),
                ]),
              ),
          ]),
        ),
      ),
    );
  }

  /// Page footer: footer text left, page x / y right.
  pw.Widget footer(pw.Context ctx, {String? text}) {
    final t = (text ?? '').isNotEmpty ? text! : 'দোকানদার অ্যাপ দিয়ে তৈরি';
    return pw.Container(
      padding: const pw.EdgeInsets.only(top: 8),
      decoration: pw.BoxDecoration(border: pw.Border(top: pw.BorderSide(color: hairline, width: 0.6))),
      child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
        pw.Expanded(child: pw.Text(t, style: ts(8, color: muted), maxLines: 2)),
        pw.SizedBox(width: 12),
        pw.Text('পৃষ্ঠা ${digits('${ctx.pageNumber}')} / ${digits('${ctx.pagesCount}')}', style: ts(8, color: muted)),
      ]),
    );
  }

  pw.Widget sectionTitle(String s) => pw.Padding(
        padding: const pw.EdgeInsets.only(top: 14, bottom: 6),
        child: pw.Row(children: [
          pw.Container(width: 3, height: 12, color: indigo),
          pw.SizedBox(width: 6),
          pw.Text(s, style: ts(11, bold: true)),
        ]),
      );
}

class TotalLine {
  final String label;
  final String value;
  final bool strong;
  final bool highlight;
  final PdfColor? color;
  const TotalLine(this.label, this.value, {this.strong = false, this.highlight = false, this.color});
}
