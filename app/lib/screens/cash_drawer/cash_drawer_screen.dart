import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/currency_formatter.dart';
import '../../core/utils/date_formatter.dart';
import '../../models/daily_expense.dart';
import '../../providers/cash_drawer_provider.dart';
import '../../core/utils/voice_parser.dart';
import '../../widgets/common_widgets.dart';
import '../../widgets/voice_sheet.dart';
import '../billing/memo_preview_screen.dart';

/// ক্যাশ বাক্স – day summary + expenses.
class CashDrawerScreen extends StatelessWidget {
  const CashDrawerScreen({super.key});

  static Future<void> showAddExpense(BuildContext context) =>
      AppBottomSheet.show(context, title: 'খরচ লিখুন', child: const ExpenseFormSheet());

  @override
  Widget build(BuildContext context) {
    final cash = context.watch<CashDrawerProvider>();
    final day = cash.selectedDay;

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: cash.loadExpenses,
        child: CustomScrollView(slivers: [
          TabHeader(
            title: 'ক্যাশ বাক্স',
            actions: [
              IconButton(
                tooltip: 'তারিখ বাছুন',
                onPressed: () async {
                  final picked = await showDatePicker(context: context, initialDate: day, firstDate: DateTime(2020), lastDate: DateTime.now());
                  if (picked != null) cash.setDay(picked);
                },
                icon: const Icon(Icons.calendar_month_rounded),
              ),
            ],
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(AppTheme.gutter, AppTheme.s4, AppTheme.gutter, 0),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                // Day switcher
                Row(children: [
                  _DayBtn(icon: Icons.chevron_left_rounded, onTap: () => cash.setDay(day.subtract(const Duration(days: 1)))),
                  Expanded(
                    child: Center(
                      child: Column(children: [
                        Text(cash.isToday ? 'আজ' : relativeTimeBn(day), style: AppTheme.bodyStrong),
                        Text(AppDateFormatter.formatDateOnly(day), style: AppTheme.caption),
                      ]),
                    ),
                  ),
                  _DayBtn(icon: Icons.chevron_right_rounded, onTap: cash.isToday ? null : () => cash.setDay(day.add(const Duration(days: 1)))),
                ]),
                const SizedBox(height: 12),
                // Hero: net cash
                RepaintBoundary(
                  child: PaperCard(
                    padding: const EdgeInsets.all(AppTheme.s16),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(cash.isToday ? 'আজকের নগদ' : 'ঐ দিনের নগদ', style: AppTheme.label),
                      const SizedBox(height: AppTheme.s8),
                      FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: TakaText(cash.netCash, size: AppTheme.amountXlSize, color: cash.netCash < 0 ? AppTheme.coral : AppTheme.ink, weight: FontWeight.w700, animate: true)),
                      const SizedBox(height: 4),
                      Text('নগদ বিক্রি + বাকি আদায় − খরচ − মহাজনকে দেওয়া', style: AppTheme.caption, maxLines: 2),
                      const SizedBox(height: 14),
                      const Divider(),
                      const SizedBox(height: 12),
                      Row(children: [
                        _HeroStat(label: 'নগদ বিক্রি', value: cash.cashSales, color: AppTheme.indigo),
                        _HeroStat(label: 'বাকি আদায়', value: cash.collections, color: AppTheme.emerald),
                        _HeroStat(label: 'খরচ', value: cash.totalExpense, color: AppTheme.coral),
                        if (cash.supplierPayments > 0) _HeroStat(label: 'মহাজনকে', value: cash.supplierPayments, color: AppTheme.coral),
                      ]),
                    ]),
                  ),
                ),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(child: StatCard(label: 'মোট বিক্রি', amount: cash.totalSales, icon: Icons.receipt_long_rounded, color: AppTheme.indigo, compact: true, sublabel: '${cash.memos.length} টি মেমো')),
                  const SizedBox(width: AppTheme.s8),
                  Expanded(child: StatCard(label: 'বাকিতে বিক্রি', amount: cash.creditSales, icon: Icons.hourglass_bottom_rounded, color: AppTheme.coral, compact: true)),
                ]),
              ]),
            ),
          ),
          SliverToBoxAdapter(
            child: SectionHeader(
              title: 'খরচের তালিকা',
              actionLabel: 'খরচ লিখুন',
              onAction: () => showAddExpense(context),
            ),
          ),
          if (cash.expenses.isEmpty)
            const SliverToBoxAdapter(
              child: EmptyState(
                icon: Icons.savings_outlined,
                title: 'কোনো খরচ লেখা হয়নি',
                message: 'ছোট খরচও লিখে রাখুন; মাস শেষে হিসাব মিলবে।',
              ),
            )
          else
            SliverPadding(
              padding: AppTheme.pagePadding,
              sliver: SliverListGroup(
                sliver: SliverList.separated(
                  itemCount: cash.expenses.length,
                  separatorBuilder: (_, _) => const AppDivider(),
                  itemBuilder: (_, i) => _ExpenseTile(expense: cash.expenses[i]),
                ),
              ),
            ),
          if (cash.memos.isNotEmpty) ...[
            const SliverToBoxAdapter(child: SectionHeader(title: 'ঐ দিনের মেমো')),
            SliverPadding(
              padding: AppTheme.pagePadding,
              sliver: SliverListGroup(
                sliver: SliverList.separated(
                  itemCount: cash.memos.length,
                  separatorBuilder: (_, _) => const AppDivider(),
                  itemBuilder: (_, i) {
                    final m = cash.memos[i];
                    return AppListRow(
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => MemoPreviewScreen(memo: m))),
                      leading: const TintedIcon(Icons.receipt_long_outlined),
                      title: m.customerName,
                      subtitle: '${m.memoNumber}  ·  নগদ ${CurrencyFormatter.format(m.cashReceived)}${m.dueAmount > 0 ? '  ·  বাকি ${CurrencyFormatter.format(m.dueAmount)}' : ''}',
                      amount: m.grandTotal,
                    );
                  },
                ),
              ),
            ),
          ],
          const SliverToBoxAdapter(child: SizedBox(height: 130)),
        ]),
      ),
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 84),
        child: FloatingActionButton.extended(
          onPressed: () => showAddExpense(context),
          icon: const Icon(Icons.add_rounded),
          label: const Text('খরচ লিখুন'),
        ),
      ),
    );
  }
}

