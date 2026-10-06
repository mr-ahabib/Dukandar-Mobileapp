import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/currency_formatter.dart';
import '../../core/utils/date_formatter.dart';
import '../../core/utils/reminder_helper.dart';
import '../../models/customer.dart';
import '../../models/transaction_item.dart';
import '../../providers/auth_provider.dart';
import '../../providers/billing_provider.dart';
import '../../providers/cash_drawer_provider.dart';
import '../../providers/ledger_provider.dart';
import '../../providers/license_provider.dart';
import '../../widgets/infra_widgets.dart' show NotificationList;
import '../../providers/products_provider.dart';
import '../../providers/shop_settings_provider.dart';
import '../../widgets/common_widgets.dart';
import '../../widgets/due_banner.dart';
import '../billing/create_memo_screen.dart';
import '../cash_drawer/cash_drawer_screen.dart';
import '../ledger/add_customer_dialog.dart';
import '../ledger/customer_detail_screen.dart';
import '../products/products_screen.dart';
import '../reports/reports_screen.dart';

/// First tab: greeting header, hero receivables/payables, today's strip,
/// quick actions, overdue reminders, recent activity.
class HomeDashboardScreen extends StatelessWidget {
  final ValueChanged<int>? onGoToTab;
  const HomeDashboardScreen({super.key, this.onGoToTab});

  String _greeting() {
    final h = DateTime.now().hour;
    if (h < 12) return 'শুভ সকাল';
    if (h < 16) return 'শুভ দুপুর';
    if (h < 19) return 'শুভ বিকেল';
    return 'শুভ সন্ধ্যা';
  }

