import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/currency_formatter.dart';
import '../../core/utils/voice_parser.dart';
import '../../models/cash_memo.dart';
import '../../widgets/common_widgets.dart';
import '../../widgets/voice_sheet.dart';

/// Voice → memo item. Listens with [VoiceSheet], then shows the parsed item
/// for confirmation/editing before returning a [MemoItem].
class VoiceItemModal {
  VoiceItemModal._();

  static const examples = ['১ কেজি চিনি ৮০ টাকা', 'মিনিকেট চাল ২৫ কেজি ৭০ টাকা', 'সয়াবিন তেল ৫ লিটার ১৯০ টাকা', '১০ টা ডিম ১২ টাকা করে'];

  static Future<MemoItem?> show(BuildContext context) async {
    final text = await VoiceSheet.listen(context, title: 'ভয়েসে পণ্য যোগ', hint: 'যেমন: "১ কেজি চিনি ৮০ টাকা"', examples: examples);
    if (text == null || !context.mounted) return null;
    final parsed = VoiceParser.parse(text);
    return AppBottomSheet.show<MemoItem>(context, title: 'ঠিক আছে কি?', child: _ConfirmItem(parsed: parsed));
  }
}

class _ConfirmItem extends StatefulWidget {
  final VoiceItemResult parsed;
  const _ConfirmItem({required this.parsed});
  @override
  State<_ConfirmItem> createState() => _ConfirmItemState();
}

class _ConfirmItemState extends State<_ConfirmItem> {
  late final _name = TextEditingController(text: widget.parsed.itemName);
  late final _qty = TextEditingController(text: _f(widget.parsed.quantity));
  late final _price = TextEditingController(text: widget.parsed.unitPrice == 0 ? '' : _f(widget.parsed.unitPrice));
  static String _f(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();
  double get _total => (double.tryParse(_qty.text) ?? 0) * (double.tryParse(_price.text) ?? 0);

  @override
  void dispose() {
    _name.dispose();
    _qty.dispose();
    _price.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const numType = TextInputType.numberWithOptions(decimal: true);
    final body = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      NoteBox(icon: Icons.mic_none_rounded, text: '“${widget.parsed.originalText}”'),
      const SizedBox(height: 14),
      AppTextField(controller: _name, label: 'পণ্যের নাম', icon: Icons.shopping_basket_outlined),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(child: AppTextField(controller: _qty, label: 'পরিমাণ', keyboardType: numType, onChanged: (_) => setState(() {}))),
        const SizedBox(width: 10),
        Expanded(child: AppTextField(controller: _price, label: 'দর (৳)', keyboardType: numType, onChanged: (_) => setState(() {}))),
      ]),
      const SizedBox(height: 14),
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text('মোট', style: AppTheme.body.copyWith(color: AppTheme.inkMuted)),
        Text(CurrencyFormatter.format(_total), style: AppTheme.amountLg),
      ]),
    ]);
    return SheetForm(
      body: body,
      bar: BottomActionBar(
        primary: PrimaryButton(
          label: 'মেমোতে যুক্ত করুন',
          onPressed: () {
            final q = double.tryParse(_qty.text) ?? 0;
            final p = double.tryParse(_price.text) ?? 0;
            if (_name.text.trim().isEmpty || q <= 0 || p <= 0) return showSnack(context, 'নাম, পরিমাণ ও দর ঠিক করুন', error: true);
            Navigator.pop(context, MemoItem(name: _name.text.trim(), quantity: q, unitPrice: p));
          },
        ),
      ),
    );
  }
}
