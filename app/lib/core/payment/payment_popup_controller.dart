import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/license_provider.dart';
import '../../screens/settings/subscription_screen.dart';
import '../../widgets/infra_widgets.dart';
import '../app_config.dart';
import '../notifications/notification_service.dart';
import '../theme/app_theme.dart';
import 'payment_popup_scheduler.dart';

/// Shows the server-driven "fee due" dialog while the license is `due`.
///
/// Attached once from HomeNavigationScreen.initState via [attach]. Listens
/// to [LicenseProvider] (which already polls /app/me every 5 min in the
/// foreground and on resume) and re-evaluates on every change plus a local
/// timer for the `every_minutes` interval. Demo mode: inert.
///
/// Also reacts to a tapped system notification with payload
/// `notifications` by opening the notification sheet.
class PaymentPopupController with WidgetsBindingObserver {
  PaymentPopupController._();
  static final PaymentPopupController instance = PaymentPopupController._();

  final PaymentPopupScheduler _scheduler = PaymentPopupScheduler();
  BuildContext? _context;
  LicenseProvider? _license;
  Timer? _tick;
  bool _attached = false;
  bool _foreground = true;

  /// Call from HomeNavigationScreen.initState (idempotent).
  void attach(BuildContext context) {
    if (AppConfig.isDemo) return;
    _context = context;
    if (_attached) return;
    _attached = true;
    final lic = context.read<LicenseProvider>();
    _license = lic;
    lic.addListener(_evaluate);
    WidgetsBinding.instance.addObserver(this);
    NotificationService.instance.tappedPayload.addListener(_onNotificationTap);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _evaluate();
      _onNotificationTap();
    });
  }

  void detach() {
    _license?.removeListener(_evaluate);
    NotificationService.instance.tappedPayload.removeListener(_onNotificationTap);
    WidgetsBinding.instance.removeObserver(this);
    _tick?.cancel();
    _tick = null;
    _attached = false;
    _context = null;
    _license = null;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground) {
      // LicenseProvider refreshes on resume; evaluate when it reports back,
      // but also right away in case the cached state already says `due`.
      _evaluate();
    } else {
      _tick?.cancel();
      _tick = null;
    }
  }

  void _evaluate() {
    final lic = _license;
    final ctx = _context;
    if (lic == null || ctx == null || !ctx.mounted) return;
    final decision = _scheduler.evaluate(
      isDue: lic.status == LicenseStatus.due,
      serverWantsPopup: lic.paymentPopup.show,
      interval: lic.paymentPopup.interval,
      isDemo: AppConfig.isDemo,
    );
    switch (decision) {
      case PopupDecision.show:
        if (_foreground) _show(ctx, lic);
      case PopupDecision.justCleared:
        _tick?.cancel();
        _tick = null;
        if (lic.status == LicenseStatus.active || lic.status == LicenseStatus.trial) {
          showSnack(ctx, 'পেমেন্ট গৃহীত হয়েছে, ধন্যবাদ');
        }
      case PopupDecision.none:
        break;
    }
    _armTimer(lic);
  }

  void _armTimer(LicenseProvider lic) {
    _tick?.cancel();
    _tick = null;
    if (!_foreground || !lic.shouldShowPaymentPopup) return;
    final wait = _scheduler.nextIn(lic.paymentPopup.interval) ?? lic.paymentPopup.interval;
    _tick = Timer(wait + const Duration(seconds: 1), _evaluate);
  }

  Future<void> _show(BuildContext ctx, LicenseProvider lic) async {
    _scheduler.markShown();
    try {
      final pay = await showDialog<bool>(
        context: ctx,
        barrierDismissible: false,
        builder: (_) => _PaymentDueDialog(lic: lic),
      );
      if (pay == true && ctx.mounted) {
        await Navigator.of(ctx).push(
          MaterialPageRoute(builder: (_) => const SubscriptionScreen()),
        );
      }
    } finally {
      _scheduler.markDismissed();
      if (_license != null) _armTimer(_license!);
    }
  }

  void _onNotificationTap() {
    final payload = NotificationService.instance.tappedPayload.value;
    if (payload == null) return;
    final ctx = _context;
    if (ctx == null || !ctx.mounted) return;
    NotificationService.instance.tappedPayload.value = null;
    if (payload == 'notifications' || payload == 'subscription') {
      Navigator.of(ctx).push(
        MaterialPageRoute(builder: (_) => const SubscriptionScreen()),
      );
    }
  }
}

class _PaymentDueDialog extends StatelessWidget {
  const _PaymentDueDialog({required this.lic});
  final LicenseProvider lic;

  @override
  Widget build(BuildContext context) {
    final cfg = lic.paymentPopup;
    final graceEnd = lic.effectiveGraceEnd;
    final graceLeft = graceEnd == null
        ? null
        : DateTime(graceEnd.year, graceEnd.month, graceEnd.day)
            .difference(DateTime.now().copyWith(hour: 0, minute: 0, second: 0, millisecond: 0, microsecond: 0))
            .inDays;
    final title = cfg.titleBn.isNotEmpty ? cfg.titleBn : 'সাবস্ক্রিপশন ফি বাকি';
    final body = cfg.bodyBn.isNotEmpty
        ? cfg.bodyBn
        : (lic.messageBn.isNotEmpty
            ? lic.messageBn
            : 'এই মাসের ফি এখনো জমা হয়নি। বিকাশ/নগদে ফি পাঠিয়ে Transaction ID দিন।');

    return AlertDialog(
      icon: const Icon(Icons.payments_outlined, color: AppTheme.saffron, size: 32),
      title: Text(title, textAlign: TextAlign.center),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(body, style: AppTheme.bodySm.copyWith(height: 1.45, color: AppTheme.inkMuted)),
          const SizedBox(height: AppTheme.s16),
          Container(
            padding: const EdgeInsets.all(AppTheme.s12),
            decoration: BoxDecoration(
              color: AppTheme.sand,
              borderRadius: BorderRadius.circular(AppTheme.radiusMd),
            ),
            child: Column(children: [
              _kv('প্ল্যান', lic.planName.isEmpty ? '—' : lic.planName),
              const SizedBox(height: 6),
              _kv('মাসিক ফি', lic.priceBdt > 0 ? bnMoney(lic.priceBdt) : '—'),
              if (graceLeft != null) ...[
                const SizedBox(height: 6),
                _kv(
                  'গ্রেস বাকি',
                  graceLeft > 0 ? '${bn(graceLeft)} দিন' : 'আজই শেষ',
                  valueColor: graceLeft <= 2 ? AppTheme.gaveRed : null,
                ),
              ],
            ]),
          ),
        ],
      ),
      actionsAlignment: MainAxisAlignment.spaceBetween,
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          style: TextButton.styleFrom(foregroundColor: AppTheme.slateMuted),
          child: const Text('পরে'),
        ),
        FilledButton.icon(
          onPressed: () => Navigator.pop(context, true),
          icon: const Icon(Icons.arrow_forward_rounded, size: 18),
          label: const Text('পেমেন্ট করুন'),
        ),
      ],
    );
  }

  Widget _kv(String k, String v, {Color? valueColor}) => Row(
        children: [
          Expanded(child: Text(k, style: AppTheme.caption)),
          Text(v, style: AppTheme.bodySmStrong.copyWith(color: valueColor, fontFeatures: AppTheme.tabular)),
        ],
      );
}
