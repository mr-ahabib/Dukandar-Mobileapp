import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/kyc/image_utils.dart';
import '../../../core/kyc/liveness_challenge.dart';
import '../../../core/theme/app_theme.dart';
import '../../../widgets/infra_widgets.dart' show bn;
import 'camera_permission_screen.dart';

/// What the liveness step hands back to the registration flow.
class LivenessOutcome {
  const LivenessOutcome({required this.selfie, required this.frames, required this.liveness});
  final Uint8List selfie;
  final List<Uint8List> frames;
  final Map<String, dynamic> liveness;
}

/// Front-camera live face check driven by ML Kit + [LivenessController].
///
/// Challenge order: look at camera → blink → smile → turn head left.
/// Each pass captures a frame (best effort), the final selfie is taken after
/// the stream stops. 60 s timeout offers a retry.
class LivenessScreen extends StatefulWidget {
  const LivenessScreen({super.key});

  @override
  State<LivenessScreen> createState() => _LivenessScreenState();
}

class _LivenessScreenState extends State<LivenessScreen> with WidgetsBindingObserver {
  CameraController? _camera;
  CameraDescription? _desc;
  FaceDetector? _detector;
  LivenessController _flow = LivenessController();
  final List<Uint8List> _frames = [];

  bool _processing = false;
  bool _capturing = false;
  bool _finishing = false;
  bool _permissionDenied = false;
  String? _error;
  Timer? _ticker;
  bool _wasDone = false;

  // Detection health / self-healing rotation.
  bool _firstResult = false; // first successful processImage() → model ready
  DateTime? _firstFrameAt;
  int _detectErrors = 0;
  String? _detectErrorMsg;
  String? _rawDetectError; // last raw exception text (for diagnostics copy)
  int _noFaceStreak = 0;
  int _rotIndex = 0;
  bool _rotLocked = false;
  int _rotDegrees = 270;
  DateTime _lastProcessed = DateTime.fromMillisecondsSinceEpoch(0);
  static const _minFrameGap = Duration(milliseconds: 125); // ≈8 fps
  static const _noFaceFramesBeforeRotate = 15;
  static const _modelWait = Duration(seconds: 45);

