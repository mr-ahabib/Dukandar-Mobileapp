import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/database/app_database.dart' show MonthFlow;
import '../../core/theme/app_theme.dart';
import '../../core/utils/currency_formatter.dart';
import '../../providers/cash_drawer_provider.dart';
import '../../providers/ledger_provider.dart';
import '../../providers/reports_provider.dart';
import '../../providers/shop_settings_provider.dart';
import '../../widgets/common_widgets.dart';

/// রিপোর্ট – 30-day sales bars, 6-month collections vs credit, expense pie.
class ReportsScreen extends StatelessWidget {
  const ReportsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(value: ReportsProvider.instance, child: const _ReportsBody());
  }
}

class _ReportsBody extends StatefulWidget {
  const _ReportsBody();
  @override
  State<_ReportsBody> createState() => _ReportsBodyState();
}

class _ReportsBodyState extends State<_ReportsBody> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => ReportsProvider.instance.load());
  }

  Future<void> _pickMonth(ReportsProvider r) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: r.selectedMonth,
      firstDate: DateTime(now.year - 2, 1),
      lastDate: now,
      initialEntryMode: DatePickerEntryMode.calendarOnly,
      helpText: 'মাস বাছুন (যেকোনো তারিখ)',
    );
    if (picked != null) r.setMonth(picked);
  }

  @override
  Widget build(BuildContext context) {
    final r = context.watch<ReportsProvider>();
    final ledger = context.watch<LedgerProvider>();
    final flow = r.selectedFlow;

    return Scaffold(
      appBar: AppBar(
        title: const Text('রিপোর্ট'),
        actions: [
          IconButton(
            tooltip: 'মাসিক PDF',
            onPressed: () {
              final shop = context.read<ShopSettingsProvider>();
              r.shareMonthlyPdf(branding: shop.pdfBranding, receivables: ledger.totalReceivables, payables: ledger.totalPayables);
            },
            icon: const Icon(Icons.ios_share_rounded),
          ),
        ],
      ),
      body: r.isLoading && !r.loadedOnce
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: r.load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(AppTheme.gutter, AppTheme.s4, AppTheme.gutter, 40),
                children: [
                  // Month picker chip row
                  Row(children: [
                    IconButton(
                      onPressed: () => r.setMonth(DateTime(r.selectedMonth.year, r.selectedMonth.month - 1)),
                      icon: const Icon(Icons.chevron_left_rounded),
                    ),
                    Expanded(
                      child: PressScale(
                        onTap: () => _pickMonth(r),
                        child: Container(
                          height: 40,
                          decoration: BoxDecoration(color: AppTheme.paper, borderRadius: BorderRadius.circular(AppTheme.radiusMd), border: Border.all(color: AppTheme.hairline)),
                          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                            const Icon(Icons.calendar_month_outlined, size: 18, color: AppTheme.inkMuted),
                            const SizedBox(width: 8),
                            Flexible(child: Text(ReportsProvider.monthLabel(r.selectedMonth), style: AppTheme.bodyStrong, maxLines: 1, overflow: TextOverflow.ellipsis)),
                          ]),
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: DateTime(r.selectedMonth.year, r.selectedMonth.month + 1).isAfter(DateTime.now())
                          ? null
                          : () => r.setMonth(DateTime(r.selectedMonth.year, r.selectedMonth.month + 1)),
                      icon: const Icon(Icons.chevron_right_rounded),
                    ),
                  ]),
                  const SizedBox(height: 12),
                  // Month summary tiles
                  // 2×2 on phones, one row of 4 on tablets.
                  LayoutBuilder(builder: (ctx, c) {
                    final tiles = [
                      StatCard(label: 'বিক্রি', amount: flow?.sales ?? 0, icon: Icons.receipt_long_rounded, color: AppTheme.indigo, compact: true),
                      StatCard(label: 'বাকি আদায়', amount: flow?.collected ?? 0, icon: Icons.south_west_rounded, color: AppTheme.emerald, compact: true),
                      StatCard(label: 'নতুন বাকি', amount: flow?.credited ?? 0, icon: Icons.north_east_rounded, color: AppTheme.coral, compact: true),
                      StatCard(label: 'খরচ', amount: flow?.expenses ?? 0, icon: Icons.savings_rounded, color: AppTheme.coral, compact: true),
                    ];
                    final cols = c.maxWidth >= AppTheme.tabletWidth ? 4 : 2;
                    final w = (c.maxWidth - AppTheme.s8 * (cols - 1)) / cols;
                    return Wrap(spacing: AppTheme.s8, runSpacing: AppTheme.s8, children: [for (final t in tiles) SizedBox(width: w, child: t)]);
                  }),

                  // 30 day sales
                  const SectionHeader(title: 'শেষ ৩০ দিনের বিক্রি', padding: EdgeInsets.fromLTRB(0, AppTheme.s24, 0, AppTheme.s8)),
                  PaperCard(
                    padding: const EdgeInsets.fromLTRB(AppTheme.s12, AppTheme.s16, AppTheme.s16, AppTheme.s12),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Padding(
                        padding: const EdgeInsets.only(left: 6),
                        child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                          Flexible(child: FittedBox(fit: BoxFit.scaleDown, child: TakaText(r.last30Sales, size: AppTheme.amountLgSize, color: AppTheme.ink))),
                          const SizedBox(width: 8),
                          Padding(padding: const EdgeInsets.only(bottom: 3), child: Text('মোট', style: AppTheme.caption)),
                        ]),
                      ),
                      const SizedBox(height: 14),
                      SizedBox(height: 170, child: RepaintBoundary(child: _SalesBars(data: r))),
                    ]),
                  ),

                  // Collections vs credit
                  const SectionHeader(title: 'আদায় বনাম নতুন বাকি (৬ মাস)', padding: EdgeInsets.fromLTRB(0, AppTheme.s24, 0, AppTheme.s8)),
                  PaperCard(
                    padding: const EdgeInsets.fromLTRB(AppTheme.s8, AppTheme.s16, AppTheme.s16, AppTheme.s12),
                    child: Column(children: [
                      Row(mainAxisAlignment: MainAxisAlignment.end, children: const [
                        _Legend(color: AppTheme.emerald, label: 'আদায়'),
                        SizedBox(width: 14),
                        _Legend(color: AppTheme.coral, label: 'নতুন বাকি'),
                      ]),
                      const SizedBox(height: 10),
                      SizedBox(height: 190, child: RepaintBoundary(child: _FlowLines(flows: r.monthlyFlows))),
                    ]),
                  ),

                  // Expense pie
                  const SectionHeader(title: 'খরচের খাত', padding: EdgeInsets.fromLTRB(0, AppTheme.s24, 0, AppTheme.s8)),
                  PaperCard(
                    padding: const EdgeInsets.all(AppTheme.s16),
                    child: r.expensesByCategory.isEmpty
                        ? Padding(
                            padding: const EdgeInsets.symmetric(vertical: 20),
                            child: Center(child: Text('এই মাসে খরচ লেখা হয়নি', style: AppTheme.caption)),
                          )
                        : _ExpensePie(data: r.expensesByCategory, total: r.selectedMonthExpenses),
                  ),
                ],
              ),
            ),
    );
  }
}

