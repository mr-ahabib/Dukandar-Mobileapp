import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_config.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/auth_provider.dart';
import '../../providers/license_provider.dart';
import '../../widgets/infra_widgets.dart';

/// Shown after self-registration until an admin approves the KYC bundle.
class PendingVerificationScreen extends StatelessWidget {
  const PendingVerificationScreen({super.key});

  Future<void> _logout(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('লগআউট করবেন?'),
        content: const Text('আপনার আবেদন জমা থাকবে। আবার লগইন করলে যাচাইয়ের অবস্থা দেখতে পাবেন।'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('না')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('লগআউট')),
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
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppTheme.s24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: AppTheme.dialogMaxWidth),
              child: InfraCard(
                padding: const EdgeInsets.all(AppTheme.s24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      width: 72,
                      height: 72,
                      alignment: Alignment.center,
                      decoration: const BoxDecoration(color: AppTheme.saffronSoft, shape: BoxShape.circle),
                      child: const Icon(Icons.hourglass_top_rounded, color: AppTheme.saffron, size: 36),
                    ),
                    const SizedBox(height: AppTheme.s20),
                    Text('যাচাই চলছে', textAlign: TextAlign.center, style: AppTheme.headline),
                    const SizedBox(height: AppTheme.s8),
                    Text(
                      'আপনার NID ও ছবি আমাদের টিম যাচাই করছে। সাধারণত ২৪ ঘণ্টার মধ্যে অ্যাকাউন্ট চালু হয়ে যায়।',
                      textAlign: TextAlign.center,
                      style: AppTheme.bodySm.copyWith(color: AppTheme.inkMuted, height: 1.5),
                    ),
                    if (auth.shopName.isNotEmpty) ...[
                      const SizedBox(height: AppTheme.s16),
                      Container(
                        padding: const EdgeInsets.all(AppTheme.s12),
                        decoration: BoxDecoration(color: AppTheme.sand, borderRadius: BorderRadius.circular(AppTheme.radiusMd)),
                        child: Row(children: [
                          const Icon(Icons.storefront_outlined, color: AppTheme.inkMuted, size: 20),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(auth.shopName, style: AppTheme.bodyStrong, maxLines: 1, overflow: TextOverflow.ellipsis),
                              Text(bn(auth.phone), style: AppTheme.caption.copyWith(fontFeatures: AppTheme.tabular)),
                            ]),
                          ),
                          const StatusChip(label: 'অপেক্ষমাণ', color: AppTheme.saffron),
                        ]),
                      ),
                    ],
                    const SizedBox(height: AppTheme.s24),
                    BigButton(
                      label: 'আবার দেখুন',
                      icon: Icons.refresh_rounded,
                      loading: lic.isRefreshing,
                      onPressed: () async {
                        await lic.refresh(force: true);
                        if (!context.mounted) return;
                        if (lic.lastError != null) {
                          showSnack(context, lic.lastError!, error: true);
                        } else if (lic.isPendingVerification) {
                          showSnack(context, 'এখনো যাচাই শেষ হয়নি। একটু পরে আবার দেখুন।');
                        }
                      },
                    ),
                    const SizedBox(height: AppTheme.s12),
                    BigButton(
                      label: 'সাপোর্টে কল করুন  ${bn(AppConfig.supportPhone)}',
                      icon: Icons.call_outlined,
                      outlined: true,
                      onPressed: callSupport,
                    ),
                    const SizedBox(height: AppTheme.s8),
                    Center(
                      child: TextButton.icon(
                        onPressed: () => _logout(context),
                        icon: const Icon(Icons.logout_rounded, size: 18),
                        label: const Text('লগআউট'),
                        style: TextButton.styleFrom(foregroundColor: AppTheme.slateMuted),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
