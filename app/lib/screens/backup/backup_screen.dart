import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/backup/auto_backup.dart';
import '../../core/backup/backup_service.dart';
import '../../core/backup/drive_backup_service.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/common_widgets.dart' show NoteBox;
import '../../widgets/infra_widgets.dart';

/// Local + Google Drive backup / restore.
class BackupScreen extends StatefulWidget {
  const BackupScreen({super.key});

  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends State<BackupScreen> {
  final _svc = BackupService.instance;
  final _drive = DriveBackupService.instance;

  DateTime? _lastAt;
  String? _lastPath;
  DateTime? _lastDriveAt;
  bool _auto = false;
  bool _busyLocal = false;
  bool _busyRestore = false;
  bool _loadingDrive = false;
  List<DriveBackup> _driveBackups = const [];

  @override
  void initState() {
    super.initState();
    _drive.addListener(_onDrive);
    _load();
  }

  @override
  void dispose() {
    _drive.removeListener(_onDrive);
    super.dispose();
  }

  void _onDrive() {
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    final auth = context.read<AuthProvider>();
    BackupService.shopName = auth.shopName;
    final results = await Future.wait([
      _svc.lastBackupAt(),
      _svc.lastBackupPath(),
      _svc.isAutoBackupEnabled(),
      _drive.lastDriveBackupAt(),
    ]);
    if (!mounted) return;
    setState(() {
      _lastAt = results[0] as DateTime?;
      _lastPath = results[1] as String?;
      _auto = results[2] as bool;
      _lastDriveAt = results[3] as DateTime?;
    });
    await _drive.init();
    if (_drive.isSignedIn) await _refreshDriveList();
    // Opportunistic daily auto-backup.
    AutoBackup.maybeRun().then((ran) {
      if (ran && mounted) _load();
    });
  }

  // ------------------------------------------------------------------
  // Local
  // ------------------------------------------------------------------

  Future<void> _backupNow() async {
    setState(() => _busyLocal = true);
    try {
      final path = await _svc.localBackup();
      if (!mounted) return;
      showSnack(context, 'ব্যাকআপ তৈরি হয়েছে');
      await _load();
      if (!mounted) return;
      setState(() => _lastPath = path);
    } catch (e) {
      if (mounted) showSnack(context, 'ব্যাকআপ তৈরি করা যায়নি: $e', error: true);
    } finally {
      if (mounted) setState(() => _busyLocal = false);
    }
  }

  Future<void> _share() async {
    var path = _lastPath;
    if (path == null) {
      setState(() => _busyLocal = true);
      try {
        path = await _svc.localBackup();
        await _load();
      } catch (e) {
        if (mounted) showSnack(context, 'ব্যাকআপ তৈরি করা যায়নি', error: true);
        return;
      } finally {
        if (mounted) setState(() => _busyLocal = false);
      }
    }
    try {
      await _svc.shareBackup(path);
    } catch (_) {
      if (mounted) showSnack(context, 'শেয়ার করা যায়নি', error: true);
    }
  }

  Future<void> _toggleAuto(bool v) async {
    setState(() => _auto = v);
    await _svc.setAutoBackupEnabled(v);
    if (v && mounted) {
      showSnack(context, 'Wi‑Fi থাকলে দিনে একবার নিজে নিজে ব্যাকআপ হবে');
    }
  }

  // ------------------------------------------------------------------
  // Restore
  // ------------------------------------------------------------------

  Future<bool> _confirmRestore(BackupMeta meta) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.warning_amber_rounded, color: AppTheme.gaveRed, size: 32),
        title: const Text('ব্যাকআপ ফিরিয়ে আনবেন?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'এই ফোনের বর্তমান সব হিসাব, গ্রাহক, মেমো ও ছবি মুছে গিয়ে ব্যাকআপের তথ্য বসবে। এটি ফেরানো যাবে না।',
              style: AppTheme.bodySm.copyWith(height: 1.45, color: AppTheme.inkMuted),
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.sand,
                borderRadius: BorderRadius.circular(AppTheme.radiusMd),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('ব্যাকআপের সময়: ${bnDateTime(meta.createdAt)}',
                      style: AppTheme.bodySm),
                  if (meta.shopName.isNotEmpty)
                    Text('দোকান: ${meta.shopName}',
                        style: AppTheme.bodySm),
                  Text('ফাইল: ${bn(meta.files.length)} টি',
                      style: AppTheme.bodySm),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('বাতিল')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppTheme.gaveRed),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('হ্যাঁ, ফিরিয়ে আনুন'),
          ),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _afterRestore(bool reopened) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.check_circle_outline_rounded, color: AppTheme.gotGreen, size: 32),
        title: const Text('ব্যাকআপ ফিরিয়ে আনা হয়েছে'),
        content: Text(
          reopened
              ? 'সব তথ্য ফিরে এসেছে। নতুন তথ্য দেখতে স্ক্রিন রিফ্রেশ করুন।'
              : 'সব তথ্য ফিরে এসেছে। নতুন তথ্য দেখতে অ্যাপটি সম্পূর্ণ বন্ধ করে আবার চালু করুন।',
        ),
        actions: [
          FilledButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('ঠিক আছে')),
        ],
      ),
    );
  }

  Future<void> _restoreFromFile() async {
    List<PlatformFile> picked;
    try {
      picked = await FilePicker.pickFiles(
        dialogTitle: 'ব্যাকআপ ফাইল বাছুন',
        type: FileType.any,
      );
    } catch (_) {
      if (mounted) showSnack(context, 'ফাইল বাছাই করা যায়নি', error: true);
      return;
    }
    if (picked.isEmpty || picked.first.path == null) return;
    final path = picked.first.path!;
    if (!path.toLowerCase().endsWith('.zip')) {
      if (mounted) showSnack(context, 'শুধু .zip ব্যাকআপ ফাইল বাছুন', error: true);
      return;
    }
    await _restorePath(path);
  }

  Future<void> _restorePath(String path) async {
    BackupMeta meta;
    try {
      meta = await _svc.inspect(path);
    } on BackupException catch (e) {
      if (mounted) showSnack(context, e.messageBn, error: true);
      return;
    } catch (_) {
      if (mounted) showSnack(context, 'ফাইলটি পড়া যায়নি', error: true);
      return;
    }
    if (!mounted || !await _confirmRestore(meta)) return;
    setState(() => _busyRestore = true);
    try {
      final reopened = await _svc.restoreFromFile(path);
      await _afterRestore(reopened);
    } on BackupException catch (e) {
      if (mounted) showSnack(context, e.messageBn, error: true);
    } catch (e) {
      if (mounted) showSnack(context, 'ফিরিয়ে আনা যায়নি: $e', error: true);
    } finally {
      if (mounted) setState(() => _busyRestore = false);
    }
  }

  // ------------------------------------------------------------------
  // Drive
  // ------------------------------------------------------------------

  Future<void> _refreshDriveList() async {
    setState(() => _loadingDrive = true);
    try {
      final list = await _drive.listBackups();
      if (mounted) setState(() => _driveBackups = list);
    } catch (_) {
      // error surfaced via _drive.lastError
    } finally {
      if (mounted) setState(() => _loadingDrive = false);
    }
  }

  Future<void> _driveSignIn() async {
    final err = await _drive.signIn();
    if (!mounted) return;
    if (err != null) {
      showSnack(context, err, error: true);
    } else if (_drive.isSignedIn) {
      await _refreshDriveList();
    }
  }

  Future<void> _driveUpload() async {
    try {
      await _drive.backupNow();
      if (!mounted) return;
      showSnack(context, 'Google Drive-এ ব্যাকআপ আপলোড হয়েছে');
      _lastDriveAt = await _drive.lastDriveBackupAt();
      await _refreshDriveList();
    } catch (_) {
      if (mounted) {
        showSnack(context, _drive.lastError ?? 'আপলোড করা যায়নি', error: true);
      }
    }
  }

  Future<void> _driveRestore(DriveBackup b) async {
    final ok = await _confirmRestore(BackupMeta(
      version: BackupService.formatVersion,
      appVersion: '',
      createdAt: b.createdTime ?? DateTime.now(),
      shopName: '',
      files: const [],
    ));
    if (!ok) return;
    setState(() => _busyRestore = true);
    try {
      final reopened = await _drive.restore(b.id);
      await _afterRestore(reopened);
    } on BackupException catch (e) {
      if (mounted) showSnack(context, e.messageBn, error: true);
    } catch (_) {
      if (mounted) {
        showSnack(context, _drive.lastError ?? 'ফিরিয়ে আনা যায়নি', error: true);
      }
    } finally {
      if (mounted) setState(() => _busyRestore = false);
    }
  }

  // ------------------------------------------------------------------
  // UI
  // ------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final busy = _busyLocal || _busyRestore || _drive.isBusy;
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(title: const Text('ব্যাকআপ ও রিস্টোর')),
      body: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.fromLTRB(AppTheme.gutter, AppTheme.s8, AppTheme.gutter, 40),
            children: [
              // ---- Privacy note ----
              const NoteBox(
                icon: Icons.phonelink_lock_outlined,
                text: 'আপনার সব তথ্য শুধু আপনার ফোনেই থাকে। ফোন হারালে বা বদলালে যেন হিসাব না হারায়, তাই নিয়মিত ব্যাকআপ রাখুন। ব্যাকআপ ফাইল শুধু আপনার কাছে ও আপনার Google Drive-এ থাকে।',
              ),

              // ---- Local backup ----
              const SectionTitle('ফোনে ব্যাকআপ'),
              InfraCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.history_rounded, color: AppTheme.inkMuted, size: 20),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('সর্বশেষ ব্যাকআপ', style: AppTheme.caption),
                              const SizedBox(height: 2),
                              Text(
                                _lastAt == null
                                    ? 'এখনো ব্যাকআপ নেওয়া হয়নি'
                                    : bnDateTime(_lastAt),
                                style: AppTheme.bodyStrong,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    BigButton(
                      label: 'এখনই ব্যাকআপ নিন',
                      loading: _busyLocal,
                      onPressed: busy ? null : _backupNow,
                    ),
                    const SizedBox(height: 12),
                    BigButton(
                      label: 'শেয়ার / সেভ করুন',
                      icon: Icons.ios_share_rounded,
                      outlined: true,
                      onPressed: busy ? null : _share,
                    ),
                    const SizedBox(height: 8),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      value: _auto,
                      onChanged: _toggleAuto,
                      title: Text('অটো ব্যাকআপ', style: AppTheme.bodyStrong),
                      subtitle: Text(
                        'Wi‑Fi থাকলে দিনে একবার নিজে থেকে ব্যাকআপ (Drive-এ সাইন ইন থাকলে সেখানেও)',
                        style: AppTheme.caption,
                      ),
                    ),
                  ],
                ),
              ),
              // ---- Google Drive ----
              const SectionTitle('Google Drive'),
              InfraCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.cloud_outlined, color: AppTheme.inkMuted, size: 20),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _drive.isSignedIn
                              ? _AccountChip(
                                  email: _drive.account!.email,
                                  name: _drive.account!.displayName,
                                  photoUrl: _drive.account!.photoUrl,
                                  onSignOut: () async {
                                    await _drive.signOut();
                                    if (mounted) {
                                      setState(() => _driveBackups = const []);
                                    }
                                  },
                                )
                              : Text(
                                  'Google অ্যাকাউন্টে সাইন ইন করলে ব্যাকআপ ক্লাউডেও থাকবে — নতুন ফোনে সহজে ফিরিয়ে আনা যাবে।',
                                  style: AppTheme.bodySm.copyWith(height: 1.45, color: AppTheme.inkMuted),
                                ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    if (!_drive.isSignedIn)
                      BigButton(
                        label: 'Google দিয়ে সাইন ইন',
                        icon: Icons.login_rounded,
                        loading: _drive.isBusy,
                        onPressed: busy ? null : _driveSignIn,
                      )
                    else ...[
                      if (_lastDriveAt != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Text(
                            'Drive-এ সর্বশেষ: ${bnDateTime(_lastDriveAt)}',
                            style: AppTheme.caption.copyWith(color: AppTheme.slateMuted),
                          ),
                        ),
                      BigButton(
                        label: 'Drive-এ আপলোড করুন',
                        icon: Icons.cloud_upload_outlined,
                        loading: _drive.isBusy && !_busyRestore,
                        onPressed: busy ? null : _driveUpload,
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Text('Drive-এ থাকা ব্যাকআপ', style: AppTheme.bodyStrong),
                          const Spacer(),
                          IconButton(
                            tooltip: 'রিফ্রেশ',
                            onPressed: _loadingDrive ? null : _refreshDriveList,
                            icon: _loadingDrive
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2))
                                : const Icon(Icons.refresh_rounded, size: 20),
                          ),
                        ],
                      ),
                      if (_drive.lastError != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text(_drive.lastError!,
                              style: AppTheme.caption.copyWith(color: AppTheme.gaveRed)),
                        ),
                      if (_driveBackups.isEmpty && !_loadingDrive)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 8),
                          child: Text('Drive-এ কোনো ব্যাকআপ নেই', style: TextStyle(color: AppTheme.slateMuted)),
                        ),
                      for (final b in _driveBackups) ...[
                        const Divider(),
                        _DriveRow(
                          backup: b,
                          enabled: !busy,
                          onRestore: () => _driveRestore(b),
                        ),
                      ],
                    ],
                  ],
                ),
              ),
              // ---- Restore from file ----
              const SectionTitle('ফাইল থেকে ফিরিয়ে আনুন'),
              InfraCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.folder_zip_outlined, color: AppTheme.inkMuted, size: 20),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'আগে সেভ/শেয়ার করা dukandar-backup-….zip ফাইল বেছে নিন। বর্তমান তথ্য মুছে ব্যাকআপের তথ্য বসবে।',
                            style: AppTheme.bodySm.copyWith(height: 1.45, color: AppTheme.inkMuted),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    BigButton(
                      label: 'ফাইল বেছে ফিরিয়ে আনুন',
                      icon: Icons.restore_rounded,
                      outlined: true,
                      onPressed: busy ? null : _restoreFromFile,
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (_busyRestore)
            Container(
              color: Colors.black.withValues(alpha: 0.45),
              alignment: Alignment.center,
              child: InfraCard(
                padding: const EdgeInsets.all(28),
                child: const Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text('ফিরিয়ে আনা হচ্ছে… অ্যাপ বন্ধ করবেন না'),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _AccountChip extends StatelessWidget {
  const _AccountChip({
    required this.email,
    required this.name,
    required this.photoUrl,
    required this.onSignOut,
  });
  final String email;
  final String? name;
  final String? photoUrl;
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        CircleAvatar(
          radius: 16,
          backgroundColor: AppTheme.primaryBlueLight,
          foregroundImage: photoUrl != null ? NetworkImage(photoUrl!) : null,
          child: Text(
            (name ?? email).isNotEmpty
                ? (name ?? email).characters.first.toUpperCase()
                : '?',
            style: const TextStyle(color: AppTheme.primaryBlue, fontWeight: FontWeight.w600),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (name != null && name!.isNotEmpty)
                Text(name!, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTheme.bodyStrong),
              Text(email,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.caption.copyWith(color: AppTheme.slateMuted)),
            ],
          ),
        ),
        TextButton(
          onPressed: onSignOut,
          style: TextButton.styleFrom(
              foregroundColor: AppTheme.slateMuted,
              padding: const EdgeInsets.symmetric(horizontal: 8)),
          child: const Text('সাইন আউট'),
        ),
      ],
    );
  }
}

class _DriveRow extends StatelessWidget {
  const _DriveRow({
    required this.backup,
    required this.enabled,
    required this.onRestore,
  });
  final DriveBackup backup;
  final bool enabled;
  final VoidCallback onRestore;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          const Icon(Icons.folder_zip_outlined, color: AppTheme.inkMuted, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(bnDateTime(backup.createdTime), style: AppTheme.bodyStrong),
                const SizedBox(height: 2),
                Text(
                  '${BackupService.formatSize(backup.size)}  ·  ${backup.name}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.caption,
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: enabled ? onRestore : null,
            style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8)),
            child: const Text('ফিরিয়ে আনুন'),
          ),
        ],
      ),
    );
  }
}