class _Legend extends StatelessWidget {
  final Color color;
  final String label;
  const _Legend({required this.color, required this.label});
  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text(label, style: AppTheme.caption),
      ]);
}

class _SalesBars extends StatelessWidget {
  final ReportsProvider data;
  const _SalesBars({required this.data});

  @override
  Widget build(BuildContext context) {
    final days = data.dailySales;
    if (days.isEmpty) return const SizedBox.shrink();
    final maxY = days.fold<double>(0, (m, d) => d.amount > m ? d.amount : m);
    final top = maxY <= 0 ? 100.0 : maxY * 1.2;
    return BarChart(
      BarChartData(
        maxY: top,
        minY: 0,
        alignment: BarChartAlignment.spaceBetween,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: top / 4,
          getDrawingHorizontalLine: (_) => const FlLine(color: AppTheme.hairline, strokeWidth: 1),
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 22,
              getTitlesWidget: (v, meta) {
                final i = v.toInt();
                if (i < 0 || i >= days.length || i % 7 != 0 && i != days.length - 1) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text('${days[i].day.day}/${days[i].day.month}', style: AppTheme.label),
                );
              },
            ),
          ),
        ),
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipColor: (_) => AppTheme.ink,
            getTooltipItem: (g, gi, rod, ri) => BarTooltipItem(
              '${days[g.x].day.day}/${days[g.x].day.month}\n${CurrencyFormatter.format(rod.toY)}',
              AppTheme.label.copyWith(color: Colors.white),
            ),
          ),
        ),
        barGroups: [
          for (int i = 0; i < days.length; i++)
            BarChartGroupData(x: i, barRods: [
              BarChartRodData(
                toY: days[i].amount,
                width: 6,
                borderRadius: BorderRadius.circular(3),
                color: i == days.length - 1 ? AppTheme.accentEmerald : AppTheme.indigoMid,
                backDrawRodData: BackgroundBarChartRodData(show: true, toY: top, color: AppTheme.sand),
              ),
            ]),
        ],
      ),
    );
  }
}

