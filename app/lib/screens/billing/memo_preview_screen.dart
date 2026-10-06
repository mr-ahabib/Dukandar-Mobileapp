import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/currency_formatter.dart';
import '../../core/utils/photo_helper.dart';
import '../../core/utils/reminder_helper.dart';
import '../../models/cash_memo.dart';
import '../../providers/billing_provider.dart';
import '../../providers/cash_drawer_provider.dart';
import '../../providers/ledger_provider.dart';
import '../../providers/shop_settings_provider.dart';
import '../../widgets/common_widgets.dart';

/// Memo preview that mirrors the PDF (header band, meta block, zebra items
/// table, totals box with due highlighted) plus share / print / delete.
class MemoPreviewScreen extends StatefulWidget {
  final CashMemo memo;
  final bool justCreated;
  const MemoPreviewScreen({super.key, required this.memo, this.justCreated = false});

  @override
  State<MemoPreviewScreen> createState() => _MemoPreviewScreenState();
}

class _MemoPreviewScreenState extends State<MemoPreviewScreen> {
  CashMemo get memo => widget.memo;
  bool get justCreated => widget.justCreated;

  /// True while a PDF is being generated (fonts parsed, pages laid out).
  /// Buttons show a spinner and ignore repeat taps instead of queueing a
  /// second multi-hundred-millisecond build.
  bool _busy = false;

  Future<void> _runPdf(Future<void> Function() job) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await job();
    } catch (e) {
      if (mounted) showSnack(context, 'PDF তৈরি করা যায়নি: $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  MemoBranding _branding(ShopSettingsProvider s) => MemoBranding(
        shopName: s.shopName,
        shopPhone: s.phone,
        shopAddress: s.address,
        footer: s.memoFooter,
        logoPath: s.showMemoLogo ? s.logoPath : null,
        banglaDigits: s.useBanglaDigits,
      );

  Future<void> _delete(BuildContext context) async {
    final billing = context.read<BillingProvider>();
    final ok = await AppBottomSheet.confirm(
      context,
      title: 'মেমো মুছবেন?',
      message: memo.customerId != null && memo.dueAmount > 0
          ? 'এই মেমো মুছে যাবে এবং খাতায় লেখা বাকি ${CurrencyFormatter.format(memo.dueAmount)} ফিরিয়ে নেওয়া হবে। স্টকও ফেরত যাবে।'
          : 'এই মেমো মুছে যাবে। স্টক ফেরত যাবে।',
      confirmLabel: 'মুছুন',
      danger: true,
    );
    if (!ok || !context.mounted) return;
    await billing.deleteMemo(memo);
    if (!context.mounted) return;
    context.read<CashDrawerProvider>().onMemoDeleted(memo);
    if (memo.customerId != null) context.read<LedgerProvider>().refreshContact(memo.customerId!);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final shop = context.watch<ShopSettingsProvider>();
    final billing = context.read<BillingProvider>();
    final hasLogo = shop.showMemoLogo && PhotoHelper.exists(shop.logoPath);

    return Scaffold(
      appBar: AppBar(
        title: Text(justCreated ? 'মেমো তৈরি হয়েছে' : memo.memoNumber),
        actions: [
          IconButton(
            tooltip: 'প্রিন্ট',
            onPressed: _busy ? null : () => _runPdf(() => billing.printMemo(memo, _branding(shop))),
            icon: const Icon(Icons.print_rounded),
          ),
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'delete') _delete(context);
            },
            itemBuilder: (_) => const [PopupMenuItem(value: 'delete', child: Text('মেমো মুছুন'))],
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(AppTheme.gutter, AppTheme.s8, AppTheme.gutter, 140),
        children: [
          if (justCreated)
            const Padding(
              padding: EdgeInsets.only(bottom: AppTheme.s12),
              child: NoteBox(icon: Icons.check_circle_outline_rounded, color: AppTheme.emerald, text: 'মেমো সংরক্ষিত হয়েছে। এখন শেয়ার বা প্রিন্ট করুন।'),
            ),
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: AppTheme.sheetMaxWidth),
              child: _Receipt(memo: memo, shop: shop, hasLogo: hasLogo),
            ),
          ),
        ],
      ),
      bottomNavigationBar: BottomActionBar(
        secondary: memo.customerPhone.isEmpty
            ? null
            : TonalButton(
                label: 'WhatsApp',
                icon: Icons.chat_outlined,
                expanded: false,
                onPressed: () => ReminderHelper.sendWhatsAppReminder(
                  phoneNumber: memo.customerPhone,
                  customerName: memo.customerName,
                  dueAmount: memo.dueAmount,
                  shopName: shop.shopName,
                ),
              ),
        primary: PrimaryButton(
          label: 'PDF শেয়ার করুন',
          icon: Icons.share_outlined,
          loading: _busy,
          onPressed: () => _runPdf(() => billing.shareMemo(memo, _branding(shop))),
        ),
      ),
    );
  }
}

