import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

import 'backup_service.dart';
import 'drive_backup_service.dart';

/// Daily automatic backup.
///
/// Call [AutoBackup.maybeRun] once on app start (e.g. from the home screen's
/// initState or BackupScreen). Runs only when:
///  * the user enabled auto-backup,
///  * the last backup is older than 24h,
///  * the phone is on Wi-Fi.
/// Performs a local backup, then uploads to Drive if signed in.
class AutoBackup {
  AutoBackup._();

  static bool _running = false;
  static const Duration interval = Duration(hours: 24);

  /// Returns true when a backup was performed.
  static Future<bool> maybeRun() async {
    if (_running) return false;
    _running = true;
    try {
      final svc = BackupService.instance;
      if (!await svc.isAutoBackupEnabled()) return false;

      final last = await svc.lastBackupAt();
      if (last != null && DateTime.now().difference(last) < interval) {
        return false;
      }

      final conn = await Connectivity().checkConnectivity();
      final onWifi = conn.contains(ConnectivityResult.wifi) ||
          conn.contains(ConnectivityResult.ethernet);
      if (!onWifi) return false;

      final path = await svc.localBackup();
      debugPrint('AutoBackup: local -> $path');

      final driveSvc = DriveBackupService.instance;
      await driveSvc.init();
      if (driveSvc.isSignedIn) {
        try {
          await driveSvc.backupNow();
          debugPrint('AutoBackup: uploaded to Drive');
        } catch (e) {
          debugPrint('AutoBackup: drive upload failed: $e');
        }
      }
      return true;
    } catch (e) {
      debugPrint('AutoBackup failed: $e');
      return false;
    } finally {
      _running = false;
    }
  }
}
