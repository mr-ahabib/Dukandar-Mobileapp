import 'package:intl/intl.dart';

class CurrencyFormatter {
  static final NumberFormat _enFormat = NumberFormat('#,##,##0', 'en_US');
  static final NumberFormat _enFormat2 = NumberFormat('#,##,##0.##', 'en_US');

  /// Global toggle (set from ShopSettingsProvider): render ০-৯ instead of 0-9.
  static bool banglaDigits = false;

  static const _bn = ['০', '১', '২', '৩', '৪', '৫', '৬', '৭', '৮', '৯'];

  static String digits(String s) {
    if (!banglaDigits) return s;
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

  /// Formats amount into clean Taka representation: ৳ 1,200
  /// Whole amounts show no decimals; fractional ones show up to 2.
  static String format(double amount, {bool includeSymbol = true}) {
    final isNegative = amount < 0;
    final absAmount = amount.abs();
    final rounded = (absAmount * 100).roundToDouble() / 100;
    final formattedNumber = digits(rounded == rounded.roundToDouble() ? _enFormat.format(rounded) : _enFormat2.format(rounded));
    final prefix = isNegative ? '-' : '';
    if (includeSymbol) {
      return '$prefix৳ $formattedNumber';
    }
    return '$prefix$formattedNumber';
  }

  /// Plain quantity / price number without grouping: 5, 2.5, 72.75
  static String number(double v) {
    final r = (v * 100).roundToDouble() / 100;
    return digits(r == r.roundToDouble() ? r.toStringAsFixed(0) : r.toStringAsFixed(2).replaceFirst(RegExp(r'0+$'), ''));
  }

  /// Compact format for large summaries: e.g. ৳ 45K or ৳ 1.2L
  static String formatCompact(double amount) {
    if (amount >= 100000) {
      return '৳ ${digits((amount / 100000).toStringAsFixed(1))}L';
    } else if (amount >= 1000) {
      return '৳ ${digits((amount / 1000).toStringAsFixed(1))}K';
    }
    return '৳ ${digits(amount.toStringAsFixed(0))}';
  }
}
