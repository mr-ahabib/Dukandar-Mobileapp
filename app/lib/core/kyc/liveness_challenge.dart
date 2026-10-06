import 'dart:typed_data';

/// Pure-Dart liveness challenge state machine (no camera / ML Kit types) so
/// it can be unit-tested. The screen feeds it one [FaceSample] per detected
/// frame and reacts to [LivenessStep] transitions.
enum LivenessStep { lookAtCamera, blink, smile, turnLeft, done }

/// Sanitised view of one ML Kit face in a frame.
class FaceSample {
  const FaceSample({
    required this.faceCount,
    this.widthRatio = 0,
    this.centerOffset = 1,
    this.leftEyeOpen,
    this.rightEyeOpen,
    this.smiling,
    this.headEulerY,
    this.trackingId,
  });

  /// Frame with no face at all.
  const FaceSample.none() : this(faceCount: 0);

  final int faceCount;

  /// Face width / frame width (0..1).
  final double widthRatio;

  /// Distance of the face centre from the frame centre, normalised by the
  /// frame's half-size (0 = perfectly centred, 1 = at the edge).
  final double centerOffset;
  final double? leftEyeOpen;
  final double? rightEyeOpen;
  final double? smiling;
  final double? headEulerY;
  final int? trackingId;

  bool get hasSingleFace => faceCount == 1;
}

class ChallengeResult {
  const ChallengeResult({required this.name, required this.confidence, required this.at});
  final String name;
  final double confidence;
  final DateTime at;

  Map<String, dynamic> toJson() => {
        'name': name,
        'confidence': double.parse(confidence.toStringAsFixed(3)),
        'at': at.toUtc().toIso8601String(),
      };
}

class LivenessController {
  LivenessController({DateTime Function()? clock, this.timeout = const Duration(seconds: 60)})
      : _clock = clock ?? DateTime.now {
    _startedAt = _clock();
  }

  final DateTime Function() _clock;
  final Duration timeout;
  late final DateTime _startedAt;

  LivenessStep step = LivenessStep.lookAtCamera;
  final List<ChallengeResult> results = [];

  /// Frames the controller asks the screen to capture (one per challenge).
  int captureRequests = 0;

  // ---- per-step scratch ----
  int _stableFrames = 0;
  bool _eyesClosedSeen = false;
  double _blinkMin = 1;
  int? _trackingId;
  bool _timedOut = false;

  // Thresholds are deliberately forgiving: ML Kit's fast mode on a budget
  // phone in a dim shop is noisy, and a stuck step is worse than a lenient
  // one (the server re-checks the selfie anyway).
  static const int requiredStableFrames = 3;
  static const double minFaceWidth = 0.18;
  static const double maxFaceWidth = 0.95;
  static const double maxCenterOffset = 0.6;
  static const double eyeClosed = 0.4;
  static const double eyeOpen = 0.6;
  static const double smileThreshold = 0.6;
  static const double turnDeg = 18;

  bool get isDone => step == LivenessStep.done;
  bool get timedOut => _timedOut;
  bool get passed => isDone && !_timedOut && results.length == 4;

  /// Mean confidence over passed challenges (0..1).
  double get score {
    if (results.isEmpty) return 0;
    final sum = results.fold<double>(0, (a, r) => a + r.confidence);
    return (sum / results.length).clamp(0, 1);
  }

  Duration get elapsed => _clock().difference(_startedAt);
  Duration get remaining {
    final r = timeout - elapsed;
    return r.isNegative ? Duration.zero : r;
  }

  /// Bangla instruction for the current step.
  String get instructionBn => switch (step) {
        LivenessStep.lookAtCamera => 'ক্যামেরার দিকে তাকান',
        LivenessStep.blink => 'চোখ পিটপিট করুন',
        LivenessStep.smile => 'হাসুন',
        LivenessStep.turnLeft => 'মাথা বামে ঘোরান',
        LivenessStep.done => 'যাচাই সম্পন্ন',
      };

  /// Secondary hint for the current frame (why the step is not passing).
  String hintBn = '';

  /// Feed one frame. Returns true when the step advanced on this frame
  /// (the screen should capture the current frame).
  bool feed(FaceSample s) {
    if (isDone) return false;
    if (elapsed > timeout) {
      _timedOut = true;
      step = LivenessStep.done;
      return false;
    }
    if (!s.hasSingleFace) {
      hintBn = s.faceCount == 0 ? 'মুখ পাওয়া যাচ্ছে না — আলোতে আসুন / ক্যামেরার সামনে আসুন' : 'একজনের মুখ রাখুন';
      _stableFrames = 0;
      return false;
    }
    if (_trackingId != null && s.trackingId != null && s.trackingId != _trackingId) {
      // A different face appeared mid-flow: start over.
      _resetAll();
      hintBn = 'একই ব্যক্তি থাকুন';
      return false;
    }
    _trackingId ??= s.trackingId;

    switch (step) {
      case LivenessStep.lookAtCamera:
        final ok = _framingOk(s);
        if (!ok) {
          _stableFrames = 0;
          return false;
        }
        _stableFrames++;
        if (_stableFrames >= requiredStableFrames) {
          final conf = (1 - s.centerOffset).clamp(0.5, 1.0);
          return _advance('face_present', conf, LivenessStep.blink);
        }
        return false;

      case LivenessStep.blink:
        final l = s.leftEyeOpen;
        final r = s.rightEyeOpen;
        if (l == null || r == null) {
          hintBn = 'চোখ স্পষ্ট দেখা যাচ্ছে না';
          return false;
        }
        final open = l < r ? l : r; // both eyes must be below threshold
        if (open < _blinkMin) _blinkMin = open;
        if (open < eyeClosed) _eyesClosedSeen = true;
        if (_eyesClosedSeen && l > eyeOpen && r > eyeOpen) {
          final conf = (1 - _blinkMin).clamp(0.5, 1.0);
          return _advance('blink', conf, LivenessStep.smile);
        }
        hintBn = _eyesClosedSeen ? 'চোখ খুলুন' : 'দুই চোখ বন্ধ করে খুলুন';
        return false;

      case LivenessStep.smile:
        final p = s.smiling;
        if (p == null) {
          hintBn = 'মুখ স্পষ্ট দেখা যাচ্ছে না';
          return false;
        }
        if (p > smileThreshold) {
          return _advance('smile', p, LivenessStep.turnLeft);
        }
        hintBn = 'একটু বেশি হাসুন';
        return false;

      case LivenessStep.turnLeft:
        final y = s.headEulerY;
        if (y == null) return false;
        // We instruct "left" but accept either direction: the front camera
        // preview is mirrored, so users routinely turn the "wrong" way, and
        // the sign of ML Kit's yaw depends on the sensor/rotation setup.
        if (y.abs() > turnDeg) {
          final conf = ((y.abs() - turnDeg) / 25 + 0.7).clamp(0.7, 1.0);
          return _advance('turn_left', conf, LivenessStep.done);
        }
        hintBn = 'আরেকটু ঘোরান';
        return false;

      case LivenessStep.done:
        return false;
    }
  }

