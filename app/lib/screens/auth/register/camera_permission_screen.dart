import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../widgets/infra_widgets.dart';

/// Explains that the camera permission was denied and how to turn it on.
/// (No app-settings deep link available; instructions only.)
class CameraPermissionScreen extends StatelessWidget {
  const CameraPermissionScreen({super.key, required this.title, required this.onRetry, this.onGallery});
  final String title;
  final VoidCallback onRetry;
  final VoidCallback? onGallery;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppTheme.s24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: AppTheme.dialogMaxWidth),
            child: InfraCard(
              padding: const EdgeInsets.all(AppTheme.s24),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Container(
                  width: 72,
                  height: 72,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(color: AppTheme.saffronSoft, shape: BoxShape.circle),
                  child: const Icon(Icons.no_photography_outlined, color: AppTheme.saffron, size: 34),
                ),
                const SizedBox(height: AppTheme.s20),
                Text('ক্যামেরার অনুমতি দরকার', textAlign: TextAlign.center, style: AppTheme.headline),
                const SizedBox(height: AppTheme.s8),
                Text(
                  'NID ও মুখের ছবি তুলতে ক্যামেরার অনুমতি লাগবে। ছবি শুধু যাচাইয়ের জন্য ব্যবহার হবে।',
                  textAlign: TextAlign.center,
                  style: AppTheme.bodySm.copyWith(color: AppTheme.inkMuted, height: 1.5),
                ),
                const SizedBox(height: AppTheme.s16),
                Container(
                  padding: const EdgeInsets.all(AppTheme.s12),
                  decoration: BoxDecoration(color: AppTheme.sand, borderRadius: BorderRadius.circular(AppTheme.radiusMd)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('সেটিংসে যান', style: AppTheme.bodySmStrong),
                    const SizedBox(height: 6),
                    Text(
                      'ফোনের Settings → Apps → দোকানদার → Permissions → Camera → Allow। তারপর এখানে ফিরে "আবার চেষ্টা করুন" চাপুন।',
                      style: AppTheme.bodySm.copyWith(height: 1.5),
                    ),
                  ]),
                ),
                const SizedBox(height: AppTheme.s24),
                BigButton(label: 'আবার চেষ্টা করুন', icon: Icons.refresh_rounded, onPressed: onRetry),
                if (onGallery != null) ...[
                  const SizedBox(height: AppTheme.s12),
                  BigButton(label: 'গ্যালারি থেকে ছবি দিন', icon: Icons.photo_library_outlined, outlined: true, onPressed: onGallery),
                ],
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
