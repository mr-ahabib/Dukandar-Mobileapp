import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_config.dart';
import '../../core/kyc/registration_data.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/auth_provider.dart';
import '../../providers/license_provider.dart';
import '../../widgets/infra_widgets.dart';
import '../auth/register/register_flow_screen.dart';

/// Admin rejected the KYC bundle. Shows the reason and lets the shopkeeper
/// re-apply with the shop info prefilled.
class RejectedScreen extends StatelessWidget {
  const RejectedScreen({super.key});

  Future<void> _reapply(BuildContext context) async {
    final auth = context.read<AuthProvider>();
    final prefill = RegistrationData()
      ..shopName = auth.shopName
      ..ownerName = auth.ownerName
      ..phone = auth.phone
      ..address = auth.address;
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => RegisterFlowScreen(prefill: prefill, reapply: true)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final lic = context.watch<LicenseProvider>();
    final reason = lic.rejectionReasonBn.isNotEmpty
        ? lic.rejectionReasonBn
        : 'জমা দেওয়া তথ্য বা ছবি স্পষ্ট ছিল না।';
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
                      decoration: const BoxDecoration(color: AppTheme.coralSoft, shape: BoxShape.circle),
                      child: const Icon(Icons.cancel_outlined, color: AppTheme.coral, size: 36),
                    ),
                    const SizedBox(height: AppTheme.s20),
                    Text('আবেদন গৃহীত হয়নি', textAlign: TextAlign.center, style: AppTheme.headline),
                    const SizedBox(height: AppTheme.s8),
                    Text(
                      'দুঃখিত, আপনার অ্যাকাউন্ট যাচাই সম্পন্ন করা যায়নি। নিচের কারণ দেখে আবার আবেদন করুন।',
                      textAlign: TextAlign.center,
                      style: AppTheme.bodySm.copyWith(color: AppTheme.inkMuted, height: 1.5),
                    ),
                    const SizedBox(height: AppTheme.s16),
                    Container(
                      padding: const EdgeInsets.all(AppTheme.s12),
                      decoration: BoxDecoration(
                        color: AppTheme.coralSoft,
                        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                      ),
                      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const Icon(Icons.info_outline_rounded, color: AppTheme.coralDeep, size: 20),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text('কারণ', style: AppTheme.label.copyWith(color: AppTheme.coralDeep)),
                            const SizedBox(height: 2),
                            Text(reason, style: AppTheme.bodySm.copyWith(height: 1.45)),
                          ]),
                        ),
                      ]),
                    ),
                    const SizedBox(height: AppTheme.s24),
                    BigButton(
                      label: 'আবার আবেদন করুন',
                      icon: Icons.replay_rounded,
                      onPressed: () => _reapply(context),
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
                        onPressed: () => context.read<AuthProvider>().logout(),
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
