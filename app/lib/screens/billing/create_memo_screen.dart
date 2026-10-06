import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/currency_formatter.dart';
import '../../models/cash_memo.dart';
import '../../models/customer.dart';
import '../../models/product.dart';
import '../../providers/billing_provider.dart';
import '../../providers/cash_drawer_provider.dart';
import '../../providers/ledger_provider.dart';
import '../../providers/products_provider.dart';
import '../../widgets/common_widgets.dart';
import '../ledger/add_customer_dialog.dart';
import '../products/products_screen.dart';
import 'memo_preview_screen.dart';
import 'voice_item_modal.dart';

class CreateMemoScreen extends StatefulWidget {
  final Customer? customer;
  const CreateMemoScreen({super.key, this.customer});

  @override
  State<CreateMemoScreen> createState() => _CreateMemoScreenState();
}

class _CreateMemoScreenState extends State<CreateMemoScreen> {
  final List<MemoItem> _items = [];
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _discount = TextEditingController();
  final _paid = TextEditingController();
  Customer? _customer;
  bool _pushDue = true;
  bool _saving = false;

  // Same arithmetic as CashMemo / money_rules.md, computed live on the form.
  double get _subtotal => _items.fold(0.0, (s, i) => s + i.total);
  double get _discountRaw => double.tryParse(_discount.text) ?? 0;
  double get _discountV => _discountRaw.clamp(0, _subtotal).toDouble();
  bool get _discountTooBig => _discountRaw > _subtotal && _subtotal > 0;
  double get _total => (_subtotal - _discountV).clamp(0, double.infinity);
  double get _paidRaw => double.tryParse(_paid.text) ?? 0;
  double get _paidV => _paidRaw.clamp(0, _total).toDouble();
  double get _due => (_total - _paidV).clamp(0, double.infinity);
  double get _change => (_paidRaw - _total).clamp(0, double.infinity);

  @override
  void initState() {
    super.initState();
    if (widget.customer != null) _setCustomer(widget.customer!);
  }

  @override
  void dispose() {
    for (final c in [_name, _phone, _discount, _paid]) {
      c.dispose();
    }
    super.dispose();
  }

  void _setCustomer(Customer c) {
    _customer = c;
    _name.text = c.name;
    _phone.text = c.phone;
  }

  Future<void> _pickCustomer() async {
    final ledger = context.read<LedgerProvider>();
    final chosen = await AppBottomSheet.show<Customer>(
      context,
      title: 'খরিদ্দার বাছুন',
      child: _CustomerPicker(customers: ledger.allCustomersRaw),
    );
    if (chosen != null && mounted) setState(() => _setCustomer(chosen));
  }

  Future<void> _addManual() async {
    final item = await AppBottomSheet.show<MemoItem>(context, title: 'পণ্য লিখুন', child: const _ManualItemSheet());
    if (item != null) setState(() => _items.add(item));
  }

  Future<void> _addVoice() async {
    final item = await VoiceItemModal.show(context);
    if (item != null) setState(() => _items.add(item));
  }

  Future<void> _addFromProducts() async {
    final product = await ProductPickerSheet.show(context);
    if (product == null || !mounted) return;
    final item = await AppBottomSheet.show<MemoItem>(
      context,
      title: product.name,
      child: _ManualItemSheet(product: product),
    );
    if (item != null) setState(() => _items.add(item));
  }