class _FlowLines extends StatelessWidget {
  final List<MonthFlow> flows;
  const _FlowLines({required this.flows});

  @override
  Widget build(BuildContext context) {
    if (flows.isEmpty) return const SizedBox.shrink();
    double maxY = 0;
    for (final f in flows) {
      if (f.collected > maxY) maxY = f.collected;
      if (f.credited > maxY) maxY = f.credited;
    }
    final top = maxY <= 0 ? 100.0 : maxY * 1.25;
    LineChartBarData line(List<double> ys, Color c) => LineChartBarData(
          spots: [for (int i = 0; i < ys.length; i++) FlSpot(i.toDouble(), ys[i])],
          isCurved: true,
          curveSmoothness: 0.3,
          color: c,
          barWidth: 3,
          isStrokeCapRound: true,
          dotData: FlDotData(
            show: true,
            getDotPainter: (s, p, b, i) => FlDotCirclePainter(radius: 4, color: Colors.white, strokeWidth: 2.5, strokeColor: c),
          ),
          belowBarData: BarAreaData(show: true, color: c.withValues(alpha: 0.08)),
        );
    return LineChart(
      LineChartData(
        minY: 0,
        maxY: top,
        minX: 0,
        maxX: (flows.length - 1).toDouble(),
        gridData: FlGridData(show: true, drawVerticalLine: false, horizontalInterval: top / 4, getDrawingHorizontalLine: (_) => const FlLine(color: AppTheme.hairline, strokeWidth: 1)),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 24,
              interval: 1,
              getTitlesWidget: (v, meta) {
                final i = v.toInt();
                if (i < 0 || i >= flows.length) return const SizedBox.shrink();
                return Padding(padding: const EdgeInsets.only(top: 6), child: Text(ReportsProvider.bnMonthsShort[flows[i].month.month - 1], style: AppTheme.label));
              },
            ),
          ),
        ),
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (_) => AppTheme.ink,
            getTooltipItems: (spots) => spots
                .map((s) => LineTooltipItem(CurrencyFormatter.format(s.y), AppTheme.label.copyWith(color: s.bar.color)))
                .toList(),
          ),
        ),
        lineBarsData: [
          line(flows.map((f) => f.collected).toList(), AppTheme.emerald),
          line(flows.map((f) => f.credited).toList(), AppTheme.coral),
        ],
      ),
    );
  }
}

class _ExpensePie extends StatelessWidget {
  final Map<String, double> data;
  final double total;
  const _ExpensePie({required this.data, required this.total});

  @override
  Widget build(BuildContext context) {
    final entries = data.entries.toList();
    return Column(children: [
      SizedBox(
        height: 190,
        child: Stack(alignment: Alignment.center, children: [
          PieChart(
            PieChartData(
              sectionsSpace: 3,
              centerSpaceRadius: 58,
              startDegreeOffset: -90,
              sections: entries.map((e) {
                final cat = CashDrawerProvider.categoryOf(e.key);
                return PieChartSectionData(value: e.value, color: cat.color, radius: 30, showTitle: false);
              }).toList(),
            ),
          ),
          Column(mainAxisSize: MainAxisSize.min, children: [
            Text('মোট খরচ', style: AppTheme.label),
            FittedBox(child: TakaText(total, size: AppTheme.amountMdSize, color: AppTheme.coral)),
          ]),
        ]),
      ),
      const SizedBox(height: 12),
      ...entries.map((e) {
        final cat = CashDrawerProvider.categoryOf(e.key);
        final pct = total <= 0 ? 0 : (e.value / total * 100).round();
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(children: [
            Container(width: 10, height: 10, decoration: BoxDecoration(color: cat.color, shape: BoxShape.circle)),
            const SizedBox(width: 10),
            Expanded(child: Text(e.key, style: AppTheme.bodySm, maxLines: 1, overflow: TextOverflow.ellipsis)),
            Text('$pct%', style: AppTheme.caption),
            const SizedBox(width: 12),
            Text(CurrencyFormatter.format(e.value), style: AppTheme.bodyStrong.copyWith(fontFeatures: AppTheme.tabular)),
          ]),
        );
      }),
    ]);
  }
}
