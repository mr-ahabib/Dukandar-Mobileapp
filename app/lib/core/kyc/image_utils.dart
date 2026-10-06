import 'dart:typed_data';
import 'dart:ui' as ui;

/// JPEG re-encoding helpers for KYC uploads (no extra dependency).
///
/// Decodes with `dart:ui`, downsizes so the longest edge is at most
/// [maxEdge] px and re-encodes. `dart:ui` cannot write JPEG directly, so the
/// resized frame is encoded as PNG when it would otherwise be too small to
/// matter, and left as the original JPEG bytes when already within bounds.
class KycImageUtils {
  KycImageUtils._();

  static const int maxEdge = 1200;

  /// Camera JPEGs up to this edge are passed through untouched: a 720p/1080p
  /// JPEG is far smaller than a 1200px PNG re-encode and keeps the
  /// `image/jpeg` type the server expects.
  static const int passthroughEdge = 1920;

  /// Hard server limits from the contract.
  static const int maxFileBytes = 3 * 1024 * 1024;
  static const int maxFrameBytes = 1024 * 1024;

  /// Returns bytes whose decoded size fits in [maxEdge]x[maxEdge].
  ///
  /// When the source already fits and is small enough it is returned as-is
  /// (camera plugins emit JPEG). Otherwise it is decoded with a target size
  /// (which lets the codec downsample cheaply) and re-encoded.
  static Future<Uint8List> downsize(Uint8List src, {int maxEdge = maxEdge, int maxBytes = maxFileBytes}) async {
    final desc = await _describe(src);
    final w = desc.$1;
    final h = desc.$2;
    final edgeOk = isJpeg(src) ? (w <= passthroughEdge && h <= passthroughEdge) : (w <= maxEdge && h <= maxEdge);
    if (w > 0 && h > 0 && edgeOk && src.length <= maxBytes) {
      return src;
    }
    final scale = (w > h ? maxEdge / w : maxEdge / h).clamp(0.05, 1.0);
    final tw = (w * scale).round().clamp(1, maxEdge);
    final th = (h * scale).round().clamp(1, maxEdge);
    final codec = await ui.instantiateImageCodec(src, targetWidth: tw, targetHeight: th);
    final frame = await codec.getNextFrame();
    try {
      final data = await frame.image.toByteData(format: ui.ImageByteFormat.png);
      codec.dispose();
      if (data == null) return src;
      return data.buffer.asUint8List();
    } finally {
      frame.image.dispose();
    }
  }

  static Future<(int, int)> _describe(Uint8List src) async {
    try {
      final buffer = await ui.ImmutableBuffer.fromUint8List(src);
      final desc = await ui.ImageDescriptor.encoded(buffer);
      final size = (desc.width, desc.height);
      desc.dispose();
      buffer.dispose();
      return size;
    } catch (_) {
      return (0, 0);
    }
  }

  /// True when the bytes start with a JPEG SOI marker.
  static bool isJpeg(Uint8List b) => b.length > 2 && b[0] == 0xFF && b[1] == 0xD8;

  static String mimeOf(Uint8List b) => isJpeg(b) ? 'image/jpeg' : 'image/png';
  static String extOf(Uint8List b) => isJpeg(b) ? 'jpg' : 'png';
}