  Future<void> _save() async {
    if (_items.isEmpty) return showSnack(context, 'অন্তত একটি পণ্য যোগ করুন', error: true);
    setState(() => _saving = true);
    try {
      final memo = await context.read<BillingProvider>().createMemo(
            customerName: _name.text,
            customerPhone: _phone.text,
            customerId: _customer?.id,
            items: List.of(_items),
            discount: _discountV,
            paidAmount: _paidV,
            pushDueToLedger: _pushDue && _customer != null,
          );
      if (!mounted) return;
      // Refresh only what changed: the one ledger contact, today's drawer,
      // and products (stock decremented in the DB layer).
      final ledger = context.read<LedgerProvider>();
      if (_customer != null && _pushDue) {
        ledger.refreshContact(_customer!.id);
      }
      context.read<CashDrawerProvider>().onMemoCreated(memo);
      // Stock was decremented inside the memo's DB transaction; mirror it in
      // memory instead of re-reading the whole products table.
      final deltas = <String, double>{};
      for (final i in _items) {
        final pid = i.productId;
        if (pid != null) deltas[pid] = (deltas[pid] ?? 0) - i.quantity;
      }
      ProductsProvider.instance.applyStockDeltas(deltas);
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => MemoPreviewScreen(memo: memo, justCreated: true)));
    } catch (e) {
      if (mounted) showSnack(context, 'ত্রুটি: $e', error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('নতুন মেমো')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(AppTheme.gutter, AppTheme.s4, AppTheme.gutter, 140),
        children: [
          // Customer
          PaperCard(
            padding: const EdgeInsets.all(AppTheme.s16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Text('ক্রেতা', style: AppTheme.sectionHeader),
                const Spacer(),
                TextButton(
                  onPressed: _pickCustomer,
                  style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8), minimumSize: const Size(0, 32), textStyle: AppTheme.bodySmStrong),
                  child: const Text('খাতা থেকে বাছুন'),
                ),
              ]),
              const SizedBox(height: 4),
              if (_customer != null)
                Row(children: [
                  AvatarCircle(name: _customer!.name, photoPath: _customer!.photoPath, size: 40),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(_customer!.name, style: AppTheme.bodyStrong, maxLines: 1, overflow: TextOverflow.ellipsis),
                      Text(
                        _customer!.currentBalance > 0
                            ? 'আগের বাকি ${CurrencyFormatter.format(_customer!.currentBalance)}'
                            : _customer!.currentBalance < 0
                                ? 'অগ্রিম জমা ${CurrencyFormatter.format(-_customer!.currentBalance)}'
                                : (_customer!.phone.isEmpty ? 'খাতার খরিদ্দার' : _customer!.phone),
                        style: AppTheme.caption.copyWith(color: _customer!.currentBalance > 0 ? AppTheme.coral : (_customer!.currentBalance < 0 ? AppTheme.emerald : null)),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ]),
                  ),
                  IconButton(
                    onPressed: () => setState(() {
                      _customer = null;
                      _name.clear();
                      _phone.clear();
                    }),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ])
              else ...[
                TextField(controller: _name, scrollPadding: const EdgeInsets.only(bottom: 120), decoration: const InputDecoration(hintText: 'ক্রেতার নাম (ঐচ্ছিক)', prefixIcon: Icon(Icons.person_outline_rounded))),
                const SizedBox(height: 12),
                TextField(controller: _phone, keyboardType: TextInputType.phone, scrollPadding: const EdgeInsets.only(bottom: 120), decoration: const InputDecoration(hintText: 'মোবাইল নম্বর (ঐচ্ছিক)', prefixIcon: Icon(Icons.phone_outlined))),
              ],
            ]),
          ),
          // Items
          SectionHeader(
            title: _items.isEmpty ? 'পণ্য' : 'পণ্য (${_items.length})',
            padding: const EdgeInsets.fromLTRB(0, AppTheme.s24, 0, AppTheme.s8),
          ),
          Row(children: [
            Expanded(child: _AddButton(icon: Icons.inventory_2_outlined, label: 'তালিকা', onTap: _addFromProducts)),
            const SizedBox(width: 8),
            Expanded(child: _AddButton(icon: Icons.mic_none_rounded, label: 'মুখে বলুন', onTap: _addVoice)),
            const SizedBox(width: 8),
            Expanded(child: _AddButton(icon: Icons.edit_outlined, label: 'হাতে লিখুন', onTap: _addManual)),
          ]),
          const SizedBox(height: 12),
          if (_items.isEmpty)
            PaperCard(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(child: Text('উপরের বোতাম দিয়ে পণ্য যোগ করুন', style: AppTheme.bodySm.copyWith(color: AppTheme.inkMuted))),
            )
          else
            ListGroup(
              dividerInset: AppTheme.gutter,
              children: [
                for (int i = 0; i < _items.length; i++)
                  Dismissible(
                    key: ValueKey('item_$i${_items[i].name}'),
                    direction: DismissDirection.endToStart,
                    background: Container(
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.only(right: 20),
                      color: AppTheme.coralSoft,
                      child: const Icon(Icons.delete_outline_rounded, color: AppTheme.coral),
                    ),
                    onDismissed: (_) => setState(() => _items.removeAt(i)),
                    child: AppListRow(
                      title: _items[i].name,
                      subtitle: '${_qty(_items[i].quantity)} × ${CurrencyFormatter.format(_items[i].unitPrice)}',
                      amount: _items[i].total,
                    ),
                  ),
              ],
            ),
          const SizedBox(height: AppTheme.s24),

          // Totals
          PaperCard(
            padding: const EdgeInsets.all(AppTheme.s16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              InfoRow('উপমোট', CurrencyFormatter.format(_subtotal)),
              const SizedBox(height: AppTheme.s8),
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(
                  child: TextField(
                    controller: _discount,
                    scrollPadding: const EdgeInsets.only(bottom: 120),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      labelText: 'ডিসকাউন্ট',
                      prefixText: '৳ ',
                      errorText: _discountTooBig ? 'উপমোটের বেশি নয়' : null,
                    ),
                  ),
                ),
                const SizedBox(width: AppTheme.s8),
                Expanded(
                  child: TextField(
                    controller: _paid,
                    scrollPadding: const EdgeInsets.only(bottom: 120),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                    onChanged: (_) => setState(() {}),
                    style: AppTheme.bodyStrong.copyWith(color: AppTheme.emerald, fontFeatures: AppTheme.tabular),
                    decoration: InputDecoration(
                      labelText: 'নগদ পেলাম',
                      prefixText: '৳ ',
                      suffixIcon: IconButton(
                        tooltip: 'পুরো টাকা',
                        icon: const Icon(Icons.done_all_rounded, color: AppTheme.emerald),
                        onPressed: () => setState(() => _paid.text = CurrencyFormatter.number(_total)),
                      ),
                    ),
                  ),
                ),
              ]),
              const SizedBox(height: AppTheme.s12),
              const Divider(),
              const SizedBox(height: AppTheme.s8),
              Row(children: [
                Expanded(child: Text('সর্বমোট', style: AppTheme.bodyStrong)),
                FittedBox(fit: BoxFit.scaleDown, child: TakaText(_total, size: AppTheme.amountLgSize, color: AppTheme.ink)),
              ]),
              if (_change > 0) ...[
                const SizedBox(height: AppTheme.s4),
                // Over-payment: the memo keeps only the total; the rest goes back.
                InfoRow('ফেরত দিন', CurrencyFormatter.format(_change), valueColor: AppTheme.saffronDeep, bold: true),
              ],
              if (_due > 0) ...[
                const SizedBox(height: AppTheme.s4),
                Row(children: [
                  Expanded(child: Text('বাকি থাকছে', style: AppTheme.body.copyWith(color: AppTheme.inkMuted))),
                  TakaText(_due, size: AppTheme.amountSmSize, color: AppTheme.coral),
                ]),
                if (_customer != null) ...[
                  const SizedBox(height: AppTheme.s4),
                  CheckboxListTile(
                    value: _pushDue,
                    onChanged: (v) => setState(() => _pushDue = v ?? true),
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    title: Text('${_customer!.name}-এর বাকি খাতায় লিখুন', style: AppTheme.bodySm, maxLines: 2, overflow: TextOverflow.ellipsis),
                    subtitle: _pushDue
                        ? Text('শুধু বাকি ${CurrencyFormatter.format(_due)} খাতায় যাবে; নগদ অংশ নয়', style: AppTheme.caption)
                        : null,
                  ),
                ] else
                  Padding(
                    padding: const EdgeInsets.only(top: AppTheme.s8),
                    child: Text('বাকি খাতায় তুলতে চাইলে উপরে "খাতা থেকে বাছুন" দিয়ে খরিদ্দার যুক্ত করুন', style: AppTheme.caption),
                  ),
              ] else if (_items.isNotEmpty) ...[
                const SizedBox(height: AppTheme.s4),
                Row(children: [
                  const Icon(Icons.check_circle_outline_rounded, color: AppTheme.emerald, size: AppTheme.iconList),
                  const SizedBox(width: AppTheme.s8),
                  Text('পুরো টাকা পরিশোধিত', style: AppTheme.bodySm.copyWith(color: AppTheme.emerald)),
                ]),
              ],
            ]),
          ),
        ],
      ),
      // bottomNavigationBar (not bottomSheet) so the body is inset above the
      // bar and the keyboard: a focused field can never end up underneath it.
      bottomNavigationBar: BottomActionBar(
        leading: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text('মোট', style: AppTheme.label),
          TakaText(_total, size: AppTheme.amountLgSize),
        ]),
        primary: PrimaryButton(label: 'মেমো সংরক্ষণ', loading: _saving, onPressed: _save),
      ),
    );
  }

  static String _qty(double v) => CurrencyFormatter.number(v);
}

