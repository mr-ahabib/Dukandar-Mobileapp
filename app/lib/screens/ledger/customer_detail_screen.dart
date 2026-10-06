import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/currency_formatter.dart';
import '../../core/utils/date_formatter.dart';
import '../../core/utils/photo_helper.dart';
import '../../core/utils/reminder_helper.dart';
import '../../core/utils/statement_pdf.dart';
import '../../models/customer.dart';
import '../../models/transaction_item.dart';
import '../../providers/ledger_provider.dart';
import '../../providers/shop_settings_provider.dart';
import '../../widgets/common_widgets.dart';
import 'add_customer_dialog.dart';
import 'record_transaction_dialog.dart';

class CustomerDetailScreen extends StatefulWidget {
  final String customerId;
  const CustomerDetailScreen({super.key, required this.customerId});

  @override
  State<CustomerDetailScreen> createState() => _CustomerDetailScreenState();
}

class _CustomerDetailScreenState extends State<CustomerDetailScreen> {
  List<TransactionItem> _txs = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final list = await context.read<LedgerProvider>().getCustomerTransactions(widget.customerId);
    if (mounted) {
      setState(() {
        _txs = list;
        _loading = false;
      });
    }
  }

  Future<void> _record(Customer c, TransactionType type) async {
    final ok = await RecordTransactionSheet.show(context, customer: c, type: type);
    if (ok == true) _load();
  }

  Future<void> _txActions(Customer c, TransactionItem tx) async {
    final ledger = context.read<LedgerProvider>();
    await AppBottomSheet.show(
      context,
      title: CurrencyFormatter.format(tx.amount),
      scrollable: false,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        if (PhotoHelper.exists(tx.photoPath))
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppTheme.radiusMd),
              child: Image.file(File(tx.photoPath!), height: 200, fit: BoxFit.cover),
            ),
          ),
        ListTile(
          leading: const Icon(Icons.edit_outlined, color: AppTheme.inkMuted),
          title: const Text('পরিবর্তন করুন'),
          onTap: () async {
            Navigator.pop(context);
            final ok = await RecordTransactionSheet.show(context, customer: c, type: tx.type, existing: tx);
            if (ok == true) _load();
          },
        ),
        ListTile(
          leading: const Icon(Icons.delete_outline_rounded, color: AppTheme.coral),
          title: Text('মুছে ফেলুন', style: AppTheme.bodyStrong.copyWith(color: AppTheme.coral)),
          onTap: () async {
            Navigator.pop(context);
            final ok = await AppBottomSheet.confirm(context,
                title: 'লেনদেন মুছবেন?', message: 'এই এন্ট্রি মুছে গেলে ব্যালেন্স আবার হিসাব হবে।', confirmLabel: 'মুছুন', danger: true);
            if (ok) {
              await ledger.deleteTransaction(tx);
              _load();
            }
          },
        ),
      ]),
    );
  }

  Future<void> _remind(Customer c) async {
    final shop = context.read<ShopSettingsProvider>();
    await AppBottomSheet.show(
      context,
      title: 'তাগাদা দিন',
      scrollable: false,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        _RemindTile(icon: Icons.call_outlined, color: AppTheme.emerald, title: 'ফোন করুন', subtitle: c.phone, onTap: () {
          Navigator.pop(context);
          ReminderHelper.makePhoneCall(c.phone);
        }),
        _RemindTile(icon: Icons.chat_outlined, color: AppTheme.emeraldDeep, title: 'WhatsApp বার্তা', subtitle: 'বাকির পরিমাণসহ বার্তা পাঠান', onTap: () {
          Navigator.pop(context);
          ReminderHelper.sendWhatsAppReminder(phoneNumber: c.phone, customerName: c.name, dueAmount: c.currentBalance, shopName: shop.shopName);
        }),
        _RemindTile(icon: Icons.sms_outlined, color: AppTheme.indigo, title: 'SMS পাঠান', subtitle: 'সাধারণ মেসেজ', onTap: () {
          Navigator.pop(context);
          ReminderHelper.sendSmsReminder(phoneNumber: c.phone, customerName: c.name, dueAmount: c.currentBalance, shopName: shop.shopName);
        }),
      ]),
    );
  }

  Future<void> _more(Customer c) async {
    final ledger = context.read<LedgerProvider>();
    final shop = context.read<ShopSettingsProvider>();
    await AppBottomSheet.show(
      context,
      title: c.name,
      scrollable: false,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        ListTile(
          leading: const Icon(Icons.picture_as_pdf_outlined, color: AppTheme.inkMuted),
          title: const Text('হিসাব বিবরণী (PDF) শেয়ার'),
          onTap: () async {
            Navigator.pop(context);
            await StatementPdf.share(customer: c, transactions: _txs, branding: shop.pdfBranding);
          },
        ),
        ListTile(
          leading: const Icon(Icons.edit_outlined, color: AppTheme.inkMuted),
          title: const Text('তথ্য পরিবর্তন'),
          onTap: () async {
            Navigator.pop(context);
            await CustomerFormSheet.show(context, existing: c);
          },
        ),
        ListTile(
          leading: const Icon(Icons.delete_outline_rounded, color: AppTheme.coral),
          title: Text('মুছে ফেলুন', style: AppTheme.bodyStrong.copyWith(color: AppTheme.coral)),
          onTap: () async {
            Navigator.pop(context);
            final ok = await AppBottomSheet.confirm(context,
                title: 'মুছে ফেলবেন?', message: '${c.name} এবং সব লেনদেন মুছে যাবে।', confirmLabel: 'মুছুন', danger: true);
            if (ok) {
              await ledger.deleteContact(c);
              if (mounted) Navigator.pop(context);
            }
          },
        ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ledger = context.watch<LedgerProvider>();
    final c = ledger.byId(widget.customerId);
    if (c == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final isCustomer = c.isCustomer;
    final hasDue = c.currentBalance > 0;
    final hasAdvance = c.currentBalance < 0;
    // Positive → they owe / we owe; negative → advance (shown, never hidden).
    final balanceLabel = hasDue
        ? (isCustomer ? 'পাবেন' : 'দেবেন')
        : hasAdvance
            ? (isCustomer ? 'অগ্রিম জমা আছে' : 'অগ্রিম দেওয়া আছে')
            : 'হিসাব পরিষ্কার';

    final balanceColor = hasAdvance ? AppTheme.accentEmerald : Colors.white;
    final meta = [c.phone, c.address].where((x) => x.isNotEmpty).join('  ·  ');

    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppTheme.navy,
        foregroundColor: Colors.white,
        title: Text(c.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTheme.title.copyWith(color: Colors.white)),
        actions: [
          IconButton(onPressed: () => _more(c), icon: const Icon(Icons.more_vert_rounded)),
        ],
      ),
      body: CustomScrollView(slivers: [
        // Compact flat header: phone/address left, balance pill right.
        SliverToBoxAdapter(
          child: Container(
            color: AppTheme.navy,
            padding: const EdgeInsets.fromLTRB(AppTheme.gutter, 0, AppTheme.gutter, AppTheme.s16),
            child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
              Expanded(
                child: Text(
                  meta.isEmpty ? (isCustomer ? 'খরিদ্দার' : 'মহাজন') : meta,
                  style: AppTheme.bodySm.copyWith(color: Colors.white70),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: AppTheme.s12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(AppTheme.radiusMd)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.end, mainAxisSize: MainAxisSize.min, children: [
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 160),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerRight,
                      child: TakaText(c.currentBalance.abs(), size: AppTheme.amountLgSize, color: balanceColor, weight: FontWeight.w700, animate: true),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(balanceLabel, style: AppTheme.label.copyWith(color: Colors.white70), maxLines: 1, overflow: TextOverflow.ellipsis),
                ]),
              ),
            ]),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(AppTheme.gutter, AppTheme.s16, AppTheme.gutter, 0),
            child: Column(children: [
              Row(children: [
                Expanded(
                  child: BigActionButton(
                    label: 'দিলাম',
                    sublabel: isCustomer ? 'বাকিতে মাল দিলাম' : 'টাকা পরিশোধ করলাম',
                    icon: Icons.arrow_upward_rounded,
                    color: AppTheme.coral,
                    onTap: () => _record(c, TransactionType.gave),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: BigActionButton(
                    label: 'পেলাম',
                    sublabel: isCustomer ? 'টাকা জমা পেলাম' : 'বাকিতে মাল পেলাম',
                    icon: Icons.arrow_downward_rounded,
                    color: AppTheme.emerald,
                    onTap: () => _record(c, TransactionType.got),
                  ),
                ),
              ]),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                  child: TonalButton(
                    label: 'তাগাদা',
                    icon: Icons.notifications_none_rounded,
                    onPressed: c.phone.isEmpty ? null : () => _remind(c),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TonalButton(
                    label: 'PDF বিবরণী',
                    icon: Icons.picture_as_pdf_outlined,
                    onPressed: () async {
                      final shop = context.read<ShopSettingsProvider>();
                      await StatementPdf.share(customer: c, transactions: _txs, branding: shop.pdfBranding);
                    },
                  ),
                ),
              ]),
              if (c.note.isNotEmpty) ...[
                const SizedBox(height: AppTheme.s12),
                NoteBox(icon: Icons.sticky_note_2_outlined, text: c.note),
              ],
            ]),
          ),
        ),
        const SliverToBoxAdapter(child: SectionHeader(title: 'লেনদেনের ইতিহাস')),
        if (_loading)
          const SliverToBoxAdapter(child: Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator())))
        else if (_txs.isEmpty)
          const SliverToBoxAdapter(
            child: EmptyState(
              icon: Icons.receipt_long_outlined,
              title: 'এখনো কোনো লেনদেন নেই',
              message: 'উপরের দিলাম / পেলাম বোতামে প্রথম এন্ট্রি লিখুন।',
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(AppTheme.gutter, 0, AppTheme.gutter, 40),
            sliver: SliverListGroup(
              sliver: SliverList.separated(
                itemCount: _txs.length,
                separatorBuilder: (_, _) => const AppDivider(),
                itemBuilder: (_, i) => _TxRow(
                  tx: _txs[i],
                  customer: c,
                  onTap: () => _txActions(c, _txs[i]),
                ),
              ),
            ),
          ),
      ]),
    );
  }
}

