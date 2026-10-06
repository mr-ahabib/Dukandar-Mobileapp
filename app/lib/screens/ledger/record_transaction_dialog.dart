import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/photo_helper.dart';
import '../../models/customer.dart';
import '../../models/transaction_item.dart';
import '../../providers/cash_drawer_provider.dart';
import '../../providers/ledger_provider.dart';
import '../../core/utils/voice_parser.dart';
import '../../widgets/common_widgets.dart';
import '../../widgets/voice_sheet.dart';

/// দিলাম / পেলাম entry sheet with quick-amount chips, date chip and receipt photo.
class RecordTransactionSheet extends StatefulWidget {
  final Customer customer;
  final TransactionType type;
  final TransactionItem? existing;
  final double? initialAmount;
  final String? initialNote;

  const RecordTransactionSheet({
    super.key,
    required this.customer,
    required this.type,
    this.existing,
    this.initialAmount,
    this.initialNote,
  });

  static Future<bool?> show(
    BuildContext context, {
    required Customer customer,
    required TransactionType type,
    TransactionItem? existing,
    double? initialAmount,
    String? initialNote,
  }) {
    return AppBottomSheet.show<bool>(
      context,
      child: RecordTransactionSheet(
        customer: customer,
        type: type,
        existing: existing,
        initialAmount: initialAmount,
        initialNote: initialNote,
      ),
    );
  }

  @override
  State<RecordTransactionSheet> createState() => _RecordTransactionSheetState();
}

class _RecordTransactionSheetState extends State<RecordTransactionSheet> {
  late final TextEditingController _amount;
  late final TextEditingController _note;
  late DateTime _date;
  late TransactionType _type;
  String? _photoPath;
  bool _saving = false;
  late final String _txId;

  bool get isCustomer => widget.customer.type == ContactType.customer;
  bool get isGave => _type == TransactionType.gave;

  String get _title {
    if (isCustomer) return isGave ? 'বাকি দিলাম' : 'টাকা পেলাম';
    return isGave ? 'টাকা দিলাম' : 'মাল পেলাম (বাকিতে)';
  }

  String get _hint {
    if (isCustomer) {
      return isGave ? 'খরিদ্দারকে বাকিতে মাল দিলেন' : 'খরিদ্দার টাকা জমা দিলেন';
    }
    return isGave
        ? 'মহাজনকে টাকা পরিশোধ করলেন'
        : 'মহাজনের কাছ থেকে বাকিতে মাল নিলেন';
  }

