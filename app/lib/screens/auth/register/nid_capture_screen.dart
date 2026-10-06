import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/kyc/image_utils.dart';
import '../../../core/theme/app_theme.dart';
import '../../../widgets/common_widgets.dart' show BottomActionBar, PrimaryButton, TonalButton;
import '../../../widgets/infra_widgets.dart' show showSnack;
import 'camera_permission_screen.dart';

/// Full-screen rear-camera capture with an ID-card guide frame.
/// Pops with the downsized image bytes, or null when cancelled.
class NidCaptureScreen extends StatefulWidget {
  const NidCaptureScreen({super.key, required this.title, required this.hint});
  final String title;
  final String hint;

  /// Gallery fallback (also used when the device has no camera).
  static Future<Uint8List?> pickFromGallery() async {
    try {
      final x = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: KycImageUtils.maxEdge.toDouble(),
        maxHeight: KycImageUtils.maxEdge.toDouble(),
        imageQuality: 80,
      );
      if (x == null) return null;
      return await KycImageUtils.downsize(await x.readAsBytes());
    } catch (_) {
      return null;
    }
  }

  @override
  State<NidCaptureScreen> createState() => _NidCaptureScreenState();
}

class _NidCaptureScreenState extends State<NidCaptureScreen> with WidgetsBindingObserver {
  CameraController? _controller;
  Uint8List? _shot;
  bool _busy = false;
  bool _permissionDenied = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _init();
  }

  Future<void> _init() async {
    try {
      final cams = await availableCameras();
      if (cams.isEmpty) {
        setState(() => _error = 'এই ফোনে ক্যামেরা পাওয়া যায়নি। গ্যালারি থেকে ছবি দিন।');
        return;
      }
      final rear = cams.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cams.first,
      );
      final c = CameraController(rear, ResolutionPreset.high, enableAudio: false);
      await c.initialize();
      try {
        await c.setFlashMode(FlashMode.off);
      } catch (_) {}
      if (!mounted) {
        await c.dispose();
        return;
      }
      setState(() => _controller = c);
    } on CameraException catch (e) {
      if (!mounted) return;
      final denied = e.code.toLowerCase().contains('denied') || e.code.toLowerCase().contains('permission');
      setState(() {
        _permissionDenied = denied;
        _error = denied ? null : 'ক্যামেরা চালু করা যায়নি। গ্যালারি থেকে ছবি দিন।';
      });
    } catch (_) {
      if (mounted) setState(() => _error = 'ক্যামেরা চালু করা যায়নি। গ্যালারি থেকে ছবি দিন।');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final c = _controller;
    if (c == null) return;
    if (state == AppLifecycleState.inactive || state == AppLifecycleState.paused) {
      c.dispose();
      _controller = null;
    } else if (state == AppLifecycleState.resumed) {
      _init();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _take() async {
    final c = _controller;
    if (c == null || _busy || !c.value.isInitialized) return;
    setState(() => _busy = true);
    try {
      final x = await c.takePicture();
      final bytes = await KycImageUtils.downsize(await x.readAsBytes());
      if (!mounted) return;
      setState(() => _shot = bytes);
    } catch (_) {
      if (mounted) showSnack(context, 'ছবি তোলা যায়নি। আবার চেষ্টা করুন।', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _gallery() async {
    setState(() => _busy = true);
    final bytes = await NidCaptureScreen.pickFromGallery();
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (bytes != null) _shot = bytes;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_permissionDenied) {
      return CameraPermissionScreen(
        title: widget.title,
        onRetry: () {
          setState(() => _permissionDenied = false);
          _init();
        },
        onGallery: () async {
          final b = await NidCaptureScreen.pickFromGallery();
          if (context.mounted && b != null) Navigator.pop(context, b);
        },
      );
    }
    final shot = _shot;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(widget.title),
      ),
      body: Column(
        children: [
          Expanded(
            child: shot != null
                ? Center(child: Image.memory(shot, fit: BoxFit.contain))
                : _Preview(controller: _controller, error: _error),
          ),
          Container(
            color: Colors.black,
            padding: const EdgeInsets.fromLTRB(AppTheme.gutter, AppTheme.s12, AppTheme.gutter, 0),
            child: Text(
              shot != null ? 'ছবি স্পষ্ট ও পুরো কার্ড দেখা যাচ্ছে কি?' : widget.hint,
              textAlign: TextAlign.center,
              style: AppTheme.bodySm.copyWith(color: Colors.white70, height: 1.4),
            ),
          ),
          if (shot != null)
            BottomActionBar(
              secondary: TonalButton(
                label: 'আবার তুলুন',
                icon: Icons.replay_rounded,
                expanded: false,
                onPressed: () => setState(() => _shot = null),
              ),
              primary: PrimaryButton(
                label: 'ঠিক আছে',
                icon: Icons.check_rounded,
                onPressed: () => Navigator.pop(context, shot),
              ),
            )
          else
            BottomActionBar(
              secondary: TonalButton(
                label: 'গ্যালারি',
                icon: Icons.photo_library_outlined,
                expanded: false,
                onPressed: _busy ? null : _gallery,
              ),
              primary: PrimaryButton(
                label: 'ছবি তুলুন',
                icon: Icons.photo_camera_rounded,
                loading: _busy,
                onPressed: _controller?.value.isInitialized == true ? _take : null,
              ),
            ),
        ],
      ),
    );
  }
}

class _Preview extends StatelessWidget {
  const _Preview({required this.controller, required this.error});
  final CameraController? controller;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    if (error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppTheme.s24),
          child: Text(error!, textAlign: TextAlign.center, style: AppTheme.body.copyWith(color: Colors.white70)),
        ),
      );
    }
    if (c == null || !c.value.isInitialized) {
      return const Center(child: CircularProgressIndicator(color: Colors.white));
    }
    return LayoutBuilder(builder: (context, box) {
      final previewAspect = c.value.aspectRatio; // width/height (landscape sensor)
      return Stack(fit: StackFit.expand, children: [
        ClipRect(
          child: OverflowBox(
            alignment: Alignment.center,
            maxWidth: double.infinity,
            maxHeight: double.infinity,
            child: SizedBox(
              width: box.maxWidth,
              height: box.maxWidth * previewAspect,
              child: CameraPreview(c),
            ),
          ),
        ),
        CustomPaint(painter: _CardGuidePainter()),
      ]);
    });
  }
}

/// Dim everything except an ID-card shaped window (ISO 7810 ratio 1.586).
class _CardGuidePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width * 0.88;
    final h = w / 1.586;
    final rect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset(size.width / 2, size.height / 2), width: w, height: h),
      const Radius.circular(14),
    );
    final overlay = Path()
      ..addRect(Offset.zero & size)
      ..addRRect(rect)
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(overlay, Paint()..color = Colors.black.withValues(alpha: 0.55));
    canvas.drawRRect(
      rect,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
