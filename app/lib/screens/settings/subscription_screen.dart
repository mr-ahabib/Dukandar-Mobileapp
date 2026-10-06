import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_config.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/auth_provider.dart';
import '../../providers/license_provider.dart';
import '../../widgets/common_widgets.dart' show AppListRow, ListGroup;
import '../../widgets/infra_widgets.dart';

/// Subscription details for non-blocked users: status, days left,
/// payment instructions, claim form and server notifications.
class SubscriptionScreen extends StatefulWidget {
  const SubscriptionScreen({super.key});

  @override
  State<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends State<SubscriptionScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<LicenseProvider>().refresh();
    });
  }

  @override
  Widget build(BuildContext context) {
    final lic = context.watch<LicenseProvider>();
    final auth = context.watch<AuthProvider>();
    final needsPayment = lic.status == LicenseStatus.due ||
        lic.status == LicenseStatus.trial ||
        lic.isStale;

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('সাবস্ক্রিপশন'),
        actions: [
          IconButton(
            tooltip: 'রিফ্রেশ',
            onPressed:
                lic.isRefreshing ? null : () => lic.refresh(force: true),
            icon: lic.isRefreshing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.refresh_rounded),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => lic.refresh(force: true),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(AppTheme.gutter, AppTheme.s8, AppTheme.gutter, 32),
          children: [
            // ---- Status card ----
            InfraCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          auth.shopName.isEmpty ? 'আপনার দোকান' : auth.shopName,
                          style: AppTheme.bodySm.copyWith(color: AppTheme.inkMuted),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      StatusChip(
                        label: lic.statusBn,
                        color: statusColor(lic.status),
                        icon: _statusIcon(lic.status),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    lic.planName.isEmpty ? 'মাসিক প্ল্যান' : lic.planName,
                    style: AppTheme.headline,
                  ),
                  if (lic.priceBdt > 0)
                    Text(
                      '${bnMoney(lic.priceBdt)} / মাস',
                      style: AppTheme.body.copyWith(color: AppTheme.inkMuted),
                    ),
                  const SizedBox(height: 14),
                  const Divider(),
                  _KV(label: _daysLabel(lic.status), value: '${bn(lic.daysLeft.abs())} দিন'),
                  const Divider(),
                  _KV(
                    label: lic.status == LicenseStatus.trial ? 'ট্রায়াল শেষ' : 'পরবর্তী ফি',
                    value: bnDate(lic.nextDueAt),
                  ),
                  if (lic.status == LicenseStatus.due && lic.graceEndsAt != null) ...[
                    const Divider(),
                    _KV(label: 'গ্রেস পিরিয়ড শেষ', value: bnDate(lic.graceEndsAt)),
                  ],
                  if (lic.messageBn.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(lic.messageBn, style: AppTheme.bodySm.copyWith(color: AppTheme.inkMuted, height: 1.4)),
                  ],
                ],
              ),
            ),
            if (lic.fetchedAt != null) ...[
              const SizedBox(height: 8),
              Center(
                child: Text(
                  'সর্বশেষ যাচাই: ${bnDateTime(lic.fetchedAt)}',
                  style: AppTheme.label.copyWith(color: AppTheme.slateMuted),
                ),
              ),
            ],
            if (lic.lastError != null) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  const Icon(Icons.wifi_off_rounded, color: AppTheme.gaveRed, size: 18),
                  const SizedBox(width: 8),
                  Expanded(child: Text(lic.lastError!, style: AppTheme.bodySm.copyWith(color: AppTheme.gaveRed))),
                ],
              ),
            ],

            const SectionTitle('ফি জমা দেওয়ার নিয়ম'),
            const PaymentInfoCard(),
            const SizedBox(height: 16),
            const PaymentClaimForm(),
            if (!needsPayment) ...[
              const SizedBox(height: 10),
              Text(
                'আগে থেকে ফি দিলে মেয়াদ পরের মাসে যোগ হবে।',
                textAlign: TextAlign.center,
                style: AppTheme.caption.copyWith(color: AppTheme.slateMuted),
              ),
            ],

            SectionTitle(
              'নোটিফিকেশন',
              trailing: lic.unreadCount > 0
                  ? TextButton(
                      onPressed: lic.markAllRead,
                      style: TextButton.styleFrom(
                          padding: EdgeInsets.zero,
                          minimumSize: const Size(0, 32)),
                      child: Text('সব পড়া হয়েছে (${bn(lic.unreadCount)})'),
                    )
                  : null,
            ),
            const NotificationList(),

            const SizedBox(height: AppTheme.s24),
            ListGroup(children: [
              AppListRow(
                onTap: callSupport,
                leading: const Icon(Icons.support_agent_outlined, color: AppTheme.inkMuted, size: 22),
                title: 'সাহায্য দরকার? কল করুন',
                subtitle: bn(AppConfig.supportPhone),
                chevron: true,
              ),
            ]),
          ],
        ),
      ),
    );
  }

  IconData _statusIcon(LicenseStatus s) {
    switch (s) {
      case LicenseStatus.active:
        return Icons.check_circle_rounded;
      case LicenseStatus.trial:
        return Icons.auto_awesome_rounded;
      case LicenseStatus.due:
        return Icons.schedule_rounded;
      case LicenseStatus.suspended:
      case LicenseStatus.disabled:
        return Icons.block_rounded;
      case LicenseStatus.pendingVerification:
        return Icons.hourglass_top_rounded;
      case LicenseStatus.rejected:
        return Icons.cancel_outlined;
      case LicenseStatus.unknown:
        return Icons.help_outline_rounded;
    }
  }

  String _daysLabel(LicenseStatus s) {
    switch (s) {
      case LicenseStatus.due:
        return 'দেরি হয়েছে';
      case LicenseStatus.trial:
        return 'ট্রায়াল বাকি';
      default:
        return 'মেয়াদ বাকি';
    }
  }
}

class _KV extends StatelessWidget {
  const _KV({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Expanded(child: Text(label, style: AppTheme.body.copyWith(color: AppTheme.inkMuted), maxLines: 1, overflow: TextOverflow.ellipsis)),
          const SizedBox(width: 12),
          Text(value, style: AppTheme.bodyStrong.copyWith(fontFeatures: AppTheme.tabular)),
        ],
      ),
    );
  }
}
