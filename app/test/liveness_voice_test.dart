import 'dart:typed_data';

import 'package:dukandar/core/kyc/liveness_challenge.dart';
import 'package:dukandar/widgets/voice_sheet.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('pickVoiceLocale', () {
    test('prefers bn_BD, then bn_IN, then any bn, then en_IN', () {
      expect(pickVoiceLocale(['en_US', 'bn_IN', 'bn_BD']), 'bn_BD');
      expect(pickVoiceLocale(['en_US', 'bn_IN']), 'bn_IN');
      expect(pickVoiceLocale(['en_US', 'bn']), 'bn');
      expect(pickVoiceLocale(['en_US', 'en_IN']), 'en_IN');
    });
    test('accepts dash spelling and returns the device id as-is', () {
      expect(pickVoiceLocale(['en-US', 'bn-BD']), 'bn-BD');
      expect(pickVoiceLocale(['EN-us', 'BN-in']), 'BN-in');
    });
    test('falls back to the system locale, then the first entry', () {
      expect(pickVoiceLocale(['en_US', 'hi_IN'], systemLocaleId: 'hi_IN'), 'hi_IN');
      expect(pickVoiceLocale(['en_US', 'hi_IN'], systemLocaleId: 'fr_FR'), 'en_US');
      expect(pickVoiceLocale([], systemLocaleId: 'fr_FR'), 'fr_FR');
      expect(pickVoiceLocale([]), isNull);
    });
    test('does not treat bnx-like prefixes as Bangla', () {
      expect(pickVoiceLocale(['bnx_XX', 'en_IN']), 'en_IN');
    });
  });

  group('voiceErrorBn', () {
    test('maps network and no-match codes to Bangla', () {
      expect(voiceErrorBn('error_network'), contains('ইন্টারনেট'));
      expect(voiceErrorBn('error_no_match'), 'কিছু শোনা যায়নি, আবার বলুন');
      expect(voiceErrorBn('error_speech_timeout'), 'কিছু শোনা যায়নি, আবার বলুন');
      expect(voiceErrorBn('error_permission'), contains('অনুমতি'));
      expect(voiceErrorBn('whatever'), isNotNull);
    });
  });

  group('liveness rotation', () {
    test('front camera adds device rotation, back subtracts', () {
      expect(livenessRotationDegrees(sensorOrientation: 270, deviceDegrees: 0, isFront: true), 270);
      expect(livenessRotationDegrees(sensorOrientation: 270, deviceDegrees: 90, isFront: true), 0);
      expect(livenessRotationDegrees(sensorOrientation: 90, deviceDegrees: 90, isFront: false), 0);
      expect(livenessRotationDegrees(sensorOrientation: 90, deviceDegrees: 270, isFront: false), 180);
      expect(livenessRotationDegrees(sensorOrientation: 270, deviceDegrees: null, isFront: true), 270);
    });
    test('candidates start with the computed rotation and cover all four', () {
      expect(rotationCandidates(270), [270, 90, 0, 180]);
      expect(rotationCandidates(0), [0, 270, 90, 180]);
      expect(rotationCandidates(90).toSet(), {0, 90, 180, 270});
    });
  });

  group('nv21FromYuv420', () {
    test('interleaves VU after Y honouring strides', () {
      const w = 4, h = 2;
      final y = Uint8List.fromList([1, 2, 3, 4, 99, 99, 5, 6, 7, 8, 99, 99]); // rowStride 6
      final u = Uint8List.fromList([10, 0, 11, 0]); // pixelStride 2, rowStride 4
      final v = Uint8List.fromList([20, 0, 21, 0]);
      final out = nv21FromYuv420(width: w, height: h, y: y, u: u, v: v, yRowStride: 6, uvRowStride: 4, uvPixelStride: 2);
      expect(out.length, w * h + (w ~/ 2) * (h ~/ 2) * 2);
      expect(out.sublist(0, 8), [1, 2, 3, 4, 5, 6, 7, 8]);
      expect(out.sublist(8), [20, 10, 21, 11]);
    });
    test('tight planes copy straight through', () {
      final y = Uint8List.fromList(List.generate(8, (i) => i));
      final out = nv21FromYuv420(
          width: 4, height: 2, y: y, u: Uint8List.fromList([7, 8]), v: Uint8List.fromList([5, 6]), yRowStride: 4, uvRowStride: 2, uvPixelStride: 1);
      expect(out, [0, 1, 2, 3, 4, 5, 6, 7, 5, 7, 6, 8]);
    });
  });

  group('LivenessController relaxed thresholds', () {
    test('head turn passes in either direction', () {
      final c = LivenessController();
      const good = FaceSample(faceCount: 1, widthRatio: 0.5, centerOffset: 0.1, leftEyeOpen: 0.9, rightEyeOpen: 0.9, smiling: 0.1, headEulerY: 0);
      for (var i = 0; i < LivenessController.requiredStableFrames; i++) {
        c.feed(good);
      }
      expect(c.step, LivenessStep.blink);
      c.feed(const FaceSample(faceCount: 1, widthRatio: 0.5, centerOffset: 0.1, leftEyeOpen: 0.3, rightEyeOpen: 0.3));
      c.feed(good);
      expect(c.step, LivenessStep.smile);
      c.feed(const FaceSample(faceCount: 1, widthRatio: 0.5, centerOffset: 0.1, smiling: 0.65));
      expect(c.step, LivenessStep.turnLeft);
      c.feed(const FaceSample(faceCount: 1, widthRatio: 0.5, centerOffset: 0.1, headEulerY: -20));
      expect(c.passed, isTrue);
    });
    test('framing feedback covers near/far/centre/none', () {
      expect(LivenessController.framingFeedbackBn(const FaceSample.none()), contains('মুখ পাওয়া যাচ্ছে না'));
      expect(LivenessController.framingFeedbackBn(const FaceSample(faceCount: 1, widthRatio: 0.1, centerOffset: 0)), 'আরেকটু কাছে আসুন');
      expect(LivenessController.framingFeedbackBn(const FaceSample(faceCount: 1, widthRatio: 0.97, centerOffset: 0)), 'দূরে যান');
      expect(LivenessController.framingFeedbackBn(const FaceSample(faceCount: 1, widthRatio: 0.5, centerOffset: 0.7)), 'মাঝখানে রাখুন');
      expect(LivenessController.framingFeedbackBn(const FaceSample(faceCount: 1, widthRatio: 0.5, centerOffset: 0.2)), isNull);
    });
  });
}
