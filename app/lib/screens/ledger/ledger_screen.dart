import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/reminder_helper.dart';
import '../../models/customer.dart';
import '../../providers/ledger_provider.dart';
import '../../providers/shop_settings_provider.dart';
import '../../widgets/common_widgets.dart';
import 'add_customer_dialog.dart';
import 'customer_detail_screen.dart';
import 'record_transaction_dialog.dart';
import '../../models/transaction_item.dart';

/// বাকি খাতা – customers & suppliers.
class LedgerScreen extends StatefulWidget {
  final ContactType initialType;
  const LedgerScreen({super.key, this.initialType = ContactType.customer});

  @override
  State<LedgerScreen> createState() => _LedgerScreenState();
}

class _LedgerScreenState extends State<LedgerScreen> {
  late ContactType _type = widget.initialType;
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    final c = await CustomerFormSheet.show(context, type: _type);
    if (c != null && mounted) {
      Navigator.push(context, MaterialPageRoute(builder: (_) => CustomerDetailScreen(customerId: c.id)));
    }
  }

  void _open(Customer c) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => CustomerDetailScreen(customerId: c.id)));
  }

  Future<void> _actions(Customer c) async {
    final shop = context.read<ShopSettingsProvider>();
    final ledger = context.read<LedgerProvider>();
    await AppBottomSheet.show(
      context,
      title: c.name,
      scrollable: false,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        _ActionRow(icon: Icons.open_in_new_rounded, label: 'খাতা দেখুন', onTap: () {
          Navigator.pop(context);
          _open(c);
        }),
        if (c.phone.isNotEmpty)
          _ActionRow(icon: Icons.call_rounded, color: AppTheme.emerald, label: 'ফোন করুন', onTap: () {
            Navigator.pop(context);
            ReminderHelper.makePhoneCall(c.phone);
          }),
        if (c.phone.isNotEmpty && c.currentBalance > 0)
          _ActionRow(icon: Icons.chat_rounded, color: AppTheme.emeraldDeep, label: 'WhatsApp তাগাদা', onTap: () {
            Navigator.pop(context);
            ReminderHelper.sendWhatsAppReminder(
                phoneNumber: c.phone, customerName: c.name, dueAmount: c.currentBalance, shopName: shop.shopName);
          }),
        _ActionRow(icon: Icons.edit_rounded, label: 'তথ্য পরিবর্তন', onTap: () async {
          Navigator.pop(context);
          await CustomerFormSheet.show(context, existing: c);
        }),
        _ActionRow(icon: Icons.delete_outline_rounded, color: AppTheme.coral, label: 'মুছে ফেলুন', onTap: () async {
          Navigator.pop(context);
          final ok = await AppBottomSheet.confirm(context,
              title: 'মুছে ফেলবেন?',
              message: '${c.name} এবং তার সব লেনদেন মুছে যাবে। এটি ফেরানো যাবে না।',
              confirmLabel: 'মুছুন',
              danger: true);
          if (ok) await ledger.deleteContact(c);
        }),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ledger = context.watch<LedgerProvider>();
    final isCustomer = _type == ContactType.customer;
    // Filtering, sorting and partitioning are cached in the provider and
    // recomputed only when data / search / filter change — not per frame.
    final sections = ledger.sections(_type);
    final list = sections.visible;
    final raw = isCustomer ? ledger.allCustomersRaw : ledger.allSuppliersRaw;
    final total = isCustomer ? ledger.totalReceivables : ledger.totalPayables;
    final dueCount = isCustomer ? ledger.dueCustomerCount : ledger.dueSupplierCount;
    final settledCount = ledger.settledCount(_type);
    final activeCount = ledger.activeCount(_type);
    final isHistory = ledger.selectedFilter == 'zero';
    final color = isCustomer ? AppTheme.coral : AppTheme.slate;
    final dueList = sections.due;
    final advanceList = sections.advance;
    final settledList = sections.settled;

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: ledger.loadData,
        child: CustomScrollView(
          slivers: [
            TabHeader(
              title: 'বাকি খাতা',
              actions: [
                IconButton(onPressed: _add, icon: const Icon(Icons.person_add_alt_1_rounded), tooltip: 'নতুন যোগ'),
              ],
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(AppTheme.gutter, AppTheme.s4, AppTheme.gutter, 0),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Segmented<ContactType>(
                    values: const [ContactType.customer, ContactType.supplier],
                    selected: _type,
                    label: (t) => t == ContactType.customer ? 'খরিদ্দার' : 'মহাজন',
                    colorOf: (t) => t == ContactType.customer ? AppTheme.indigo : AppTheme.slate,
                    onChanged: (t) => setState(() => _type = t),
                  ),
                  const SizedBox(height: 16),
                  // Summary strip
                  PaperCard(
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                    child: Row(children: [
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(isCustomer ? 'মোট পাবেন' : 'মোট দেবেন', style: AppTheme.label),
                          const SizedBox(height: 4),
                          FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: TakaText(total, size: AppTheme.amountLgSize, color: color, weight: FontWeight.w700, animate: true)),
                        ]),
                      ),
                      Container(width: 1, height: 40, color: AppTheme.hairline),
                      const SizedBox(width: AppTheme.s16),
                      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('বাকি আছে', style: AppTheme.label),
                        const SizedBox(height: 4),
                        Text('$dueCount জন', style: AppTheme.amountMd),
                      ]),
                    ]),
                  ),
                  const SizedBox(height: 12),
                  SearchField(
                    controller: _search,
                    hint: 'নাম বা মোবাইল নম্বর খুঁজুন',
                    onChanged: ledger.setSearchQuery,
                    onVoice: (_) {},
                  ),
                  const SizedBox(height: 12),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(children: [
                      FilterPill(label: 'চলতি খাতা', selected: ledger.selectedFilter == 'all', count: activeCount, onTap: () => ledger.setFilter('all')),
                      const SizedBox(width: 8),
                      FilterPill(label: isCustomer ? 'বাকি আছে' : 'দেনা আছে', selected: ledger.selectedFilter == 'due', count: dueCount, color: color, onTap: () => ledger.setFilter('due')),
                      const SizedBox(width: 8),
                      FilterPill(label: 'হিসাব মিটে গেছে', selected: isHistory, count: settledCount, color: AppTheme.emerald, onTap: () => ledger.setFilter('zero')),
                    ]),
                  ),
                  const SizedBox(height: 4),
                ]),
              ),
            ),
            if ((ledger.isLoading || !ledger.loadedOnce) && raw.isEmpty)
              const SliverFillRemaining(child: Center(child: CircularProgressIndicator()))
            else if (raw.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: EmptyState(
                  icon: isCustomer ? Icons.people_alt_outlined : Icons.local_shipping_outlined,
                  title: isCustomer ? 'এখনো কোনো খরিদ্দার নেই' : 'এখনো কোনো মহাজন নেই',
                  message: isCustomer
                      ? 'যারা বাকিতে মাল নেয়, তাদের নাম যোগ করুন।'
                      : 'যাদের কাছ থেকে মাল কেনেন, তাদের যোগ করুন।',
                  actionLabel: isCustomer ? 'খরিদ্দার যোগ করুন' : 'মহাজন যোগ করুন',
                  onAction: _add,
                ),
              )
            else if (list.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: isHistory
                    ? const EmptyState(icon: Icons.history_rounded, title: 'এখনো কারো হিসাব মেটেনি', message: 'কারো বাকি শূন্য হলে সে এখানে আসবে।')
                    : (ledger.searchQuery.isNotEmpty
                        ? const EmptyState(icon: Icons.search_off_rounded, title: 'কাউকে পাওয়া যায়নি', message: 'অন্য নাম বা নম্বর দিয়ে খুঁজুন')
                        : const EmptyState(icon: Icons.task_alt_rounded, title: 'সবার হিসাব মিটে গেছে', message: 'মিটে যাওয়া হিসাব "হিসাব মিটে গেছে" ফিল্টারে দেখুন।')),
              )
            else ...[
              if (isHistory) ...[
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(AppTheme.gutter, AppTheme.s8, AppTheme.gutter, AppTheme.s8),
                    child: const NoteBox(
                      icon: Icons.history_rounded,
                      text: 'এদের হিসাব মিটে গেছে। নতুন লেনদেন লিখলেই আবার চলতি খাতায় ফিরবে।',
                    ),
                  ),
                ),
                _list(settledList, settled: true),
              ] else ...[
                if (dueList.isNotEmpty) ...[
                  _stickyHeader(isCustomer ? 'বাকি আছে' : 'দেনা আছে', dueList.length, color),
                  _list(dueList),
                ],
                if (advanceList.isNotEmpty) ...[
                  _stickyHeader(isCustomer ? 'অগ্রিম জমা আছে' : 'অগ্রিম দেওয়া আছে', advanceList.length, AppTheme.emerald),
                  _list(advanceList),
                ],
              ],
              const SliverToBoxAdapter(child: SizedBox(height: 120)),
            ],
          ],
        ),
      ),
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 84),
        child: FloatingActionButton.extended(
          onPressed: _add,
          backgroundColor: isCustomer ? AppTheme.indigo : AppTheme.slate,
          icon: const Icon(Icons.add_rounded),
          label: Text(isCustomer ? 'খরিদ্দার' : 'মহাজন'),
        ),
      ),
    );
  }

  Widget _stickyHeader(String title, int count, Color color) {
    return SliverPersistentHeader(
      pinned: true,
      delegate: StickyHeader(
        height: 40,
        child: Padding(
          padding: AppTheme.pagePadding,
          child: Text('$title · $count জন', style: AppTheme.sectionHeader),
        ),
      ),
    );
  }

  Widget _list(List<Customer> items, {bool settled = false}) {
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(AppTheme.gutter, 0, AppTheme.gutter, AppTheme.s12),
      sliver: SliverListGroup(
        sliver: SliverList.separated(
          itemCount: items.length,
          separatorBuilder: (_, _) => const AppDivider(),
          itemBuilder: (_, i) => CustomerTile(
            customer: items[i],
            onTap: () => _open(items[i]),
            onLongPress: () => _actions(items[i]),
            onReopen: settled ? () => _reopen(items[i]) : null,
          ),
        ),
      ),
    );
  }

  /// One-tap reopen: a new transaction brings a settled contact back to the খাতা.
  Future<void> _reopen(Customer c) async {
    final ok = await RecordTransactionSheet.show(context, customer: c, type: c.isCustomer ? TransactionType.gave : TransactionType.got);
    if (ok == true && mounted) {
      context.read<LedgerProvider>().setFilter('all');
      showSnack(context, '${c.name} আবার চলতি খাতায় ফিরেছে');
    }
  }
}

