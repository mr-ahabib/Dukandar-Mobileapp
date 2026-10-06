import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../app_config.dart';
import '../network/api_client.dart';
import '../storage/secure_store.dart';

/// Result of the native `inspect` call.
class SecurityReport {
  const SecurityReport({
    this.isRooted = false,
    this.isDebuggerAttached = false,
    this.hookingDetected = false,
    this.isEmulator = false,
    this.signatureSha256 = '',
    this.isDebugBuild = kDebugMode,
    this.details = const {},
  });

  final bool isRooted;
  final bool isDebuggerAttached;
  final bool hookingDetected;
  final bool isEmulator;
  final String signatureSha256;
  final bool isDebugBuild;
  final Map<String, dynamic> details;

  factory SecurityReport.fromMap(Map<dynamic, dynamic> m) => SecurityReport(
        isRooted: m['isRooted'] == true,
        isDebuggerAttached: m['isDebuggerAttached'] == true,
        hookingDetected: m['hookingDetected'] == true,
        isEmulator: m['isEmulator'] == true,
        signatureSha256:
            ((m['signatureSha256'] as String?) ?? '').toLowerCase(),
        isDebugBuild: m['isDebugBuild'] == true,
        details: Map<String, dynamic>.from(m['details'] as Map? ?? const {}),
      );
}

/// Runs tamper checks on launch; if any fail the app locks until an admin
/// unlock code is entered. Lock state is persisted locally first (works
/// offline) and then reported to the server when a connection is available.
class SecurityGate extends ChangeNotifier {
  SecurityGate({SecureStore? store, ApiClient? api})
      : _store = store ?? SecureStore.instance,
        _api = api ?? ApiClient.instance {
    _shared = this;
  }

  static const MethodChannel _channel = MethodChannel('com.dukandar/security');

  static SecurityGate? _shared;

  /// Last created instance (so AuthProvider can read the signature and
  /// trigger a server-side lock without changes in main.dart).
  static SecurityGate? get shared => _shared;

  final SecureStore _store;
  final ApiClient _api;

  bool isLocked = false;
  String? lockReason; // ROOT_DETECTED | SIGNATURE_MISMATCH | ...
  String? lockDetails;
  String? unlockRequestId;
  bool isReporting = false;
  bool isUnlocking = false;
  String? lastError;
  bool checksDone = false;

  SecurityReport? _report;
  SecurityReport? get report => _report;

  /// Signing certificate SHA-256 as seen by the OS (lowercase hex).
  String get signatureSha256 => _report?.signatureSha256 ?? '';
  bool get isEmulator => _report?.isEmulator ?? false;

  /// Bangla label for the current [lockReason].
  String get lockReasonBn => reasonToBn(lockReason);

  static String reasonToBn(String? reason) {
    switch (reason) {
      case 'ROOT_DETECTED':
        return 'ফোনটি রুট করা (Root) অবস্থায় পাওয়া গেছে';
      case 'SIGNATURE_MISMATCH':
        return 'অ্যাপটির আসল স্বাক্ষর (Signature) মিলছে না';
      case 'DEBUGGER':
        return 'ডিবাগার যুক্ত অবস্থায় অ্যাপ চালানো হয়েছে';
      case 'HOOKING_FRAMEWORK':
        return 'অ্যাপে হস্তক্ষেপকারী টুল (Frida/Xposed) শনাক্ত হয়েছে';
      case 'EMULATOR':
        return 'এমুলেটরে অ্যাপ চালানো হয়েছে';
      case 'TAMPERED_BINARY':
        return 'অ্যাপের ফাইল পরিবর্তন করা হয়েছে';
      default:
        return 'নিরাপত্তা জনিত সমস্যা শনাক্ত হয়েছে';
    }
  }

  // ---------------------------------------------------------------------
  // Checks
  // ---------------------------------------------------------------------

  Future<void> runChecks() async {
    if (AppConfig.isDemo) {
      checksDone = true;
      notifyListeners();
      return;
    }
    // 1. Restore persisted lock so a relaunch stays locked (even offline).
    await _loadPersistedLock();
    notifyListeners();

    // 2. Ask the native side.
    try {
      final raw = await _channel
          .invokeMethod<Map<dynamic, dynamic>>('inspect')
          .timeout(const Duration(seconds: 5));
      if (raw != null) _report = SecurityReport.fromMap(raw);
    } on MissingPluginException {
      _report = const SecurityReport();
    } catch (e) {
      lastError = e.toString();
      _report = const SecurityReport();
    }

    final r = _report!;
    final isRelease = kReleaseMode && !r.isDebugBuild;

    String? reason;
    String? details;
    if (r.isRooted) {
      reason = 'ROOT_DETECTED';
      details = _detail(r, 'root');
    } else if (r.hookingDetected) {
      reason = 'HOOKING_FRAMEWORK';
      details = _detail(r, 'hooking');
    } else if (r.isDebuggerAttached && isRelease) {
      reason = 'DEBUGGER';
      details = 'debugger attached in release build';
    } else if (isRelease &&
        AppConfig.expectedSignatureSha256.isNotEmpty &&
        r.signatureSha256 != AppConfig.expectedSignatureSha256.toLowerCase()) {
      reason = 'SIGNATURE_MISMATCH';
      details = 'got=${r.signatureSha256}';
    }

    checksDone = true;
    if (reason != null && !isLocked) {
      await lock(reason, details: details);
    } else if (isLocked && unlockRequestId == null) {
      // Previously locked offline without a request id – try reporting again.
      unawaited(reportToServer());
    }
    notifyListeners();
  }