  // Live feedback.
  String _feedbackBn = '';
  String _debugLine = '';
  int _failedAttempts = 0;
  bool _pickingGallery = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _detector = FaceDetector(
      options: FaceDetectorOptions(
        enableClassification: true,
        enableTracking: true,
        performanceMode: FaceDetectorMode.fast,
        minFaceSize: 0.15,
      ),
    );
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      // Drive the timeout even when no frame arrives (no face → no feed).
      // Only once detection is actually producing results; the model may
      // still be downloading before that.
      if (_firstResult && !_flow.isDone && _flow.remaining == Duration.zero) {
        _flow.feed(const FaceSample.none());
        _onFlowMaybeDone();
      }
      // Model never answered: give up with a retry instead of a silent hang.
      final ff = _firstFrameAt;
      if (!_firstResult && _error == null && ff != null && DateTime.now().difference(ff) > _modelWait) {
        _error = _detectErrorMsg ?? 'ফেস মডেল লোড হয়নি। ইন্টারনেট চালু রেখে আবার চেষ্টা করুন।';
      }
      setState(() {});
    });
    _init();
  }

  Future<void> _init() async {
    try {
      final cams = await availableCameras();
      if (cams.isEmpty) {
        setState(() => _error = 'এই ফোনে ক্যামেরা পাওয়া যায়নি।');
        return;
      }
      final front = cams.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cams.first,
      );
      final c = CameraController(
        front,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: Platform.isAndroid ? ImageFormatGroup.nv21 : ImageFormatGroup.bgra8888,
      );
      await c.initialize();
      if (!mounted) {
        await c.dispose();
        return;
      }
      _desc = front;
      _rotIndex = 0;
      _rotLocked = false;
      _rotDegrees = _computedRotation(front, c);
      setState(() => _camera = c);
      await c.startImageStream(_onFrame);
    } on CameraException catch (e) {
      if (!mounted) return;
      final code = e.code.toLowerCase();
      final denied = code.contains('denied') || code.contains('permission');
      setState(() {
        _permissionDenied = denied;
        _error = denied ? null : 'ক্যামেরা চালু করা যায়নি। আবার চেষ্টা করুন।';
      });
    } catch (_) {
      if (mounted) setState(() => _error = 'ক্যামেরা চালু করা যায়নি। আবার চেষ্টা করুন।');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive || state == AppLifecycleState.paused) {
      _teardownCamera();
    } else if (state == AppLifecycleState.resumed && _camera == null && !_finishing) {
      _init();
    }
  }

  Future<void> _teardownCamera() async {
    final c = _camera;
    _camera = null;
    if (c == null) return;
    try {
      if (c.value.isStreamingImages) await c.stopImageStream();
    } catch (_) {}
    await c.dispose();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker?.cancel();
    _teardownCamera();
    _detector?.close();
    super.dispose();
  }

  // ---------------------------------------------------------------------
  // Frame processing
  // ---------------------------------------------------------------------

  Future<void> _onFrame(CameraImage img) async {
    if (_processing || _finishing || _flow.isDone || !mounted) return;
    final now = DateTime.now();
    if (now.difference(_lastProcessed) < _minFrameGap) return; // throttle ≈8 fps
    final det = _detector;
    final desc = _desc;
    final cam = _camera;
    if (det == null || desc == null || cam == null) return;
    _processing = true;
    _lastProcessed = now;
    _firstFrameAt ??= now;
    try {
      final rotDeg = _currentRotation(desc, cam);
      final input = _toInputImage(img, rotDeg);
      if (input == null) {
        _detectErrorMsg = 'ক্যামেরার ছবির ফরম্যাট (${img.format.raw}) সাপোর্ট করে না।';
        _rawDetectError = 'unsupported format raw=${img.format.raw} planes=${img.planes.length} ${img.width}x${img.height}';
        _detectErrors++;
        return;
      }
      final faces = await det.processImage(input);
      if (!_firstResult) {
        _firstResult = true;
        _detectErrors = 0;
        _detectErrorMsg = null;
        // Start the 60 s clock only once detection actually works.
        _flow = LivenessController();
      }
      _selfHealRotation(faces.length);
      final rotated = rotDeg == 90 || rotDeg == 270;
      final frameW = rotated ? img.height.toDouble() : img.width.toDouble();
      final frameH = rotated ? img.width.toDouble() : img.height.toDouble();
      final sample = _sample(faces, frameW, frameH);
      final advanced = _flow.feed(sample);
      _updateFeedback(sample, rotDeg);
      if (advanced && !_flow.isDone) {
        unawaited(_captureFrame());
      }
      _onFlowMaybeDone();
      if (mounted) setState(() {});
    } catch (e) {
      // ML Kit throws while the model is still downloading via Play
      // Services ("Waiting for the face detection model to be downloaded")
      // or when Play Services is missing. Keep the spinner; the ticker
      // turns it into a retryable error after _modelWait.
      _detectErrors++;
      _detectErrorMsg = _bnDetectError(e);
      _rawDetectError = e.toString();
      if (kDebugMode) _debugLine = 'detect error #$_detectErrors: $e';
      if (mounted && _detectErrors % 8 == 1) setState(() {});
    } finally {
      _processing = false;
    }
  }

  void _onFlowMaybeDone() {
    if (_flow.isDone && !_wasDone) {
      _wasDone = true;
      if (!_flow.passed) _failedAttempts++;
      unawaited(_finish());
    }
  }

  String _bnDetectError(Object e) {
    final m = e.toString().toLowerCase();
    if (m.contains('download') || m.contains('waiting') || m.contains('unavailable') || m.contains('model')) {
      return 'ফেস মডেল ডাউনলোড হয়নি। ইন্টারনেট ও Google Play Services চালু রেখে আবার চেষ্টা করুন।';
    }
    return 'ফেস ডিটেকশন কাজ করছে না। আবার চেষ্টা করুন।';
  }

  /// After [_noFaceFramesBeforeRotate] consecutive empty results, try the
  /// next rotation; lock onto the first one that yields a face.
  void _selfHealRotation(int faceCount) {
    if (faceCount > 0) {
      _noFaceStreak = 0;
      _rotLocked = true;
      return;
    }
    if (_rotLocked) return;
    _noFaceStreak++;
    if (_noFaceStreak >= _noFaceFramesBeforeRotate) {
      _noFaceStreak = 0;
      _rotIndex++;
    }
  }

  int _computedRotation(CameraDescription desc, CameraController cam) {
    if (Platform.isIOS) return desc.sensorOrientation;
    return livenessRotationDegrees(
      sensorOrientation: desc.sensorOrientation,
      deviceDegrees: _orientations[cam.value.deviceOrientation],
      isFront: desc.lensDirection == CameraLensDirection.front,
    );
  }

  int _currentRotation(CameraDescription desc, CameraController cam) {
    if (_rotLocked) return _rotDegrees;
    final cands = rotationCandidates(_computedRotation(desc, cam));
    _rotDegrees = cands[_rotIndex % cands.length];
    return _rotDegrees;
  }

  void _updateFeedback(FaceSample s, int rotDeg) {
    final framing = LivenessController.framingFeedbackBn(s);
    _feedbackBn = framing ?? (_flow.hintBn.isNotEmpty ? _flow.hintBn : 'স্থির থাকুন ✓');
    if (kDebugMode) {
      String f(double? v) => v == null ? '-' : v.toStringAsFixed(2);
      _debugLine = 'faces: ${s.faceCount}, size: ${f(s.widthRatio)}, off: ${f(s.centerOffset)}, '
          'yaw: ${s.headEulerY?.toStringAsFixed(0) ?? '-'}, eyes: ${f(s.leftEyeOpen)}/${f(s.rightEyeOpen)}, '
          'smile: ${f(s.smiling)}, rot: $rotDeg${_rotLocked ? '' : '?'}';
    }
  }

  FaceSample _sample(List<Face> faces, double w, double h) {
    if (faces.isEmpty) return const FaceSample.none();
    if (faces.length > 1) return FaceSample(faceCount: faces.length);
    final f = faces.first;
    final box = f.boundingBox;
    final cx = w == 0 ? 0.0 : ((box.center.dx - w / 2) / (w / 2)).abs();
    final cy = h == 0 ? 0.0 : ((box.center.dy - h / 2) / (h / 2)).abs();
    final offset = cx > cy ? cx : cy;
    return FaceSample(
      faceCount: 1,
      widthRatio: w == 0 ? 0 : (box.width / w).clamp(0, 1),
      centerOffset: offset.clamp(0, 1),
      leftEyeOpen: f.leftEyeOpenProbability,
      rightEyeOpen: f.rightEyeOpenProbability,
      smiling: f.smilingProbability,
      headEulerY: f.headEulerAngleY,
      trackingId: f.trackingId,
    );
  }

  static const _orientations = {
    DeviceOrientation.portraitUp: 0,
    DeviceOrientation.landscapeLeft: 90,
    DeviceOrientation.portraitDown: 180,
    DeviceOrientation.landscapeRight: 270,
  };

  /// Converts a camera frame for ML Kit. On Android camerax 0.7 the raw
  /// format may report 35 (YUV_420_888) even when NV21 was requested, and
  /// may deliver 1 or 3 planes; both are normalised to packed NV21.
  InputImage? _toInputImage(CameraImage img, int rotDeg) {
    final rotation = InputImageRotationValue.fromRawValue(rotDeg);
    if (rotation == null || img.planes.isEmpty) return null;
    if (Platform.isIOS) {
      final p = img.planes.first;
      return InputImage.fromBytes(
        bytes: p.bytes,
        metadata: InputImageMetadata(
          size: Size(img.width.toDouble(), img.height.toDouble()),
          rotation: rotation,
          format: InputImageFormat.bgra8888,
          bytesPerRow: p.bytesPerRow,
        ),
      );
    }
    final raw = img.format.raw;
    final rawInt = raw is int ? raw : int.tryParse('$raw') ?? -1;
    final group = img.format.group;
    final yuvLike = rawInt == 17 || rawInt == 35 || group == ImageFormatGroup.nv21 || group == ImageFormatGroup.yuv420;
    if (!yuvLike) return null;
    final Uint8List bytes;
    final int bytesPerRow;
    if (img.planes.length == 1) {
      bytes = img.planes[0].bytes;
      bytesPerRow = img.planes[0].bytesPerRow;
    } else if (img.planes.length >= 3) {
      final y = img.planes[0];
      final u = img.planes[1];
      final v = img.planes[2];
      bytes = nv21FromYuv420(
        width: img.width,
        height: img.height,
        y: y.bytes,
        u: u.bytes,
        v: v.bytes,
        yRowStride: y.bytesPerRow,
        uvRowStride: u.bytesPerRow,
        uvPixelStride: u.bytesPerPixel ?? 1,
      );
      bytesPerRow = img.width;
    } else {
      return null;
    }
    return InputImage.fromBytes(
      bytes: bytes,
      metadata: InputImageMetadata(
        size: Size(img.width.toDouble(), img.height.toDouble()),
        rotation: rotation,
        format: InputImageFormat.nv21,
        bytesPerRow: bytesPerRow,
      ),
    );
  }

  /// Best-effort still for a passed challenge (max 3 are uploaded).
  Future<void> _captureFrame() async {
    final c = _camera;
    if (c == null || _capturing || _frames.length >= 3) return;
    _capturing = true;
    try {
      final x = await c.takePicture();
      final b = await KycImageUtils.downsize(await x.readAsBytes(), maxEdge: 800, maxBytes: KycImageUtils.maxFrameBytes);
      if (_frames.length < 3) _frames.add(b);
    } catch (_) {
      // Some devices cannot take a still while streaming; frames are optional.
    } finally {
      _capturing = false;
    }
  }

  Future<void> _finish() async {
    if (_finishing) return;
    _finishing = true;
    if (mounted) setState(() {});
    if (!_flow.passed) {
      // Timed out.
      _finishing = false;
      if (mounted) setState(() {});
      return;
    }
    final c = _camera;
    Uint8List? selfie;
    try {
      if (c != null) {
        if (c.value.isStreamingImages) await c.stopImageStream();
        // Let the preview settle so the selfie is not the "turned" pose.
        await Future<void>.delayed(const Duration(milliseconds: 350));
        final x = await c.takePicture();
        selfie = await KycImageUtils.downsize(await x.readAsBytes());
      }
    } catch (_) {}
    selfie ??= _frames.isNotEmpty ? _frames.last : null;
    if (!mounted) return;
    if (selfie == null) {
      setState(() {
        _finishing = false;
        _error = 'সেলফি তোলা যায়নি। আবার চেষ্টা করুন।';
      });
      return;
    }
    Navigator.pop(
      context,
      LivenessOutcome(
        selfie: selfie,
        frames: List.unmodifiable(_frames),
        liveness: _flow.toJson(capturedAt: DateTime.now()),
      ),
    );
  }

  Future<void> _retry() async {
    _flow = LivenessController();
    _frames.clear();
    _wasDone = false;
    _finishing = false;
    _error = null;
    _feedbackBn = '';
    _detectErrors = 0;
    _detectErrorMsg = null;
    _noFaceStreak = 0;
    if (!_firstResult) {
      // Model never answered: restart the wait window too.
      _firstFrameAt = null;
    }
    setState(() {});
    final c = _camera;
    if (c == null) {
      await _init();
    } else if (!c.value.isStreamingImages) {
      try {
        await c.startImageStream(_onFrame);
      } catch (_) {}
    }
  }

  /// Fallback after repeated failures: a gallery selfie so the user can see
  /// the rest of the flow. Liveness stays `passed: false` (never faked); the
  /// server requires a live pass, so the review step cannot submit with it.
  Future<void> _pickFromGallery() async {
    if (_pickingGallery) return;
    _pickingGallery = true;
    setState(() {});
    try {
      final x = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 90);
      if (x == null || !mounted) return;
      final selfie = await KycImageUtils.downsize(await x.readAsBytes());
      if (!mounted) return;
      final liveness = LivenessController().toJson(capturedAt: DateTime.now())
        ..['passed'] = false
        ..['challenges'] = <String>[]
        ..['score'] = 0.0
        ..['fallback'] = 'manual_selfie';
      Navigator.pop(context, LivenessOutcome(selfie: selfie, frames: const [], liveness: liveness));
    } catch (_) {
      if (mounted) setState(() => _error = 'ছবি নেওয়া যায়নি। আবার চেষ্টা করুন।');
    } finally {
      _pickingGallery = false;
      if (mounted) setState(() {});
    }
  }

  // ---------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    if (_permissionDenied) {
      return CameraPermissionScreen(
        title: 'লাইভ ফেস যাচাই',
        onRetry: () {
          setState(() => _permissionDenied = false);
          _init();
        },
      );
    }
    final timedOut = _flow.timedOut || (_flow.isDone && !_flow.passed);
    final stepIndex = switch (_flow.step) {
      LivenessStep.lookAtCamera => 0,
      LivenessStep.blink => 1,
      LivenessStep.smile => 2,
      LivenessStep.turnLeft => 3,
      LivenessStep.done => 4,
    };
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('লাইভ ফেস যাচাই'),
      ),
      body: Column(children: [
        Expanded(
          child: Stack(fit: StackFit.expand, children: [
            _CameraFill(controller: _camera, error: _error),
            CustomPaint(painter: _OvalGuidePainter(progress: stepIndex / 4)),
            if (_finishing || _pickingGallery)
              Container(
                color: Colors.black45,
                alignment: Alignment.center,
                child: const CircularProgressIndicator(color: Colors.white),
              )
            else if (!_firstResult && _camera != null && _error == null)
              Container(
                color: Colors.black38,
                alignment: Alignment.center,
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const CircularProgressIndicator(color: Colors.white),
                  const SizedBox(height: 12),
                  Text('ফেস মডেল লোড হচ্ছে…', style: AppTheme.body.copyWith(color: Colors.white)),
                  const SizedBox(height: 4),
                  Text('প্রথমবার ১০–৩০ সেকেন্ড লাগতে পারে', style: AppTheme.caption.copyWith(color: Colors.white70)),
                ]),
              ),
            if (_firstResult)
              Positioned(
                top: 12,
                right: 16,
                child: _Timer(remaining: _flow.remaining),
              ),
            if (kDebugMode && _debugLine.isNotEmpty)
              Positioned(
                left: 8,
                right: 8,
                bottom: 8,
                child: Text(
                  _debugLine,
                  style: const TextStyle(color: Colors.yellowAccent, fontSize: 11, fontFamily: 'monospace'),
                ),
              ),
          ]),
        ),
        Container(
          color: Colors.black,
          padding: const EdgeInsets.fromLTRB(AppTheme.gutter, AppTheme.s16, AppTheme.gutter, AppTheme.s24),
          child: SafeArea(
            top: false,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              _StepDots(current: stepIndex),
              const SizedBox(height: AppTheme.s16),
              if (timedOut) ...[
                Text('সময় শেষ', style: AppTheme.title.copyWith(color: Colors.white)),
                const SizedBox(height: 6),
                Text(
                  'মুখ স্পষ্ট দেখা যায়নি বা নির্দেশ অনুসরণ হয়নি। আলো আছে এমন জায়গায় আবার চেষ্টা করুন।',
                  textAlign: TextAlign.center,
                  style: AppTheme.bodySm.copyWith(color: Colors.white70, height: 1.4),
                ),
                const SizedBox(height: AppTheme.s16),
                SizedBox(
                  width: double.infinity,
                  height: AppTheme.controlHeight,
                  child: FilledButton.icon(
                    onPressed: _retry,
                    icon: const Icon(Icons.replay_rounded),
                    label: const Text('আবার চেষ্টা করুন'),
                  ),
                ),
                if (_failedAttempts >= 2) ...[
                  const SizedBox(height: AppTheme.s12),
                  TextButton.icon(
                    onPressed: _pickingGallery ? null : _pickFromGallery,
                    icon: const Icon(Icons.photo_library_outlined, color: Colors.white70),
                    label: const Text('সমস্যা হচ্ছে? গ্যালারি থেকে সেলফি দিন', style: TextStyle(color: Colors.white70)),
                  ),
                  Text(
                    'গ্যালারির ছবিতে লাইভ যাচাই হবে না; জমা দিতে লাইভ যাচাই লাগবে।',
                    textAlign: TextAlign.center,
                    style: AppTheme.caption.copyWith(color: Colors.white54),
                  ),
                ],
              ] else ...[
                Text(
                  _flow.instructionBn,
                  textAlign: TextAlign.center,
                  style: AppTheme.headline.copyWith(color: Colors.white),
                ),
                const SizedBox(height: 6),
                Text(
                  _error ??
                      (!_firstResult
                          ? 'ক্যামেরার সামনে মুখ রাখুন, মডেল প্রস্তুত হলে শুরু হবে'
                          : (_feedbackBn.isNotEmpty ? _feedbackBn : 'মুখ ডিম্বাকার ঘরের মধ্যে রাখুন')),
                  textAlign: TextAlign.center,
                  style: AppTheme.bodySm.copyWith(
                    color: _error != null
                        ? AppTheme.saffron
                        : (_feedbackBn.endsWith('✓') ? AppTheme.accentEmerald : Colors.white70),
                  ),
                ),
                if (_error != null) ...[
                  if (_rawDetectError != null) ...[
                    const SizedBox(height: AppTheme.s8),
                    Text(
                      _rawDetectError!,
                      textAlign: TextAlign.center,
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white54, fontSize: 11, fontFamily: 'monospace'),
                    ),
                  ],
                  const SizedBox(height: AppTheme.s12),
                  Wrap(spacing: AppTheme.s8, alignment: WrapAlignment.center, children: [
                    TextButton.icon(
                      onPressed: _retry,
                      icon: const Icon(Icons.replay_rounded, color: Colors.white),
                      label: const Text('আবার চেষ্টা করুন', style: TextStyle(color: Colors.white)),
                    ),
                    TextButton.icon(
                      onPressed: () {
                        final diag = 'liveness error: ${_error ?? ''}\nraw: ${_rawDetectError ?? '-'}\ndebug: $_debugLine\nerrors: $_detectErrors';
                        Clipboard.setData(ClipboardData(text: diag));
                        ScaffoldMessenger.maybeOf(context)?.showSnackBar(const SnackBar(content: Text('ডায়াগনস্টিক কপি হয়েছে')));
                      },
                      icon: const Icon(Icons.copy_rounded, color: Colors.white70, size: 18),
                      label: const Text('ডায়াগনস্টিক কপি', style: TextStyle(color: Colors.white70)),
                    ),
                  ]),
                ],
              ],
            ]),
          ),
        ),
      ]),
    );
  }
}