class _ActionRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color color;
  const _ActionRow({required this.icon, required this.label, required this.onTap, this.color = AppTheme.indigo});

  @override
  Widget build(BuildContext context) {
    final danger = color == AppTheme.coral;
    return AppListRow(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      leading: Icon(icon, size: 22, color: danger ? AppTheme.coral : AppTheme.inkMuted),
      title: label,
      titleColor: danger ? AppTheme.coral : null,
      chevron: true,
    );
  }
}

/// Row used in lists: avatar, name, last activity, right-aligned amount + label.
class CustomerTile extends StatelessWidget {
  final Customer customer;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final VoidCallback? onReopen;
  const CustomerTile({super.key, required this.customer, required this.onTap, this.onLongPress, this.onReopen});

  @override
  Widget build(BuildContext context) {
    final c = customer;
    final hasDue = c.currentBalance > 0;
    final settled = c.currentBalance == 0;
    final color = hasDue ? (c.isCustomer ? AppTheme.coral : AppTheme.slate) : AppTheme.emerald;
    final label = hasDue ? (c.isCustomer ? 'পাবেন' : 'দেবেন') : (settled ? 'মিটে গেছে' : (c.isCustomer ? 'অগ্রিম জমা' : 'অগ্রিম দেওয়া'));
    final sub = [relativeTimeBn(c.updatedAt), if (c.phone.isNotEmpty) c.phone].join('  ·  ');
    return AppListRow(
      onTap: onTap,
      onLongPress: onLongPress,
      leading: AvatarCircle(name: c.name, photoPath: c.photoPath, size: 40),
      title: c.name,
      subtitle: sub,
      trailing: onReopen == null
          ? null
          : TonalButton(label: 'নতুন লেনদেন', expanded: false, height: 36, onPressed: onReopen),
      amount: onReopen == null ? c.currentBalance.abs() : null,
      amountColor: color,
      trailingLabel: onReopen == null ? label : null,
      trailingLabelColor: settled ? AppTheme.inkMuted : color,
    );
  }
}
