import 'package:url_launcher/url_launcher.dart';

class ReminderHelper {
  /// Makes a direct phone call to the customer/supplier
  static Future<bool> makePhoneCall(String phoneNumber) async {
    final cleanedNumber = phoneNumber.replaceAll(RegExp(r'\s+'), '');
    final uri = Uri.parse('tel:$cleanedNumber');
    if (await canLaunchUrl(uri)) {
      return await launchUrl(uri);
    }
    return false;
  }

  /// Sends a payment reminder via WhatsApp
  static Future<bool> sendWhatsAppReminder({
    required String phoneNumber,
    required String customerName,
    required double dueAmount,
    required String shopName,
  }) async {
    // Sanitize phone number (e.g., 01712345678 -> 8801712345678 if needed)
    String cleanNumber = phoneNumber.replaceAll(RegExp(r'[^0-9+]'), '');
    if (cleanNumber.startsWith('0')) {
      cleanNumber = '88$cleanNumber';
    } else if (cleanNumber.startsWith('+')) {
      cleanNumber = cleanNumber.substring(1);
    }

    final message =
        'আসসালামু আলাইকুম $customerName ভাই/আপা, $shopName-এ আপনার পূর্বের বাকি ৳ ${dueAmount.toStringAsFixed(0)} টাকা পরিশোধের অনুরোধ জানাচ্ছি। ধন্যবাদ।';

    final uri = Uri.parse('https://wa.me/$cleanNumber?text=${Uri.encodeComponent(message)}');
    if (await canLaunchUrl(uri)) {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
    return false;
  }

  /// Sends an SMS via the native messaging app
  static Future<bool> sendSmsReminder({
    required String phoneNumber,
    required String customerName,
    required double dueAmount,
    required String shopName,
  }) async {
    final message =
        'আসসালামু আলাইকুম $customerName, $shopName-এ আপনার বাকি ৳ ${dueAmount.toStringAsFixed(0)} টাকা পরিশোধের অনুরোধ জানাচ্ছি। ধন্যবাদ।';

    final uri = Uri.parse('sms:$phoneNumber?body=${Uri.encodeComponent(message)}');
    if (await canLaunchUrl(uri)) {
      return await launchUrl(uri);
    }
    return false;
  }
}
