import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../core/backup/backup_service.dart';
import '../core/payment/payment_popup_controller.dart';
import '../core/app_bootstrap.dart';
import '../core/database/app_database.dart';
import '../core/utils/perf.dart';
import '../core/utils/photo_helper.dart';
import '../core/theme/app_theme.dart';
import '../core/utils/voice_parser.dart';
import '../models/customer.dart';
import '../models/transaction_item.dart';
import '../providers/billing_provider.dart';
import '../providers/cash_drawer_provider.dart';
import '../providers/ledger_provider.dart';
import '../providers/products_provider.dart';
import '../providers/reports_provider.dart';
import '../widgets/common_widgets.dart';
import '../widgets/voice_sheet.dart';
import 'billing/billing_screen.dart';
import 'billing/create_memo_screen.dart';
import 'cash_drawer/cash_drawer_screen.dart';
import 'home/home_dashboard_screen.dart';
import 'ledger/add_customer_dialog.dart';
import 'ledger/ledger_screen.dart';
import 'ledger/record_transaction_dialog.dart';
import 'settings/shop_settings_screen.dart';

class HomeNavigationScreen extends StatefulWidget {
  const HomeNavigationScreen({super.key});

  @override
  State<HomeNavigationScreen> createState() => _HomeNavigationScreenState();
}

class _HomeNavigationScreenState extends State<HomeNavigationScreen> {
  int _index = 0;

