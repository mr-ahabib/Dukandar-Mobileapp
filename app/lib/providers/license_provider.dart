import 'dart:async';

import 'package:flutter/widgets.dart';

import '../core/app_config.dart';
import '../core/demo/demo_mode.dart';
import '../core/network/api_client.dart';
import '../core/notifications/new_notification_detector.dart';
import '../core/notifications/notification_service.dart';
import '../core/storage/secure_store.dart';

enum LicenseStatus {
  trial,
  active,
  due,
  suspended,
  disabled,
  pendingVerification,
  rejected,
  unknown,
}

LicenseStatus licenseStatusFrom(String? s) {
  switch (s) {
    case 'trial':
      return LicenseStatus.trial;
    case 'active':
      return LicenseStatus.active;
    case 'due':
      return LicenseStatus.due;
    case 'suspended':
      return LicenseStatus.suspended;
    case 'disabled':
      return LicenseStatus.disabled;
    case 'pending_verification':
      return LicenseStatus.pendingVerification;
    case 'rejected':
      return LicenseStatus.rejected;
    default:
      return LicenseStatus.unknown;
  }
}

String licenseStatusBn(LicenseStatus s) {
  switch (s) {
    case LicenseStatus.trial:
      return 'ফ্রি ট্রায়াল';
    case LicenseStatus.active:
      return 'সক্রিয়';
    case LicenseStatus.due:
      return 'ফি বাকি';
    case LicenseStatus.suspended:
      return 'স্থগিত';
    case LicenseStatus.disabled:
      return 'বন্ধ';
    case LicenseStatus.pendingVerification:
      return 'যাচাই চলছে';
    case LicenseStatus.rejected:
      return 'আবেদন বাতিল';
    case LicenseStatus.unknown:
      return 'অজানা';
  }
}

/// Server-driven "fee due" popup settings (`license.payment_popup`).
class PaymentPopupConfig {
  const PaymentPopupConfig({
    this.show = false,
    this.everyMinutes = 30,
    this.titleBn = '',
    this.bodyBn = '',
  });

  final bool show;
  final int everyMinutes;
  final String titleBn;
  final String bodyBn;

  Duration get interval => Duration(minutes: everyMinutes);

  factory PaymentPopupConfig.fromJson(Map<String, dynamic>? j) {
    if (j == null) return const PaymentPopupConfig();
    final every = (j['every_minutes'] as num?)?.toInt() ?? 30;
    return PaymentPopupConfig(
      show: j['show'] == true,
      everyMinutes: every <= 0 ? 30 : every,
      titleBn: (j['title_bn'] as String?) ?? '',
      bodyBn: (j['body_bn'] as String?) ?? '',
    );
  }
}

/// A server notification (`Notification` schema).
class AppNotification {
  AppNotification({
    required this.id,
    required this.titleBn,
    required this.bodyBn,
    required this.kind,
    required this.createdAt,
    required this.read,
  });

  final String id;
  final String titleBn;
  final String bodyBn;
  final String kind; // due | info | warning
  final DateTime? createdAt;
  bool read;

  factory AppNotification.fromJson(Map<String, dynamic> j) => AppNotification(
        id: j['id'].toString(),
        titleBn: (j['title_bn'] as String?) ?? '',
        bodyBn: (j['body_bn'] as String?) ?? '',
        kind: (j['kind'] as String?) ?? 'info',
        createdAt: DateTime.tryParse(j['created_at']?.toString() ?? ''),
        read: j['read'] == true,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title_bn': titleBn,
        'body_bn': bodyBn,
        'kind': kind,
        'created_at': createdAt?.toIso8601String(),
        'read': read,
      };
}

/// Holds the subscription license and server notifications.
///
/// Reads/writes the cached license via [SecureStore]; refreshed from the
/// server at most every [AppConfig.licenseRefreshInterval] unless forced,
/// plus a periodic timer every 6h while the app is alive.
class LicenseProvider extends ChangeNotifier with WidgetsBindingObserver {
  LicenseProvider({SecureStore? store, ApiClient? api, bool observeLifecycle = true})
      : _store = store ?? SecureStore.instance,
        _api = api ?? ApiClient.instance {
    shared = this;
    _api.onSessionRefreshed = (payload) {
      final lic = payload['license'];
      if (lic is Map<String, dynamic>) unawaited(applyLicense(lic));
    };
    _timer = Timer.periodic(AppConfig.licenseRefreshInterval, (_) {
      if (_hasSession) unawaited(refresh());
    });
    if (observeLifecycle && !AppConfig.isDemo) {
      WidgetsBinding.instance.addObserver(this);
      _startForegroundPoll();
    }
    unawaited(_loadCached());
  }