  @override
  Widget build(BuildContext context) {
    // `select` keeps this (always-alive, IndexedStack) tab from rebuilding on
    // every keystroke in the খাতা / মেমো search boxes: only the values the
    // dashboard actually shows are watched. Writes still refresh it because
    // the provider swaps list instances on every data change.
    final ledger = context.read<LedgerProvider>();
    final overdueAll = context.select<LedgerProvider, List<Customer>>((l) => l.overdueCustomers);
    final recent = context.select<LedgerProvider, List<TransactionItem>>((l) => l.recentTransactions);
    final billing = context.read<BillingProvider>();
    final todaySales = context.select<BillingProvider, double>((b) => b.todaySales);
    final hasMemos = context.select<BillingProvider, bool>((b) => b.allMemos.isNotEmpty);
    final cash = context.watch<CashDrawerProvider>();
    final shop = context.watch<ShopSettingsProvider>();
    final auth = context.watch<AuthProvider>();
    final license = context.watch<LicenseProvider>();
    final lowStockCount = context.select<ProductsProvider, int>((p) => p.lowStockCount);
    final shopName = shop.shopName.isNotEmpty && shop.shopName != 'আমার দোকান' ? shop.shopName : (auth.shopName.isNotEmpty ? auth.shopName : shop.shopName);
    final overdue = overdueAll.take(5).toList();
    final todayCollections = cash.isToday ? cash.collections : 0.0;
    final todayExpense = cash.isToday ? cash.totalExpense : 0.0;
    final notifCount = overdue.length + (license.showDueBanner ? 1 : 0) + license.unreadCount;

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: () async {
          await Future.wait([ledger.loadData(), billing.loadMemos(), cash.loadExpenses()]);
        },
        child: CustomScrollView(slivers: [
          // Dark gradient header + overlapping hero card
          SliverToBoxAdapter(
            child: Stack(clipBehavior: Clip.none, children: [
              Container(
                height: 236 + MediaQuery.of(context).padding.top,
                decoration: const BoxDecoration(
                  gradient: AppTheme.heroGradient,
                  borderRadius: BorderRadius.vertical(bottom: Radius.circular(AppTheme.radiusXl)),
                ),
                child: SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(AppTheme.gutter, 14, AppTheme.s8, 0),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('${_greeting()}${shop.ownerName.isNotEmpty ? ', ${shop.ownerName.split(' ').first}' : ''}', style: AppTheme.caption.copyWith(color: Colors.white70)),
                          const SizedBox(height: 2),
                          Text(shopName, style: AppTheme.headline.copyWith(color: Colors.white), maxLines: 1, overflow: TextOverflow.ellipsis),
                          const SizedBox(height: 4),
                          Text(AppDateFormatter.formatDateOnly(DateTime.now()), style: AppTheme.label.copyWith(color: Colors.white54)),
                        ]),
                      ),
                      _Bell(count: notifCount, onTap: () => _showNotifications(context, overdue, license)),
                    ]),
                  ),
                ),
              ),
              Positioned(
                left: AppTheme.gutter,
                right: AppTheme.gutter,
                top: 118 + MediaQuery.of(context).padding.top,
                child: RepaintBoundary(child: _HeroCard(onGoToTab: onGoToTab)),
              ),
            ]),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 86)),
          SliverToBoxAdapter(
            child: Padding(
              padding: AppTheme.pagePadding,
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                const DueBanner(margin: EdgeInsets.only(bottom: AppTheme.s12)),
                // Today's strip
                Row(children: [
                  _MiniTile(label: 'আজ বিক্রি', value: todaySales, color: AppTheme.indigo, icon: Icons.receipt_long_rounded),
                  const SizedBox(width: 8),
                  _MiniTile(label: 'আজ জমা', value: todayCollections, color: AppTheme.emerald, icon: Icons.south_west_rounded),
                  const SizedBox(width: 8),
                  _MiniTile(label: 'আজ খরচ', value: todayExpense, color: AppTheme.coral, icon: Icons.savings_rounded),
                ]),
              ]),
            ),
          ),
          // Quick actions
          const SliverToBoxAdapter(child: SectionHeader(title: 'দ্রুত কাজ')),
          SliverPadding(
            padding: AppTheme.pagePadding,
            sliver: SliverGrid.count(
              // 2 columns on narrow phones, 3 on phones, 4 on tablets.
              crossAxisCount: AppTheme.gridColumns(MediaQuery.sizeOf(context).width),
              mainAxisSpacing: AppTheme.s8,
              crossAxisSpacing: AppTheme.s8,
              childAspectRatio: 1.0,
              children: [
                QuickActionTile(icon: Icons.person_add_alt_1_rounded, label: 'খরিদ্দার যোগ', color: AppTheme.indigo, onTap: () => CustomerFormSheet.show(context)),
                QuickActionTile(icon: Icons.receipt_long_rounded, label: 'মেমো বানান', color: AppTheme.indigoMid, onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CreateMemoScreen()))),
                QuickActionTile(icon: Icons.savings_rounded, label: 'খরচ লিখুন', color: AppTheme.coral, onTap: () => CashDrawerScreen.showAddExpense(context)),
                QuickActionTile(icon: Icons.notifications_active_rounded, label: 'তাগাদা দিন', color: AppTheme.emeraldDeep, badge: overdueAll.length, onTap: () => _showNotifications(context, overdueAll, license)),
                QuickActionTile(icon: Icons.inventory_2_rounded, label: 'পণ্য ও স্টক', color: AppTheme.emerald, badge: lowStockCount, onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ProductsScreen()))),
                QuickActionTile(icon: Icons.bar_chart_rounded, label: 'রিপোর্ট', color: AppTheme.slate, onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ReportsScreen()))),
              ],
            ),
          ),
          // Cash drawer link
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(AppTheme.gutter, AppTheme.s12, AppTheme.gutter, 0),
              child: PaperCard(
                padding: EdgeInsets.zero,
                child: AppListRow(
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CashDrawerScreen())),
                  leading: const Icon(Icons.account_balance_wallet_outlined, color: AppTheme.inkMuted, size: 22),
                  title: 'আজকের নগদ',
                  subtitle: cash.isToday
                      // নগদ বিক্রি + আদায় − খরচ − মহাজনকে (money_rules.md)
                      ? 'নগদ ${CurrencyFormatter.format(cash.cashSales, includeSymbol: false)} + আদায় ${CurrencyFormatter.format(cash.collections, includeSymbol: false)} − খরচ ${CurrencyFormatter.format(cash.totalExpense, includeSymbol: false)}${cash.supplierPayments > 0 ? ' − মহাজন ${CurrencyFormatter.format(cash.supplierPayments, includeSymbol: false)}' : ''}'
                      : 'ক্যাশ বাক্স দেখুন',
                  amount: cash.isToday ? cash.netCash : 0,
                  amountColor: cash.isToday && cash.netCash < 0 ? AppTheme.coral : AppTheme.emeraldDeep,
                  chevron: true,
                ),
              ),
            ),
          ),
          // Overdue
          if (overdue.isNotEmpty) ...[
            SliverToBoxAdapter(
              child: SectionHeader(title: 'তাগাদা দিন', actionLabel: 'সব দেখুন', onAction: () {
                ledger.setFilter('due');
                onGoToTab?.call(1);
              }),
            ),
            SliverToBoxAdapter(
              child: SizedBox(
                height: 164,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: AppTheme.pagePadding,
                  itemCount: overdue.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 10),
                  itemBuilder: (_, i) => _OverdueCard(customer: overdue[i], shopName: shopName),
                ),
              ),
            ),
          ],
          // Recent activity
          SliverToBoxAdapter(
            child: SectionHeader(title: 'সাম্প্রতিক লেনদেন', actionLabel: 'খাতা', onAction: () => onGoToTab?.call(1)),
          ),
          if (recent.isEmpty && !hasMemos)
            SliverToBoxAdapter(
              child: Padding(
                padding: AppTheme.pagePadding,
                child: PaperCard(
                  padding: EdgeInsets.zero,
                  child: EmptyState(
                    icon: Icons.receipt_long_outlined,
                    title: 'এখনো কোনো লেনদেন নেই',
                    message: 'প্রথম খরিদ্দার যোগ করুন বা একটি মেমো বানান।',
                    actionLabel: 'খরিদ্দার যোগ করুন',
                    onAction: () => CustomerFormSheet.show(context),
                  ),
                ),
              ),
            )
          else
            SliverPadding(
              padding: AppTheme.pagePadding,
              sliver: SliverListGroup(
                sliver: SliverList.separated(
                  itemCount: recent.length,
                  separatorBuilder: (_, _) => const AppDivider(),
                  itemBuilder: (_, i) => _RecentTile(tx: recent[i], customer: ledger.byId(recent[i].customerId)),
                ),
              ),
            ),
          const SliverToBoxAdapter(child: SizedBox(height: 120)),
        ]),
      ),
    );
  }

  void _showNotifications(BuildContext context, List<Customer> overdue, LicenseProvider license) {
    final shop = context.read<ShopSettingsProvider>();
    AppBottomSheet.show(
      context,
      title: 'তাগাদা ও নোটিশ',
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (license.notifications.isNotEmpty) ...[
          Row(children: [
            Expanded(child: Text('নোটিশ', style: AppTheme.sectionHeader)),
            if (license.unreadCount > 0)
              TextButton(
                onPressed: license.markAllRead,
                style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                child: const Text('সব পড়া হয়েছে'),
              ),
          ]),
          const SizedBox(height: 4),
          const NotificationList(max: 5),
          const SizedBox(height: AppTheme.s16),
          Text('তাগাদা', style: AppTheme.sectionHeader),
          const SizedBox(height: AppTheme.s8),
        ],
        if (license.showDueBanner)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: NoteBox(
              icon: Icons.payments_outlined,
              color: AppTheme.saffron,
              text: license.messageBn.isNotEmpty ? license.messageBn : 'সাবস্ক্রিপশন ফি বাকি আছে। ${license.daysLeft} দিন বাকি।',
            ),
          ),
        if (overdue.isEmpty)
          const EmptyState(icon: Icons.task_alt_rounded, title: 'কারো তাগাদা বাকি নেই', message: '৭ দিনের বেশি বাকি থাকলে এখানে দেখাবে।')
        else
          ListGroup(
            children: [
              for (final c in overdue)
                AppListRow(
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(context, MaterialPageRoute(builder: (_) => CustomerDetailScreen(customerId: c.id)));
                  },
                  leading: AvatarCircle(name: c.name, photoPath: c.photoPath, size: 40),
                  title: c.name,
                  subtitle: '${relativeTimeBn(c.updatedAt)} থেকে বাকি',
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 110),
                      child: FittedBox(fit: BoxFit.scaleDown, child: TakaText(c.currentBalance, size: AppTheme.amountSmSize, color: AppTheme.coral)),
                    ),
                    if (c.phone.isNotEmpty) ...[
                      const SizedBox(width: 4),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        onPressed: () => ReminderHelper.makePhoneCall(c.phone),
                        icon: const Icon(Icons.call_outlined, color: AppTheme.inkMuted, size: 22),
                      ),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        onPressed: () => ReminderHelper.sendWhatsAppReminder(phoneNumber: c.phone, customerName: c.name, dueAmount: c.currentBalance, shopName: shop.shopName),
                        icon: const Icon(Icons.chat_outlined, color: AppTheme.inkMuted, size: 22),
                      ),
                    ],
                  ]),
                ),
            ],
          ),
      ]),
    );
  }
}