  @override
  void initState() {
    super.initState();
    // Backup/restore hooks: close the sqflite handle before the file is
    // replaced, then reopen (runs migrations) and reload every provider.
    BackupService.onBeforeBackup = () => AppDatabase.instance.checkpoint();
    BackupService.onBeforeRestore = () => AppDatabase.instance.close();
    BackupService.onAfterRestore = () async {
      await AppDatabase.instance.reopen();
      PhotoHelper.invalidate();
      if (!mounted) return;
      await Future.wait([
        context.read<LedgerProvider>().loadData(),
        context.read<BillingProvider>().loadMemos(),
        context.read<CashDrawerProvider>().loadExpenses(),
        ProductsProvider.instance.load(),
        ReportsProvider.instance.load(),
      ]);
    };
    // Data loads start only after the first frame has been painted; the
    // screens render their empty/skeleton state instantly meanwhile.
    final ledger = context.read<LedgerProvider>();
    final billing = context.read<BillingProvider>();
    final cash = context.read<CashDrawerProvider>();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Perf.mark('first-frame');
      AppBootstrap.run(ledger: ledger, billing: billing, cash: cash);
    });
    // Fee-due popup + notification-tap routing (no-op in demo mode).
    PaymentPopupController.instance.attach(context);
  }

  static const _tabs = [
    _Tab('হোম', Icons.home_outlined, Icons.home_rounded),
    _Tab('খাতা', Icons.menu_book_outlined, Icons.menu_book_rounded),
    _Tab('', Icons.add, Icons.add), // center action placeholder
    _Tab('মেমো', Icons.receipt_long_outlined, Icons.receipt_long_rounded),
    _Tab('আরও', Icons.grid_view_outlined, Icons.grid_view_rounded),
  ];

  void _go(int i) {
    if (i == _index) return;
    HapticFeedback.selectionClick();
    setState(() => _index = i);
  }

  /// Center action: new transaction / memo / expense / voice.
  Future<void> _quickAdd() async {
    HapticFeedback.mediumImpact();
    await AppBottomSheet.show(
      context,
      title: 'নতুন লেনদেন',
      scrollable: false,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          Expanded(child: _QuickTile(icon: Icons.mic_rounded, label: 'মুখে বলুন', color: AppTheme.indigo, onTap: () {
            Navigator.pop(context);
            _voiceLedger();
          })),
          const SizedBox(width: 10),
          Expanded(child: _QuickTile(icon: Icons.receipt_long_rounded, label: 'মেমো বানান', color: AppTheme.indigoMid, onTap: () {
            Navigator.pop(context);
            Navigator.push(context, MaterialPageRoute(builder: (_) => const CreateMemoScreen()));
          })),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: _QuickTile(icon: Icons.person_add_alt_1_rounded, label: 'খরিদ্দার যোগ', color: AppTheme.emerald, onTap: () {
            Navigator.pop(context);
            CustomerFormSheet.show(context);
          })),
          const SizedBox(width: 10),
          Expanded(child: _QuickTile(icon: Icons.savings_rounded, label: 'খরচ লিখুন', color: AppTheme.coral, onTap: () {
            Navigator.pop(context);
            CashDrawerScreen.showAddExpense(context);
          })),
        ]),
      ]),
    );
  }

  /// "কামালকে ৫০০ টাকা বাকি দিলাম" → find customer → prefilled sheet (confirm before save).
  Future<void> _voiceLedger() async {
    final text = await VoiceSheet.listen(
      context,
      title: 'লেনদেন বলুন',
      hint: 'যেমন: "কামালকে ৫০০ টাকা বাকি দিলাম"',
      examples: const ['কামালকে ৫০০ টাকা বাকি দিলাম', 'রহিম ২০০ টাকা জমা দিলো', 'বিদ্যুৎ বিল ৬৫০ টাকা খরচ'],
    );
    if (text == null || !mounted) return;
    final lower = text.toLowerCase();
    if (lower.contains('খরচ') || lower.contains('বিল') || lower.contains('ভাড়া')) {
      await AppBottomSheet.show(context, title: 'খরচ লিখুন', child: ExpenseFormSheet(voiceText: text));
      return;
    }
    final r = VoiceParser.parseLedger(text);
    final ledger = context.read<LedgerProvider>();
    Customer? match;
    if (r.customerName != null) {
      final q = r.customerName!.toLowerCase();
      final all = [...ledger.allCustomersRaw, ...ledger.allSuppliersRaw];
      match = all.where((c) => c.name.toLowerCase().contains(q) || q.contains(c.name.toLowerCase().split(' ').first)).firstOrNull;
    }
    if (match == null) {
      // Let the user pick / create the customer, then prefill.
      final picked = await AppBottomSheet.show<Customer>(
        context,
        title: r.customerName == null ? 'কার লেনদেন?' : '“${r.customerName}” পাওয়া যায়নি — কে?',
        child: _PickCustomer(customers: ledger.allCustomersRaw, suggestedName: r.customerName),
      );
      if (picked == null || !mounted) return;
      match = picked;
    }
    if (!mounted) return;
    await RecordTransactionSheet.show(
      context,
      customer: match,
      type: r.intent == VoiceIntent.got ? TransactionType.got : TransactionType.gave,
      initialAmount: r.amount,
      initialNote: r.note.isEmpty ? null : r.note,
    );
  }

  @override
  Widget build(BuildContext context) {
    final screens = [
      HomeDashboardScreen(onGoToTab: (i) => _go(i)),
      const LedgerScreen(),
      const SizedBox.shrink(),
      const BillingScreen(),
      const ShopSettingsScreen(),
    ];
    return Scaffold(
      extendBody: true,
      body: Stack(children: [
        IndexedStack(index: _index, children: screens),
        // Soft fade under the status bar so scrolling content melts into the edge.
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: IgnorePointer(
            child: Container(
              height: MediaQuery.of(context).padding.top + 18,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0x55000000), Color(0x00000000)],
                ),
              ),
            ),
          ),
        ),
      ]),
      bottomNavigationBar: _FloatingNavBar(
        tabs: _tabs,
        index: _index,
        onTap: _go,
        onCenter: _quickAdd,
      ),
    );
  }
}

class _Tab {
  final String label;
  final IconData icon;
  final IconData activeIcon;
  const _Tab(this.label, this.icon, this.activeIcon);
}