class _Receipt extends StatelessWidget {
  final CashMemo memo;
  final ShopSettingsProvider shop;
  final bool hasLogo;
  const _Receipt({required this.memo, required this.shop, required this.hasLogo});

  @override
  Widget build(BuildContext context) {
    final hasDue = memo.dueAmount > 0;
    return PaperCard(
      padding: const EdgeInsets.all(AppTheme.s12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        // Header band (same as PDF)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: AppTheme.s16, vertical: AppTheme.s12),
          decoration: BoxDecoration(color: AppTheme.navy, borderRadius: BorderRadius.circular(AppTheme.radiusSm)),
          child: Row(children: [
            if (hasLogo) ...[
              Container(
                width: 44,
                height: 44,
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8)),
                child: Image.file(File(shop.logoPath!), fit: BoxFit.contain),
              ),
              const SizedBox(width: AppTheme.s8),
            ],
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(shop.shopName, style: AppTheme.title.copyWith(color: Colors.white), maxLines: 1, overflow: TextOverflow.ellipsis),
                if (shop.address.isNotEmpty) Text(shop.address, style: AppTheme.caption.copyWith(color: Colors.white70), maxLines: 1, overflow: TextOverflow.ellipsis),
                if (shop.phone.isNotEmpty) Text('ফোন: ${CurrencyFormatter.digits(shop.phone)}', style: AppTheme.caption.copyWith(color: Colors.white70)),
              ]),
            ),
            const SizedBox(width: AppTheme.s8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: AppTheme.s8, vertical: AppTheme.s4),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(6)),
              child: Text('ক্যাশ মেমো', style: AppTheme.label.copyWith(color: AppTheme.navy)),
            ),
          ]),
        ),
        const SizedBox(height: AppTheme.s8),
        // Meta block
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: _MetaBox(title: 'ক্রেতা', children: [
              Text(memo.customerName, style: AppTheme.bodyStrong, maxLines: 2, overflow: TextOverflow.ellipsis),
              if (memo.customerPhone.isNotEmpty) Text(CurrencyFormatter.digits(memo.customerPhone), style: AppTheme.caption),
            ]),
          ),
          const SizedBox(width: AppTheme.s8),
          Expanded(
            child: _MetaBox(title: 'মেমো', children: [
              _kv('নং', CurrencyFormatter.digits(memo.memoNumber)),
              _kv('তারিখ', CurrencyFormatter.digits('${memo.date.day.toString().padLeft(2, '0')}/${memo.date.month.toString().padLeft(2, '0')}/${memo.date.year}')),
              _kv('অবস্থা', hasDue ? 'বাকি আছে' : 'পরিশোধিত', color: hasDue ? AppTheme.coral : AppTheme.emerald),
            ]),
          ),
        ]),
        const SizedBox(height: AppTheme.s8),
        // Items table with zebra rows
        ClipRRect(
          borderRadius: BorderRadius.circular(AppTheme.radiusSm),
          child: Column(children: [
            Container(
              color: AppTheme.sand,
              padding: const EdgeInsets.symmetric(horizontal: AppTheme.s8, vertical: 6),
              child: Row(children: [
                SizedBox(width: 22, child: Text('#', style: AppTheme.label)),
                Expanded(flex: 5, child: Text('পণ্য', style: AppTheme.label)),
                Expanded(flex: 2, child: Text('পরিমাণ', style: AppTheme.label, textAlign: TextAlign.right)),
                Expanded(flex: 2, child: Text('দর', style: AppTheme.label, textAlign: TextAlign.right)),
                Expanded(flex: 3, child: Text('মোট', style: AppTheme.label, textAlign: TextAlign.right)),
              ]),
            ),
            for (int i = 0; i < memo.items.length; i++)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: AppTheme.s8, vertical: 7),
                decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppTheme.hairline))),
                child: Row(children: [
                  SizedBox(width: 22, child: Text(CurrencyFormatter.digits('${i + 1}'), style: AppTheme.caption)),
                  Expanded(flex: 5, child: Text(memo.items[i].name, style: AppTheme.bodySm, maxLines: 2, overflow: TextOverflow.ellipsis)),
                  Expanded(flex: 2, child: Text(CurrencyFormatter.number(memo.items[i].quantity), style: AppTheme.bodySm, textAlign: TextAlign.right)),
                  Expanded(flex: 2, child: Text(CurrencyFormatter.format(memo.items[i].unitPrice, includeSymbol: false), style: AppTheme.bodySm, textAlign: TextAlign.right)),
                  Expanded(flex: 3, child: Text(CurrencyFormatter.format(memo.items[i].total, includeSymbol: false), style: AppTheme.bodySmStrong, textAlign: TextAlign.right)),
                ]),
              ),
          ]),
        ),
        const SizedBox(height: AppTheme.s8),
        // Totals box
        Align(
          alignment: Alignment.centerRight,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 260),
            child: Container(
              decoration: BoxDecoration(border: Border.all(color: AppTheme.hairline), borderRadius: BorderRadius.circular(AppTheme.radiusSm)),
              clipBehavior: Clip.antiAlias,
              child: Column(children: [
                _TotalLine('উপমোট', CurrencyFormatter.format(memo.subtotal)),
                if (memo.discount > 0) _TotalLine('ডিসকাউন্ট', '− ${CurrencyFormatter.format(memo.discount)}'),
                _TotalLine('সর্বমোট', CurrencyFormatter.format(memo.grandTotal), strong: true),
                _TotalLine('নগদ জমা', CurrencyFormatter.format(memo.cashReceived), color: AppTheme.emerald),
                if (memo.changeAmount > 0) _TotalLine('ফেরত', CurrencyFormatter.format(memo.changeAmount)),
                _TotalLine(
                  hasDue ? 'বাকি' : 'বাকি নেই',
                  CurrencyFormatter.format(memo.dueAmount),
                  strong: true,
                  highlight: true,
                  color: hasDue ? AppTheme.coral : AppTheme.emerald,
                ),
              ]),
            ),
          ),
        ),
        const SizedBox(height: AppTheme.s12),
        const Divider(),
        const SizedBox(height: AppTheme.s8),
        Text(shop.memoFooter.isEmpty ? 'ধন্যবাদ! আবার আসবেন।' : shop.memoFooter, textAlign: TextAlign.center, style: AppTheme.caption),
      ]),
    );
  }

  Widget _kv(String k, String v, {Color? color}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 1),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 44, child: Text(k, style: AppTheme.caption)),
          Expanded(child: Text(v, style: AppTheme.bodySmStrong.copyWith(color: color), maxLines: 1, overflow: TextOverflow.ellipsis)),
        ]),
      );
}