  bool _framingOk(FaceSample s) {
    final f = framingFeedbackBn(s);
    hintBn = f ?? 'স্থির থাকুন ✓';
    return f == null;
  }

  /// Live framing feedback for a single-face frame, or null when the face is
  /// well framed. Exposed so the screen can show it on every step.
  static String? framingFeedbackBn(FaceSample s) {
    if (s.faceCount == 0) return 'মুখ পাওয়া যাচ্ছে না — আলোতে আসুন / ক্যামেরার সামনে আসুন';
    if (s.faceCount > 1) return 'একজনের মুখ রাখুন';
    if (s.widthRatio < minFaceWidth) return 'আরেকটু কাছে আসুন';
    if (s.widthRatio > maxFaceWidth) return 'দূরে যান';
    if (s.centerOffset > maxCenterOffset) return 'মাঝখানে রাখুন';
    return null;
  }

  bool _advance(String name, double conf, LivenessStep next) {
    results.add(ChallengeResult(name: name, confidence: conf, at: _clock()));
    captureRequests++;
    step = next;
    _stableFrames = 0;
    _eyesClosedSeen = false;
    _blinkMin = 1;
    hintBn = '';
    return true;
  }

  void _resetAll() {
    step = LivenessStep.lookAtCamera;
    results.clear();
    captureRequests = 0;
    _stableFrames = 0;
    _eyesClosedSeen = false;
    _blinkMin = 1;
    _trackingId = null;
  }

  /// Contract payload: `{passed, challenges, score, captured_at}`.
  Map<String, dynamic> toJson({DateTime? capturedAt}) => {
        'passed': passed,
        'challenges': results.map((r) => r.name).toList(),
        'challenge_details': results.map((r) => r.toJson()).toList(),
        'score': double.parse(score.toStringAsFixed(3)),
        'captured_at': (capturedAt ?? _clock()).toUtc().toIso8601String(),
      };
}


// ---------------------------------------------------------------------------
// Camera-frame helpers (pure Dart so they can be unit-tested).
// ---------------------------------------------------------------------------

/// ML Kit rotation compensation in degrees for an Android camera.
///
/// [deviceDegrees] is the UI orientation (0 portraitUp, 90 landscapeLeft,
/// 180 portraitDown, 270 landscapeRight); null = unknown → sensor only.
int livenessRotationDegrees({required int sensorOrientation, required int? deviceDegrees, required bool isFront}) {
  final d = deviceDegrees ?? 0;
  final r = isFront ? (sensorOrientation + d) % 360 : (sensorOrientation - d + 360) % 360;
  return ((r % 360) + 360) % 360;
}

/// Rotations to try when the computed one yields no faces: computed first,
/// then the others in a fixed order (self-healing for odd OEM sensors).
List<int> rotationCandidates(int computed) {
  final c = ((computed % 360) + 360) % 360;
  return [c, ...[270, 90, 0, 180].where((r) => r != c)];
}

/// Builds a tightly packed NV21 buffer (Y plane, then interleaved VU) from
/// the three planes of a YUV_420_888 image, honouring row/pixel strides.
Uint8List nv21FromYuv420({
  required int width,
  required int height,
  required Uint8List y,
  required Uint8List u,
  required Uint8List v,
  required int yRowStride,
  required int uvRowStride,
  required int uvPixelStride,
}) {
  final ySize = width * height;
  final uvW = (width + 1) ~/ 2;
  final uvH = (height + 1) ~/ 2;
  final out = Uint8List(ySize + uvW * uvH * 2);
  if (yRowStride == width && y.length >= ySize) {
    out.setRange(0, ySize, y);
  } else {
    for (var r = 0; r < height; r++) {
      final src = r * yRowStride;
      final n = src + width <= y.length ? width : (y.length - src).clamp(0, width);
      if (n <= 0) break;
      out.setRange(r * width, r * width + n, y, src);
    }
  }
  var k = ySize;
  for (var r = 0; r < uvH; r++) {
    final row = r * uvRowStride;
    for (var c = 0; c < uvW; c++) {
      final i = row + c * uvPixelStride;
      out[k++] = i < v.length ? v[i] : 0;
      out[k++] = i < u.length ? u[i] : 0;
    }
  }
  return out;
}
