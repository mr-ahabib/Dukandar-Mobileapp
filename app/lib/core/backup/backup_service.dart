import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

/// Describes one backup archive on disk.
class BackupInfo {
  const BackupInfo({
    required this.path,
    required this.name,
    required this.size,
    required this.createdAt,
  });

  final String path;
  final String name;
  final int size;
  final DateTime createdAt;
}

/// Metadata stored in `meta.json` inside every backup zip.
class BackupMeta {
  const BackupMeta({
    required this.version,
    required this.appVersion,
    required this.createdAt,
    required this.shopName,
    required this.files,
  });

  final int version;
  final String appVersion;
  final DateTime createdAt;
  final String shopName;
  final List<String> files;

  Map<String, dynamic> toJson() => {
        'version': version,
        'app_version': appVersion,
        'created_at': createdAt.toUtc().toIso8601String(),
        'shop_name': shopName,
        'files': files,
      };

  static BackupMeta? tryParse(String s) {
    try {
      final j = jsonDecode(s) as Map<String, dynamic>;
      return BackupMeta(
        version: (j['version'] as num?)?.toInt() ?? 1,
        appVersion: (j['app_version'] as String?) ?? '',
        createdAt: DateTime.tryParse(j['created_at']?.toString() ?? '') ??
            DateTime.now(),
        shopName: (j['shop_name'] as String?) ?? '',
        files: ((j['files'] as List?) ?? const []).map((e) => '$e').toList(),
      );
    } catch (_) {
      return null;
    }
  }
}

/// Exception with a Bangla message for the UI.
class BackupException implements Exception {
  BackupException(this.messageBn);
  final String messageBn;
  @override
  String toString() => messageBn;
}

/// Creates / restores zip backups of all local business data.
///
/// Archive layout:
/// ```
/// dukandar.db (+ -wal / -shm / -journal if present)
/// photos/<files>
/// settings.json      (shared_preferences dump)
/// meta.json          (version, createdAt, shopName)
/// ```
class BackupService {
  BackupService._();
  static final BackupService instance = BackupService._();

  static const int formatVersion = 1;
  static const String dbName = 'dukandar.db';
  static const String backupDirName = 'DukandarBackup';
  static const int keepLocal = 10;

  static const String prefLastBackupAt = 'backup.last_at';
  static const String prefLastBackupPath = 'backup.last_path';
  static const String prefAutoBackup = 'backup.auto_enabled';

  /// Register to flush the WAL through the app's own connection before the
  /// DB file is copied. When null, a throw-away connection is used instead.
  static Future<void> Function()? onBeforeBackup;

  /// Register to close the sqflite database before the file is replaced.
  /// (The DB owner should wire `AppDatabase.instance.close()` here.)
  static Future<void> Function()? onBeforeRestore;

  /// Register to reopen the database / reload providers after restore.
  static Future<void> Function()? onAfterRestore;

  /// Set by the app (AuthProvider.shopName) so meta.json can name the shop.
  static String shopName = '';

  // ------------------------------------------------------------------
  // Paths
  // ------------------------------------------------------------------

  Future<String> _dbPath() async => p.join(await getDatabasesPath(), dbName);

  Future<Directory> _photosDir() async {
    final docs = await getApplicationDocumentsDirectory();
    return Directory(p.join(docs.path, 'photos'));
  }

  /// `<externalFiles>/DukandarBackup` on Android, app docs elsewhere.
  Future<Directory> backupDir() async {
    Directory? base;
    try {
      if (!kIsWeb && Platform.isAndroid) {
        base = await getExternalStorageDirectory();
      }
    } catch (_) {}
    base ??= await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(base.path, backupDirName));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  static String fileNameFor(DateTime t) {
    String two(int n) => n.toString().padLeft(2, '0');
    return 'dukandar-backup-${t.year}${two(t.month)}${two(t.day)}-${two(t.hour)}${two(t.minute)}.zip';
  }

  // ------------------------------------------------------------------
  // Create
  // ------------------------------------------------------------------

