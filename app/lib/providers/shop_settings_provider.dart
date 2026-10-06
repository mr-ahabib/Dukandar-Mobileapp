import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/utils/currency_formatter.dart';
import '../core/utils/pdf_kit.dart';

class ShopSettingsProvider extends ChangeNotifier {
  /// Branding block handed to every PDF (memo, statement, monthly report).
  PdfBranding get pdfBranding => PdfBranding(
        shopName: _shopName,
        shopPhone: _phone,
        shopAddress: _address,
        footer: _memoFooter,
        logoPath: _showMemoLogo ? _logoPath : null,
        banglaDigits: _useBanglaDigits,
      );

  String _shopName = 'আমার দোকান';
  String _ownerName = '';
  String _phone = '';
  String _address = '';
  String _bkashNumber = '';
  String? _logoPath;
  String _memoFooter = 'আমাদের সাথে কেনাকাটা করার জন্য ধন্যবাদ। আবার আসবেন।';
  bool _showMemoLogo = true;
  bool _useBanglaDigits = false;
  bool _loaded = false;

  String get shopName => _shopName;
  String get ownerName => _ownerName;
  String get phone => _phone;
  String get address => _address;
  String get bkashNumber => _bkashNumber;
  String? get logoPath => _logoPath;
  String get memoFooter => _memoFooter;
  bool get showMemoLogo => _showMemoLogo;
  bool get useBanglaDigits => _useBanglaDigits;
  bool get isLoaded => _loaded;

  ShopSettingsProvider() {
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _shopName = prefs.getString('shop_name') ?? _shopName;
      _ownerName = prefs.getString('owner_name') ?? _ownerName;
      _phone = prefs.getString('phone') ?? _phone;
      _address = prefs.getString('address') ?? _address;
      _bkashNumber = prefs.getString('bkash_number') ?? _bkashNumber;
      _logoPath = prefs.getString('logo_path');
      _memoFooter = prefs.getString('memo_footer') ?? _memoFooter;
      _showMemoLogo = prefs.getBool('show_memo_logo') ?? true;
      _useBanglaDigits = prefs.getBool('bangla_digits') ?? false;
    } catch (e) {
      debugPrint('Settings load error: $e');
    }
    CurrencyFormatter.banglaDigits = _useBanglaDigits;
    _loaded = true;
    notifyListeners();
  }

  /// Fills blanks from the server profile after login (never overwrites edits).
  Future<void> prefillFromAuth({String? shopName, String? ownerName, String? phone}) async {
    bool changed = false;
    if ((_shopName.isEmpty || _shopName == 'আমার দোকান') && (shopName ?? '').isNotEmpty) {
      _shopName = shopName!;
      changed = true;
    }
    if (_ownerName.isEmpty && (ownerName ?? '').isNotEmpty) {
      _ownerName = ownerName!;
      changed = true;
    }
    if (_phone.isEmpty && (phone ?? '').isNotEmpty) {
      _phone = phone!;
      changed = true;
    }
    if (changed) await _persist();
  }

  Future<void> updateSettings({
    required String shopName,
    required String ownerName,
    required String phone,
    required String address,
    required String bkashNumber,
  }) async {
    _shopName = shopName.trim().isEmpty ? _shopName : shopName.trim();
    _ownerName = ownerName.trim();
    _phone = phone.trim();
    _address = address.trim();
    _bkashNumber = bkashNumber.trim();
    await _persist();
  }

  Future<void> setLogoPath(String? path) async {
    _logoPath = path;
    await _persist();
  }

  Future<void> updateMemoSettings({String? footer, bool? showLogo}) async {
    if (footer != null) _memoFooter = footer.trim();
    if (showLogo != null) _showMemoLogo = showLogo;
    await _persist();
  }

  Future<void> setBanglaDigits(bool value) async {
    _useBanglaDigits = value;
    CurrencyFormatter.banglaDigits = value;
    await _persist();
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final logo = _logoPath;
      // One platform round trip per key, all in flight together.
      await Future.wait<bool>([
        prefs.setString('shop_name', _shopName),
        prefs.setString('owner_name', _ownerName),
        prefs.setString('phone', _phone),
        prefs.setString('address', _address),
        prefs.setString('bkash_number', _bkashNumber),
        logo == null ? prefs.remove('logo_path') : prefs.setString('logo_path', logo),
        prefs.setString('memo_footer', _memoFooter),
        prefs.setBool('show_memo_logo', _showMemoLogo),
        prefs.setBool('bangla_digits', _useBanglaDigits),
      ]);
    } catch (e) {
      debugPrint('Settings save error: $e');
    }
    notifyListeners();
  }
}
