
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../core/kyc/registration_data.dart';
import '../../../core/network/api_client.dart';
import '../../../core/theme/app_theme.dart';
import '../../../providers/auth_provider.dart';
import '../../../widgets/common_widgets.dart' show BottomActionBar, PrimaryButton, TonalButton, NoteBox;
import '../../../widgets/infra_widgets.dart';
import 'liveness_screen.dart';
import 'nid_capture_screen.dart';

/// Self-registration with KYC: 4 steps, one shared BottomActionBar.
///
/// 1. দোকানের তথ্য   2. NID ছবি   3. লাইভ ফেস যাচাই   4. রিভিউ ও জমা
class RegisterFlowScreen extends StatefulWidget {
  const RegisterFlowScreen({super.key, this.prefill, this.reapply = false});

  /// Shop info to prefill (re-application after rejection).
  final RegistrationData? prefill;
  final bool reapply;

  @override
  State<RegisterFlowScreen> createState() => _RegisterFlowScreenState();
}

class _RegisterFlowScreenState extends State<RegisterFlowScreen> {
  late final RegistrationData _data = widget.prefill ?? RegistrationData();
  final _pages = PageController();
  final _form1 = GlobalKey<FormState>();
  int _step = 0;
  bool _consent = false;
  bool _submitting = false;
  String? _error;

  late final _shop = TextEditingController(text: _data.shopName);
  late final _owner = TextEditingController(text: _data.ownerName);
  late final _phone = TextEditingController(text: _data.phone);
  final _pass = TextEditingController();
  final _pass2 = TextEditingController();
  late final _address = TextEditingController(text: _data.address);
  late final _nid = TextEditingController(text: _data.nidNumber);
  bool _obscure = true;

  static const _titles = ['দোকানের তথ্য', 'NID ছবি', 'লাইভ ফেস যাচাই', 'রিভিউ ও জমা'];

  @override
  void dispose() {
    _pages.dispose();
    for (final c in [_shop, _owner, _phone, _pass, _pass2, _address, _nid]) {
      c.dispose();
    }
    super.dispose();
  }

  void _goTo(int i) {
    FocusScope.of(context).unfocus();
    setState(() {
      _step = i;
      _error = null;
    });
    _pages.animateToPage(i, duration: const Duration(milliseconds: 260), curve: Curves.easeOutCubic);
  }

  bool _canContinue() => switch (_step) {
        0 => true, // validated on press
        1 => _data.step2Done,
        2 => _data.step3Done,
        _ => _consent && !_submitting,
      };

  Future<void> _next() async {
    switch (_step) {
      case 0:
        if (!_form1.currentState!.validate()) return;
        _data
          ..shopName = _shop.text
          ..ownerName = _owner.text
          ..phone = _phone.text
          ..password = _pass.text
          ..address = _address.text
          ..nidNumber = _nid.text;
        _goTo(1);
      case 1:
        if (_data.step2Done) _goTo(2);
      case 2:
        if (_data.step3Done) _goTo(3);
      case 3:
        await _submit();
    }
  }

  Future<void> _capture(bool front) async {
    final bytes = await Navigator.of(context).push<Uint8List>(
      MaterialPageRoute(
        builder: (_) => NidCaptureScreen(
          title: front ? 'NID সামনের দিক' : 'NID পিছনের দিক',
          hint: front
              ? 'কার্ডের সামনের দিক (ছবি ও নাম) ফ্রেমের ভিতরে রাখুন। আলো যেন কার্ডে প্রতিফলিত না হয়।'
              : 'কার্ডের পিছনের দিক (ঠিকানা) ফ্রেমের ভিতরে রাখুন।',
        ),
      ),
    );
    if (bytes == null || !mounted) return;
    setState(() {
      if (front) {
        _data.nidFront = bytes;
      } else {
        _data.nidBack = bytes;
      }
    });
  }

  Future<void> _runLiveness() async {
    final out = await Navigator.of(context).push<LivenessOutcome>(
      MaterialPageRoute(builder: (_) => const LivenessScreen()),
    );
    if (out == null || !mounted) return;
    setState(() {
      _data.selfie = out.selfie;
      _data.livenessFrames
        ..clear()
        ..addAll(out.frames);
      _data.liveness = out.liveness;
    });
  }