class _DayBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  const _DayBtn({required this.icon, this.onTap});
  @override
  Widget build(BuildContext context) {
    return Material(
      color: onTap == null ? AppTheme.sand.withValues(alpha: 0.5) : AppTheme.paper,
      shape: const CircleBorder(side: BorderSide(color: AppTheme.hairline)),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(width: 48, height: 48, child: Icon(icon, color: onTap == null ? AppTheme.inkHint : AppTheme.ink)),
      ),
    );
  }
}

class _HeroStat extends StatelessWidget {
  final String label;
  final double value;
  final Color color;
  const _HeroStat({required this.label, required this.value, required this.color});
  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: AppTheme.label, maxLines: 1, overflow: TextOverflow.ellipsis),
        const SizedBox(height: 3),
        FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: TakaText(value, size: AppTheme.amountSmSize, color: color)),
      ]),
    );
  }
}

class _ExpenseTile extends StatelessWidget {
  final DailyExpense expense;
  const _ExpenseTile({required this.expense});

  @override
  Widget build(BuildContext context) {
    final cat = CashDrawerProvider.categoryOf(expense.category);
    return AppListRow(
      onLongPress: () async {
        final ok = await AppBottomSheet.confirm(context, title: 'খরচ মুছবেন?', message: '${expense.title} — ${CurrencyFormatter.format(expense.amount)}', confirmLabel: 'মুছুন', danger: true);
        if (ok && context.mounted) context.read<CashDrawerProvider>().deleteExpense(expense.id);
      },
      leading: TintedIcon(cat.icon, color: cat.color),
      title: expense.title,
      subtitle: '${expense.category}  ·  ${AppDateFormatter.formatShort(expense.date)}',
      amount: expense.amount,
      amountColor: AppTheme.coral,
    );
  }
}

