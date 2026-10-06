import 'package:intl/intl.dart';

class AppDateFormatter {
  static String formatShort(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final targetDate = DateTime(date.year, date.month, date.day);

    final timeStr = DateFormat('hh:mm a').format(date);

    if (targetDate == today) {
      return 'আজ, $timeStr';
    } else if (targetDate == today.subtract(const Duration(days: 1))) {
      return 'গতকাল, $timeStr';
    } else if (date.year == now.year) {
      return DateFormat('d MMM, hh:mm a').format(date);
    } else {
      return DateFormat('d MMM yyyy').format(date);
    }
  }

  static String formatDateOnly(DateTime date) {
    return DateFormat('dd/MM/yyyy').format(date);
  }
}
