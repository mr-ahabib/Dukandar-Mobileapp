import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/currency_formatter.dart';
import '../../models/product.dart';
import '../../providers/products_provider.dart';
import '../../core/utils/voice_parser.dart';
import '../../widgets/common_widgets.dart';
import '../../widgets/voice_sheet.dart';

/// পণ্য ও স্টক
class ProductsScreen extends StatelessWidget {
  const ProductsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: ProductsProvider.instance,
      child: const _ProductsBody(),
    );
  }
}

class _ProductsBody extends StatelessWidget {
  const _ProductsBody();

  @override
  Widget build(BuildContext context) {
    final p = context.watch<ProductsProvider>();
    final items = p.products;
    final lowCount = p.lowStockCount;

    return Scaffold(
      appBar: AppBar(
        title: const Text('পণ্য ও স্টক'),
        actions: [
          IconButton(
            onPressed: () => ProductFormSheet.show(context),
            icon: const Icon(Icons.add_rounded),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: p.load,
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppTheme.gutter,
                  AppTheme.s4,
                  AppTheme.gutter,
                  AppTheme.s8,
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: PaperCard(
                            padding: const EdgeInsets.all(AppTheme.s16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('মোট পণ্য', style: AppTheme.label),
                                const SizedBox(height: 8),
                                Text(
                                  '${p.allProducts.length}',
                                  style: AppTheme.amountMd,
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: AppTheme.s8),
                        Expanded(
                          child: PaperCard(
                            padding: const EdgeInsets.all(AppTheme.s16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('স্টক কম', style: AppTheme.label),
                                const SizedBox(height: 8),
                                Text(
                                  '$lowCount',
                                  style: AppTheme.amountMd.copyWith(
                                    color: lowCount > 0
                                        ? AppTheme.coral
                                        : AppTheme.ink,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    SearchField(hint: 'পণ্য খুঁজুন', onChanged: p.setQuery),
                  ],
                ),
              ),
            ),
            if (p.allProducts.isEmpty && !p.isLoading)
              SliverFillRemaining(
                hasScrollBody: false,
                child: EmptyState(
                  icon: Icons.inventory_2_outlined,
                  title: 'পণ্যের তালিকা খালি',
                  message: 'পণ্য যোগ করলে মেমো বানানো দ্রুত হবে।',
                  actionLabel: 'পণ্য যোগ করুন',
                  onAction: () => ProductFormSheet.show(context),
                ),
              )
            else if (items.isEmpty)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: EmptyState(
                  icon: Icons.search_off_rounded,
                  title: 'পাওয়া যায়নি',
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(
                  AppTheme.gutter,
                  AppTheme.s4,
                  AppTheme.gutter,
                  100,
                ),
                sliver: SliverListGroup(
                  sliver: SliverList.separated(
                    itemCount: items.length,
                    separatorBuilder: (_, _) => const AppDivider(),
                    itemBuilder: (_, i) => ProductTile(
                      product: items[i],
                      onTap: () =>
                          ProductFormSheet.show(context, existing: items[i]),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => ProductFormSheet.show(context),
        icon: const Icon(Icons.add_rounded),
        label: const Text('নতুন পণ্য'),
      ),
    );
  }
}

class ProductTile extends StatelessWidget {
  final Product product;
  final VoidCallback onTap;
  final Widget? trailing;
  const ProductTile({
    super.key,
    required this.product,
    required this.onTap,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final p = product;
    final stockStr = p.stock == p.stock.roundToDouble()
        ? p.stock.toStringAsFixed(0)
        : p.stock.toStringAsFixed(1);
    return AppListRow(
      onTap: onTap,
      leading: TintedIcon(
        Icons.shopping_basket_outlined,
        color: AvatarCircle.inkFor(p.name),
      ),
      title: p.name,
      subtitleWidget: Row(
        children: [
          Flexible(
            child: Text(
              'স্টক: $stockStr ${p.unit}',
              style: AppTheme.bodySm.copyWith(color: AppTheme.inkMuted),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (p.isLowStock) ...[
            const SizedBox(width: 8),
            Pill(text: p.isOutOfStock ? 'শেষ' : 'কম', color: AppTheme.coral),
          ],
        ],
      ),
      trailing: trailing,
      amount: trailing == null ? p.salePrice : null,
      trailingLabel: trailing == null ? '/${p.unit}' : null,
    );
  }
}

/// Add / edit product sheet.
class ProductFormSheet extends StatefulWidget {
  final Product? existing;
  const ProductFormSheet({super.key, this.existing});

  static Future<Product?> show(BuildContext context, {Product? existing}) {
    return AppBottomSheet.show<Product>(
      context,
      title: existing == null ? 'নতুন পণ্য' : 'পণ্য পরিবর্তন',
      child: ChangeNotifierProvider.value(
        value: ProductsProvider.instance,
        child: ProductFormSheet(existing: existing),
      ),
    );
  }

  @override
  State<ProductFormSheet> createState() => _ProductFormSheetState();
}

class _ProductFormSheetState extends State<ProductFormSheet> {
  static const units = [
    'পিস',
    'কেজি',
    'গ্রাম',
    'লিটার',
    'ডজন',
    'প্যাকেট',
    'বস্তা',
    'হালি',
  ];
  late final TextEditingController _name;
  late final TextEditingController _sale;
  late final TextEditingController _buy;
  late final TextEditingController _stock;
  late final TextEditingController _alert;
  late String _unit;
  bool _saving = false;

  String _num(double v) => v == 0
      ? ''
      : (v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString());

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _name = TextEditingController(text: e?.name ?? '');
    _sale = TextEditingController(text: e == null ? '' : _num(e.salePrice));
    _buy = TextEditingController(text: e == null ? '' : _num(e.buyPrice));
    _stock = TextEditingController(text: e == null ? '' : _num(e.stock));
    _alert = TextEditingController(
      text: e == null ? '' : _num(e.lowStockAlert),
    );
    _unit = e?.unit ?? 'পিস';
  }

  @override
  void dispose() {
    for (final c in [_name, _sale, _buy, _stock, _alert]) {
      c.dispose();
    }
    super.dispose();
  }

  void _applyVoice(String text) {
    final r = VoiceParser.parseProduct(text);
    String f(double v) =>
        v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();
    setState(() {
      if (r.name.isNotEmpty) _name.text = r.name;
      if (units.contains(r.unit)) _unit = r.unit;
      if (r.price != null) _sale.text = f(r.price!);
      if (r.stock != null) _stock.text = f(r.stock!);
    });
    showSnack(context, 'শুনেছি: “$text” — ঠিক থাকলে যোগ করুন');
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    final sale = double.tryParse(_sale.text.trim()) ?? 0;
    if (name.isEmpty) {
      return showSnack(context, 'পণ্যের নাম লিখুন', error: true);
    }
    if (sale <= 0) {
      return showSnack(context, 'বিক্রয় মূল্য লিখুন', error: true);
    }
    setState(() => _saving = true);
    final p = context.read<ProductsProvider>();
    try {
      Product result;
      if (widget.existing != null) {
        result = widget.existing!.copyWith(
          name: name,
          unit: _unit,
          salePrice: sale,
          buyPrice: double.tryParse(_buy.text.trim()) ?? 0,
          stock: double.tryParse(_stock.text.trim()) ?? 0,
          lowStockAlert: double.tryParse(_alert.text.trim()) ?? 0,
        );
        await p.updateProduct(result);
      } else {
        result = await p.addProduct(
          name: name,
          unit: _unit,
          salePrice: sale,
          buyPrice: double.tryParse(_buy.text.trim()) ?? 0,
          stock: double.tryParse(_stock.text.trim()) ?? 0,
          lowStockAlert: double.tryParse(_alert.text.trim()) ?? 0,
        );
      }
      if (mounted) Navigator.pop(context, result);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final ok = await AppBottomSheet.confirm(
      context,
      title: 'পণ্য মুছবেন?',
      message: '${widget.existing!.name} তালিকা থেকে মুছে যাবে।',
      confirmLabel: 'মুছুন',
      danger: true,
    );
    if (!ok || !mounted) return;
    await context.read<ProductsProvider>().deleteProduct(widget.existing!.id);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    const numType = TextInputType.numberWithOptions(decimal: true);
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppTextField(
          controller: _name,
          label: 'পণ্যের নাম *',
          hint: 'যেমন: মিনিকেট চাল',
          icon: Icons.shopping_basket_outlined,
          autofocus: widget.existing == null,
          suffix: Padding(
            padding: const EdgeInsets.only(right: 4),
            child: VoiceInputButton(
              size: 44,
              filled: false,
              title: 'পণ্য বলুন',
              hint: 'যেমন: "মিনিকেট চাল কেজি ৭২ টাকা স্টক ৫০"',
              examples: const [
                'মিনিকেট চাল কেজি ৭২ টাকা স্টক ৫০',
                'লাক্স সাবান ৪৫ টাকা',
              ],
              onResult: _applyVoice,
            ),
          ),
        ),
        const SizedBox(height: 14),
        Padding(
          padding: const EdgeInsets.only(left: 2, bottom: 6),
          child: Text('একক', style: AppTheme.sectionHeader),
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: units
              .map(
                (u) => ChoiceChip(
                  label: Text(u),
                  selected: _unit == u,
                  onSelected: (_) => setState(() => _unit = u),
                  labelStyle: AppTheme.bodySm.copyWith(
                    color: _unit == u ? Colors.white : AppTheme.ink,
                    fontWeight: _unit == u ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              )
              .toList(),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: AppTextField(
                controller: _sale,
                label: 'বিক্রয় মূল্য *',
                hint: '৳',
                keyboardType: numType,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: AppTextField(
                controller: _buy,
                label: 'ক্রয় মূল্য',
                hint: '৳',
                keyboardType: numType,
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: AppTextField(
                controller: _stock,
                label: 'বর্তমান স্টক',
                hint: '0',
                keyboardType: numType,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: AppTextField(
                controller: _alert,
                label: 'কম হলে সতর্ক',
                hint: 'যেমন: 5',
                keyboardType: numType,
              ),
            ),
          ],
        ),
        if (widget.existing != null) ...[
          const SizedBox(height: 12),
          Center(
            child: Text(
              'মূল্য: ${CurrencyFormatter.format(widget.existing!.salePrice)} / ${widget.existing!.unit}',
              style: AppTheme.caption,
            ),
          ),
        ],
      ],
    );
    return SheetForm(
      body: body,
      bar: BottomActionBar(
        primary: PrimaryButton(
          label: widget.existing == null ? 'যোগ করুন' : 'সংরক্ষণ',
          loading: _saving,
          onPressed: _save,
        ),
        below: widget.existing == null
            ? null
            : Padding(
                padding: const EdgeInsets.only(top: 8),
                child: TextButton(
                  onPressed: _delete,
                  style: TextButton.styleFrom(foregroundColor: AppTheme.coral),
                  child: const Text('পণ্য মুছুন'),
                ),
              ),
      ),
    );
  }
}

/// Picks one product from inventory (used by memo screen).
class ProductPickerSheet extends StatefulWidget {
  const ProductPickerSheet({super.key});

  static Future<Product?> show(BuildContext context) {
    return AppBottomSheet.show<Product>(
      context,
      title: 'পণ্য বাছুন',
      child: ChangeNotifierProvider.value(
        value: ProductsProvider.instance,
        child: const ProductPickerSheet(),
      ),
    );
  }

  @override
  State<ProductPickerSheet> createState() => _ProductPickerSheetState();
}

class _ProductPickerSheetState extends State<ProductPickerSheet> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final p = context.watch<ProductsProvider>();
    final q = _q.trim().toLowerCase();
    final items = q.isEmpty
        ? p.allProducts
        : [
            for (final x in p.allProducts)
              if (x.searchKey.contains(q)) x,
          ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SearchField(
          hint: 'পণ্য খুঁজুন',
          onChanged: (v) => setState(() => _q = v),
        ),
        const SizedBox(height: 12),
        if (p.allProducts.isEmpty)
          EmptyState(
            icon: Icons.inventory_2_outlined,
            title: 'কোনো পণ্য নেই',
            message: 'আগে পণ্য তালিকায় পণ্য যোগ করুন',
            actionLabel: 'পণ্য যোগ করুন',
            onAction: () async {
              final created = await ProductFormSheet.show(context);
              if (created != null && context.mounted) {
                Navigator.pop(context, created);
              }
            },
          )
        else
          ListGroup(
            children: [
              for (final x in items)
                ProductTile(product: x, onTap: () => Navigator.pop(context, x)),
            ],
          ),
      ],
    );
  }
}