  Future<void> _submit() async {
    if (!_consent || _submitting) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    final auth = context.read<AuthProvider>();
    final nav = Navigator.of(context);
    // Server requires a passed live-face check; say so before spending a request.
    final live = _data.liveness;
    if (live == null || live['passed'] != true) {
      setState(() {
        _submitting = false;
        _error = 'লাইভ ফেস যাচাই সম্পন্ন হয়নি। ধাপ ৩-এ ফিরে গিয়ে ফেস যাচাই করুন।';
      });
      return;
    }
    if (!await ApiClient.isOnline()) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = 'ইন্টারনেট সংযোগ নেই। অ্যাকাউন্ট খুলতে ইন্টারনেট লাগবে — সংযোগ চালু করে আবার চেষ্টা করুন।';
      });
      return;
    }
    if (widget.reapply) {
      // Replace the session: the register response carries fresh tokens.
      try {
        await auth.logout();
      } catch (_) {}
    }
    final err = await auth.register(_data);
    if (!mounted) return;
    setState(() {
      _submitting = false;
      _error = err;
    });
    if (err == null) {
      // AppGate now sees a logged-in, pending-verification session.
      nav.popUntil((r) => r.isFirst);
    }
  }

  @override
  Widget build(BuildContext context) {
    final last = _step == 3;
    return PopScope(
      canPop: _step == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _goTo(_step - 1);
      },
      child: Scaffold(
        backgroundColor: AppTheme.background,
        appBar: AppBar(
          title: Text(widget.reapply ? 'আবার আবেদন' : 'নতুন অ্যাকাউন্ট'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: () => _step == 0 ? Navigator.maybePop(context) : _goTo(_step - 1),
          ),
        ),
        body: Column(children: [
          _Stepper(step: _step, titles: _titles),
          Expanded(
            child: PageView(
              controller: _pages,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                _step1(),
                _step2(),
                _step3(),
                _step4(),
              ],
            ),
          ),
          BottomActionBar(
            secondary: _step == 0
                ? null
                : TonalButton(
                    label: 'আগে',
                    icon: Icons.arrow_back_rounded,
                    expanded: false,
                    onPressed: _submitting ? null : () => _goTo(_step - 1),
                  ),
            primary: PrimaryButton(
              label: last ? 'জমা দিন' : 'পরের ধাপ',
              icon: last ? Icons.cloud_upload_outlined : Icons.arrow_forward_rounded,
              loading: _submitting,
              onPressed: _canContinue() ? _next : null,
            ),
          ),
        ]),
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Step 1
  // ---------------------------------------------------------------------

  Widget _step1() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(AppTheme.gutter, AppTheme.s16, AppTheme.gutter, AppTheme.s24),
      child: Form(
        key: _form1,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('দোকান ও মালিকের তথ্য', style: AppTheme.title),
          const SizedBox(height: 4),
          Text('NID-তে যেভাবে আছে সেভাবে নাম লিখুন।', style: AppTheme.bodySm.copyWith(color: AppTheme.inkMuted)),
          const SizedBox(height: AppTheme.s20),
          TextFormField(
            controller: _shop,
            textInputAction: TextInputAction.next,
            scrollPadding: const EdgeInsets.only(bottom: 140),
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'দোকানের নাম', prefixIcon: Icon(Icons.storefront_outlined)),
            validator: (v) => (v ?? '').trim().length < 2 ? 'দোকানের নাম দিন' : null,
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: _owner,
            textInputAction: TextInputAction.next,
            scrollPadding: const EdgeInsets.only(bottom: 140),
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'মালিকের নাম (NID অনুযায়ী)', prefixIcon: Icon(Icons.person_outline_rounded)),
            validator: (v) => (v ?? '').trim().length < 2 ? 'মালিকের নাম দিন' : null,
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: _phone,
            keyboardType: TextInputType.phone,
            textInputAction: TextInputAction.next,
            scrollPadding: const EdgeInsets.only(bottom: 140),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9+\- ]'))],
            style: AppTheme.body.copyWith(fontFeatures: AppTheme.tabular),
            decoration: const InputDecoration(labelText: 'মোবাইল নম্বর', hintText: '01XXXXXXXXX', prefixIcon: Icon(Icons.phone_outlined)),
            validator: (v) => RegistrationData.isValidBdPhone(v ?? '') ? null : 'সঠিক বাংলাদেশি নম্বর দিন (01XXXXXXXXX)',
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: _pass,
            obscureText: _obscure,
            textInputAction: TextInputAction.next,
            scrollPadding: const EdgeInsets.only(bottom: 140),
            decoration: InputDecoration(
              labelText: 'পাসওয়ার্ড (কমপক্ষে ৬ অক্ষর)',
              prefixIcon: const Icon(Icons.lock_outline_rounded),
              suffixIcon: IconButton(
                tooltip: _obscure ? 'দেখুন' : 'লুকান',
                icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
            validator: (v) => (v ?? '').length < 6 ? 'কমপক্ষে ৬ অক্ষরের পাসওয়ার্ড দিন' : null,
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: _pass2,
            obscureText: _obscure,
            textInputAction: TextInputAction.next,
            scrollPadding: const EdgeInsets.only(bottom: 140),
            decoration: const InputDecoration(labelText: 'পাসওয়ার্ড আবার দিন', prefixIcon: Icon(Icons.lock_reset_rounded)),
            validator: (v) => v != _pass.text ? 'দুটি পাসওয়ার্ড মিলছে না' : null,
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: _address,
            textInputAction: TextInputAction.next,
            scrollPadding: const EdgeInsets.only(bottom: 140),
            maxLines: 2,
            decoration: const InputDecoration(labelText: 'দোকানের ঠিকানা', prefixIcon: Icon(Icons.location_on_outlined)),
            validator: (v) => (v ?? '').trim().length < 4 ? 'ঠিকানা দিন' : null,
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: _nid,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.done,
            scrollPadding: const EdgeInsets.only(bottom: 140),
            inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(17)],
            style: AppTheme.body.copyWith(fontFeatures: AppTheme.tabular),
            decoration: const InputDecoration(labelText: 'NID নম্বর (১০/১৩/১৭ সংখ্যা)', prefixIcon: Icon(Icons.badge_outlined)),
            validator: (v) => RegistrationData.isValidNid(v ?? '') ? null : 'NID নম্বর ১০, ১৩ বা ১৭ সংখ্যার হতে হবে',
            onFieldSubmitted: (_) => _next(),
          ),
          const SizedBox(height: AppTheme.s16),
          const NoteBox(
            icon: Icons.verified_user_outlined,
            text: 'আপনার তথ্য শুধু অ্যাকাউন্ট যাচাইয়ের জন্য ব্যবহার হবে। যাচাই শেষে ফ্রি ট্রায়াল শুরু হবে।',
          ),
        ]),
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Step 2
  // ---------------------------------------------------------------------

  Widget _step2() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(AppTheme.gutter, AppTheme.s16, AppTheme.gutter, AppTheme.s24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('NID কার্ডের ছবি', style: AppTheme.title),
        const SizedBox(height: 4),
        Text('দুই দিকের ছবি তুলুন। লেখা যেন স্পষ্ট পড়া যায়।', style: AppTheme.bodySm.copyWith(color: AppTheme.inkMuted)),
        const SizedBox(height: AppTheme.s20),
        _NidTile(label: 'সামনের দিক', bytes: _data.nidFront, onTap: () => _capture(true)),
        const SizedBox(height: AppTheme.s12),
        _NidTile(label: 'পিছনের দিক', bytes: _data.nidBack, onTap: () => _capture(false)),
        const SizedBox(height: AppTheme.s16),
        const NoteBox(
          icon: Icons.lightbulb_outline_rounded,
          text: 'টিপস: আলোতে সমতল জায়গায় কার্ড রাখুন, ফ্ল্যাশ বন্ধ রাখুন, পুরো কার্ড ফ্রেমের ভিতরে রাখুন।',
        ),
      ]),
    );
  }

  // ---------------------------------------------------------------------
  // Step 3
  // ---------------------------------------------------------------------

  Widget _step3() {
    final done = _data.step3Done;
    final selfie = _data.selfie;
    final score = (_data.liveness?['score'] as num?)?.toDouble();
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(AppTheme.gutter, AppTheme.s16, AppTheme.gutter, AppTheme.s24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('লাইভ ফেস যাচাই', style: AppTheme.title),
        const SizedBox(height: 4),
        Text('সামনের ক্যামেরায় আপনার মুখ দেখিয়ে কয়েকটি সহজ নির্দেশ অনুসরণ করুন।', style: AppTheme.bodySm.copyWith(color: AppTheme.inkMuted, height: 1.4)),
        const SizedBox(height: AppTheme.s20),
        InfraCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Container(
                width: 72,
                height: 72,
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: AppTheme.sand,
                  shape: BoxShape.circle,
                  border: Border.all(color: done ? AppTheme.gotGreen : AppTheme.hairline, width: 2),
                ),
                child: selfie != null
                    ? Image.memory(selfie, fit: BoxFit.cover)
                    : const Icon(Icons.face_retouching_natural_rounded, color: AppTheme.inkHint, size: 36),
              ),
              const SizedBox(width: AppTheme.s16),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(done ? 'যাচাই সম্পন্ন' : 'এখনো করা হয়নি', style: AppTheme.bodyStrong),
                  const SizedBox(height: 4),
                  if (done)
                    StatusChip(
                      label: score == null ? 'পাস' : 'পাস · ${bn((score * 100).round())}%',
                      color: AppTheme.gotGreen,
                      icon: Icons.check_rounded,
                    )
                  else
                    Text('৪টি ধাপ: তাকান → পলক → হাসুন → বামে ঘোরান', style: AppTheme.caption),
                ]),
              ),
            ]),
            const SizedBox(height: AppTheme.s16),
            BigButton(
              label: done ? 'আবার করুন' : 'যাচাই শুরু করুন',
              icon: done ? Icons.replay_rounded : Icons.videocam_outlined,
              outlined: done,
              onPressed: _runLiveness,
            ),
          ]),
        ),
        const SizedBox(height: AppTheme.s16),
        const NoteBox(
          icon: Icons.wb_sunny_outlined,
          text: 'মুখে পর্যাপ্ত আলো থাকতে হবে। চশমা বা টুপি খুলে রাখলে ভালো হয়।',
        ),
      ]),
    );
  }

  // ---------------------------------------------------------------------
  // Step 4
  // ---------------------------------------------------------------------

  Widget _step4() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(AppTheme.gutter, AppTheme.s16, AppTheme.gutter, AppTheme.s24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('সব ঠিক আছে কি?', style: AppTheme.title),
        const SizedBox(height: 4),
        Text('জমা দেওয়ার আগে একবার মিলিয়ে নিন।', style: AppTheme.bodySm.copyWith(color: AppTheme.inkMuted)),
        const SizedBox(height: AppTheme.s20),
        InfraCard(
          padding: const EdgeInsets.symmetric(horizontal: AppTheme.s16, vertical: AppTheme.s8),
          child: Column(children: [
            _kv('দোকান', _data.shopName),
            const Divider(height: 1),
            _kv('মালিক', _data.ownerName),
            const Divider(height: 1),
            _kv('মোবাইল', bn(RegistrationData.normalizePhone(_data.phone)), tabular: true),
            const Divider(height: 1),
            _kv('ঠিকানা', _data.address),
            const Divider(height: 1),
            _kv('NID', bn(_data.nidNumber), tabular: true),
          ]),
        ),
        const SizedBox(height: AppTheme.s12),
        InfraCard(
          child: Row(children: [
            _thumb(_data.nidFront, 'NID সামনে'),
            const SizedBox(width: AppTheme.s12),
            _thumb(_data.nidBack, 'NID পিছনে'),
            const SizedBox(width: AppTheme.s12),
            _thumb(_data.selfie, 'সেলফি', circle: true),
          ]),
        ),
        const SizedBox(height: AppTheme.s16),
        InkWell(
          borderRadius: BorderRadius.circular(AppTheme.radiusMd),
          onTap: _submitting ? null : () => setState(() => _consent = !_consent),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Checkbox(value: _consent, onChanged: _submitting ? null : (v) => setState(() => _consent = v ?? false)),
              const SizedBox(width: 4),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text('আমার তথ্য যাচাইয়ের জন্য ব্যবহার হবে — আমি সম্মত।', style: AppTheme.bodySm.copyWith(height: 1.4)),
                ),
              ),
            ]),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
          child: _error == null
              ? const SizedBox.shrink()
              : Padding(
                  padding: const EdgeInsets.only(top: AppTheme.s8),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Icon(Icons.error_outline_rounded, color: AppTheme.gaveRed, size: 20),
                    const SizedBox(width: 8),
                    Expanded(child: Text(_error!, style: AppTheme.bodySm.copyWith(color: AppTheme.gaveRed, height: 1.35))),
                  ]),
                ),
        ),
        const SizedBox(height: AppTheme.s16),
        const NoteBox(
          icon: Icons.hourglass_top_rounded,
          text: 'জমা দেওয়ার পর আমাদের টিম যাচাই করবে (সাধারণত ২৪ ঘণ্টার মধ্যে)। যাচাই শেষে ফ্রি ট্রায়াল শুরু হবে।',
        ),
      ]),
    );
  }

  Widget _kv(String k, String v, {bool tabular = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 72, child: Text(k, style: AppTheme.caption)),
          Expanded(
            child: Text(
              v.isEmpty ? '—' : v,
              style: AppTheme.bodySmStrong.copyWith(fontFeatures: tabular ? AppTheme.tabular : null),
            ),
          ),
        ]),
      );

  Widget _thumb(Uint8List? b, String label, {bool circle = false}) => Expanded(
        child: Column(children: [
          AspectRatio(
            aspectRatio: circle ? 1 : 1.586,
            child: Container(
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: AppTheme.sand,
                shape: circle ? BoxShape.circle : BoxShape.rectangle,
                borderRadius: circle ? null : BorderRadius.circular(AppTheme.radiusSm),
                border: Border.all(color: AppTheme.hairline),
              ),
              child: b == null
                  ? const Icon(Icons.image_not_supported_outlined, color: AppTheme.inkHint)
                  : Image.memory(b, fit: BoxFit.cover),
            ),
          ),
          const SizedBox(height: 6),
          Text(label, style: AppTheme.caption, maxLines: 1, overflow: TextOverflow.ellipsis),
        ]),
      );
}

