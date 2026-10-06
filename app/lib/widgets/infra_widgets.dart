import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/app_config.dart';
import '../core/theme/app_theme.dart';
import '../providers/license_provider.dart';
import 'common_widgets.dart' show AppListRow, ListGroup, TintedIcon;

// ---------------------------------------------------------------------------
// Bangla formatting helpers
// ---------------------------------------------------------------------------

const _bnDigits = ['০', '১', '২', '৩', '৪', '৫', '৬', '৭', '৮', '৯'];

/// Converts ASCII digits in [s] to Bangla digits.
String bn(Object s) {
  final str = s.toString();
  final sb = StringBuffer();
  for (final r in str.runes) {
    if (r >= 0x30 && r <= 0x39) {
      sb.write(_bnDigits[r - 0x30]);
    } else {
      sb.writeCharCode(r);
    }
  }
  return sb.toString();
}

const _bnMonths = [
  'জানুয়ারি',
  'ফেব্রুয়ারি',
  'মার্চ',
  'এপ্রিল',
  'মে',
  'জুন',
  'জুলাই',
  'আগস্ট',
  'সেপ্টেম্বর',
  'অক্টোবর',
  'নভেম্বর',
  'ডিসেম্বর',
];

/// `১২ অক্টোবর ২০২৬`
String bnDate(DateTime? d) {
  if (d == null) return '—';
  final l = d.toLocal();
  return '${bn(l.day)} ${_bnMonths[l.month - 1]} ${bn(l.year)}';
}

/// `১২ অক্টোবর, সকাল ১০:০৫`
String bnDateTime(DateTime? d) {
  if (d == null) return '—';
  final l = d.toLocal();
  final h = l.hour;
  final period = h < 6
      ? 'রাত'
      : h < 12
          ? 'সকাল'
          : h < 16
              ? 'দুপুর'
              : h < 19
                  ? 'বিকাল'
                  : 'রাত';
  final h12 = h % 12 == 0 ? 12 : h % 12;
  final mm = l.minute.toString().padLeft(2, '0');
  return '${bn(l.day)} ${_bnMonths[l.month - 1]}, $period ${bn(h12)}:${bn(mm)}';
}

String bnMoney(num amount) => '৳${bn(amount.toStringAsFixed(0))}';

Future<void> callSupport() async {
  final uri = Uri(scheme: 'tel', path: AppConfig.supportPhone);
  try {
    await launchUrl(uri);
  } catch (_) {}
}

void showSnack(BuildContext context, String msg, {bool error = false}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(msg),
      behavior: SnackBarBehavior.floating,
      backgroundColor: error ? AppTheme.gaveRed : AppTheme.slateDark,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
}

// ---------------------------------------------------------------------------
// Building blocks
// ---------------------------------------------------------------------------

/// Card with the system radius + hairline (same look as PaperCard).
class InfraCard extends StatelessWidget {
  const InfraCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppTheme.s16),
    this.color = AppTheme.surface,
    this.borderColor,
    this.gradient,
    this.onTap,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color color;
  final Color? borderColor;
  final Gradient? gradient;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final box = Container(
      decoration: BoxDecoration(
        color: gradient == null ? color : null,
        gradient: gradient,
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        border: Border.all(color: borderColor ?? AppTheme.border),
      ),
      child: Padding(padding: padding, child: child),
    );
    if (onTap == null) return box;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        onTap: onTap,
        child: box,
      ),
    );
  }
}

