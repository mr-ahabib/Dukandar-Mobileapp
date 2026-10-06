import 'dart:typed_data';

/// Everything collected across the 4 registration steps.
class RegistrationData {
  String shopName = '';
  String ownerName = '';
  String phone = '';
  String password = '';
  String address = '';
  String nidNumber = '';

  Uint8List? nidFront;
  Uint8List? nidBack;
  Uint8List? selfie;
  final List<Uint8List> livenessFrames = [];
  Map<String, dynamic>? liveness;

  bool get step1Done =>
      shopName.trim().isNotEmpty &&
      ownerName.trim().isNotEmpty &&
      isValidBdPhone(phone) &&
      password.length >= 6 &&
      isValidNid(nidNumber);
  bool get step2Done => nidFront != null && nidBack != null;
  bool get step3Done => selfie != null && liveness != null && liveness!['passed'] == true;

  /// Normalises `+8801…` / `8801…` / `01…` with spaces or dashes to `01XXXXXXXXX`.
  static String normalizePhone(String raw) {
    var s = raw.replaceAll(RegExp(r'[\s\-()]'), '');
    if (s.startsWith('+88')) s = s.substring(3);
    if (s.startsWith('88') && s.length == 13) s = s.substring(2);
    return s;
  }

  static bool isValidBdPhone(String raw) =>
      RegExp(r'^01[3-9]\d{8}$').hasMatch(normalizePhone(raw));

  static bool isValidNid(String raw) {
    final s = raw.replaceAll(RegExp(r'\D'), '');
    return s.length == 10 || s.length == 13 || s.length == 17;
  }
}
