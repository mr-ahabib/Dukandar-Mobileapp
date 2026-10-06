import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Picks and stores photos inside `<appDocs>/photos/<id>.jpg`.
/// Photos never leave the device (except inside the user's own backup zip).
class PhotoHelper {
  PhotoHelper._();
  static final ImagePicker _picker = ImagePicker();

  static Future<Directory> photosDir() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, 'photos'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// Opens camera or gallery, compresses (quality 70, max width 800) and
  /// copies into the photos folder as `<id>.jpg`. Null if cancelled.
  static Future<String?> pickAndStore({required String id, required bool fromCamera}) async {
    try {
      final XFile? file = await _picker.pickImage(
        source: fromCamera ? ImageSource.camera : ImageSource.gallery,
        imageQuality: 70,
        maxWidth: 800,
      );
      if (file == null) return null;
      final dir = await photosDir();
      final target = File(p.join(dir.path, '$id.jpg'));
      await File(file.path).copy(target.path);
      _existsCache[target.path] = true;
      return target.path;
    } catch (e) {
      debugPrint('Photo pick error: $e');
      return null;
    }
  }

  static Future<void> delete(String? path) async {
    if (path == null) return;
    _existsCache.remove(path);
    try {
      final f = File(path);
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }

  /// path → exists. Bounded so a very long photo history can't grow it
  /// without limit; cleared by [invalidate] after a restore.
  static final Map<String, bool> _existsCache = <String, bool>{};
  static const int _cacheLimit = 512;

  /// Synchronous existence check memoised per path (safe to call in build).
  static bool exists(String? path) {
    if (path == null || path.isEmpty) return false;
    final hit = _existsCache[path];
    if (hit != null) return hit;
    bool v;
    try {
      v = File(path).existsSync();
    } catch (_) {
      v = false;
    }
    if (_existsCache.length >= _cacheLimit) _existsCache.remove(_existsCache.keys.first);
    _existsCache[path] = v;
    return v;
  }

  /// Drops cached answers (after a backup restore replaces the photos dir).
  static void invalidate([String? path]) {
    if (path == null) {
      _existsCache.clear();
    } else {
      _existsCache.remove(path);
    }
  }
}