class _Bell extends StatelessWidget {
  final int count;
  final VoidCallback onTap;
  const _Bell({required this.count, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return Stack(clipBehavior: Clip.none, children: [
      IconButton(
        onPressed: onTap,
        icon: const Icon(Icons.notifications_none_rounded, color: Colors.white, size: 24),
        style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
      ),
      if (count > 0)
        Positioned(
          right: 4,
          top: 4,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(color: AppTheme.saffron, borderRadius: BorderRadius.circular(999), border: Border.all(color: AppTheme.navy, width: 2)),
            child: Text('$count', style: AppTheme.label.copyWith(color: Colors.white, fontSize: 10)), // badge: deliberate
          ),
        ),
    ]);
  }
}

class _HeroCard extends StatelessWidget {
  final ValueChanged<int>? onGoToTab;
  const _HeroCard({this.onGoToTab});

  @override
  Widget build(BuildContext context) {
    // Totals are cached in the provider; select() rebuilds only when they move.
    final rec = context.select<LedgerProvider, double>((l) => l.totalReceivables);
    final pay = context.select<LedgerProvider, double>((l) => l.totalPayables);
    final dueCustomers = context.select<LedgerProvider, int>((l) => l.dueCustomerCount);
    final dueSuppliers = context.select<LedgerProvider, int>((l) => l.dueSupplierCount);
    final net = rec - pay;
    return PaperCard(
      hero: true,
      radius: AppTheme.radiusLg,
      padding: const EdgeInsets.all(AppTheme.s16),
      onTap: () => onGoToTab?.call(1),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('মোট পাওনা', style: AppTheme.label),
              const SizedBox(height: 6),
              FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: TakaText(rec, size: AppTheme.amountLgSize, color: AppTheme.coral, weight: FontWeight.w700, animate: true)),
              const SizedBox(height: 2),
              Text('$dueCustomers জন খরিদ্দারের কাছে', style: AppTheme.caption, maxLines: 1, overflow: TextOverflow.ellipsis),
            ]),
          ),
          Container(width: 1, height: 64, color: AppTheme.hairline, margin: const EdgeInsets.symmetric(horizontal: 14)),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('মোট দেনা', style: AppTheme.label),
              const SizedBox(height: 6),
              FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: TakaText(pay, size: AppTheme.amountLgSize, color: AppTheme.ink, weight: FontWeight.w700, animate: true)),
              const SizedBox(height: 2),
              Text('$dueSuppliers জন মহাজনকে', style: AppTheme.caption, maxLines: 1, overflow: TextOverflow.ellipsis),
            ]),
          ),
        ]),
        const SizedBox(height: 14),
        const Divider(),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(
            child: Text(
              net >= 0 ? 'নিট পাওনা' : 'নিট দেনা',
              style: AppTheme.bodySm.copyWith(color: AppTheme.inkMuted),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(CurrencyFormatter.format(net.abs()), style: AppTheme.bodyStrong.copyWith(fontFeatures: AppTheme.tabular)),
          const SizedBox(width: 4),
          const Icon(Icons.chevron_right_rounded, size: 18, color: AppTheme.inkHint),
        ]),
      ]),
    );
  }
}