  /// Builds the zip in memory and returns its bytes.
  Future<Uint8List> buildArchiveBytes() async {
    final archive = Archive();
    final files = <String>[];

    // 1. Database (checkpoint WAL first so the main file is complete).
    final dbPath = await _dbPath();
    final dbFile = File(dbPath);
    if (await dbFile.exists()) {
      final hook = onBeforeBackup;
      if (hook != null) {
        try {
          await hook();
        } catch (_) {}
      } else {
        try {
          // No app connection registered: open a short-lived one. (sqflite
          // returns the shared instance for an already-open path, so we must
          // not close it here — that would close the app's handle.)
          final db = await openDatabase(dbPath, readOnly: false, singleInstance: false);
          await db.rawQuery('PRAGMA wal_checkpoint(TRUNCATE)');
          await db.close();
        } catch (_) {
          // Copying still works; the -wal/-shm files are archived too.
        }
      }
      final dbDir = Directory(p.dirname(dbPath));
      await for (final e in dbDir.list()) {
        if (e is File && p.basename(e.path).startsWith(dbName)) {
          final name = p.basename(e.path);
          archive.addFile(ArchiveFile.bytes(name, await e.readAsBytes()));
          files.add(name);
        }
      }
    }

    // 2. Photos.
    final photos = await _photosDir();
    if (await photos.exists()) {
      await for (final e in photos.list(recursive: true)) {
        if (e is File) {
          final rel = p.relative(e.path, from: photos.path);
          final name = 'photos/${rel.replaceAll('\\', '/')}';
          archive.addFile(ArchiveFile.bytes(name, await e.readAsBytes()));
          files.add(name);
        }
      }
    }

    // 3. Settings (shared_preferences dump).
    final prefs = await SharedPreferences.getInstance();
    final settings = <String, dynamic>{};
    for (final k in prefs.getKeys()) {
      if (k.startsWith('backup.')) continue; // not business settings
      settings[k] = prefs.get(k);
    }
    archive.addFile(ArchiveFile.string('settings.json', jsonEncode(settings)));
    files.add('settings.json');

    // 4. Meta.
    String appVersion = '';
    try {
      appVersion = (await PackageInfo.fromPlatform()).version;
    } catch (_) {}
    final meta = BackupMeta(
      version: formatVersion,
      appVersion: appVersion,
      createdAt: DateTime.now(),
      shopName: shopName,
      files: files,
    );
    archive.addFile(ArchiveFile.string('meta.json', jsonEncode(meta.toJson())));

    return ZipEncoder().encodeBytes(archive);
  }

  /// Writes a zip to the backup folder, prunes old ones and returns the path.
  Future<String> localBackup() async {
    final bytes = await buildArchiveBytes();
    final dir = await backupDir();
    final path = p.join(dir.path, fileNameFor(DateTime.now()));
    await File(path).writeAsBytes(bytes, flush: true);
    await _prune(dir);
    await _recordBackup(path);
    return path;
  }