class _RemindTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  const _RemindTile({required this.icon, required this.color, required this.title, required this.subtitle, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return AppListRow(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      leading: Icon(icon, size: 22, color: AppTheme.inkMuted),
      title: title,
      subtitle: subtitle,
      chevron: true,
    );
  }
}

class _TxRow extends StatelessWidget {
  final TransactionItem tx;
  final Customer customer;
  final VoidCallback onTap;
  const _TxRow({required this.tx, required this.customer, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isCustomer = customer.isCustomer;
    // Debit = increases balance owed.
    final isDebit = isCustomer ? tx.type == TransactionType.gave : tx.type == TransactionType.got;
    final color = isDebit ? AppTheme.coral : AppTheme.emerald;
    final label = isCustomer
        ? (tx.type == TransactionType.gave ? 'বাকি দিলাম' : 'টাকা পেলাম')
        : (tx.type == TransactionType.gave ? 'টাকা দিলাম' : 'মাল পেলাম');
    final hasPhoto = PhotoHelper.exists(tx.photoPath);
    final sub = [
      AppDateFormatter.formatShort(tx.date),
      if (tx.note.trim().isNotEmpty) tx.note.trim(),
    ].join('  ·  ');

    return AppListRow(
      onTap: onTap,
      leading: TintedIcon(tx.type == TransactionType.gave ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded, color: color),
      title: label,
      subtitleWidget: Row(children: [
        Flexible(child: Text(sub, style: AppTheme.bodySm.copyWith(color: AppTheme.inkMuted), maxLines: 1, overflow: TextOverflow.ellipsis)),
        if (hasPhoto) ...[const SizedBox(width: 6), const Icon(Icons.photo_outlined, size: 14, color: AppTheme.inkHint)],
        if (tx.memoId != null) ...[const SizedBox(width: 6), const Icon(Icons.receipt_long_outlined, size: 14, color: AppTheme.inkHint)],
      ]),
      amount: tx.amount,
      amountColor: color,
    );
  }
}
