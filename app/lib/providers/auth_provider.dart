import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

import '../core/demo/demo_mode.dart';

import '../core/kyc/image_utils.dart';
import '../core/kyc/registration_data.dart';
import '../core/network/api_client.dart';
import '../core/notifications/notification_service.dart';
import '../core/security/security_gate.dart';
import '../core/storage/secure_store.dart';
import 'license_provider.dart';

/// Login state + shop identity returned by the server.
///
/// Tokens / shop / license are persisted in [SecureStore]. License updates
/// are pushed to [LicenseProvider.shared] (set by LicenseProvider itself,
/// which main.dart creates first) so no wiring in main.dart is needed.
class AuthProvider extends ChangeNotifier {
  AuthProvider({SecureStore? store, ApiClient? api})
      : _store = store ?? SecureStore.instance,
        _api = api ?? ApiClient.instance {
    _api.onSessionExpired = _onSessionExpired;
  }

  final SecureStore _store;
  final ApiClient _api;

  bool _bootstrapping = true;
  bool _loggedIn = false;
  bool _loggingIn = false;
  Map<String, dynamic>? _shop;
  Map<String, dynamic>? _license;
  String? _deviceId;

  bool get isBootstrapping => _bootstrapping;
  bool get isLoggedIn => _loggedIn;
  bool get isLoggingIn => _loggingIn;
  Map<String, dynamic>? get shop => _shop;

  /// License map from the last login/refresh response.
  Map<String, dynamic>? get license => _license;
  String? get deviceId => _deviceId;

  String get shopName => _shop?['shop_name'] as String? ?? '';
  String get ownerName => _shop?['owner_name'] as String? ?? '';
  String get phone => _shop?['phone'] as String? ?? '';
  String get address => _shop?['address'] as String? ?? '';
  Map<String, dynamic>? get plan => _shop?['plan'] as Map<String, dynamic>?;

  // -------------------------------------------------------------------
  // Bootstrap
  // -------------------------------------------------------------------

  Future<void> bootstrap() async {
    if (DemoMode.enabled) {
      _shop = Map<String, dynamic>.from(DemoMode.shop);
      _license = DemoMode.license();
      _loggedIn = true;
      _bootstrapping = false;
      notifyListeners();
      unawaited(LicenseProvider.shared?.applyLicense(_license!));
      return;
    }
    try {
      final token = await _store.accessToken;
      _shop = await _store.shop;
      _license = await _store.license;
      _deviceId = await _store.deviceId(candidate: await _androidId());
      _loggedIn = token != null &&
          token.isNotEmpty &&
          _shop != null &&
          _shop!['shop_name'] != null;
    } catch (_) {
      _loggedIn = false;
    } finally {
      _bootstrapping = false;
      notifyListeners();
    }

    if (_loggedIn) {
      unawaited(NotificationService.instance.init());
      unawaited(_refreshLicenseInBackground());
    }
  }

  Future<void> _refreshLicenseInBackground() async {
    final lp = LicenseProvider.shared;
    if (lp != null) {
      // Forced: admin broadcasts / KYC verdicts must show up on launch.
      await lp.refresh(force: true);
      _license = lp.raw ?? _license;
    } else {
      try {
        final lic = await _api.get('/app/license');
        if (lic is Map<String, dynamic>) {
          _license = lic;
          await _store.saveLicense(lic);
          unawaited(NotificationService.instance.scheduleFromLicense(lic));
        }
      } catch (_) {}
    }
    // Shop may have been refreshed via /app/me.
    _shop = await _store.shop ?? _shop;
    notifyListeners();
  }

  // -------------------------------------------------------------------
  // Device info
  // -------------------------------------------------------------------

