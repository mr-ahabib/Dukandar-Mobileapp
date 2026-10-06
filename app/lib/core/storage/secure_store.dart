import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';

/// Thin wrapper around [FlutterSecureStorage] holding everything the app
/// must keep secret or must survive relaunch: tokens, shop identity,
/// cached license, device lock state and the stable device id.
///
/// Business data (sqflite) is NOT stored here.
class SecureStore {
  SecureStore._();
  static final SecureStore instance = SecureStore._();

  static const _kAccess = 'auth.access_token';
  static const _kRefresh = 'auth.refresh_token';
  static const _kShop = 'auth.shop_json';
  static const _kLicense = 'license.json';
  static const _kLicenseAt = 'license.fetched_at';
  static const _kLocked = 'lock.locked';
  static const _kLockReason = 'lock.reason';
  static const _kLockDetails = 'lock.details';
  static const _kUnlockReq = 'lock.unlock_request_id';
  static const _kDeviceId = 'device.id';
  static const _kNotifications = 'license.notifications';
  static const _kSeenNotifications = 'license.notifications.seen';

  final FlutterSecureStorage _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(resetOnError: true),
  );

  // Small in-memory cache so repeated reads during a session are cheap.
  final Map<String, String?> _cache = {};

  Future<String?> _read(String key) async {
    if (_cache.containsKey(key)) return _cache[key];
    String? v;
    try {
      v = await _storage.read(key: key);
    } catch (_) {
      v = null;
    }
    _cache[key] = v;
    return v;
  }

  Future<void> _write(String key, String? value) async {
    _cache[key] = value;
    try {
      if (value == null) {
        await _storage.delete(key: key);
      } else {
        await _storage.write(key: key, value: value);
      }
    } catch (_) {
      // Secure storage can fail on broken keystores; keep in-memory copy.
    }
  }

  // ---------------- Tokens ----------------
  Future<String?> get accessToken => _read(_kAccess);
  Future<String?> get refreshToken => _read(_kRefresh);

  Future<void> saveTokens(
      {required String access, required String refresh}) async {
    await _write(_kAccess, access);
    await _write(_kRefresh, refresh);
  }

  Future<void> clearTokens() async {
    await _write(_kAccess, null);
    await _write(_kRefresh, null);
  }

  // ---------------- Shop ----------------
  Future<Map<String, dynamic>?> get shop async => _readJson(_kShop);
  Future<void> saveShop(Map<String, dynamic>? shop) =>
      _write(_kShop, shop == null ? null : jsonEncode(shop));

  /// Shop phone, needed for tamper-report / unlock even when logged out.
  Future<String?> get shopPhone async => (await shop)?['phone'] as String?;

  // ---------------- License ----------------
  Future<Map<String, dynamic>?> get license async => _readJson(_kLicense);
  Future<DateTime?> get licenseFetchedAt async {
    final s = await _read(_kLicenseAt);
    return s == null ? null : DateTime.tryParse(s);
  }

  Future<void> saveLicense(Map<String, dynamic> license,
      {DateTime? fetchedAt}) async {
    await _write(_kLicense, jsonEncode(license));
    await _write(_kLicenseAt,
        (fetchedAt ?? DateTime.now().toUtc()).toIso8601String());
  }

  Future<void> clearLicense() async {
    await _write(_kLicense, null);
    await _write(_kLicenseAt, null);
    await _write(_kNotifications, null);
  }

  Future<List<Map<String, dynamic>>> get notifications async {
    final s = await _read(_kNotifications);
    if (s == null) return [];
    try {
      final list = jsonDecode(s) as List<dynamic>;
      return list.cast<Map<String, dynamic>>();
    } catch (_) {
      return [];
    }
  }

  Future<void> saveNotifications(List<Map<String, dynamic>> list) =>
      _write(_kNotifications, jsonEncode(list));

  /// Ids of server notifications already surfaced as a system notification.
  /// `null` = never synced (first run after this feature shipped).
  Future<List<String>?> get seenNotificationIds async {
    final s = await _read(_kSeenNotifications);
    if (s == null) return null;
    try {
      return (jsonDecode(s) as List<dynamic>).map((e) => e.toString()).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> saveSeenNotificationIds(List<String> ids) =>
      _write(_kSeenNotifications, jsonEncode(ids));

  // ---------------- Device lock ----------------
  Future<bool> get isLocked async => (await _read(_kLocked)) == '1';
  Future<String?> get lockReason => _read(_kLockReason);
  Future<String?> get lockDetails => _read(_kLockDetails);
  Future<String?> get unlockRequestId => _read(_kUnlockReq);

  Future<void> saveLock({
    required bool locked,
    String? reason,
    String? details,
    String? unlockRequestId,
  }) async {
    await _write(_kLocked, locked ? '1' : null);
    await _write(_kLockReason, locked ? reason : null);
    await _write(_kLockDetails, locked ? details : null);
    await _write(_kUnlockReq, locked ? unlockRequestId : null);
  }

  Future<void> saveUnlockRequestId(String? id) => _write(_kUnlockReq, id);

  Future<void> clearLock() => saveLock(locked: false);

  // ---------------- Device id ----------------
  /// Returns the persisted device id, or stores [candidate] (or a fresh UUID)
  /// on first call so the id stays stable for the life of the install.
  Future<String> deviceId({String? candidate}) async {
    final existing = await _read(_kDeviceId);
    if (existing != null && existing.isNotEmpty) return existing;
    final id = (candidate != null && candidate.isNotEmpty)
        ? candidate
        : const Uuid().v4();
    await _write(_kDeviceId, id);
    return id;
  }

  // ---------------- Helpers ----------------
  Future<Map<String, dynamic>?> _readJson(String key) async {
    final s = await _read(key);
    if (s == null) return null;
    try {
      return jsonDecode(s) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  /// Logout: remove session + license but keep device id and lock state.
  Future<void> clearSession() async {
    await clearTokens();
    await saveShop(null);
    await clearLicense();
  }
}