/// Section header above cards: 13px muted w600, 24 top / 8 bottom.
class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, this.trailing});
  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppTheme.s8, top: AppTheme.s24),
      child: Row(
        children: [
          Expanded(
            child: Text(text, style: AppTheme.sectionHeader, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// Small status pill (22px, 11.5 text, muted tint).
class StatusChip extends StatelessWidget {
  const StatusChip({
    super.key,
    required this.label,
    required this.color,
    this.background,
    this.icon,
  });

  final String label;
  final Color color;
  final Color? background;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 22,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: background ?? color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 4),
          ],
          Text(label, style: AppTheme.label.copyWith(color: color, height: 1), maxLines: 1, overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }
}

Color statusColor(LicenseStatus s) {
  switch (s) {
    case LicenseStatus.active:
      return AppTheme.gotGreen;
    case LicenseStatus.trial:
      return AppTheme.primaryBlue;
    case LicenseStatus.due:
      return AppTheme.saffron;
    case LicenseStatus.suspended:
    case LicenseStatus.disabled:
      return AppTheme.gaveRed;
    case LicenseStatus.pendingVerification:
      return AppTheme.saffron;
    case LicenseStatus.rejected:
      return AppTheme.gaveRed;
    case LicenseStatus.unknown:
      return AppTheme.slateMuted;
  }
}

/// Flat label / value row with a copy button (lives inside a card; the
/// parent separates rows with dividers).
class CopyRow extends StatelessWidget {
  const CopyRow({
    super.key,
    required this.label,
    required this.value,
    this.icon,
    this.iconColor,
    this.monospace = true,
  });

  final String label;
  final String value;
  final IconData? icon;
  final Color? iconColor;
  final bool monospace;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, size: AppTheme.iconList, color: iconColor ?? AppTheme.inkMuted),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: AppTheme.caption),
                const SizedBox(height: 2),
                Text(
                  value,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.bodyStrong.copyWith(
                    fontFeatures: monospace ? AppTheme.tabular : null,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'কপি করুন',
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: value));
              if (context.mounted) showSnack(context, 'কপি হয়েছে: $value');
            },
            icon: const Icon(Icons.copy_rounded, size: 20),
            color: AppTheme.slateMuted,
          ),
        ],
      ),
    );
  }
}

/// Full-width button with built-in loading state. Primary = solid deep
/// green; `outlined` = hairline + ink text. 48px, radius 12.
class BigButton extends StatelessWidget {
  const BigButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.loading = false,
    this.color,
    this.foreground,
    this.outlined = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool loading;
  final Color? color;
  final Color? foreground;
  final bool outlined;

  @override
  Widget build(BuildContext context) {
    final bg = color ?? AppTheme.primary;
    final fg = foreground ?? (outlined ? (color ?? AppTheme.ink) : Colors.white);
    final child = loading
        ? SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2.2, color: fg),
          )
        : Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 20, color: fg),
                const SizedBox(width: 8),
              ],
              Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis)),
            ],
          );
    final cb = loading ? null : onPressed;
    if (outlined) {
      return OutlinedButton(
        onPressed: cb,
        style: OutlinedButton.styleFrom(
          foregroundColor: fg,
          minimumSize: const Size.fromHeight(AppTheme.controlHeight),
          side: BorderSide(color: color == null ? AppTheme.hairline : fg.withValues(alpha: 0.4)),
        ),
        child: child,
      );
    }
    return ElevatedButton(
      onPressed: cb,
      style: ElevatedButton.styleFrom(
        minimumSize: const Size.fromHeight(AppTheme.controlHeight),
        backgroundColor: bg,
        foregroundColor: fg,
        disabledBackgroundColor: bg.withValues(alpha: 0.45),
        disabledForegroundColor: fg,
      ),
      child: child,
    );
  }
}

// ---------------------------------------------------------------------------
// Payment info + claim form (shared by Paywall & Subscription screens)
// ---------------------------------------------------------------------------

class PaymentInfoCard extends StatelessWidget {
  const PaymentInfoCard({super.key});

