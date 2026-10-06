import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/photo_helper.dart';
import '../../models/customer.dart';
import '../../providers/ledger_provider.dart';
import '../../core/utils/voice_parser.dart';
import '../../widgets/common_widgets.dart';
import '../../widgets/voice_sheet.dart';

/// Add / edit customer or supplier as a bottom sheet with photo capture.
class CustomerFormSheet extends StatefulWidget {
  final ContactType defaultType;
  final Customer? existing;

  const CustomerFormSheet({
    super.key,
    this.defaultType = ContactType.customer,
    this.existing,
  });

  /// Returns the saved customer (new or updated) or null.
  static Future<Customer?> show(
    BuildContext context, {
    ContactType type = ContactType.customer,
    Customer? existing,
  }) {
    return AppBottomSheet.show<Customer>(
      context,
      title: existing == null
          ? (type == ContactType.customer ? 'নতুন খরিদ্দার' : 'নতুন মহাজন')
          : 'তথ্য পরিবর্তন',
      child: CustomerFormSheet(defaultType: type, existing: existing),
    );
  }

  @override
  State<CustomerFormSheet> createState() => _CustomerFormSheetState();
}

class _CustomerFormSheetState extends State<CustomerFormSheet> {
  late final TextEditingController _name;
  late final TextEditingController _phone;
  late final TextEditingController _address;
  late final TextEditingController _note;
  final _opening = TextEditingController();
  late ContactType _type;
  String? _photoPath;
  late final String _id;
  bool _saving = false;

  bool get isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _type = e?.type ?? widget.defaultType;
    _name = TextEditingController(text: e?.name ?? '');
    _phone = TextEditingController(text: e?.phone ?? '');
    _address = TextEditingController(text: e?.address ?? '');
    _note = TextEditingController(text: e?.note ?? '');
    _photoPath = e?.photoPath;
    _id = e?.id ?? 'contact_${DateTime.now().millisecondsSinceEpoch}';
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _address.dispose();
    _note.dispose();
    _opening.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    final fromCamera = await AppBottomSheet.pickPhotoSource(context);
    if (fromCamera == null) return;
    final path = await PhotoHelper.pickAndStore(
      id: _id,
      fromCamera: fromCamera,
    );
    if (path != null && mounted) {
      // Evict cached image so the new file shows immediately.
      imageCache.clear();
      setState(() => _photoPath = path);
    }
  }

  void _applyVoice(String text) {
    final r = VoiceParser.parseContact(text);
    setState(() {
      if (r.name.isNotEmpty) _name.text = r.name;
      if (r.phone.isNotEmpty) _phone.text = r.phone;
    });
    showSnack(context, 'শুনেছি: “$text” — ঠিক থাকলে যোগ করুন');
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      showSnack(context, 'নাম লিখুন', error: true);
      return;
    }
    setState(() => _saving = true);
    final ledger = context.read<LedgerProvider>();
    try {
      Customer result;
      if (isEdit) {
        result = widget.existing!.copyWith(
          name: name,
          phone: _phone.text.trim(),
          address: _address.text.trim(),
          note: _note.text.trim(),
          type: _type,
          photoPath: _photoPath,
          clearPhoto: _photoPath == null,
        );
        await ledger.updateContact(result);
      } else {
        result = await ledger.addContact(
          id: _id,
          name: name,
          phone: _phone.text.trim(),
          address: _address.text.trim(),
          note: _note.text.trim(),
          photoPath: _photoPath,
          type: _type,
          openingBalance: double.tryParse(_opening.text.trim()) ?? 0,
        );
      }
      if (mounted) Navigator.pop(context, result);
    } catch (e) {
      if (mounted) showSnack(context, 'ত্রুটি: $e', error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _type == ContactType.customer
        ? AppTheme.indigo
        : AppTheme.slate;
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Photo
        Center(
          child: GestureDetector(
            onTap: _pickPhoto,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                AvatarCircle(
                  name: _name.text.isEmpty ? '?' : _name.text,
                  photoPath: _photoPath,
                  size: 80,
                ),
                Positioned(
                  right: -2,
                  bottom: -2,
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: AppTheme.paper,
                      shape: BoxShape.circle,
                      border: Border.all(color: AppTheme.hairline),
                    ),
                    child: const Icon(
                      Icons.photo_camera_outlined,
                      color: AppTheme.inkMuted,
                      size: 15,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 4),
        Center(
          child: TextButton(
            onPressed: _photoPath == null
                ? _pickPhoto
                : () => setState(() => _photoPath = null),
            style: TextButton.styleFrom(
              textStyle: AppTheme.bodySmStrong,
              minimumSize: const Size(0, 36),
            ),
            child: Text(_photoPath == null ? 'ছবি যোগ করুন' : 'ছবি সরান'),
          ),
        ),
        const SizedBox(height: 8),
        if (!isEdit) ...[
          Segmented<ContactType>(
            values: const [ContactType.customer, ContactType.supplier],
            selected: _type,
            label: (t) =>
                t == ContactType.customer ? 'খরিদ্দার' : 'মহাজন / পাইকার',
            colorOf: (t) =>
                t == ContactType.customer ? AppTheme.indigo : AppTheme.slate,
            onChanged: (t) => setState(() => _type = t),
          ),
          const SizedBox(height: 16),
        ],
        AppTextField(
          controller: _name,
          label: 'নাম *',
          hint: 'যেমন: কামাল হোসেন',
          icon: Icons.person_outline_rounded,
          autofocus: !isEdit,
          textInputAction: TextInputAction.next,
          onChanged: (_) => setState(() {}),
          suffix: Padding(
            padding: const EdgeInsets.only(right: 4),
            child: VoiceInputButton(
              size: 44,
              filled: false,
              color: color,
              title: 'নাম ও নম্বর বলুন',
              hint: 'যেমন: "কামাল হোসেন ০১৭১২৩৪৫৬৭৮"',
              onResult: _applyVoice,
            ),
          ),
        ),
        const SizedBox(height: 14),
        AppTextField(
          controller: _phone,
          label: 'মোবাইল নম্বর',
          hint: '01XXXXXXXXX',
          icon: Icons.phone_outlined,
          keyboardType: TextInputType.phone,
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: 14),
        AppTextField(
          controller: _address,
          label: 'ঠিকানা',
          hint: 'গ্রাম / রোড / বাসা',
          icon: Icons.location_on_outlined,
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: 14),
        AppTextField(
          controller: _note,
          label: 'নোট',
          hint: 'যেমন: প্রতি শুক্রবার টাকা দেয়',
          icon: Icons.sticky_note_2_outlined,
          maxLines: 2,
        ),
        if (!isEdit) ...[
          const SizedBox(height: 14),
          AmountField(
            controller: _opening,
            label: _type == ContactType.customer
                ? 'পূর্বের বাকি (যদি থাকে)'
                : 'পূর্বের দেনা (যদি থাকে)',
            color: AppTheme.coral,
          ),
        ],
      ],
    );
    return SheetForm(
      body: body,
      bar: BottomActionBar(
        primary: PrimaryButton(
          label: isEdit ? 'সংরক্ষণ করুন' : 'যোগ করুন',
          loading: _saving,
          color: color,
          onPressed: _save,
        ),
      ),
    );
  }
}
