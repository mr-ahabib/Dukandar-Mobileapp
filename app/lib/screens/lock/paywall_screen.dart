import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_config.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/auth_provider.dart';
import '../../providers/license_provider.dart';
import '../../widgets/infra_widgets.dart';

/// Shown when the subscription is suspended / disabled.
/// Friendly but firm: the app is blocked until payment is verified.
class PaywallScreen extends StatelessWidget {
  const PaywallScreen({super.key});

  Future<void> _logout(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('লগআউট করবেন?'),
        content: const Text(
            'আপনার হিসাবের তথ্য এই ফোনেই থেকে যাবে। আবার লগইন করলে সব আগের মতো পাবেন।'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('না')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('লগআউট')),
        ],
      ),
    );
    if (ok == true && context.mounted) {
      await context.read<AuthProvider>().logout();
    }
  }

  @override
  Widget build(BuildContext context) {
    final lic = context.watch<LicenseProvider>();
    final auth = context.watch<AuthProvider>();
    final disabled = lic.status == LicenseStatus.disabled;

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: RefreshIndicator(
        onRefresh: () => lic.refresh(force: true),
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: _Header(
                disabled: disabled,
                shopName: auth.shopName,
                planName: lic.planName,
                price: lic.priceBdt,
                dueAt: lic.nextDueAt ?? lic.paidUntil ?? lic.trialEndsAt,
                graceEndsAt: lic.graceEndsAt,
                message: lic.messageBn,
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(AppTheme.gutter, AppTheme.s16, AppTheme.gutter, 32),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  if (!disabled) ...[
                    const PaymentInfoCard(),
                    const SizedBox(height: 16),
                    const PaymentClaimForm(),
                    const SizedBox(height: 16),
                  ] else
                    InfraCard(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.block_rounded, color: AppTheme.gaveRed, size: 20),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'এই অ্যাকাউন্টটি অ্যাডমিন বন্ধ করে দিয়েছেন। চালু করতে সাপোর্টে যোগাযোগ করুন।',
                              style: AppTheme.bodySm.copyWith(height: 1.45),
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (disabled) const SizedBox(height: 16),
                  BigButton(
                    label: 'আবার যাচাই করুন',
                    loading: lic.isRefreshing,
                    onPressed: () async {
                      await lic.refresh(force: true);
                      if (!context.mounted) return;
                      if (lic.lastError != null) {
                        showSnack(context, lic.lastError!, error: true);
                      } else if (lic.isBlocked) {
                        showSnack(context,
                            'এখনো পেমেন্ট যাচাই হয়নি। একটু পরে আবার চেষ্টা করুন।');
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                  BigButton(
                    label: 'সাপোর্টে কল করুন  ${bn(AppConfig.supportPhone)}',
                    icon: Icons.call_outlined,
                    outlined: true,
                    onPressed: callSupport,
                  ),
                  const SizedBox(height: AppTheme.s24),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.verified_user_outlined, color: AppTheme.inkMuted, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'আপনার হিসাবের তথ্য নিরাপদে আছে। পেমেন্ট যাচাই হলেই সব আগের মতো পাবেন।',
                          style: AppTheme.bodySm.copyWith(height: 1.45, color: AppTheme.inkMuted),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Center(
                    child: TextButton.icon(
                      onPressed: () => _logout(context),
                      icon: const Icon(Icons.logout_rounded, size: 18),
                      label: const Text('লগআউট'),
                      style: TextButton.styleFrom(
                          foregroundColor: AppTheme.slateMuted),
                    ),
                  ),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.disabled,
    required this.shopName,
    required this.planName,
    required this.price,
    required this.dueAt,
    required this.graceEndsAt,
    required this.message,
  });

  final bool disabled;
  final String shopName;
  final String planName;
  final int price;
  final DateTime? dueAt;
  final DateTime? graceEndsAt;
  final String message;

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    return Container(
      padding: EdgeInsets.fromLTRB(AppTheme.gutter, top + 24, AppTheme.gutter, AppTheme.s24),
      color: AppTheme.navy,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            disabled ? Icons.block_rounded : Icons.lock_clock_outlined,
            color: Colors.white70,
            size: 28,
          ),
          const SizedBox(height: 12),
          Text(
            disabled ? 'অ্যাকাউন্ট বন্ধ আছে' : 'সাবস্ক্রিপশন ফি বাকি',
            style: AppTheme.headline.copyWith(color: Colors.white),
          ),
          if (shopName.isNotEmpty)
            Text(
              shopName,
              style: AppTheme.bodySm.copyWith(color: Colors.white70),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          const SizedBox(height: 12),
          Text(
            message.isNotEmpty
                ? message
                : (disabled
                    ? 'অ্যাপ ব্যবহার করতে অ্যাডমিনের সাথে যোগাযোগ করুন।'
                    : 'গ্রেস পিরিয়ড শেষ হয়ে গেছে। অ্যাপ আবার চালু করতে মাসিক ফি জমা দিন।'),
            style: AppTheme.bodySm.copyWith(color: Colors.white.withValues(alpha: 0.9), height: 1.5),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _Stat(label: 'প্ল্যান', value: planName.isEmpty ? '—' : planName),
              _divider(),
              _Stat(label: 'মাসিক ফি', value: price > 0 ? bnMoney(price) : '—'),
              _divider(),
              _Stat(
                label: 'শেষ তারিখ',
                value: bnDate(graceEndsAt ?? dueAt),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _divider() => Container(
        width: 1,
        height: 36,
        margin: const EdgeInsets.symmetric(horizontal: 12),
        color: Colors.white.withValues(alpha: 0.2),
      );
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: AppTheme.label.copyWith(color: Colors.white.withValues(alpha: 0.7))),
          const SizedBox(height: 4),
          Text(
            value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppTheme.bodyStrong.copyWith(color: Colors.white, fontFeatures: AppTheme.tabular),
          ),
        ],
      ),
    );
  }
}