class _NidTile extends StatelessWidget {
  const _NidTile({required this.label, required this.bytes, required this.onTap});
  final String label;
  final Uint8List? bytes;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final has = bytes != null;
    return InfraCard(
      onTap: onTap,
      padding: const EdgeInsets.all(AppTheme.s12),
      borderColor: has ? AppTheme.gotGreen.withValues(alpha: 0.5) : null,
      child: Row(children: [
        SizedBox(
          width: 96,
          child: AspectRatio(
            aspectRatio: 1.586,
            child: Container(
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: AppTheme.sand,
                borderRadius: BorderRadius.circular(AppTheme.radiusSm),
              ),
              child: has
                  ? Image.memory(bytes!, fit: BoxFit.cover)
                  : const Icon(Icons.credit_card_outlined, color: AppTheme.inkHint, size: 28),
            ),
          ),
        ),
        const SizedBox(width: AppTheme.s12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: AppTheme.bodyStrong),
            const SizedBox(height: 4),
            Text(has ? 'ছবি নেওয়া হয়েছে · আবার তুলতে চাপুন' : 'ছবি তুলতে চাপুন', style: AppTheme.caption),
          ]),
        ),
        Icon(
          has ? Icons.check_circle_rounded : Icons.photo_camera_outlined,
          color: has ? AppTheme.gotGreen : AppTheme.inkMuted,
        ),
      ]),
    );
  }
}