  Color get _color => isGave ? AppTheme.coral : AppTheme.emerald;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _type = e?.type ?? widget.type;
    final amt = e?.amount ?? widget.initialAmount;
    _amount = TextEditingController(
      text: amt == null
          ? ''
          : (amt == amt.roundToDouble()
                ? amt.toStringAsFixed(0)
                : amt.toString()),
    );
    _note = TextEditingController(text: e?.note ?? widget.initialNote ?? '');
    _date = e?.date ?? DateTime.now();
    _photoPath = e?.photoPath;
    _txId = e?.id ?? 'tx_${DateTime.now().millisecondsSinceEpoch}';
  }

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  void _applyVoice(String text) {
    final r = VoiceParser.parseLedger(text);
    setState(() {
      if (r.amount != null) {
        _amount.text = r.amount == r.amount!.roundToDouble()
            ? r.amount!.toStringAsFixed(0)
            : r.amount.toString();
      }
      if (r.note.isNotEmpty) _note.text = r.note;
      if (r.intent == VoiceIntent.gave) _type = TransactionType.gave;
      if (r.intent == VoiceIntent.got) _type = TransactionType.got;
    });
    showSnack(context, 'শুনেছি: “$text” — ঠিক থাকলে সংরক্ষণ করুন');
  }

  Future<void> _attachPhoto() async {
    final fromCamera = await AppBottomSheet.pickPhotoSource(context);
    if (fromCamera == null) return;
    final path = await PhotoHelper.pickAndStore(
      id: 'receipt_$_txId',
      fromCamera: fromCamera,
    );
    if (path != null && mounted) {
      imageCache.clear();
      setState(() => _photoPath = path);
    }
  }

  Future<void> _save() async {
    final amount = double.tryParse(_amount.text.trim()) ?? 0;
    if (amount <= 0) {
      showSnack(context, 'সঠিক টাকার পরিমাণ লিখুন', error: true);
      return;
    }
    setState(() => _saving = true);
    final ledger = context.read<LedgerProvider>();
    try {
      if (widget.existing != null) {
        await ledger.updateTransaction(
          widget.existing!.copyWith(
            type: _type,
            amount: amount,
            note: _note.text.trim().isEmpty
                ? (isGave ? 'বাকি' : 'জমা')
                : _note.text.trim(),
            date: _date,
            photoPath: _photoPath,
            clearPhoto: _photoPath == null,
          ),
        );
      } else {
        await ledger.recordTransaction(
          customer: widget.customer,
          type: _type,
          amount: amount,
          note: _note.text,
          date: _date,
          photoPath: _photoPath,
        );
      }
      if (!mounted) return;
      // A collection / supplier payment changes today's cash figure.
      context.read<CashDrawerProvider>().loadExpenses();
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) showSnack(context, 'ত্রুটি: $e', error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            AvatarCircle(
              name: widget.customer.name,
              photoPath: widget.customer.photoPath,
              size: 40,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.customer.name,
                    style: AppTheme.bodyStrong,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    _hint,
                    style: AppTheme.caption,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            VoiceInputButton(
              color: _color,
              title: 'লেনদেন বলুন',
              hint: 'যেমন: "৫০০ টাকা বাকি দিলাম চাল তেল"',
              examples: const [
                '৫০০ টাকা বাকি দিলাম',
                '২০০ টাকা জমা পেলাম',
                'দেড়শ টাকা চিনি বাকি',
              ],
              onResult: _applyVoice,
            ),
            const SizedBox(width: 6),
            IconButton(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.close_rounded, color: AppTheme.inkMuted),
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
        const SizedBox(height: 16),
        Segmented<TransactionType>(
          values: const [TransactionType.gave, TransactionType.got],
          selected: _type,
          label: (t) => isCustomer
              ? (t == TransactionType.gave ? 'বাকি দিলাম' : 'টাকা পেলাম')
              : (t == TransactionType.gave ? 'টাকা দিলাম' : 'মাল পেলাম'),
          colorOf: (t) =>
              t == TransactionType.gave ? AppTheme.coral : AppTheme.emerald,
          onChanged: (t) => setState(() => _type = t),
        ),
        const SizedBox(height: 18),
        AmountField(
          controller: _amount,
          label: _title,
          autofocus: widget.existing == null,
          color: _color,
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 10),
        QuickAmountChips(controller: _amount, onChanged: () => setState(() {})),
        const SizedBox(height: 16),
        AppTextField(
          controller: _note,
          label: 'বিবরণ',
          hint: isGave ? 'যেমন: চাল ৫ কেজি, তেল ১ লিটার' : 'যেমন: নগদ / বিকাশ',
          icon: Icons.edit_note_rounded,
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: AppTheme.s8,
          runSpacing: AppTheme.s8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            DateChip(date: _date, onChanged: (d) => setState(() => _date = d)),
            ActionChip(
              avatar: Icon(
                _photoPath == null
                    ? Icons.add_a_photo_outlined
                    : Icons.check_circle_outline_rounded,
                size: 16,
                color: _photoPath == null
                    ? AppTheme.inkMuted
                    : AppTheme.emerald,
              ),
              label: Text(_photoPath == null ? 'রসিদের ছবি' : 'ছবি যুক্ত'),
              onPressed: _attachPhoto,
            ),
            if (_photoPath != null)
              IconButton(
                onPressed: () => setState(() => _photoPath = null),
                icon: const Icon(
                  Icons.delete_outline_rounded,
                  color: AppTheme.coral,
                ),
                tooltip: 'ছবি সরান',
              ),
          ],
        ),
      ],
    );
    return SheetForm(
      body: body,
      bar: BottomActionBar(
        primary: PrimaryButton(
          label: widget.existing == null ? 'সংরক্ষণ করুন' : 'পরিবর্তন সংরক্ষণ',
          color: _color,
          loading: _saving,
          onPressed: _save,
        ),
      ),
    );
  }
}