  Future<String?> _androidId() async {
    if (kIsWeb || !Platform.isAndroid) return null;
    try {
      final info = await DeviceInfoPlugin().androidInfo;
      final id = info.id;
      if (id.isEmpty || id == 'unknown' || id == '9774d56d682e549c') {
        return null;
      }
      return id;
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>> _deviceInfo() async {
    String model = 'Unknown';
    String os = Platform.operatingSystem;
    String appVersion = '';
    try {
      if (!kIsWeb && Platform.isAndroid) {
        final a = await DeviceInfoPlugin().androidInfo;
        model = '${a.manufacturer} ${a.model}'.trim();
        os = 'Android ${a.version.release}';
      } else if (!kIsWeb && Platform.isIOS) {
        final i = await DeviceInfoPlugin().iosInfo;
        model = i.utsname.machine;
        os = 'iOS ${i.systemVersion}';
      }
    } catch (_) {}
    try {
      final p = await PackageInfo.fromPlatform();
      appVersion = p.version;
    } catch (_) {}
    _deviceId ??= await _store.deviceId(candidate: await _androidId());
    return {
      'device_id': _deviceId,
      'model': model,
      'os': os,
      'app_version': appVersion,
      'signature_sha256': SecurityGate.shared?.signatureSha256 ?? '',
    };
  }

  // -------------------------------------------------------------------
  // Login / logout
  // -------------------------------------------------------------------

  /// Returns null on success, otherwise a Bangla error message.
  Future<String?> login(String phone, String password) async {
    final cleanPhone = phone.trim().replaceAll(RegExp(r'[\s-]'), '');
    if (cleanPhone.isEmpty || password.isEmpty) {
      return 'ফোন নম্বর ও পাসওয়ার্ড দিন।';
    }
    if (_loggingIn) return null;
    _loggingIn = true;
    notifyListeners();
    try {
      final device = await _deviceInfo();
      final res = await _api.post(
        '/app/auth/login',
        auth: false,
        body: {
          'phone': cleanPhone,
          'password': password,
          'device': device,
        },
      );
      if (res is! Map<String, dynamic> || res['access_token'] == null) {
        return 'সার্ভার থেকে সঠিক উত্তর পাওয়া যায়নি।';
      }
      await _applySession(res);
      return null;
    } on ApiException catch (e) {
      switch (e.statusCode) {
        case 423:
          // Device locked server-side; remember the phone for tamper APIs.
          await _store.saveShop({'phone': cleanPhone});
          final id = e.detail?['unlock_request_id'] as String?;
          final hint = e.detail?['hint'] as String?;
          await SecurityGate.shared
              ?.lockFromServer(unlockRequestId: id, hint: hint);
          return 'এই ডিভাইসটি নিরাপত্তার কারণে লক করা আছে।';
        case 409:
          return 'অন্য ফোনে লগইন আছে, অ্যাডমিনের সাথে যোগাযোগ করুন।';
        case 401:
          return 'ফোন নম্বর বা পাসওয়ার্ড ভুল।';
        case 403:
          return e.messageBn.isNotEmpty
              ? e.messageBn
              : 'এই অ্যাকাউন্টটি বন্ধ করা হয়েছে। সাপোর্টে যোগাযোগ করুন।';
        default:
          return e.messageBn;
      }
    } catch (e) {
      return 'লগইন করা যায়নি। আবার চেষ্টা করুন।';
    } finally {
      _loggingIn = false;
      notifyListeners();
    }
  }

  /// POST /app/auth/register (multipart). Returns null on success (session
  /// persisted exactly like login; license will be `pending_verification`),
  /// otherwise a Bangla error message.
  Future<String?> register(RegistrationData d) async {
    if (DemoMode.enabled) return 'ডেমো মোডে অ্যাকাউন্ট খোলা যায় না।';
    if (_loggingIn) return null;
    final front = d.nidFront;
    final back = d.nidBack;
    final selfie = d.selfie;
    final liveness = d.liveness;
    if (front == null || back == null || selfie == null || liveness == null) {
      return 'সব ধাপ শেষ করুন।';
    }
    if (!await ApiClient.isOnline()) {
      return 'ইন্টারনেট সংযোগ নেই। অ্যাকাউন্ট খুলতে ইন্টারনেট লাগবে।';
    }
    _loggingIn = true;
    notifyListeners();
    try {
      final device = await _deviceInfo();
      final files = <http.MultipartFile>[
        ApiClient.fileFromBytes('nid_front', front,
            filename: 'nid_front.${KycImageUtils.extOf(front)}',
            mimeType: KycImageUtils.mimeOf(front)),
        ApiClient.fileFromBytes('nid_back', back,
            filename: 'nid_back.${KycImageUtils.extOf(back)}',
            mimeType: KycImageUtils.mimeOf(back)),
        ApiClient.fileFromBytes('selfie', selfie,
            filename: 'selfie.${KycImageUtils.extOf(selfie)}',
            mimeType: KycImageUtils.mimeOf(selfie)),
      ];
      for (var i = 0; i < d.livenessFrames.length && i < 3; i++) {
        final f = d.livenessFrames[i];
        files.add(ApiClient.fileFromBytes('liveness_frames[]', f,
            filename: 'frame_$i.${KycImageUtils.extOf(f)}',
            mimeType: KycImageUtils.mimeOf(f)));
      }
      final res = await _api.postMultipart(
        '/app/auth/register',
        fields: {
          'shop_name': d.shopName.trim(),
          'owner_name': d.ownerName.trim(),
          'phone': RegistrationData.normalizePhone(d.phone),
          'password': d.password,
          'address': d.address.trim(),
          'nid_number': d.nidNumber.replaceAll(RegExp(r'\D'), ''),
          'device': jsonEncode(device),
          'liveness': jsonEncode(liveness),
        },
        files: files,
      );
      if (res is! Map<String, dynamic> || res['access_token'] == null) {
        return 'সার্ভার থেকে সঠিক উত্তর পাওয়া যায়নি।';
      }
      await _applySession(res);
      return null;
    } on ApiException catch (e) {
      switch (e.statusCode) {
        case 409:
          return 'এই নম্বরে আগে থেকেই অ্যাকাউন্ট আছে — লগইন করুন';
        case 413:
          return 'ছবির সাইজ অনেক বড়। আবার ছবি তুলুন।';
        case 422:
          // Prefer the server's field-level reasons; fall back to a generic hint.
          final m = e.messageBn;
          return m.isNotEmpty && m != 'তথ্য সঠিকভাবে পূরণ করুন।'
              ? m
              : 'তথ্য সঠিক নয়। ফোন নম্বর, NID নম্বর, পাসওয়ার্ড ও ফেস যাচাই আবার দেখুন।';
        case 429:
          return 'অনেকবার চেষ্টা করা হয়েছে। এক ঘণ্টা পরে আবার চেষ্টা করুন।';
        default:
          return e.messageBn;
      }
    } catch (e) {
      return 'অ্যাকাউন্ট খোলা যায়নি। আবার চেষ্টা করুন।';
    } finally {
      _loggingIn = false;
      notifyListeners();
    }
  }

  Future<void> _applySession(Map<String, dynamic> res) async {
    await _store.saveTokens(
      access: res['access_token'] as String,
      refresh: (res['refresh_token'] as String?) ?? '',
    );
    final shop = res['shop'];
    if (shop is Map<String, dynamic>) {
      _shop = shop;
      await _store.saveShop(shop);
    }
    final lic = res['license'];
    if (lic is Map<String, dynamic>) {
      _license = lic;
      final lp = LicenseProvider.shared;
      if (lp != null) {
        await lp.applyLicense(lic);
      } else {
        await _store.saveLicense(lic);
        unawaited(NotificationService.instance.scheduleFromLicense(lic));
      }
    }
    _loggedIn = true;
    notifyListeners();
    unawaited(NotificationService.instance.requestPermission());
    // Pull notifications in the background.
    final lp = LicenseProvider.shared;
    if (lp != null) unawaited(lp.refresh(force: true));
  }

  /// Revoke on server (best-effort) and clear tokens.
  /// Local sqflite business data is NOT touched.
  Future<void> logout() async {
    if (DemoMode.enabled) return; // demo account cannot log out
    try {
      await _api.post('/app/auth/logout', retryOn401: false);
    } catch (_) {
      // offline or already invalid – ignore
    }
    final phone = this.phone;
    await _store.clearSession();
    // Keep the phone so tamper reports still identify the shop.
    if (phone.isNotEmpty) await _store.saveShop({'phone': phone});
    _shop = null;
    _license = null;
    _loggedIn = false;
    notifyListeners();
    await LicenseProvider.shared?.clear();
  }

  void _onSessionExpired() {
    if (!_loggedIn) return;
    _loggedIn = false;
    notifyListeners();
  }

  /// Re-read shop from store (after /app/me refresh updated it).
  Future<void> reloadShop() async {
    _shop = await _store.shop ?? _shop;
    notifyListeners();
  }
}
