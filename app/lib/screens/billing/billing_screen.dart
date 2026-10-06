import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/currency_formatter.dart';
import '../../core/utils/date_formatter.dart';
import '../../models/cash_memo.dart';
import '../../providers/billing_provider.dart';
import '../../widgets/common_widgets.dart';
import 'create_memo_screen.dart';
import 'memo_preview_screen.dart';

/// ক্যাশ মেমো list.
class BillingScreen extends StatelessWidget {
  const BillingScreen({super.key});

  void _create(BuildContext context) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => const CreateMemoScreen()));
  }

  @override
  Widget build(BuildContext context) {
    final billing = context.watch<BillingProvider>();
    final memos = billing.memos;
    // Day grouping is cached in the provider (invalidated on data/query change).
    final groups = billing.grouped(relativeTimeBn);

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: billing.loadMemos,
        child: CustomScrollView(slivers: [
          TabHeader(
            title: 'ক্যাশ মেমো',
            actions: [IconButton(onPressed: () => _create(context), icon: const Icon(Icons.add_rounded), tooltip: 'নতুন মেমো')],
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(AppTheme.gutter, AppTheme.s4, AppTheme.gutter, AppTheme.s8),
              child: Column(children: [
                PaperCard(
                  padding: const EdgeInsets.all(AppTheme.s16),
                  child: Row(children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('আজকের বিক্রি', style: AppTheme.label),
                        const SizedBox(height: 6),
                        FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: TakaText(billing.todaySales, size: AppTheme.amountXlSize, color: AppTheme.ink, weight: FontWeight.w700, animate: true)),
                        const SizedBox(height: 4),
                        Text('${billing.todayCount} টি মেমো', style: AppTheme.caption),
                      ]),
                    ),
                    PrimaryButton(label: 'নতুন মেমো', icon: Icons.add_rounded, expanded: false, onPressed: () => _create(context)),
                  ]),
                ),
                const SizedBox(height: 12),
                SearchField(hint: 'মেমো নং বা ক্রেতার নাম', onChanged: billing.setQuery),
              ]),
            ),
          ),
          if (billing.allMemos.isEmpty && !billing.isLoading && billing.loadedOnce)
            SliverFillRemaining(
              hasScrollBody: false,
              child: EmptyState(
                icon: Icons.receipt_long_outlined,
                title: 'এখনো কোনো মেমো নেই',
                message: 'বিক্রির সময় মেমো বানান; প্রিন্ট বা WhatsApp-এ পাঠানো যাবে।',
                actionLabel: 'মেমো বানান',
                onAction: () => _create(context),
              ),
            )
          else if (memos.isEmpty)
            const SliverFillRemaining(hasScrollBody: false, child: EmptyState(icon: Icons.search_off_rounded, title: 'পাওয়া যায়নি'))
          else
            ...groups.expand((e) => [
                  SliverPersistentHeader(
                    pinned: true,
                    delegate: StickyHeader(
                      height: 40,
                      child: Padding(
                        padding: AppTheme.pagePadding,
                        child: Text(e.label, style: AppTheme.sectionHeader),
                      ),
                    ),
                  ),
                  SliverPadding(
                    padding: AppTheme.pagePadding,
                    sliver: SliverListGroup(
                      sliver: SliverList.separated(
                        itemCount: e.memos.length,
                        separatorBuilder: (_, _) => const AppDivider(),
                        itemBuilder: (_, i) => _MemoTile(memo: e.memos[i]),
                      ),
                    ),
                  ),
                  const SliverToBoxAdapter(child: SizedBox(height: AppTheme.s12)),
                ]),
          const SliverToBoxAdapter(child: SizedBox(height: 110)),
        ]),
      ),
    );
  }
}

class _MemoTile extends StatelessWidget {
  final CashMemo memo;
  const _MemoTile({required this.memo});

  @override
  Widget build(BuildContext context) {
    final paid = memo.isFullyPaid;
    return AppListRow(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => MemoPreviewScreen(memo: memo))),
      leading: const TintedIcon(Icons.receipt_long_outlined),
      title: memo.customerName,
      subtitle: '${memo.memoNumber}  ·  ${memo.items.length} টি পণ্য  ·  ${AppDateFormatter.formatShort(memo.date)}',
      amount: memo.grandTotal,
      trailingLabel: paid ? 'পরিশোধিত' : 'বাকি ${CurrencyFormatter.format(memo.dueAmount)}',
      trailingLabelColor: paid ? AppTheme.emerald : AppTheme.coral,
    );
  }
}