class _AddButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _AddButton({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8), textStyle: AppTheme.bodySmStrong),
      child: Row(mainAxisAlignment: MainAxisAlignment.center, mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 18, color: AppTheme.inkMuted),
        const SizedBox(width: 6),
        Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis)),
      ]),
    );
  }
}

class _ManualItemSheet extends StatefulWidget {
  final Product? product;
  const _ManualItemSheet({this.product});

  @override
  State<_ManualItemSheet> createState() => _ManualItemSheetState();
}

class _ManualItemSheetState extends State<_ManualItemSheet> {
  late final TextEditingController _name = TextEditingController(text: widget.product?.name ?? '');
  late final TextEditingController _qty = TextEditingController(text: '1');
  late final TextEditingController _price = TextEditingController(
      text: widget.product == null ? '' : (widget.product!.salePrice == widget.product!.salePrice.roundToDouble() ? widget.product!.salePrice.toStringAsFixed(0) : widget.product!.salePrice.toString()));

  double get _total => (double.tryParse(_qty.text) ?? 0) * (double.tryParse(_price.text) ?? 0);

  @override
  void dispose() {
    _name.dispose();
    _qty.dispose();
    _price.dispose();
    super.dispose();
  }

  void _bump(int d) {
    final q = (double.tryParse(_qty.text) ?? 0) + d;
    if (q <= 0) return;
    setState(() => _qty.text = q == q.roundToDouble() ? q.toStringAsFixed(0) : q.toString());
  }

