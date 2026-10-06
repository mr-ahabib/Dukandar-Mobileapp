import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/theme/app_theme.dart';
import '../providers/license_provider.dart';
import '../screens/settings/subscription_screen.dart';
import 'infra_widgets.dart';

/// Compact banner for the top of the home screen.
/// Visible when the fee is due (grace period) or the trial ends in ≤ 3 days.
/// Tap → [SubscriptionScreen].
class DueBanner extends StatelessWidget {
  const DueBanner({super.key, this.margin = const EdgeInsets.fromLTRB(16, 8, 16, 4)});

  final EdgeInsetsGeometry margin;

  @override
  Widget build(BuildContext context) {
    final lic = context.watch<LicenseProvider>();
    final due = lic.showDueBanner;
    final trialSoon = lic.isTrialEndingSoon;
    if (!due && !trialSoon) return const SizedBox.shrink();

    final Color color = due ? AppTheme.saffron : AppTheme.primaryBlue;
    final Color bg = due ? const Color(0xFFFFFBEB) : AppTheme.primaryBlueLight;
    final IconData icon =
        due ? Icons.payments_rounded : Icons.hourglass_bottom_rounded;

    String title;
    String subtitle;
    if (due) {
      title = 'মাসিক ফি জমা দিন';
      final left = lic.graceEndsAt != null
          ? _daysUntil(lic.graceEndsAt!)
          : (lic.graceDays + lic.daysLeft);
      subtitle = lic.isStale
          ? lic.messageBn
          : left > 0
              ? 'আর ${bn(left)} দিন পর অ্যাপ বন্ধ হয়ে যাবে'
              : 'আজই শেষ দিন — পরে অ্যাপ বন্ধ হয়ে যাবে';
    } else {
      title = lic.daysLeft <= 0
          ? 'আজ ফ্রি ট্রায়াল শেষ হচ্ছে'
          : 'ফ্রি ট্রায়াল শেষ হতে ${bn(lic.daysLeft)} দিন বাকি';
      subtitle = lic.priceBdt > 0
          ? 'চালিয়ে যেতে ${bnMoney(lic.priceBdt)}/মাস ফি জমা দিন'
          : 'চালিয়ে যেতে সাবস্ক্রিপশন চালু করুন';
    }

    return Padding(
      padding: margin,
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppTheme.radiusMd),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const SubscriptionScreen()),
          ),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppTheme.radiusMd),
              border: Border.all(color: color.withValues(alpha: 0.25)),
            ),
            child: Row(
              children: [
                Icon(icon, color: color, size: AppTheme.iconList),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: AppTheme.bodySmStrong.copyWith(color: AppTheme.ink),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (subtitle.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          style: AppTheme.caption,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text('ফি দিন', style: AppTheme.bodySmStrong.copyWith(color: color)),
                Icon(Icons.chevron_right_rounded, size: 20, color: color),
              ],
            ),
          ),
        ),
      ),
    );
  }

  int _daysUntil(DateTime d) {
    final now = DateTime.now();
    return DateTime(d.year, d.month, d.day)
        .difference(DateTime(now.year, now.month, now.day))
        .inDays;
  }
}