  @override
  Widget build(BuildContext context) {
    final lic = context.watch<LicenseProvider>();
    final bkash = lic.bkash;
    final nagad = lic.nagad;
    final instr = lic.paymentInstructionsBn;
    final hasAny = bkash.isNotEmpty || nagad.isNotEmpty;

    return InfraCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text('পেমেন্ট করার নম্বর', style: AppTheme.bodyStrong)),
              if (lic.priceBdt > 0)
                StatusChip(
                  label: '${bnMoney(lic.priceBdt)} / মাস',
                  color: AppTheme.gotGreen,
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (!hasAny)
            Text(
              'পেমেন্ট নম্বর এখনো সেট করা হয়নি। সাপোর্টে কল করুন।',
              style: AppTheme.bodySm.copyWith(color: AppTheme.slateMuted),
            ),
          if (bkash.isNotEmpty)
            CopyRow(
              label: 'বিকাশ (Send Money)',
              value: bkash,
              icon: Icons.phone_android_outlined,
            ),
          if (bkash.isNotEmpty && nagad.isNotEmpty) const Divider(),
          if (nagad.isNotEmpty)
            CopyRow(
              label: 'নগদ (Send Money)',
              value: nagad,
              icon: Icons.phone_android_outlined,
            ),
          const SizedBox(height: 12),
          Text(
            instr.isNotEmpty
                ? instr
                : 'উপরের নম্বরে ${lic.priceBdt > 0 ? bnMoney(lic.priceBdt) : 'মাসিক ফি'} Send Money করুন। '
                    'তারপর নিচের ফর্মে Transaction ID দিয়ে "পেমেন্ট করেছি" চাপুন। '
                    'যাচাইয়ের পর (সাধারণত কয়েক ঘণ্টার মধ্যে) সাবস্ক্রিপশন চালু হয়ে যাবে।',
            style: AppTheme.bodySm.copyWith(height: 1.45, color: AppTheme.inkMuted),
          ),
        ],
      ),
    );
  }
}

/// "পেমেন্ট করেছি" form → POST /app/payment-claim.
class PaymentClaimForm extends StatefulWidget {
  const PaymentClaimForm({super.key, this.onSubmitted});
  final VoidCallback? onSubmitted;

  @override
  State<PaymentClaimForm> createState() => _PaymentClaimFormState();
}

class _PaymentClaimFormState extends State<PaymentClaimForm> {
  final _formKey = GlobalKey<FormState>();
  final _trx = TextEditingController();
  final _amount = TextEditingController();
  final _note = TextEditingController();
  String _method = 'bkash';
  bool _busy = false;
  bool _done = false;

  static const _methods = {
    'bkash': 'বিকাশ',
    'nagad': 'নগদ',
    'rocket': 'রকেট',
    'cash': 'নগদ টাকা',
  };

  @override
  void initState() {
    super.initState();
    final price = context.read<LicenseProvider>().priceBdt;
    if (price > 0) _amount.text = price.toString();
  }

