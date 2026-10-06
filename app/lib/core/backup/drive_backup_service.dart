import 'dart:async';
import 'dart:typed_data';

import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:shared_preferences/shared_preferences.dart';

import 'backup_service.dart';

/// A backup stored in the user's Google Drive appDataFolder.
class DriveBackup {
  const DriveBackup({
    required this.id,
    required this.name,
    required this.size,
    required this.createdTime,
  });

  final String id;
  final String name;
  final int size;
  final DateTime? createdTime;
}

/// Google Drive (appDataFolder) backup using google_sign_in v7.
///
/// The app-data folder is private to this app: the user cannot see the files
/// in Drive UI, but they roam with the Google account.
class DriveBackupService extends ChangeNotifier {
  DriveBackupService._();
  static final DriveBackupService instance = DriveBackupService._();

  static const List<String> scopes = [drive.DriveApi.driveAppdataScope];
  static const int keepRemote = 5;
  static const String prefLastDriveAt = 'backup.drive_last_at';

  GoogleSignInAccount? _account;
  GoogleSignInAccount? get account => _account;
  bool get isSignedIn => _account != null;

  bool _initialized = false;
  bool isBusy = false;
  String? lastError;
  StreamSubscription<GoogleSignInAuthenticationEvent>? _sub;

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    try {
      final gsi = GoogleSignIn.instance;
      await gsi.initialize();
      _sub = gsi.authenticationEvents.listen((event) {
        switch (event) {
          case GoogleSignInAuthenticationEventSignIn():
            _account = event.user;
          case GoogleSignInAuthenticationEventSignOut():
            _account = null;
        }
        notifyListeners();
      }, onError: (_) {});
      // Try silent sign-in so the account chip shows right away.
      final silent = gsi.attemptLightweightAuthentication();
      if (silent != null) {
        final acc = await silent.timeout(const Duration(seconds: 8),
            onTimeout: () => null);
        if (acc != null) _account = acc;
      }
    } catch (e) {
      lastError = _bn(e);
    }
    notifyListeners();
  }

  /// Interactive sign-in. Returns null on success else Bangla error.
  Future<String?> signIn() async {
    await init();
    _setBusy(true);
    try {
      _account = await GoogleSignIn.instance.authenticate(scopeHint: scopes);
      lastError = null;
      return null;
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) {
        lastError = null;
        return null;
      }
      lastError = _bn(e);
      return lastError;
    } catch (e) {
      lastError = _bn(e);
      return lastError;
    } finally {
      _setBusy(false);
    }
  }

  Future<void> signOut() async {
    try {
      await GoogleSignIn.instance.signOut();
    } catch (_) {}
    _account = null;
    notifyListeners();
  }

  Future<drive.DriveApi> _api() async {
    final acc = _account;
    if (acc == null) throw BackupException('আগে Google অ্যাকাউন্টে সাইন ইন করুন।');
    var auth = await acc.authorizationClient.authorizationForScopes(scopes);
    auth ??= await acc.authorizationClient.authorizeScopes(scopes);
    final client = auth.authClient(scopes: scopes);
    return drive.DriveApi(client);
  }

  /// Uploads [bytes] as [name]; keeps only the newest [keepRemote] backups.
  Future<DriveBackup> upload(Uint8List bytes, String name) async {
    _setBusy(true);
    try {
      final api = await _api();
      final meta = drive.File()
        ..name = name
        ..parents = ['appDataFolder']
        ..mimeType = 'application/zip';
      final media = drive.Media(Stream.value(bytes), bytes.length,
          contentType: 'application/zip');
      final created = await api.files.create(
        meta,
        uploadMedia: media,
        $fields: 'id,name,size,createdTime',
      );
      await _pruneRemote(api);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          prefLastDriveAt, DateTime.now().toUtc().toIso8601String());
      lastError = null;
      return DriveBackup(
        id: created.id ?? '',
        name: created.name ?? name,
        size: int.tryParse(created.size ?? '') ?? bytes.length,
        createdTime: created.createdTime,
      );
    } catch (e) {
      lastError = _bn(e);
      rethrow;
    } finally {
      _setBusy(false);
    }
  }

  /// Builds a fresh backup and uploads it.
  Future<DriveBackup> backupNow() async {
    final bytes = await BackupService.instance.buildArchiveBytes();
    return upload(bytes, BackupService.fileNameFor(DateTime.now()));
  }

  Future<void> _pruneRemote(drive.DriveApi api) async {
    final list = await _listRaw(api);
    if (list.length <= keepRemote) return;
    for (final f in list.skip(keepRemote)) {
      try {
        await api.files.delete(f.id);
      } catch (_) {}
    }
  }

  Future<List<DriveBackup>> _listRaw(drive.DriveApi api) async {
    final res = await api.files.list(
      spaces: 'appDataFolder',
      q: "name contains 'dukandar-backup' and trashed = false",
      $fields: 'files(id,name,size,createdTime)',
      orderBy: 'createdTime desc',
      pageSize: 50,
    );
    return (res.files ?? [])
        .map((f) => DriveBackup(
              id: f.id ?? '',
              name: f.name ?? '',
              size: int.tryParse(f.size ?? '') ?? 0,
              createdTime: f.createdTime,
            ))
        .toList();
  }

  /// Newest first.
  Future<List<DriveBackup>> listBackups() async {
    _setBusy(true);
    try {
      final api = await _api();
      final list = await _listRaw(api);
      lastError = null;
      return list;
    } catch (e) {
      lastError = _bn(e);
      rethrow;
    } finally {
      _setBusy(false);
    }
  }

  Future<Uint8List> download(String fileId) async {
    final api = await _api();
    final media = await api.files.get(fileId,
        downloadOptions: drive.DownloadOptions.fullMedia) as drive.Media;
    final builder = BytesBuilder(copy: false);
    await for (final chunk in media.stream) {
      builder.add(chunk);
    }
    return builder.takeBytes();
  }

  /// Download + restore. Returns true when the DB was reopened in place.
  Future<bool> restore(String fileId) async {
    _setBusy(true);
    try {
      final bytes = await download(fileId);
      final ok = await BackupService.instance.restoreFromBytes(bytes);
      lastError = null;
      return ok;
    } catch (e) {
      lastError = _bn(e);
      rethrow;
    } finally {
      _setBusy(false);
    }
  }

  Future<void> deleteBackup(String fileId) async {
    final api = await _api();
    await api.files.delete(fileId);
  }

  Future<DateTime?> lastDriveBackupAt() async {
    final prefs = await SharedPreferences.getInstance();
    final s = prefs.getString(prefLastDriveAt);
    return s == null ? null : DateTime.tryParse(s)?.toLocal();
  }

  void _setBusy(bool v) {
    isBusy = v;
    notifyListeners();
  }

  String _bn(Object e) {
    if (e is BackupException) return e.messageBn;
    final s = e.toString().toLowerCase();
    if (s.contains('network') || s.contains('socket') || s.contains('host')) {
      return 'ইন্টারনেট সংযোগ নেই।';
    }
    if (s.contains('sign_in_required') || s.contains('unauthenticated')) {
      return 'Google অ্যাকাউন্টে আবার সাইন ইন করুন।';
    }
    if (s.contains('developer') || s.contains('10:') || s.contains('apiexception')) {
      return 'Google সাইন-ইন কনফিগার করা নেই (SHA-1 / OAuth client)।';
    }
    return 'Google Drive-এ সমস্যা হয়েছে। আবার চেষ্টা করুন।';
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