  void _add() {
    final name = _name.text.trim();
    final qty = double.tryParse(_qty.text) ?? 0;
    final price = double.tryParse(_price.text) ?? 0;
    if (name.isEmpty) return showSnack(context, 'পণ্যের নাম লিখুন', error: true);
    if (qty <= 0) return showSnack(context, 'পরিমাণ লিখুন', error: true);
    if (price <= 0) return showSnack(context, 'দর লিখুন', error: true);
    final p = widget.product;
    Navigator.pop(context, MemoItem(name: p == null ? name : '${p.name} (${p.unit})', quantity: qty, unitPrice: price, productId: p?.id));
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.product;
    final body = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (p == null)
        AppTextField(controller: _name, label: 'পণ্যের নাম', hint: 'যেমন: চিনি', icon: Icons.shopping_basket_outlined, autofocus: true)
      else
        NoteBox(icon: Icons.inventory_2_outlined, text: 'স্টকে আছে ${p.stock == p.stock.roundToDouble() ? p.stock.toStringAsFixed(0) : p.stock} ${p.unit}'),
      const SizedBox(height: 14),
      Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(padding: const EdgeInsets.only(left: 2, bottom: 6), child: Text('পরিমাণ${p == null ? '' : ' (${p.unit})'}', style: AppTheme.sectionHeader)),
            Row(children: [
              _StepBtn(icon: Icons.remove_rounded, onTap: () => _bump(-1)),
              Expanded(
                child: TextField(
                  controller: _qty,
                  scrollPadding: const EdgeInsets.only(bottom: 120),
                  textAlign: TextAlign.center,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  onChanged: (_) => setState(() {}),
                  style: AppTheme.amountMd,
                  decoration: const InputDecoration(contentPadding: EdgeInsets.symmetric(vertical: 14)),
                ),
              ),
              _StepBtn(icon: Icons.add_rounded, onTap: () => _bump(1)),
            ]),
          ]),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: AppTextField(
            controller: _price,
            label: 'দর (৳)',
            hint: '0',
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            autofocus: p != null,
            onChanged: (_) => setState(() {}),
            style: AppTheme.amountMd,
          ),
        ),
      ]),
      const SizedBox(height: 18),
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text('মোট', style: AppTheme.body.copyWith(color: AppTheme.inkMuted)),
        TakaText(_total, size: AppTheme.amountLgSize, color: AppTheme.ink),
      ]),
    ]);
    return SheetForm(
      body: body,
      bar: BottomActionBar(primary: PrimaryButton(label: 'মেমোতে যোগ করুন', onPressed: _add)),
    );
  }
}