class _MiniTile extends StatelessWidget {
  final String label;
  final double value;
  final Color color;
  final IconData icon;
  const _MiniTile({required this.label, required this.value, required this.color, required this.icon});
  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: PaperCard(
        padding: const EdgeInsets.fromLTRB(12, 12, 10, 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(icon, size: 14, color: AppTheme.inkMuted),
            const SizedBox(width: 5),
            Expanded(child: Text(label, style: AppTheme.label, maxLines: 1, overflow: TextOverflow.ellipsis)),
          ]),
          const SizedBox(height: 8),
          FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: TakaText(value, size: AppTheme.amountMdSize, color: color)),
        ]),
      ),
    );
  }
}

class _OverdueCard extends StatelessWidget {
  final Customer customer;
  final String shopName;
  const _OverdueCard({required this.customer, required this.shopName});
  @override
  Widget build(BuildContext context) {
    final c = customer;
    return SizedBox(
      width: 210,
      child: PaperCard(
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => CustomerDetailScreen(customerId: c.id))),
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            AvatarCircle(name: c.name, photoPath: c.photoPath, size: 40),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(c.name, style: AppTheme.bodyStrong, maxLines: 1, overflow: TextOverflow.ellipsis),
                Text(relativeTimeBn(c.updatedAt), style: AppTheme.caption),
              ]),
            ),
          ]),
          const SizedBox(height: 10),
          FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: TakaText(c.currentBalance, size: AppTheme.amountMdSize, color: AppTheme.coral)),
          const Spacer(),
          Row(children: [
            Expanded(
              child: _SmallBtn(icon: Icons.call_outlined, label: 'কল', color: AppTheme.ink, onTap: c.phone.isEmpty ? null : () => ReminderHelper.makePhoneCall(c.phone)),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _SmallBtn(
                icon: Icons.chat_outlined,
                label: 'WhatsApp',
                color: AppTheme.ink,
                onTap: c.phone.isEmpty ? null : () => ReminderHelper.sendWhatsAppReminder(phoneNumber: c.phone, customerName: c.name, dueAmount: c.currentBalance, shopName: shopName),
              ),
            ),
          ]),
        ]),
      ),
    );
  }
}