class _MetaBox extends StatelessWidget {
  final String title;
  final List<Widget> children;
  const _MetaBox({required this.title, required this.children});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppTheme.s12, vertical: AppTheme.s8),
      decoration: BoxDecoration(color: AppTheme.sand, borderRadius: BorderRadius.circular(AppTheme.radiusSm)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: AppTheme.label),
        const SizedBox(height: AppTheme.s4),
        ...children,
      ]),
    );
  }
}

class _TotalLine extends StatelessWidget {
  final String label;
  final String value;
  final bool strong;
  final bool highlight;
  final Color? color;
  const _TotalLine(this.label, this.value, {this.strong = false, this.highlight = false, this.color});
  @override
  Widget build(BuildContext context) {
    final bg = highlight ? (color == AppTheme.coral ? AppTheme.coralSoft : AppTheme.emeraldSoft) : (strong ? AppTheme.sand : AppTheme.paper);
    return Container(
      color: bg,
      padding: EdgeInsets.symmetric(horizontal: AppTheme.s12, vertical: strong ? AppTheme.s8 : 5),
      child: Row(children: [
        Expanded(child: Text(label, style: strong ? AppTheme.bodySmStrong : AppTheme.bodySm.copyWith(color: AppTheme.inkMuted))),
        Text(value, style: (strong ? AppTheme.amountSm : AppTheme.bodySm).copyWith(color: color ?? AppTheme.ink, fontFeatures: AppTheme.tabular)),
      ]),
    );
  }
}