class _StepBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _StepBtn({required this.icon, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Material(
        color: AppTheme.sand,
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppTheme.radiusSm),
          onTap: onTap,
          child: SizedBox(width: 44, height: 48, child: Icon(icon, color: AppTheme.ink, size: 22)),
        ),
      ),
    );
  }
}

class _CustomerPicker extends StatefulWidget {
  final List<Customer> customers;
  const _CustomerPicker({required this.customers});
  @override
  State<_CustomerPicker> createState() => _CustomerPickerState();
}

class _CustomerPickerState extends State<_CustomerPicker> {
  String _q = '';
  @override
  Widget build(BuildContext context) {
    final q = _q.trim().toLowerCase();
    final list = q.isEmpty ? widget.customers : [for (final c in widget.customers) if (c.searchKey.contains(q)) c];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SearchField(hint: 'নাম বা নম্বর', onChanged: (v) => setState(() => _q = v)),
      const SizedBox(height: 10),
      TonalButton(
        label: 'নতুন খরিদ্দার যোগ করুন',
        icon: Icons.person_add_alt_1_outlined,
        onPressed: () async {
          final c = await CustomerFormSheet.show(context);
          if (c != null && context.mounted) Navigator.pop(context, c);
        },
      ),
      const SizedBox(height: 8),
      if (list.isEmpty)
        Padding(padding: const EdgeInsets.all(24), child: Text('কাউকে পাওয়া যায়নি', textAlign: TextAlign.center, style: AppTheme.caption))
      else
        for (final c in list.take(60)) ...[
          AppListRow(
            onTap: () => Navigator.pop(context, c),
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
            leading: AvatarCircle(name: c.name, photoPath: c.photoPath, size: 40),
            title: c.name,
            subtitle: c.phone.isEmpty ? 'নম্বর নেই' : c.phone,
            amount: c.currentBalance > 0 ? c.currentBalance : null,
            amountColor: AppTheme.coral,
            trailingLabel: c.currentBalance > 0 ? 'বাকি' : null,
          ),
          const AppDivider(inset: 56),
        ],
    ]);
  }
}
