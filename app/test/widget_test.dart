import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:dukandar/core/theme/app_theme.dart';
import 'package:dukandar/widgets/common_widgets.dart';

/// Smoke tests for the design-system widgets (the full app needs platform
/// plugins such as sqflite / secure storage, so it is not pumped here).
void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  Widget wrap(Widget child) => MaterialApp(theme: AppTheme.lightTheme, home: Scaffold(body: Center(child: child)));

  testWidgets('TakaText renders amount with ৳ sign', (tester) async {
    await tester.pumpWidget(wrap(const TakaText(1250)));
    final rich = tester.widget<RichText>(find.byType(RichText));
    expect(rich.text.toPlainText(), contains('৳'));
    expect(rich.text.toPlainText(), contains('1,250'));
  });

  testWidgets('AvatarCircle shows initials when no photo', (tester) async {
    await tester.pumpWidget(wrap(const AvatarCircle(name: 'কামাল হোসেন')));
    expect(find.text('কাহো'), findsOneWidget);
  });

  testWidgets('EmptyState shows title and CTA', (tester) async {
    var tapped = false;
    await tester.pumpWidget(wrap(EmptyState(
      icon: Icons.people_alt_rounded,
      title: 'এখনো কোনো খরিদ্দার নেই',
      actionLabel: 'খরিদ্দার যোগ করুন',
      onAction: () => tapped = true,
    )));
    expect(find.text('এখনো কোনো খরিদ্দার নেই'), findsOneWidget);
    await tester.tap(find.text('খরিদ্দার যোগ করুন'));
    expect(tapped, isTrue);
  });

  testWidgets('Segmented switches selection', (tester) async {
    String sel = 'a';
    await tester.pumpWidget(wrap(StatefulBuilder(
      builder: (ctx, set) => Segmented<String>(
        values: const ['a', 'b'],
        selected: sel,
        label: (v) => v == 'a' ? 'খরিদ্দার' : 'মহাজন',
        onChanged: (v) => set(() => sel = v),
      ),
    )));
    await tester.tap(find.text('মহাজন'));
    await tester.pumpAndSettle();
    expect(sel, 'b');
  });

  testWidgets('QuickAmountChips adds to controller', (tester) async {
    final c = TextEditingController(text: '100');
    await tester.pumpWidget(wrap(QuickAmountChips(controller: c, amounts: const [500])));
    await tester.tap(find.text('+500'));
    await tester.pump();
    expect(c.text, '600');
  });
}
