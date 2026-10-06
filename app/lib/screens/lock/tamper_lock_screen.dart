import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/app_config.dart';
import '../../core/security/security_gate.dart';
import '../../core/theme/app_theme.dart';
import '../../widgets/infra_widgets.dart';

/// Full-screen lock shown when tamper checks fail or the server locked
/// this device. Nothing else in the app is reachable until an 8-digit
/// admin unlock code is accepted.
class TamperLockScreen extends StatefulWidget {
  const TamperLockScreen({super.key});

  @override
  State<TamperLockScreen> createState() => _TamperLockScreenState();
}

class _TamperLockScreenState extends State<TamperLockScreen> {
  final _code = TextEditingController();
  final _focus = FocusNode();
  bool _busy = false;
  String? _error;

  static const _bg = Color(0xFF0B1A12);
  static const _panel = Color(0xFF13261B);
  static const _accent = Color(0xFFEF4444); // warning icon only
  static const _action = Color(0xFF10B981);
  static const _warnText = Color(0xFFFCD34D);

  @override
  void dispose() {
    _code.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _unlock() async {
    final gate = context.read<SecurityGate>();
    setState(() {
      _busy = true;
      _error = null;
    });
    final err = await gate.submitUnlockCode(_code.text);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = err;
    });
    if (err == null) {
      showSnack(context, 'আনলক সফল হয়েছে।');
    } else {
      _code.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    final gate = context.watch<SecurityGate>();
    final requestId = gate.unlockRequestId;
    final digits = _code.text.replaceAll(RegExp(r'\D'), '');

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: _bg,
      ),
      child: Scaffold(
        backgroundColor: _bg,
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 28, 24, 32),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: Column(
                  children: [
                    _ShieldMark(accent: _accent),
                    const SizedBox(height: 24),
                    Text(
                      'নিরাপত্তা জনিত কারণে\nঅ্যাপটি লক করা হয়েছে',
                      textAlign: TextAlign.center,
                      style: AppTheme.headline.copyWith(color: Colors.white, height: 1.3),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                            color: Colors.white.withValues(alpha: 0.14)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.gpp_bad_rounded,
                              size: 16, color: _accent),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              gate.lockReasonBn,
                              textAlign: TextAlign.center,
                              style: AppTheme.bodySm.copyWith(color: Colors.white),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 28),

                    // ---- Request code card ----
                    _Panel(
                      color: _panel,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'রিকোয়েস্ট কোড',
                            style: AppTheme.sectionHeader.copyWith(color: Colors.white.withValues(alpha: 0.6)),
                          ),
                          const SizedBox(height: 10),
                          if (requestId != null)
                            Row(
                              children: [
                                Expanded(
                                  child: SelectableText(
                                    requestId,
                                    style: AppTheme.display.copyWith(color: Colors.white, letterSpacing: 2, fontFeatures: AppTheme.tabular),
                                  ),
                                ),
                                IconButton.filledTonal(
                                  style: IconButton.styleFrom(
                                    backgroundColor:
                                        Colors.white.withValues(alpha: 0.1),
                                    foregroundColor: Colors.white,
                                  ),
                                  tooltip: 'কপি করুন',
                                  onPressed: () async {
                                    await Clipboard.setData(
                                        ClipboardData(text: requestId));
                                    if (context.mounted) {
                                      showSnack(context, 'কোড কপি হয়েছে');
                                    }
                                  },
                                  icon: const Icon(Icons.copy_rounded),
                                ),
                              ],
                            )
                          else
                            Row(
                              children: [
                                if (gate.isReporting)
                                  const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2, color: Colors.white),
                                  )
                                else
                                  const Icon(Icons.cloud_off_rounded,
                                      color: Colors.white70),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    gate.isReporting
                                        ? 'সার্ভারে রিপোর্ট পাঠানো হচ্ছে…'
                                        : (gate.lastError ??
                                            'কোড পেতে ইন্টারনেট সংযোগ দরকার।'),
                                    style: AppTheme.bodySm.copyWith(color: Colors.white, height: 1.4),
                                  ),
                                ),
                              ],
                            ),
                          const SizedBox(height: 16),
                          Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.06),
                              borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Icon(Icons.support_agent_outlined,
                                    color: Colors.white70, size: 20),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    'উপরের কোডটি জানিয়ে সাপোর্টে কল করুন। '
                                    'যাচাইয়ের পর আপনাকে ৮ সংখ্যার আনলক কোড দেওয়া হবে।\n'
                                    'সাপোর্ট: ${bn(AppConfig.supportPhone)}',
                                    style: AppTheme.bodySm.copyWith(color: Colors.white70, height: 1.5),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 14),
                          Row(
                            children: [
                              Expanded(
                                child: BigButton(
                                  label: 'সাপোর্টে কল',
                                  icon: Icons.call_outlined,
                                  color: _action,
                                  onPressed: callSupport,
                                ),
                              ),
                              if (requestId == null) ...[
                                const SizedBox(width: 10),
                                Expanded(
                                  child: BigButton(
                                    label: 'আবার পাঠান',
                                    icon: Icons.refresh_rounded,
                                    color: Colors.white,
                                    foreground: Colors.white,
                                    outlined: true,
                                    loading: gate.isReporting,
                                    onPressed: () => gate.reportToServer(),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),

                    // ---- Unlock code entry ----
                    _Panel(
                      color: _panel,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'আনলক কোড দিন',
                            style: AppTheme.title.copyWith(color: Colors.white),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'সাপোর্ট থেকে পাওয়া ৮ সংখ্যার কোড',
                            style: AppTheme.bodySm.copyWith(color: Colors.white.withValues(alpha: 0.6)),
                          ),
                          const SizedBox(height: 18),
                          GestureDetector(
                            onTap: () => _focus.requestFocus(),
                            child: Stack(
                              children: [
                                _PinBoxes(
                                  digits: digits,
                                  focused: _focus.hasFocus,
                                  accent: _action,
                                ),
                                // Invisible real text field capturing input.
                                Opacity(
                                  opacity: 0,
                                  child: SizedBox(
                                    height: 56,
                                    child: TextField(
                                      controller: _code,
                                      focusNode: _focus,
                                      scrollPadding: const EdgeInsets.only(bottom: 120),
                                      keyboardType: TextInputType.number,
                                      maxLength: 8,
                                      autofocus: false,
                                      enableInteractiveSelection: false,
                                      showCursor: false,
                                      inputFormatters: [
                                        FilteringTextInputFormatter.digitsOnly
                                      ],
                                      onChanged: (_) => setState(() {}),
                                      onSubmitted: (_) => _unlock(),
                                      decoration: const InputDecoration(
                                          counterText: '',
                                          border: InputBorder.none),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          AnimatedSize(
                            duration: const Duration(milliseconds: 200),
                            child: _error == null
                                ? const SizedBox(height: 18)
                                : Padding(
                                    padding: const EdgeInsets.only(
                                        top: 14, bottom: 8),
                                    child: Row(
                                      children: [
                                        const Icon(Icons.error_outline_rounded,
                                            color: _warnText, size: 18),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            _error!,
                                            style: const TextStyle(
                                                color: _warnText,
                                                fontWeight: FontWeight.w600),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                          ),
                          BigButton(
                            label: 'আনলক করুন',
                            color: _action,
                            loading: _busy || gate.isUnlocking,
                            onPressed: digits.length == 8 ? _unlock : null,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 22),
                    Text(
                      'আপনার হিসাবের তথ্য ফোনে নিরাপদে আছে — আনলকের পর আগের মতোই পাবেন।',
                      textAlign: TextAlign.center,
                      style: AppTheme.caption.copyWith(color: Colors.white.withValues(alpha: 0.5), height: 1.4),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.child, required this.color});
  final Widget child;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppTheme.s16),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: child,
    );
  }
}

class _ShieldMark extends StatelessWidget {
  const _ShieldMark({required this.accent});
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Icon(Icons.gpp_maybe_outlined, size: 56, color: accent);
  }
}

class _PinBoxes extends StatelessWidget {
  const _PinBoxes({
    required this.digits,
    required this.focused,
    required this.accent,
  });
  final String digits;
  final bool focused;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(8, (i) {
        final filled = i < digits.length;
        final active = focused && i == digits.length;
        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(right: i == 7 ? 0 : 6),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              height: 56,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: filled ? 0.14 : 0.06),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: active
                      ? accent
                      : Colors.white.withValues(alpha: filled ? 0.35 : 0.12),
                  width: active ? 2 : 1,
                ),
              ),
              alignment: Alignment.center,
              child: Text(
                filled ? bn(digits[i]) : '',
                style: AppTheme.headline.copyWith(color: Colors.white, fontFeatures: AppTheme.tabular),
              ),
            ),
          ),
        );
      }),
    );
  }
}
