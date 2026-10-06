/// Pure-Dart decision logic for the "fee due" popup (unit-tested).
///
/// Rules (docs/API_CONTRACT.md, "App — payment popup rules"):
///  * show once on launch while `due` and `payment_popup.show`;
///  * then every `every_minutes` while the app is in the foreground;
///  * "পরে" dismisses until the next interval;
///  * when the status is no longer `due`, stop and report `justCleared` once.
class PaymentPopupScheduler {
  PaymentPopupScheduler({DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  final DateTime Function() _clock;

  DateTime? _lastShownAt;
  bool _wasDue = false;
  bool _visible = false;

  /// True while a popup dialog is on screen (never stack two).
  bool get isVisible => _visible;
  DateTime? get lastShownAt => _lastShownAt;

  /// Decide what to do for the current license snapshot.
  PopupDecision evaluate({
    required bool isDue,
    required bool serverWantsPopup,
    required Duration interval,
    bool isDemo = false,
  }) {
    if (isDemo) return PopupDecision.none;
    final due = isDue && serverWantsPopup;
    if (!due) {
      final cleared = _wasDue && isDue == false;
      _wasDue = false;
      _lastShownAt = null;
      return cleared ? PopupDecision.justCleared : PopupDecision.none;
    }
    _wasDue = true;
    if (_visible) return PopupDecision.none;
    final last = _lastShownAt;
    if (last == null) return PopupDecision.show; // launch / first time due
    final gap = _clock().difference(last);
    return gap >= interval ? PopupDecision.show : PopupDecision.none;
  }

  /// Time until the next popup is allowed (null = now / not scheduled).
  Duration? nextIn(Duration interval) {
    final last = _lastShownAt;
    if (last == null) return null;
    final r = interval - _clock().difference(last);
    return r.isNegative ? Duration.zero : r;
  }

  void markShown() {
    _visible = true;
    _lastShownAt = _clock();
  }

  /// "পরে" or any dismissal: the interval counts from when it was shown.
  void markDismissed() {
    _visible = false;
  }
}

enum PopupDecision { none, show, justCleared }