  Future<void> _recordBackup(String path) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        prefLastBackupAt, DateTime.now().toUtc().toIso8601String());
    await prefs.setString(prefLastBackupPath, path);
  }

  Future<void> _prune(Directory dir) async {
    final list = await listLocalBackups();
    if (list.length <= keepLocal) return;
    for (final old in list.skip(keepLocal)) {
      try {
        await File(old.path).delete();
      } catch (_) {}
    }
  }

  /// Newest first.
  Future<List<BackupInfo>> listLocalBackups() async {
    final dir = await backupDir();
    final out = <BackupInfo>[];
    await for (final e in dir.list()) {
      if (e is File && e.path.endsWith('.zip')) {
        final stat = await e.stat();
        out.add(BackupInfo(
          path: e.path,
          name: p.basename(e.path),
          size: stat.size,
          createdAt: stat.modified,
        ));
      }
    }
    out.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return out;
  }

  Future<DateTime?> lastBackupAt() async {
    final prefs = await SharedPreferences.getInstance();
    final s = prefs.getString(prefLastBackupAt);
    return s == null ? null : DateTime.tryParse(s)?.toLocal();
  }

  Future<String?> lastBackupPath() async {
    final prefs = await SharedPreferences.getInstance();
    final path = prefs.getString(prefLastBackupPath);
    if (path != null && await File(path).exists()) return path;
    return null;
  }

  Future<bool> isAutoBackupEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(prefAutoBackup) ?? false;
  }

  Future<void> setAutoBackupEnabled(bool v) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(prefAutoBackup, v);
  }

  /// Opens the system share sheet with the zip.
  Future<void> shareBackup(String path) async {
    await SharePlus.instance.share(ShareParams(
      files: [XFile(path, mimeType: 'application/zip')],
      subject: 'দোকানদার ব্যাকআপ',
      text: 'দোকানদার অ্যাপের ব্যাকআপ ফাইল – নিরাপদ জায়গায় সংরক্ষণ করুন।',
    ));
  }

  // ------------------------------------------------------------------
  // Restore
  // ------------------------------------------------------------------

  /// Reads meta.json without restoring. Throws [BackupException] if invalid.
  Future<BackupMeta> inspect(String path) async {
    final file = File(path);
    if (!await file.exists()) throw BackupException('ফাইলটি পাওয়া যায়নি।');
    final bytes = await file.readAsBytes();
    return _inspectBytes(bytes);
  }

  BackupMeta _inspectBytes(Uint8List bytes) {
    Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes, verify: true);
    } catch (_) {
      throw BackupException('এটি সঠিক ব্যাকআপ ফাইল নয় (zip খোলা যায়নি)।');
    }
    final metaFile = archive.findFile('meta.json');
    final hasDb = archive.findFile(dbName) != null;
    if (metaFile == null || !hasDb) {
      throw BackupException('এটি দোকানদার অ্যাপের ব্যাকআপ ফাইল নয়।');
    }
    final meta = BackupMeta.tryParse(utf8.decode(metaFile.readBytes()!));
    if (meta == null) throw BackupException('ব্যাকআপের তথ্য পড়া যায়নি।');
    if (meta.version > formatVersion) {
      throw BackupException(
          'এই ব্যাকআপটি নতুন ভার্সনের অ্যাপে তৈরি। অ্যাপ আপডেট করুন।');
    }
    return meta;
  }

  /// Restores from a zip file. Overwrites DB, photos and settings.
  ///
  /// Returns true if the DB was reopened via [onAfterRestore]; false means
  /// the caller should ask the user to restart the app.
  Future<bool> restoreFromFile(String path) async {
    final bytes = await File(path).readAsBytes();
    return restoreFromBytes(bytes);
  }

  Future<bool> restoreFromBytes(Uint8List bytes) async {
    _inspectBytes(bytes); // validates
    final archive = ZipDecoder().decodeBytes(bytes);

    // Close DB first.
    if (onBeforeRestore != null) {
      try {
        await onBeforeRestore!();
      } catch (_) {}
    }

    final dbPath = await _dbPath();
    final dbDir = Directory(p.dirname(dbPath));
    if (!await dbDir.exists()) await dbDir.create(recursive: true);

    // Remove stale journal/WAL files so SQLite does not mix them.
    await for (final e in dbDir.list()) {
      if (e is File && p.basename(e.path).startsWith(dbName)) {
        try {
          await e.delete();
        } catch (_) {}
      }
    }

    final photos = await _photosDir();
    if (await photos.exists()) {
      try {
        await photos.delete(recursive: true);
      } catch (_) {}
    }
    await photos.create(recursive: true);

    for (final f in archive.files) {
      if (!f.isFile) continue;
      final name = f.name;
      final data = f.readBytes();
      if (data == null) continue;
      if (name.startsWith(dbName)) {
        await File(p.join(dbDir.path, name)).writeAsBytes(data, flush: true);
      } else if (name.startsWith('photos/')) {
        final target = File(p.join(photos.path, name.substring(7)));
        await target.parent.create(recursive: true);
        await target.writeAsBytes(data, flush: true);
      } else if (name == 'settings.json') {
        await _restoreSettings(utf8.decode(data));
      }
    }

    if (onAfterRestore != null) {
      try {
        await onAfterRestore!();
        return true;
      } catch (_) {
        return false;
      }
    }
    return false;
  }

  Future<void> _restoreSettings(String json) async {
    Map<String, dynamic> map;
    try {
      map = jsonDecode(json) as Map<String, dynamic>;
    } catch (_) {
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    for (final entry in map.entries) {
      final k = entry.key;
      final v = entry.value;
      if (k.startsWith('backup.')) continue;
      if (v is bool) {
        await prefs.setBool(k, v);
      } else if (v is int) {
        await prefs.setInt(k, v);
      } else if (v is double) {
        await prefs.setDouble(k, v);
      } else if (v is String) {
        await prefs.setString(k, v);
      } else if (v is List) {
        await prefs.setStringList(k, v.map((e) => '$e').toList());
      }
    }
  }

  static String formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