  String _detail(SecurityReport r, String key) {
    final d = r.details[key];
    if (d == null) return key;
    return d.toString();
  }

  Future<void> _loadPersistedLock() async {
    isLocked = await _store.isLocked;
    if (isLocked) {
      lockReason = await _store.lockReason;
      lockDetails = await _store.lockDetails;
      unlockRequestId = await _store.unlockRequestId;
    }
  }

  // ---------------------------------------------------------------------
  // Lock / report / unlock
  // ---------------------------------------------------------------------

  /// Lock the app locally right away, then report to the server.
  Future<void> lock(String reason, {String? details}) async {
    isLocked = true;
    lockReason = reason;
    lockDetails = details;
    await _store.saveLock(
      locked: true,
      reason: reason,
      details: details,
      unlockRequestId: unlockRequestId,
    );
    notifyListeners();
    await reportToServer();
  }

  /// POST /app/tamper-report. Safe to call repeatedly (server is idempotent).
  /// Returns true when an unlock request id is now known.
  Future<bool> reportToServer() async {
    if (!isLocked || isReporting) return unlockRequestId != null;
    isReporting = true;
    lastError = null;
    notifyListeners();
    try {
      final phone = await _store.shopPhone;
      final deviceId = await _store.deviceId();
      String appVersion = '';
      try {
        appVersion = (await PackageInfo.fromPlatform()).version;
      } catch (_) {}

      final res = await _api.post(
        '/app/tamper-report',
        auth: true,
        retryOn401: false,
        body: {
          'phone': phone ?? '',
          'device_id': deviceId,
          'reason': lockReason ?? 'TAMPERED_BINARY',
          'details': lockDetails ?? '',
          'app_version': appVersion,
        },
      );
      if (res is Map<String, dynamic>) {
        final id = res['unlock_request_id'] as String?;
        if (id != null && id.isNotEmpty) {
          unlockRequestId = id;
          await _store.saveUnlockRequestId(id);
        }
      }
      return unlockRequestId != null;
    } on ApiException catch (e) {
      lastError = e.isOffline
          ? 'ইন্টারনেট নেই। সংযোগ চালু করে "আবার পাঠান" চাপুন।'
          : e.messageBn;
      return false;
    } catch (e) {
      lastError = 'রিপোর্ট পাঠানো যায়নি।';
      return false;
    } finally {
      isReporting = false;
      notifyListeners();
    }
  }

  /// POST /app/unlock. Returns null on success, else a Bangla error message.
  Future<String?> submitUnlockCode(String code) async {
    final clean = code.replaceAll(RegExp(r'\D'), '');
    if (clean.length != 8) return '৮ সংখ্যার কোড দিন।';
    if (unlockRequestId == null) {
      final ok = await reportToServer();
      if (!ok) {
        return lastError ??
            'রিকোয়েস্ট আইডি পাওয়া যায়নি। ইন্টারনেট চালু করুন।';
      }
    }
    isUnlocking = true;
    lastError = null;
    notifyListeners();
    try {
      final phone = await _store.shopPhone;
      final deviceId = await _store.deviceId();
      final res = await _api.post(
        '/app/unlock',
        auth: false,
        body: {
          'phone': phone ?? '',
          'device_id': deviceId,
          'unlock_request_id': unlockRequestId,
          'unlock_code': clean,
        },
      );
      if (res is Map<String, dynamic> && res['unlocked'] == true) {
        await _clearLock();
        return null;
      }
      lastError = 'কোডটি সঠিক নয়।';
      return lastError;
    } on ApiException catch (e) {
      if (e.statusCode == 400) {
        final msg = e.messageBn;
        lastError = msg.isNotEmpty && msg != 'অনুরোধটি সঠিক নয়।'
            ? msg
            : 'ভুল কোড। আবার চেষ্টা করুন (সর্বোচ্চ ৫ বার)।';
      } else {
        lastError = e.messageBn;
      }
      return lastError;
    } catch (_) {
      lastError = 'আনলক করা যায়নি। আবার চেষ্টা করুন।';
      return lastError;
    } finally {
      isUnlocking = false;
      notifyListeners();
    }
  }

  Future<void> _clearLock() async {
    isLocked = false;
    lockReason = null;
    lockDetails = null;
    unlockRequestId = null;
    lastError = null;
    await _store.clearLock();
    notifyListeners();
  }

  /// Lock triggered by the server (login returned 423 DEVICE_LOCKED).
  Future<void> lockFromServer({String? unlockRequestId, String? hint}) async {
    isLocked = true;
    lockReason ??= 'TAMPERED_BINARY';
    lockDetails = hint;
    this.unlockRequestId = unlockRequestId ?? this.unlockRequestId;
    await _store.saveLock(
      locked: true,
      reason: lockReason,
      details: hint,
      unlockRequestId: this.unlockRequestId,
    );
    notifyListeners();
  }
}