/// Expense entry sheet with category icon chips and quick amounts.
class ExpenseFormSheet extends StatefulWidget {
  final String? voiceText;
  const ExpenseFormSheet({super.key, this.voiceText});
  @override
  State<ExpenseFormSheet> createState() => _ExpenseFormSheetState();
}

class _ExpenseFormSheetState extends State<ExpenseFormSheet> {
  final _amount = TextEditingController();
  final _title = TextEditingController();
  String _category = CashDrawerProvider.categories.first.name;
  DateTime _date = DateTime.now();
  bool _saving = false;

  @override
  void dispose() {
    _amount.dispose();
    _title.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    if (widget.voiceText != null) _applyVoice(widget.voiceText!, silent: true);
  }

  void _applyVoice(String text, {bool silent = false}) {
    final r = VoiceParser.parseExpense(text);
    setState(() {
      if (r.amount != null) _amount.text = r.amount == r.amount!.roundToDouble() ? r.amount!.toStringAsFixed(0) : r.amount.toString();
      _category = r.category;
      if (r.title.isNotEmpty && r.title != r.category) _title.text = r.title;
    });
    if (!silent) showSnack(context, 'শুনেছি: “$text” — ঠিক থাকলে সংরক্ষণ করুন');
  }

  Future<void> _save() async {
    final amount = double.tryParse(_amount.text.trim()) ?? 0;
    if (amount <= 0) return showSnack(context, 'টাকার পরিমাণ লিখুন', error: true);
    setState(() => _saving = true);
    try {
      await context.read<CashDrawerProvider>().addExpense(title: _title.text, category: _category, amount: amount, date: _date);
      if (mounted) Navigator.pop(context, true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final body = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Expanded(child: AmountField(controller: _amount, autofocus: widget.voiceText == null, color: AppTheme.coral)),
        const SizedBox(width: 10),
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: VoiceInputButton(
            size: 56,
            color: AppTheme.coral,
            title: 'খরচ বলুন',
            hint: 'যেমন: "বিদ্যুৎ বিল ৬৫০ টাকা"',
            examples: const ['বিদ্যুৎ বিল ৬৫০ টাকা', 'চা নাস্তা ১২০ টাকা', 'রিকশা ভাড়া ৫০'],
            onResult: _applyVoice,
          ),
        ),
      ]),
      const SizedBox(height: 10),
      QuickAmountChips(controller: _amount, amounts: const [20, 50, 100, 500, 1000]),
      const SizedBox(height: 16),
      Padding(padding: const EdgeInsets.only(left: 2, bottom: 8), child: Text('খরচের খাত', style: AppTheme.sectionHeader)),
      GridView.count(
        // 3 / 4 / 5 columns by width; category tiles are small.
        crossAxisCount: AppTheme.gridColumns(MediaQuery.sizeOf(context).width) + 1,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: AppTheme.s8,
        crossAxisSpacing: AppTheme.s8,
        childAspectRatio: 0.95,
        children: CashDrawerProvider.categories.map((c) {
          final sel = c.name == _category;
          return PressScale(
            onTap: () => setState(() => _category = c.name),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              decoration: BoxDecoration(
                color: sel ? AppTheme.indigoSoft : AppTheme.paper,
                borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                border: Border.all(color: sel ? AppTheme.indigo : AppTheme.hairline, width: sel ? 1.5 : 1),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(c.icon, color: sel ? AppTheme.indigo : AppTheme.inkMuted, size: 22),
                const SizedBox(height: 6),
                Text(c.name,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.label.copyWith(color: sel ? AppTheme.indigo : AppTheme.ink)),
              ]),
            ),
          );
        }).toList(),
      ),
      const SizedBox(height: 16),
      AppTextField(controller: _title, label: 'বিবরণ (ঐচ্ছিক)', hint: 'যেমন: দুপুরের নাস্তা', icon: Icons.edit_note_rounded),
      const SizedBox(height: 12),
      Row(children: [DateChip(date: _date, onChanged: (d) => setState(() => _date = d))]),
    ]);
    return SheetForm(
      body: body,
      bar: BottomActionBar(primary: PrimaryButton(label: 'খরচ সংরক্ষণ', loading: _saving, onPressed: _save)),
    );
  }
}