/// Floating bottom bar, symmetric: two oval tabs, a centre circle that sits
/// half inside the bar (the bar's outline bulges up around it), two oval tabs.
/// Sits low on the safe area; content fades behind it; scales to tablets.
class _FloatingNavBar extends StatelessWidget {
  final List<_Tab> tabs;
  final int index;
  final ValueChanged<int> onTap;
  final VoidCallback onCenter;
  const _FloatingNavBar({required this.tabs, required this.index, required this.onTap, required this.onCenter});

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final bottomInset = mq.padding.bottom;
    final width = mq.size.width;
    final compact = width < 360;
    final barWidth = width >= 640 ? 560.0 : width - 24;
    final barHeight = compact ? 60.0 : 64.0;
    final gap = bottomInset > 0 ? 4.0 : 10.0;
    const inset = 3.0; // pill hugs the bar edge
    final fabSize = compact ? 56.0 : 62.0;
    const notchGap = 3.0; // tight gap between the button and the bar's curved edge
    final fabCenterFromTop = fabSize * 0.12; // button centre sits just below the bar's top edge
    final notchRadius = fabSize / 2 + notchGap;
    final lift = fabSize / 2 - fabCenterFromTop; // how far the button rises above the bar

    return MediaQuery(
      data: mq.copyWith(textScaler: TextScaler.linear(mq.textScaler.scale(1).clamp(0.9, 1.15))),
      child: Container(
        height: lift + 16 + barHeight + bottomInset + gap,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0x00F7FAF8), Color(0xCCF7FAF8), Color(0xFFF7FAF8)],
            stops: [0.0, 0.45, 1.0],
          ),
        ),
        padding: EdgeInsets.only(bottom: bottomInset + gap),
        child: Align(
          alignment: Alignment.bottomCenter,
          child: SizedBox(
            width: barWidth,
            height: barHeight + lift,
            child: Stack(clipBehavior: Clip.none, children: [
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: barHeight,
                child: CustomPaint(
                  painter: _NotchBarPainter(
                    notchRadius: notchRadius,
                    notchCenterY: fabCenterFromTop,
                    cornerRadius: barHeight / 2,
                  ),
                  child: LayoutBuilder(builder: (ctx, c) {
                    final slot = c.maxWidth / tabs.length;
                    final pillW = slot - inset * 2 + 12; // slightly wider than the slot
                    final pillH = barHeight - inset * 2;
                    final radius = BorderRadius.circular(pillH / 2);
                    return Stack(children: [
                      AnimatedPositioned(
                        duration: const Duration(milliseconds: 260),
                        curve: Curves.easeOutCubic,
                        left: (slot * index + inset - 6).clamp(inset, c.maxWidth - inset - pillW),
                        top: inset,
                        child: Container(
                          width: pillW,
                          height: pillH,
                          decoration: BoxDecoration(color: AppTheme.indigoSoft, borderRadius: radius, border: Border.all(color: AppTheme.indigo.withValues(alpha: 0.28), width: 1)),
                        ),
                      ),
                      Row(
                        children: List.generate(tabs.length, (i) {
                          if (i == 2) return SizedBox(width: slot);
                          final t = tabs[i];
                          final sel = i == index;
                          return SizedBox(
                            width: slot,
                            child: Semantics(
                              button: true,
                              selected: sel,
                              label: t.label,
                              child: InkWell(
                                borderRadius: radius,
                                splashColor: AppTheme.indigoSoft,
                                highlightColor: Colors.transparent,
                                onTap: () => onTap(i),
                                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                                  AnimatedSwitcher(
                                    duration: const Duration(milliseconds: 160),
                                    transitionBuilder: (child, a) => ScaleTransition(scale: a, child: child),
                                    child: Icon(
                                      sel ? t.activeIcon : t.icon,
                                      key: ValueKey(sel),
                                      color: sel ? AppTheme.indigo : AppTheme.inkMuted,
                                      size: compact ? 21 : 23,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  AnimatedDefaultTextStyle(
                                    duration: const Duration(milliseconds: 160),
                                    style: AppTheme.label.copyWith(
                                      fontSize: compact ? 10.5 : 11.5,
                                      height: 1.1,
                                      color: sel ? AppTheme.indigo : AppTheme.inkMuted,
                                      fontWeight: sel ? FontWeight.w800 : FontWeight.w600,
                                    ),
                                    child: Text(t.label, maxLines: 1, overflow: TextOverflow.ellipsis),
                                  ),
                                ]),
                              ),
                            ),
                          );
                        }),
                      ),
                    ]);
                  }),
                ),
              ),
              // Centre button, seated inside the bulge
              Positioned(
                left: 0,
                right: 0,
                top: lift + fabCenterFromTop - fabSize / 2,
                child: Center(
                  child: Semantics(
                    button: true,
                    label: 'নতুন লেনদেন',
                    child: PressScale(
                      onTap: onCenter,
                      pressedScale: 0.93,
                      child: Container(
                        width: fabSize,
                        height: fabSize,
                        decoration: BoxDecoration(color: AppTheme.indigo, shape: BoxShape.circle, boxShadow: [BoxShadow(color: const Color(0xFF14532D).withValues(alpha: 0.28), blurRadius: 12, offset: const Offset(0, 5))]),
                        child: Icon(Icons.add_rounded, color: Colors.white, size: compact ? 28 : 31),
                      ),
                    ),
                  ),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// White pill bar with a circular notch cut into its top edge; the bar's
/// outline curves under the centre button.
class _NotchBarPainter extends CustomPainter {
  final double notchRadius;
  final double notchCenterY; // measured down from the bar's top edge
  final double cornerRadius;
  const _NotchBarPainter({required this.notchRadius, required this.notchCenterY, required this.cornerRadius});

  Path _path(Size size) {
    final bar = Path()..addRRect(RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(cornerRadius)));
    final hole = Path()..addOval(Rect.fromCircle(center: Offset(size.width / 2, notchCenterY), radius: notchRadius));
    return Path.combine(PathOperation.difference, bar, hole);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final path = _path(size);
    canvas.drawShadow(path, const Color(0xFF14532D).withValues(alpha: 0.30), 10, false);
    canvas.drawPath(path, Paint()..color = Colors.white);
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = const Color(0xFFD3DDD6),
    );
  }

  @override
  bool hitTest(Offset position) => true;

  @override
  bool shouldRepaint(_NotchBarPainter old) =>
      old.notchRadius != notchRadius || old.notchCenterY != notchCenterY || old.cornerRadius != cornerRadius;
}

class _QuickTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _QuickTile({required this.icon, required this.label, required this.color, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return PressScale(
      onTap: onTap,
      child: Container(
        height: 96,
        decoration: BoxDecoration(color: color.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(AppTheme.radiusMd)),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, color: color, size: 30),
          const SizedBox(height: 8),
          Text(label, style: AppTheme.bodyStrong.copyWith(color: color)),
        ]),
      ),
    );
  }
}

class _PickCustomer extends StatelessWidget {
  final List<Customer> customers;
  final String? suggestedName;
  const _PickCustomer({required this.customers, this.suggestedName});
  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (suggestedName != null)
        PrimaryButton(
          label: '“$suggestedName” নামে নতুন খরিদ্দার',
          icon: Icons.person_add_alt_1_rounded,
          color: AppTheme.emerald,
          onPressed: () async {
            final c = await context.read<LedgerProvider>().addContact(name: suggestedName!, phone: '', type: ContactType.customer);
            if (context.mounted) Navigator.pop(context, c);
          },
        ),
      const SizedBox(height: 10),
      ...customers.take(30).map((c) => ListTile(
            onTap: () => Navigator.pop(context, c),
            contentPadding: const EdgeInsets.symmetric(horizontal: 4),
            leading: AvatarCircle(name: c.name, photoPath: c.photoPath, size: 44),
            title: Text(c.name),
            subtitle: Text(c.phone.isEmpty ? '' : c.phone),
          )),
    ]);
  }
}