class _Stepper extends StatelessWidget {
  const _Stepper({required this.step, required this.titles});
  final int step;
  final List<String> titles;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppTheme.paper,
      padding: const EdgeInsets.fromLTRB(AppTheme.gutter, AppTheme.s8, AppTheme.gutter, AppTheme.s12),
      child: Column(children: [
        Row(children: [
          for (var i = 0; i < titles.length; i++) ...[
            if (i > 0)
              Expanded(
                child: Container(
                  height: 2,
                  margin: const EdgeInsets.symmetric(horizontal: 6),
                  color: i <= step ? AppTheme.primary : AppTheme.hairline,
                ),
              ),
            Container(
              width: 28,
              height: 28,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: i < step ? AppTheme.primary : (i == step ? AppTheme.primarySoft : AppTheme.sand),
                border: Border.all(color: i <= step ? AppTheme.primary : AppTheme.hairline, width: i == step ? 2 : 1),
              ),
              child: i < step
                  ? const Icon(Icons.check_rounded, size: 16, color: Colors.white)
                  : Text(bn(i + 1), style: AppTheme.label.copyWith(color: i == step ? AppTheme.primary : AppTheme.inkMuted)),
            ),
          ],
        ]),
        const SizedBox(height: AppTheme.s8),
        Row(children: [
          Text('ধাপ ${bn(step + 1)}/${bn(titles.length)}', style: AppTheme.label),
          const SizedBox(width: 8),
          Expanded(child: Text(titles[step], style: AppTheme.bodySmStrong, maxLines: 1, overflow: TextOverflow.ellipsis)),
        ]),
      ]),
    );
  }
}
