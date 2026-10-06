import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../app_config.dart';

/// Local (on-device) notifications for subscription reminders.
///
/// All reminders are scheduled at 10:00 Asia/Dhaka:
///  * 3 days before `next_due_at`
///  * on the due day
///  * every day of the grace period (up to [AppConfig.graceDays])
class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  static const String channelId = 'subscription';
  static const String channelName = 'সাবস্ক্রিপশন';
  static const String channelDesc = 'মাসিক ফি জমা দেওয়ার রিমাইন্ডার';

  /// Reserved id range for subscription reminders.
  static const int _baseId = 7000;
  static const int _maxReminders = 20;

  static const String reminderTitle = 'দোকানদার';
  static const String reminderBody =
      'দোকানদার: মাসিক সাবস্ক্রিপশন ফি জমা দিন';

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;
  bool get isInitialized => _initialized;

  /// Payload of the notification the user tapped (if the UI wants to react).
  final ValueNotifier<String?> tappedPayload = ValueNotifier<String?>(null);

  Future<void> init() async {
    if (_initialized) return;
    try {
      tzdata.initializeTimeZones();
      tz.setLocalLocation(tz.getLocation('Asia/Dhaka'));
    } catch (_) {
      // Fall back to the default (UTC) location.
    }

    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const darwin = DarwinInitializationSettings();
    const settings = InitializationSettings(android: android, iOS: darwin);
    try {
      await _plugin.initialize(
        settings: settings,
        onDidReceiveNotificationResponse: (resp) {
          tappedPayload.value = resp.payload ?? 'subscription';
        },
      );
      final androidImpl = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      await androidImpl?.createNotificationChannel(
        const AndroidNotificationChannel(
          channelId,
          channelName,
          description: channelDesc,
          importance: Importance.high,
        ),
      );
      _initialized = true;
    } catch (e) {
      debugPrint('NotificationService init failed: $e');
    }
  }

  /// Ask for POST_NOTIFICATIONS (Android 13+). Returns true when granted
  /// or not required.
  Future<bool> requestPermission() async {
    await init();
    try {
      final androidImpl = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      if (androidImpl != null) {
        final granted = await androidImpl.requestNotificationsPermission();
        return granted ?? true;
      }
      final ios = _plugin.resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin>();
      if (ios != null) {
        final ok =
            await ios.requestPermissions(alert: true, badge: true, sound: true);
        return ok ?? true;
      }
    } catch (_) {}
    return true;
  }

  /// Details for a notification whose expanded text is [body].
  NotificationDetails _detailsFor(String body) => NotificationDetails(
        android: AndroidNotificationDetails(
          channelId,
          channelName,
          channelDescription: channelDesc,
          importance: Importance.high,
          priority: Priority.high,
          styleInformation: BigTextStyleInformation(body),
        ),
        iOS: const DarwinNotificationDetails(),
      );

  NotificationDetails get _details => _detailsFor(reminderBody);

  Future<void> cancelAll() async {
    await init();
    try {
      await _plugin.cancelAll();
    } catch (_) {}
  }

  /// Re-creates the reminder schedule from a License JSON map.
  Future<void> scheduleFromLicense(Map<String, dynamic>? license) async {
    await init();
    if (!_initialized) return;
    try {
      // Cancel only our ids so other notifications (if any) are unaffected.
      for (var i = 0; i < _maxReminders; i++) {
        await _plugin.cancel(id: _baseId + i);
      }
    } catch (_) {}
    if (license == null) return;

    final status = (license['status'] as String?) ?? '';
    if (status == 'suspended' || status == 'disabled') return;

    final nextDue = _parse(license['next_due_at']) ??
        _parse(license['paid_until']) ??
        _parse(license['trial_ends_at']);
    if (nextDue == null) return;

    final graceDays =
        (license['grace_days'] as num?)?.toInt() ?? AppConfig.graceDays;
    final graceEnd = _parse(license['grace_ends_at']) ??
        nextDue.add(Duration(days: graceDays));

    final now = tz.TZDateTime.now(tz.local);
    final days = <DateTime>{};

    days.add(nextDue.subtract(const Duration(days: 3)));
    days.add(nextDue);
    final maxGrace = graceDays.clamp(0, 10);
    for (var d = 1; d <= maxGrace; d++) {
      final day = nextDue.add(Duration(days: d));
      if (day.isAfter(graceEnd.add(const Duration(days: 1)))) break;
      days.add(day);
    }

    final sorted = days.toList()..sort();
    var id = _baseId;
    for (final day in sorted) {
      if (id >= _baseId + _maxReminders) break;
      final local = tz.TZDateTime.from(day.toUtc(), tz.local);
      final at =
          tz.TZDateTime(tz.local, local.year, local.month, local.day, 10);
      if (!at.isAfter(now)) continue;
      final isBefore = day.isBefore(nextDue);
      final body = isBefore
          ? 'দোকানদার: ${_daysDiff(nextDue, day)} দিন পর সাবস্ক্রিপশন ফি জমা দেওয়ার তারিখ'
          : reminderBody;
      try {
        await _plugin.zonedSchedule(
          id: id,
          title: reminderTitle,
          body: body,
          scheduledDate: at,
          notificationDetails: _details,
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          payload: 'subscription',
        );
        id++;
      } catch (e) {
        debugPrint('schedule failed: $e');
      }
    }
  }

  int _daysDiff(DateTime a, DateTime b) => DateTime(a.year, a.month, a.day)
      .difference(DateTime(b.year, b.month, b.day))
      .inDays;

  DateTime? _parse(dynamic v) {
    if (v == null) return null;
    if (v is DateTime) return v;
    return DateTime.tryParse(v.toString());
  }

  /// Show an immediate notification.
  Future<void> showNow({
    required int id,
    required String title,
    required String body,
    String? payload,
  }) async {
    await init();
    try {
      await _plugin.show(
        id: id,
        title: title,
        body: body,
        notificationDetails: _detailsFor(body),
        payload: payload,
      );
    } catch (e) {
      debugPrint('show failed: $e');
    }
  }
}
