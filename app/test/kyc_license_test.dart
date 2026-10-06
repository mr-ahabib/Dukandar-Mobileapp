import 'package:dukandar/core/kyc/liveness_challenge.dart';
import 'package:dukandar/core/kyc/registration_data.dart';
import 'package:dukandar/core/notifications/new_notification_detector.dart';
import 'package:dukandar/core/payment/payment_popup_scheduler.dart';
import 'package:dukandar/providers/license_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LicenseStatus KYC parsing', () {
    test('maps new status strings', () {
      expect(licenseStatusFrom('pending_verification'), LicenseStatus.pendingVerification);
      expect(licenseStatusFrom('rejected'), LicenseStatus.rejected);
      expect(licenseStatusFrom('due'), LicenseStatus.due);
      expect(licenseStatusBn(LicenseStatus.pendingVerification), 'যাচাই চলছে');
    });

    test('PaymentPopupConfig parses with defaults', () {
      final c = PaymentPopupConfig.fromJson({'show': true, 'title_bn': 'ফি বাকি'});
      expect(c.show, isTrue);
      expect(c.everyMinutes, 30);
      expect(c.interval, const Duration(minutes: 30));
      expect(c.titleBn, 'ফি বাকি');
      expect(PaymentPopupConfig.fromJson(null).show, isFalse);
      expect(PaymentPopupConfig.fromJson({'every_minutes': 0}).everyMinutes, 30);
      expect(PaymentPopupConfig.fromJson({'every_minutes': 15}).everyMinutes, 15);
    });
  });

  group('PaymentPopupScheduler', () {
    var now = DateTime(2026, 10, 4, 10);
    PaymentPopupScheduler make() => PaymentPopupScheduler(clock: () => now);
    const every = Duration(minutes: 30);

    test('shows on launch when due + server wants it, then waits an interval', () {
      final s = make();
      expect(s.evaluate(isDue: true, serverWantsPopup: true, interval: every), PopupDecision.show);
      s.markShown();
      // Still visible: never stack.
      expect(s.evaluate(isDue: true, serverWantsPopup: true, interval: every), PopupDecision.none);
      s.markDismissed();
      now = now.add(const Duration(minutes: 10));
      expect(s.evaluate(isDue: true, serverWantsPopup: true, interval: every), PopupDecision.none);
      expect(s.nextIn(every), const Duration(minutes: 20));
      now = now.add(const Duration(minutes: 20));
      expect(s.evaluate(isDue: true, serverWantsPopup: true, interval: every), PopupDecision.show);
    });

    test('never shows when server says no, in demo, or when not due', () {
      final s = make();
      expect(s.evaluate(isDue: true, serverWantsPopup: false, interval: every), PopupDecision.none);
      expect(s.evaluate(isDue: true, serverWantsPopup: true, interval: every, isDemo: true), PopupDecision.none);
      expect(s.evaluate(isDue: false, serverWantsPopup: true, interval: every), PopupDecision.none);
    });

    test('reports justCleared exactly once when due becomes active', () {
      final s = make();
      s.evaluate(isDue: true, serverWantsPopup: true, interval: every);
      s.markShown();
      s.markDismissed();
      expect(s.evaluate(isDue: false, serverWantsPopup: false, interval: every), PopupDecision.justCleared);
      expect(s.evaluate(isDue: false, serverWantsPopup: false, interval: every), PopupDecision.none);
      // Becomes due again later -> shows immediately (launch semantics).
      expect(s.evaluate(isDue: true, serverWantsPopup: true, interval: every), PopupDecision.show);
    });
  });

  group('NewNotificationDetector', () {
    test('first sync marks backlog seen without alerting', () {
      final d = NewNotificationDetector(const []);
      final fresh = d.detect([(id: 'a', read: false), (id: 'b', read: true)], isFirstSync: true);
      expect(fresh, isEmpty);
      expect(d.seenIds, {'a', 'b'});
    });

    test('alerts only for unread, unseen ids and only once', () {
      final d = NewNotificationDetector(['a']);
      final fresh = d.detect([(id: 'a', read: false), (id: 'b', read: false), (id: 'c', read: true)]);
      expect(fresh, ['b']);
      expect(d.detect([(id: 'b', read: false), (id: 'c', read: false)]), isEmpty);
      expect(d.toPersist(), containsAll(['a', 'b', 'c']));
    });

    test('platform id is stable, positive and outside reminder range', () {
      final a = NewNotificationDetector.platformId('notif-123');
      expect(a, NewNotificationDetector.platformId('notif-123'));
      expect(a, greaterThanOrEqualTo(100000));
      expect(a, isNot(NewNotificationDetector.platformId('notif-124')));
    });
  });

  group('LivenessController', () {
    var now = DateTime(2026, 10, 4, 10);
    LivenessController make() => LivenessController(clock: () => now);
    const good = FaceSample(faceCount: 1, widthRatio: 0.5, centerOffset: 0.1, leftEyeOpen: 0.9, rightEyeOpen: 0.9, smiling: 0.1, headEulerY: 0, trackingId: 7);

    test('runs the four challenges in order and scores them', () {
      final c = make();
      expect(c.step, LivenessStep.lookAtCamera);
      for (var i = 0; i < LivenessController.requiredStableFrames - 1; i++) {
        expect(c.feed(good), isFalse);
      }
      expect(c.feed(good), isTrue); // last stable frame
      expect(c.step, LivenessStep.blink);
      // blink: must close both eyes then reopen
      expect(c.feed(good), isFalse);
      expect(c.feed(const FaceSample(faceCount: 1, widthRatio: 0.5, centerOffset: 0.1, leftEyeOpen: 0.1, rightEyeOpen: 0.2, trackingId: 7)), isFalse);
      expect(c.feed(good), isTrue);
      expect(c.step, LivenessStep.smile);
      expect(c.feed(const FaceSample(faceCount: 1, widthRatio: 0.5, centerOffset: 0.1, smiling: 0.5, trackingId: 7)), isFalse);
      expect(c.feed(const FaceSample(faceCount: 1, widthRatio: 0.5, centerOffset: 0.1, smiling: 0.9, trackingId: 7)), isTrue);
      expect(c.step, LivenessStep.turnLeft);
      expect(c.feed(const FaceSample(faceCount: 1, widthRatio: 0.5, centerOffset: 0.1, headEulerY: 10, trackingId: 7)), isFalse);
      expect(c.feed(const FaceSample(faceCount: 1, widthRatio: 0.5, centerOffset: 0.1, headEulerY: 30, trackingId: 7)), isTrue);
      expect(c.isDone, isTrue);
      expect(c.passed, isTrue);
      expect(c.captureRequests, 4);
      final j = c.toJson();
      expect(j['passed'], isTrue);
      expect(j['challenges'], ['face_present', 'blink', 'smile', 'turn_left']);
      expect(j['score'], inInclusiveRange(0.5, 1.0));
      expect(j['captured_at'], isA<String>());
    });

    test('times out after 60s', () {
      final c = make();
      now = now.add(const Duration(seconds: 61));
      expect(c.feed(good), isFalse);
      expect(c.timedOut, isTrue);
      expect(c.passed, isFalse);
    });

    test('one eye closed is not a blink; bad framing gives hints', () {
      final c = make();
      expect(c.feed(const FaceSample(faceCount: 1, widthRatio: 0.1, centerOffset: 0.1)), isFalse);
      expect(c.hintBn, 'আরেকটু কাছে আসুন');
      expect(c.feed(const FaceSample(faceCount: 2)), isFalse);
      expect(c.hintBn, 'একজনের মুখ রাখুন');
    });
  });

  group('RegistrationData validation', () {
    test('BD phone + NID rules', () {
      expect(RegistrationData.isValidBdPhone('01712345678'), isTrue);
      expect(RegistrationData.isValidBdPhone('+880 1712-345678'), isTrue);
      expect(RegistrationData.isValidBdPhone('01212345678'), isFalse);
      expect(RegistrationData.isValidBdPhone('0171234567'), isFalse);
      expect(RegistrationData.normalizePhone('+8801712345678'), '01712345678');
      expect(RegistrationData.isValidNid('1234567890'), isTrue);
      expect(RegistrationData.isValidNid('1234567890123'), isTrue);
      expect(RegistrationData.isValidNid('12345678901234567'), isTrue);
      expect(RegistrationData.isValidNid('123456789012'), isFalse);
    });
  });
}
