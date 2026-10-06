import 'dart:io';

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

import '../../core/app_config.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/photo_helper.dart';
import '../../core/utils/reminder_helper.dart';
import '../../providers/auth_provider.dart';
import '../../providers/license_provider.dart';
import '../../providers/shop_settings_provider.dart';
import '../../widgets/common_widgets.dart';
import '../backup/backup_screen.dart';
import '../products/products_screen.dart';
import '../reports/reports_screen.dart';
import 'subscription_screen.dart';

/// "আরও" tab – profile card + settings list.
class ShopSettingsScreen extends StatelessWidget {
  const ShopSettingsScreen({super.key});

  Future<void> _pickLogo(BuildContext context) async {
    final shop = context.read<ShopSettingsProvider>();
    final fromCamera = await AppBottomSheet.pickPhotoSource(context);
    if (fromCamera == null) return;
    final path = await PhotoHelper.pickAndStore(
      id: 'shop_logo',
      fromCamera: fromCamera,
    );
    if (path != null) {
      imageCache.clear();
      await shop.setLogoPath(path);
    }
  }

  @override
  Widget build(BuildContext context) {
    final shop = context.watch<ShopSettingsProvider>();
    final license = context.watch<LicenseProvider>();
    final auth = context.watch<AuthProvider>();
    final hasLogo = shop.logoPath != null && File(shop.logoPath!).existsSync();

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          const TabHeader(title: 'আরও'),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppTheme.gutter,
                AppTheme.s4,
                AppTheme.gutter,
                0,
              ),
              child: Column(
                children: [
                  // Shop card
                  PaperCard(
                    padding: const EdgeInsets.all(AppTheme.s16),
                    child: Row(
                      children: [
                        GestureDetector(
                          onTap: () => _pickLogo(context),
                          child: Container(
                            width: 56,
                            height: 56,
                            decoration: BoxDecoration(
                              color: AppTheme.sand,
                              borderRadius: BorderRadius.circular(
                                AppTheme.radiusMd,
                              ),
                              border: Border.all(color: AppTheme.hairline),
                              image: hasLogo
                                  ? DecorationImage(
                                      image: FileImage(File(shop.logoPath!)),
                                      fit: BoxFit.cover,
                                    )
                                  : null,
                            ),
                            child: hasLogo
                                ? null
                                : const Icon(
                                    Icons.storefront_outlined,
                                    color: AppTheme.inkMuted,
                                    size: 26,
                                  ),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                shop.shopName,
                                style: AppTheme.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              if (shop.ownerName.isNotEmpty ||
                                  auth.ownerName.isNotEmpty ||
                                  shop.phone.isNotEmpty ||
                                  auth.phone.isNotEmpty)
                                Text(
                                  [
                                    shop.ownerName.isNotEmpty
                                        ? shop.ownerName
                                        : auth.ownerName,
                                    shop.phone.isNotEmpty
                                        ? shop.phone
                                        : auth.phone,
                                  ].where((x) => x.isNotEmpty).join('  ·  '),
                                  style: AppTheme.bodySm.copyWith(
                                    color: AppTheme.inkMuted,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              if (license.planName.isNotEmpty ||
                                  license.status != LicenseStatus.unknown) ...[
                                const SizedBox(height: 6),
                                Pill(
                                  text: license.planName.isNotEmpty
                                      ? license.planName
                                      : _statusBn(license.status),
                                  color: license.showDueBanner
                                      ? AppTheme.saffron
                                      : AppTheme.emerald,
                                ),
                              ],
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: () => _editInfo(context, shop),
                          icon: const Icon(
                            Icons.edit_outlined,
                            color: AppTheme.inkMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  _Group(
                    title: 'অ্যাকাউন্ট',
                    children: [
                      _Tile(
                        icon: Icons.workspace_premium_outlined,
                        color: AppTheme.indigo,
                        title: 'সাবস্ক্রিপশন',
                        subtitle: license.showDueBanner
                            ? 'ফি বাকি — ${license.daysLeft} দিন'
                            : (license.planName.isNotEmpty
                                  ? license.planName
                                  : 'প্ল্যান ও পেমেন্ট'),
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const SubscriptionScreen(),
                          ),
                        ),
                      ),
                      _Tile(
                        icon: Icons.cloud_sync_outlined,
                        color: AppTheme.indigo,
                        title: 'ব্যাকআপ ও রিস্টোর',
                        subtitle: 'ফোনে বা Google Drive-এ',
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const BackupScreen(),
                          ),
                        ),
                      ),
                    ],
                  ),
                  _Group(
                    title: 'দোকান',
                    children: [
                      _Tile(
                        icon: Icons.storefront_outlined,
                        color: AppTheme.indigo,
                        title: 'দোকানের তথ্য',
                        subtitle: 'নাম, ঠিকানা, ফোন, বিকাশ',
                        onTap: () => _editInfo(context, shop),
                      ),
                      _Tile(
                        icon: Icons.receipt_long_outlined,
                        color: AppTheme.indigo,
                        title: 'মেমো সেটিংস',
                        subtitle: 'লোগো ও নিচের লেখা',
                        onTap: () => _memoSettings(context, shop),
                      ),
                      _Tile(
                        icon: Icons.inventory_2_outlined,
                        color: AppTheme.indigo,
                        title: 'পণ্য ও স্টক',
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const ProductsScreen(),
                          ),
                        ),
                      ),
                      _Tile(
                        icon: Icons.bar_chart_rounded,
                        color: AppTheme.indigo,
                        title: 'রিপোর্ট',
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const ReportsScreen(),
                          ),
                        ),
                      ),
                    ],
                  ),
                  _Group(
                    title: 'অ্যাপ',
                    children: [
                      _Tile(
                        icon: Icons.translate_rounded,
                        color: AppTheme.indigo,
                        title: 'বাংলা সংখ্যা',
                        subtitle: 'টাকার অঙ্ক ও PDF-এ বাংলা সংখ্যা',
                        trailing: Switch(
                          value: shop.useBanglaDigits,
                          onChanged: shop.setBanglaDigits,
                        ),
                      ),
                      _Tile(
                        icon: Icons.support_agent_outlined,
                        color: AppTheme.indigo,
                        title: 'সাহায্য',
                        subtitle: AppConfig.supportPhone,
                        onTap: () => ReminderHelper.makePhoneCall(
                          AppConfig.supportPhone,
                        ),
                      ),
                      _Tile(
                        icon: Icons.info_outline_rounded,
                        color: AppTheme.indigo,
                        title: 'অ্যাপ সম্পর্কে',
                        onTap: () => _about(context),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppTheme.s24),
                  _Tile(
                    icon: Icons.logout_rounded,
                    color: AppTheme.coral,
                    title: 'লগআউট',
                    titleColor: AppTheme.coral,
                    subtitle: 'ফোনের হিসাব মুছবে না',
                    onTap: () async {
                      final ok = await AppBottomSheet.confirm(
                        context,
                        title: 'লগআউট করবেন?',
                        message: 'আপনার খাতা, মেমো ও খরচের সব হিসাব এই ফোনেই থাকবে। আবার লগইন করলে সব আগের মতোই পাবেন।',
                        confirmLabel: 'লগআউট',
                        danger: true,
                      );
                      if (ok && context.mounted) {
                        await context.read<AuthProvider>().logout();
                      }
                    },
                  ),
                  const SizedBox(height: 120),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _statusBn(LicenseStatus s) => switch (s) {
    LicenseStatus.trial => 'ট্রায়াল',
    LicenseStatus.active => 'সক্রিয়',
    LicenseStatus.due => 'ফি বাকি',
    LicenseStatus.suspended => 'স্থগিত',
    LicenseStatus.disabled => 'বন্ধ',
    LicenseStatus.pendingVerification => 'যাচাই চলছে',
    LicenseStatus.rejected => 'আবেদন বাতিল',
    LicenseStatus.unknown => '',
  };

  Future<void> _editInfo(
    BuildContext context,
    ShopSettingsProvider shop,
  ) async {
    final name = TextEditingController(text: shop.shopName);
    final owner = TextEditingController(text: shop.ownerName);
    final phone = TextEditingController(text: shop.phone);
    final address = TextEditingController(text: shop.address);
    final bkash = TextEditingController(text: shop.bkashNumber);
    await AppBottomSheet.show(
      context,
      title: 'দোকানের তথ্য',
      child: SheetForm(
        bar: BottomActionBar(
          primary: PrimaryButton(
            label: 'সংরক্ষণ করুন',
            icon: Icons.check_rounded,
            onPressed: () async {
              await shop.updateSettings(
                shopName: name.text,
                ownerName: owner.text,
                phone: phone.text,
                address: address.text,
                bkashNumber: bkash.text,
              );
              if (context.mounted) Navigator.pop(context);
            },
          ),
        ),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppTextField(
              controller: name,
              label: 'দোকানের নাম',
              icon: Icons.storefront_outlined,
            ),
            const SizedBox(height: 12),
            AppTextField(
              controller: owner,
              label: 'মালিকের নাম',
              icon: Icons.person_outline_rounded,
            ),
            const SizedBox(height: 12),
            AppTextField(
              controller: phone,
              label: 'মোবাইল নম্বর',
              icon: Icons.phone_outlined,
              keyboardType: TextInputType.phone,
            ),
            const SizedBox(height: 12),
            AppTextField(
              controller: address,
              label: 'ঠিকানা',
              icon: Icons.location_on_outlined,
              maxLines: 2,
            ),
            const SizedBox(height: 12),
            AppTextField(
              controller: bkash,
              label: 'বিকাশ / নগদ নম্বর',
              icon: Icons.account_balance_wallet_outlined,
              keyboardType: TextInputType.phone,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _memoSettings(
    BuildContext context,
    ShopSettingsProvider shop,
  ) async {
    final footer = TextEditingController(text: shop.memoFooter);
    bool showLogo = shop.showMemoLogo;
    await AppBottomSheet.show(
      context,
      title: 'মেমো সেটিংস',
      child: StatefulBuilder(
        builder: (ctx, setSt) => SheetForm(
          bar: BottomActionBar(
            primary: PrimaryButton(
              label: 'সংরক্ষণ করুন',
              onPressed: () async {
                await shop.updateMemoSettings(
                  footer: footer.text,
                  showLogo: showLogo,
                );
                if (ctx.mounted) Navigator.pop(ctx);
              },
            ),
          ),
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SwitchListTile(
                value: showLogo,
                onChanged: (v) => setSt(() => showLogo = v),
                contentPadding: EdgeInsets.zero,
                title: const Text('মেমোতে দোকানের লোগো দেখান'),
                subtitle: Text(
                  shop.logoPath == null
                      ? 'লোগো দিতে উপরের দোকান কার্ডে চাপ দিন'
                      : 'লোগো যুক্ত আছে',
                ),
              ),
              const SizedBox(height: 8),
              AppTextField(
                controller: footer,
                label: 'মেমোর নিচের লেখা',
                hint: 'যেমন: ধন্যবাদ, আবার আসবেন',
                icon: Icons.short_text_rounded,
                maxLines: 2,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _about(BuildContext context) async {
    String version = '';
    try {
      final info = await PackageInfo.fromPlatform();
      version = '${info.version} (${info.buildNumber})';
    } catch (_) {}
    if (!context.mounted) return;
    await AppBottomSheet.show(
      context,
      title: 'দোকানদার',
      scrollable: false,
      child: Column(
        children: [
          const Icon(
            Icons.menu_book_outlined,
            color: AppTheme.inkMuted,
            size: 48,
          ),
          const SizedBox(height: 12),
          Text('দোকানদার', style: AppTheme.title),
          Text(
            version.isEmpty ? 'সংস্করণ' : 'সংস্করণ $version',
            style: AppTheme.caption,
          ),
          const SizedBox(height: 12),
          Text(
            'বাকি খাতা, ক্যাশ মেমো ও দৈনিক খরচের হিসাব — সম্পূর্ণ অফলাইনে, আপনার ফোনেই। আপনার ব্যবসার তথ্য কখনো সার্ভারে পাঠানো হয় না।',
            textAlign: TextAlign.center,
            style: AppTheme.bodySm.copyWith(
              height: 1.5,
              color: AppTheme.inkMuted,
            ),
          ),
          const SizedBox(height: 10),
        ],
      ),
    );
  }
}

class _Group extends StatelessWidget {
  final String title;
  final List<Widget> children;
  const _Group({required this.title, required this.children});
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: title,
          padding: const EdgeInsets.fromLTRB(0, AppTheme.s24, 0, AppTheme.s8),
        ),
        ListGroup(children: children),
      ],
    );
  }
}

class _Tile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;
  final Widget? trailing;
  final Color? titleColor;
  const _Tile({
    required this.icon,
    required this.color,
    required this.title,
    this.subtitle,
    this.onTap,
    this.trailing,
    this.titleColor,
  });
  @override
  Widget build(BuildContext context) {
    final row = AppListRow(
      onTap: onTap,
      leading: TintedIcon(icon, color: color),
      title: title,
      titleColor: titleColor,
      subtitle: subtitle,
      trailing: trailing,
      chevron: trailing == null && onTap != null,
    );
    if (titleColor != null) {
      return ListGroup(children: [row]);
    }
    return row;
  }
}