  @override
  void dispose() {
    _trx.dispose();
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    final lic = context.read<LicenseProvider>();
    final err = await lic.submitPaymentClaim(
      method: _method,
      trxId: _trx.text.trim(),
      amount: int.tryParse(_amount.text.trim()) ?? lic.priceBdt,
      note: _note.text.trim(),
    );
    if (!mounted) return;
    setState(() {
      _busy = false;
      _done = err == null;
    });
    if (err != null) {
      showSnack(context, err, error: true);
    } else {
      showSnack(context, 'পেমেন্টের তথ্য পাঠানো হয়েছে। যাচাইয়ের পর চালু হবে।');
      widget.onSubmitted?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_done) {
      return InfraCard(
        child: Row(
          children: [
            const Icon(Icons.check_circle_outline_rounded,
                color: AppTheme.gotGreen, size: 24),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('পেমেন্টের তথ্য পেয়েছি', style: AppTheme.bodyStrong),
                  const SizedBox(height: 4),
                  Text(
                    'আমাদের টিম যাচাই করে সাবস্ক্রিপশন চালু করে দেবে। কিছুক্ষণ পর "আবার যাচাই করুন" চাপুন।',
                    style: AppTheme.bodySm,
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () => setState(() => _done = false),
                    child: const Text('আরেকটি পেমেন্ট জানান'),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return InfraCard(
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('পেমেন্ট করেছি', style: AppTheme.bodyStrong),
            const SizedBox(height: 2),
            Text('টাকা পাঠানোর পর Transaction ID (TrxID) দিন।', style: AppTheme.caption),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _methods.entries.map((e) {
                final selected = _method == e.key;
                return ChoiceChip(
                  label: Text(e.value),
                  selected: selected,
                  onSelected: (_) => setState(() => _method = e.key),
                  labelStyle: AppTheme.bodySm.copyWith(
                    color: selected ? Colors.white : AppTheme.ink,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 14),
            TextFormField(
              scrollPadding: const EdgeInsets.only(bottom: 120),
              controller: _trx,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                labelText: 'Transaction ID (TrxID)',
                hintText: 'যেমন: 9HJ2K5L7M1',
                prefixIcon: Icon(Icons.tag_rounded),
              ),
              validator: (v) {
                if (_method == 'cash') return null;
                if (v == null || v.trim().length < 4) {
                  return 'সঠিক Transaction ID দিন';
                }
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              scrollPadding: const EdgeInsets.only(bottom: 120),
              controller: _amount,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                labelText: 'টাকার পরিমাণ',
                prefixText: '৳ ',
                prefixIcon: Icon(Icons.payments_outlined),
              ),
              validator: (v) {
                final n = int.tryParse(v ?? '');
                if (n == null || n <= 0) return 'টাকার পরিমাণ দিন';
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              scrollPadding: const EdgeInsets.only(bottom: 120),
              controller: _note,
              decoration: const InputDecoration(
                labelText: 'নোট (ঐচ্ছিক)',
                hintText: 'যে নম্বর থেকে পাঠিয়েছেন ইত্যাদি',
                prefixIcon: Icon(Icons.notes_rounded),
              ),
            ),
            const SizedBox(height: 18),
            BigButton(
              label: 'পেমেন্টের তথ্য পাঠান',
              icon: Icons.send_rounded,
              loading: _busy,
              onPressed: _submit,
            ),
          ],
        ),
      ),
    );
  }
}

/// Notification list from LicenseProvider.
class NotificationList extends StatelessWidget {
  const NotificationList({super.key, this.max});
  final int? max;

  IconData _icon(String kind) {
    switch (kind) {
      case 'due':
        return Icons.payments_outlined;
      case 'warning':
        return Icons.warning_amber_rounded;
      default:
        return Icons.campaign_outlined;
    }
  }

  Color _color(String kind) {
    switch (kind) {
      case 'due':
        return AppTheme.saffron;
      case 'warning':
        return AppTheme.gaveRed;
      default:
        return AppTheme.primaryBlue;
    }
  }

  @override
  Widget build(BuildContext context) {
    final lic = context.watch<LicenseProvider>();
    var items = lic.notifications;
    if (max != null && items.length > max!) items = items.sublist(0, max!);

    if (items.isEmpty) {
      return const InfraCard(
        padding: EdgeInsets.zero,
        child: AppListRow(
          leading: Icon(Icons.notifications_none_rounded, color: AppTheme.inkHint, size: 22),
          title: 'কোনো নোটিফিকেশন নেই',
          titleColor: AppTheme.inkMuted,
        ),
      );
    }

    return ListGroup(
      children: [
        for (final n in items)
          AppListRow(
            onTap: () => lic.markRead(n.id),
            leading: TintedIcon(_icon(n.kind), color: _color(n.kind)),
            title: n.titleBn,
            subtitleWidget: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(n.bodyBn, style: AppTheme.bodySm.copyWith(color: AppTheme.inkMuted), maxLines: 2, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 2),
              Text(bnDateTime(n.createdAt), style: AppTheme.caption),
            ]),
            trailing: n.read
                ? null
                : Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(color: AppTheme.primaryBlue, shape: BoxShape.circle),
                  ),
          ),
      ],
    );
  }
}