  /// Foreground poll (admin broadcasts, payment approval, KYC verdicts).
  /// Runs only while the app is resumed; immediate refresh on resume.
  static const Duration foregroundPollInterval = Duration(minutes: 5);
  Timer? _fgTimer;

  void _startForegroundPoll() {
    _fgTimer?.cancel();
    _fgTimer = Timer.periodic(foregroundPollInterval, (_) {
      if (_hasSession) unawaited(refresh(force: true));
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (AppConfig.isDemo) return;
    if (state == AppLifecycleState.resumed) {
      _startForegroundPoll();
      if (_hasSession) unawaited(refresh(force: true));
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached ||
        state == AppLifecycleState.hidden) {
      _fgTimer?.cancel();
      _fgTimer = null;
    }
  }

  /// Bridge so AuthProvider can push license updates without main.dart wiring.
  static LicenseProvider? shared;

  final SecureStore _store;
  final ApiClient _api;
  Timer? _timer;

  // ---- public state (kept from stub) ----
  LicenseStatus status = LicenseStatus.unknown;
  int daysLeft = 0;
  String planName = '';
  int priceBdt = 0;
  DateTime? nextDueAt;
  DateTime? graceEndsAt;
  DateTime? trialEndsAt;
  DateTime? paidUntil;
  String messageBn = '';
  Map<String, dynamic> paymentInfo = const {};
  List<String> features = const [];
  int graceDays = AppConfig.graceDays;
  DateTime? fetchedAt;
  Map<String, dynamic>? raw;

  /// KYC verification state: `pending` | `approved` | `rejected` | ''.
  String verification = '';
  String rejectionReasonBn = '';
  DateTime? verifiedAt;
  PaymentPopupConfig paymentPopup = const PaymentPopupConfig();

  bool isRefreshing = false;
  String? lastError;
  bool _hasSession = false;

  /// Server status before the offline rule was applied.
  LicenseStatus serverStatus = LicenseStatus.unknown;

  /// Grace is over this long ago -> treat as suspended even offline.
  static const Duration abuseBlockAfter = Duration(days: 30);

  /// End of grace by device clock: `grace_ends_at`, or the due date + grace.
  DateTime? get effectiveGraceEnd {
    if (graceEndsAt != null) return graceEndsAt;
    final due = paidUntil ?? trialEndsAt ?? nextDueAt;
    return due?.add(Duration(days: graceDays));
  }

  /// True when the paywall is shown because of the local clock rule rather
  /// than a server verdict.
  bool get isOfflineBlocked =>
      isBlocked && serverStatus != LicenseStatus.suspended &&
      serverStatus != LicenseStatus.disabled;

  /// True when the cached license has not been verified with the server
  /// for longer than [AppConfig.offlineLicenseTolerance] (informational;
  /// never blocks on its own).
  bool get isStale {
    final at = fetchedAt;
    if (at == null) return raw != null;
    return DateTime.now().toUtc().difference(at.toUtc()) >
        AppConfig.offlineLicenseTolerance;
  }

  /// True when the paywall must block the whole app (suspended / disabled).
  bool get isBlocked =>
      status == LicenseStatus.suspended || status == LicenseStatus.disabled;

  /// Account submitted, admin has not yet verified the KYC bundle.
  bool get isPendingVerification =>
      status == LicenseStatus.pendingVerification ||
      (status == LicenseStatus.unknown && verification == 'pending');

  /// Admin rejected the KYC bundle; re-registration is allowed.
  bool get isRejected =>
      status == LicenseStatus.rejected ||
      (status == LicenseStatus.unknown && verification == 'rejected');

  /// Server asks for the periodic "fee due" popup.
  bool get shouldShowPaymentPopup =>
      status == LicenseStatus.due && paymentPopup.show;

  /// True when a persistent "fee due" banner should show (due within grace).
  bool get showDueBanner => status == LicenseStatus.due;

  /// Trial ending within 3 days.
  bool get isTrialEndingSoon =>
      status == LicenseStatus.trial && daysLeft >= 0 && daysLeft <= 3;

  bool hasFeature(String f) => features.isEmpty || features.contains(f);

  String get statusBn => licenseStatusBn(status);

  String get bkash => (paymentInfo['bkash'] ?? '').toString();
  String get nagad => (paymentInfo['nagad'] ?? '').toString();
  String get paymentInstructionsBn =>
      (paymentInfo['instructions_bn'] ?? '').toString();

  // ---- notifications ----
  List<AppNotification> notifications = [];
  int get unreadCount => notifications.where((n) => !n.read).length;

  // -------------------------------------------------------------------
  // Loading / parsing
  // -------------------------------------------------------------------

  Future<void> _loadCached() async {
    final cached = await _store.license;
    final at = await _store.licenseFetchedAt;
    final token = await _store.accessToken;
    _hasSession = token != null && token.isNotEmpty;
    if (cached != null) {
      _parse(cached, at ?? DateTime.now().toUtc());
    }
    final notes = await _store.notifications;
    if (notes.isNotEmpty) {
      notifications = notes.map(AppNotification.fromJson).toList();
    }
    notifyListeners();
  }

  /// Apply a License JSON that arrived from the server (login/refresh/me)
  /// and persist it.
  Future<void> applyLicense(Map<String, dynamic> json) async {
    final now = DateTime.now().toUtc();
    _hasSession = true;
    _parse(json, now);
    await _store.saveLicense(json, fetchedAt: now);
    notifyListeners();
    unawaited(NotificationService.instance.scheduleFromLicense(json));
  }

  void _parse(Map<String, dynamic> j, DateTime at) {
    raw = j;
    fetchedAt = at;
    serverStatus = licenseStatusFrom(j['status'] as String?);
    status = serverStatus;
    planName = (j['plan_name'] as String?) ?? '';
    priceBdt = (j['price_bdt'] as num?)?.toInt() ?? 0;
    trialEndsAt = _dt(j['trial_ends_at']);
    paidUntil = _dt(j['paid_until']);
    graceEndsAt = _dt(j['grace_ends_at']);
    nextDueAt = _dt(j['next_due_at']) ?? paidUntil ?? trialEndsAt;
    daysLeft = (j['days_left'] as num?)?.toInt() ?? _computeDaysLeft();
    graceDays = (j['grace_days'] as num?)?.toInt() ?? AppConfig.graceDays;
    messageBn = (j['message_bn'] as String?) ?? '';
    paymentInfo = Map<String, dynamic>.from(j['payment_info'] as Map? ?? {});
    features = ((j['features'] as List?) ?? const [])
        .map((e) => e.toString())
        .toList();
    verification = (j['verification'] as String?) ?? '';
    rejectionReasonBn = (j['rejection_reason_bn'] as String?) ?? '';
    verifiedAt = _dt(j['verified_at']);
    paymentPopup = PaymentPopupConfig.fromJson(
        j['payment_popup'] is Map ? Map<String, dynamic>.from(j['payment_popup'] as Map) : null);
    // A verification verdict wins over a stale subscription status.
    if (verification == 'pending') {
      status = LicenseStatus.pendingVerification;
    } else if (verification == 'rejected') {
      status = LicenseStatus.rejected;
    }

    // ---- Offline leniency ----------------------------------------------
    // The shopkeeper must be able to work fully without internet. We only
    // downgrade the cached status using the DEVICE clock:
    //  * trial/active: keep working until (paid_until | trial_ends_at |
    //    next_due_at) + grace days has passed -> then `due` (banner only).
    //  * due: stays `due` (banner only).
    //  * block only when the server said suspended/disabled, or when the
    //    grace end passed more than [abuseBlockAfter] ago (clear abuse).
    final graceEnd = effectiveGraceEnd;
    if (status == LicenseStatus.trial || status == LicenseStatus.active) {
      if (graceEnd != null && DateTime.now().isAfter(graceEnd)) {
        status = LicenseStatus.due;
        if (isStale) {
          messageBn = 'ইন্টারনেট সংযোগ দিয়ে সাবস্ক্রিপশন যাচাই করুন';
        }
      }
    }
    if ((status == LicenseStatus.due) &&
        graceEnd != null &&
        DateTime.now().isAfter(graceEnd.add(abuseBlockAfter))) {
      status = LicenseStatus.suspended;
      messageBn = 'অনেক দিন ধরে সাবস্ক্রিপশন ফি বাকি। ইন্টারনেট চালু করে ফি জমা দিন ও যাচাই করুন।';
    }
    // Recompute days left by device clock when the cache is older than a day.
    if (nextDueAt != null &&
        DateTime.now().toUtc().difference(at.toUtc()) > const Duration(days: 1)) {
      daysLeft = _computeDaysLeft();
    }
  }

  int _computeDaysLeft() {
    final target = nextDueAt;
    if (target == null) return 0;
    final now = DateTime.now();
    return DateTime(target.year, target.month, target.day)
        .difference(DateTime(now.year, now.month, now.day))
        .inDays;
  }

  DateTime? _dt(dynamic v) =>
      v == null ? null : DateTime.tryParse(v.toString())?.toLocal();

  // -------------------------------------------------------------------
  // Network
  // -------------------------------------------------------------------

  /// Refresh license (and notifications) from the server.
  /// Throttled to [AppConfig.licenseRefreshInterval] unless [force].
  Future<void> refresh({bool force = false}) async {
    if (AppConfig.isDemo) {
      if (raw == null) await applyLicense(DemoMode.license());
      return;
    }
    if (isRefreshing) return;
    final token = await _store.accessToken;
    _hasSession = token != null && token.isNotEmpty;
    if (!_hasSession) return;

    if (!force && fetchedAt != null) {
      final age = DateTime.now().toUtc().difference(fetchedAt!.toUtc());
      if (age < AppConfig.licenseRefreshInterval) return;
    }

    isRefreshing = true;
    lastError = null;
    notifyListeners();
    try {
      // /app/me gives license + notifications in one round trip.
      final me = await _api.get('/app/me');
      if (me is Map<String, dynamic>) {
        final lic = me['license'];
        if (lic is Map<String, dynamic>) await applyLicense(lic);
        final shop = me['shop'];
        if (shop is Map<String, dynamic>) await _store.saveShop(shop);
        final notes = me['notifications'];
        if (notes is List) {
          notifications = notes
              .whereType<Map<String, dynamic>>()
              .map(AppNotification.fromJson)
              .toList()
            ..sort((a, b) => (b.createdAt ?? DateTime(0))
                .compareTo(a.createdAt ?? DateTime(0)));
          await _store.saveNotifications(
              notifications.map((n) => n.toJson()).toList());
          await _surfaceNewNotifications();
        }
      }
    } on ApiException catch (e) {
      lastError = e.messageBn;
      if (e.statusCode == 404 || e.statusCode == 405) {
        // Server without /app/me – use /app/license only.
        try {
          final lic = await _api.get('/app/license');
          if (lic is Map<String, dynamic>) {
            await applyLicense(lic);
            lastError = null;
          }
        } on ApiException catch (e2) {
          lastError = e2.messageBn;
        }
      }
      // Offline: re-evaluate staleness against the cached copy.
      if (raw != null) _parse(raw!, fetchedAt ?? DateTime.now().toUtc());
    } catch (e) {
      lastError = 'লাইসেন্স যাচাই করা যায়নি।';
    } finally {
      isRefreshing = false;
      notifyListeners();
    }
  }

  /// Raise a system notification for every unread server notification we
  /// have not surfaced before (persisted seen-set in [SecureStore]).
  Future<void> _surfaceNewNotifications() async {
    if (AppConfig.isDemo) return;
    try {
      final seen = await _store.seenNotificationIds;
      final detector = NewNotificationDetector(seen ?? const []);
      // Oldest first so the newest ends up on top of the shade.
      final ordered = notifications.reversed
          .map((n) => (id: n.id, read: n.read))
          .toList();
      final fresh = detector.detect(ordered, isFirstSync: seen == null);
      await _store.saveSeenNotificationIds(detector.toPersist());
      for (final id in fresh) {
        final n = notifications.where((e) => e.id == id).firstOrNull;
        if (n == null) continue;
        unawaited(NotificationService.instance.showNow(
          id: NewNotificationDetector.platformId(id),
          title: n.titleBn.isNotEmpty ? n.titleBn : 'দোকানদার',
          body: n.bodyBn,
          payload: 'notifications',
        ));
      }
    } catch (_) {
      // best-effort
    }
  }

  Future<void> markRead(String id) async {
    final n = notifications.where((e) => e.id == id).firstOrNull;
    if (n == null || n.read) return;
    n.read = true;
    notifyListeners();
    await _store
        .saveNotifications(notifications.map((e) => e.toJson()).toList());
    try {
      await _api.post('/app/notifications/$id/read');
    } catch (_) {
      // best-effort
    }
  }

  Future<void> markAllRead() async {
    for (final n in notifications.where((n) => !n.read).toList()) {
      await markRead(n.id);
    }
  }

  /// POST /app/payment-claim. Returns null on success, else Bangla error.
  Future<String?> submitPaymentClaim({
    required String method,
    required String trxId,
    required int amount,
    String note = '',
  }) async {
    try {
      await _api.post('/app/payment-claim', body: {
        'method': method,
        'trx_id': trxId,
        'amount': amount,
        'note': note,
      });
      return null;
    } on ApiException catch (e) {
      return e.messageBn;
    } catch (_) {
      return 'পেমেন্ট তথ্য পাঠানো যায়নি।';
    }
  }

  /// Called on logout.
  Future<void> clear() async {
    _hasSession = false;
    status = LicenseStatus.unknown;
    serverStatus = LicenseStatus.unknown;
    raw = null;
    fetchedAt = null;
    daysLeft = 0;
    planName = '';
    priceBdt = 0;
    nextDueAt = null;
    graceEndsAt = null;
    trialEndsAt = null;
    paidUntil = null;
    messageBn = '';
    paymentInfo = const {};
    features = const [];
    verification = '';
    rejectionReasonBn = '';
    verifiedAt = null;
    paymentPopup = const PaymentPopupConfig();
    notifications = [];
    await _store.clearLicense();
    await NotificationService.instance.scheduleFromLicense(null);
    notifyListeners();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _fgTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    if (shared == this) shared = null;
    super.dispose();
  }
}