class _SmallBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onTap;
  const _SmallBtn({required this.icon, required this.label, required this.color, this.onTap});
  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        foregroundColor: color,
        minimumSize: const Size(0, 36),
        padding: const EdgeInsets.symmetric(horizontal: 8),
        textStyle: AppTheme.bodySmStrong,
      ),
      child: Row(mainAxisAlignment: MainAxisAlignment.center, mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 16),
        const SizedBox(width: 5),
        Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis)),
      ]),
    );
  }
}

class _RecentTile extends StatelessWidget {
  final TransactionItem tx;
  final Customer? customer;
  const _RecentTile({required this.tx, this.customer});
  @override
  Widget build(BuildContext context) {
    final isCustomer = customer?.isCustomer ?? true;
    final isDebit = isCustomer ? tx.type == TransactionType.gave : tx.type == TransactionType.got;
    final color = isDebit ? AppTheme.coral : AppTheme.emerald;
    final label = isCustomer ? (tx.type == TransactionType.gave ? 'বাকি দিলাম' : 'জমা পেলাম') : (tx.type == TransactionType.gave ? 'টাকা দিলাম' : 'মাল পেলাম');
    return AppListRow(
      onTap: customer == null ? null : () => Navigator.push(context, MaterialPageRoute(builder: (_) => CustomerDetailScreen(customerId: customer!.id))),
      leading: AvatarCircle(name: customer?.name ?? '?', photoPath: customer?.photoPath, size: 40),
      title: customer?.name ?? 'অজানা',
      subtitle: '$label  ·  ${AppDateFormatter.formatShort(tx.date)}',
      amount: tx.amount,
      amountColor: color,
    );
  }
}