class _CameraFill extends StatelessWidget {
  const _CameraFill({required this.controller, required this.error});
  final CameraController? controller;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    if (c == null || !c.value.isInitialized) {
      if (error != null) return const SizedBox.shrink();
      return const Center(child: CircularProgressIndicator(color: Colors.white));
    }
    return LayoutBuilder(builder: (context, box) {
      return ClipRect(
        child: OverflowBox(
          alignment: Alignment.center,
          maxWidth: double.infinity,
          maxHeight: double.infinity,
          child: SizedBox(
            width: box.maxWidth,
            height: box.maxWidth * c.value.aspectRatio,
            child: CameraPreview(c),
          ),
        ),
      );
    });
  }
}

/// Dim everything outside a face-shaped oval; the ring fills with progress.
class _OvalGuidePainter extends CustomPainter {
  _OvalGuidePainter({required this.progress});
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width * 0.70;
    final h = w * 1.3;
    final rect = Rect.fromCenter(center: Offset(size.width / 2, size.height / 2), width: w, height: h);
    final overlay = Path()
      ..addRect(Offset.zero & size)
      ..addOval(rect)
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(overlay, Paint()..color = Colors.black.withValues(alpha: 0.55));
    canvas.drawOval(
      rect,
      Paint()
        ..color = Colors.white38
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
    if (progress > 0) {
      canvas.drawArc(
        rect,
        -1.5708,
        6.2832 * progress.clamp(0, 1),
        false,
        Paint()
          ..color = AppTheme.accentEmerald
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _OvalGuidePainter old) => old.progress != progress;
}

class _StepDots extends StatelessWidget {
  const _StepDots({required this.current});
  final int current;
  static const _labels = ['তাকান', 'পলক', 'হাসি', 'বামে'];

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < 4; i++) ...[
          if (i > 0) const SizedBox(width: 14),
          Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 26,
              height: 26,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: i < current ? AppTheme.accentEmerald : (i == current ? Colors.white : Colors.white24),
              ),
              child: i < current
                  ? const Icon(Icons.check_rounded, size: 16, color: Colors.white)
                  : Text(bn(i + 1), style: AppTheme.label.copyWith(color: i == current ? AppTheme.navy : Colors.white70)),
            ),
            const SizedBox(height: 4),
            Text(_labels[i], style: AppTheme.label.copyWith(color: Colors.white70)),
          ]),
        ],
      ],
    );
  }
}

class _Timer extends StatelessWidget {
  const _Timer({required this.remaining});
  final Duration remaining;

  @override
  Widget build(BuildContext context) {
    final s = remaining.inSeconds;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(999)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.timer_outlined, size: 14, color: s <= 10 ? AppTheme.saffron : Colors.white70),
        const SizedBox(width: 4),
        Text('${bn(s)} সে.', style: AppTheme.label.copyWith(color: s <= 10 ? AppTheme.saffron : Colors.white70, fontFeatures: AppTheme.tabular)),
      ]),
    );
  }
}
