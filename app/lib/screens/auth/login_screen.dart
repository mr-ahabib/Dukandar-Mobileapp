import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/app_config.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/common_widgets.dart' show AppListRow, ListGroup;
import '../../widgets/infra_widgets.dart';
import 'register/register_flow_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _phone = TextEditingController();
  final _password = TextEditingController();
  final _passwordFocus = FocusNode();
  bool _obscure = true;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _phone.dispose();
    _password.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final err = await context
        .read<AuthProvider>()
        .login(_phone.text.trim(), _password.text);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = err;
    });
  }

  void _showServerInfo() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.9),
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(24, 0, 24, MediaQuery.viewInsetsOf(ctx).bottom + 32),
          child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('সার্ভার তথ্য', style: AppTheme.title),
            const SizedBox(height: 12),
            CopyRow(
              label: 'API Base URL',
              value: AppConfig.baseUrl,
              icon: Icons.dns_outlined,
              monospace: false,
            ),
            const Divider(),
            CopyRow(
              label: 'Expected signature',
              value: AppConfig.expectedSignatureSha256.isEmpty
                  ? '(not set – debug)'
                  : AppConfig.expectedSignatureSha256,
              icon: Icons.verified_user_outlined,
              monospace: false,
            ),
          ],
        ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: Stack(
        children: [
          // Dark header panel: logo + title always sit inside it.
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              height: size.height * 0.40,
              decoration: const BoxDecoration(
                borderRadius: BorderRadius.vertical(bottom: Radius.circular(AppTheme.radiusXl)),
                gradient: AppTheme.heroGradient,
              ),
            ),
          ),
          SafeArea(
            child: Align(
              alignment: Alignment.topCenter,
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 440),
                  child: Column(
                    children: [
                      SizedBox(height: size.height * 0.04),
                      GestureDetector(
                        onLongPress: _showServerInfo,
                        child: const _LogoMark(),
                      ),
                      const SizedBox(height: 18),
                      Text(
                        'দোকানদার',
                        style: AppTheme.display.copyWith(color: Colors.white),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'আপনার দোকানের বাকি-খাতা, বিল ও হিসাব — এক অ্যাপে',
                        textAlign: TextAlign.center,
                        style: AppTheme.bodySm.copyWith(color: Colors.white.withValues(alpha: 0.8), height: 1.4),
                      ),
                      const SizedBox(height: 32),
                      InfraCard(
                        padding: const EdgeInsets.all(20),
                        child: Form(
                          key: _formKey,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('লগইন করুন', style: AppTheme.headline),
                              const SizedBox(height: 4),
                              Text(
                                'দোকানের ফোন নম্বর ও পাসওয়ার্ড দিন',
                                style: AppTheme.bodySm.copyWith(color: AppTheme.slateMuted),
                              ),
                              const SizedBox(height: 20),
                              TextFormField(
                                controller: _phone,
                                scrollPadding: const EdgeInsets.only(bottom: 120),
                                keyboardType: TextInputType.phone,
                                textInputAction: TextInputAction.next,
                                autofillHints: const [AutofillHints.telephoneNumber],
                                inputFormatters: [
                                  FilteringTextInputFormatter.allow(
                                      RegExp(r'[0-9+\- ]')),
                                ],
                                style: AppTheme.body.copyWith(fontFeatures: AppTheme.tabular),
                                decoration: const InputDecoration(
                                  labelText: 'দোকানের ফোন নম্বর',
                                  hintText: '01XXXXXXXXX',
                                  prefixIcon: Icon(Icons.phone_outlined),
                                ),
                                validator: (v) {
                                  final s = (v ?? '').replaceAll(RegExp(r'\D'), '');
                                  if (s.length < 11) return 'সঠিক ফোন নম্বর দিন';
                                  return null;
                                },
                                onFieldSubmitted: (_) =>
                                    _passwordFocus.requestFocus(),
                              ),
                              const SizedBox(height: 14),
                              TextFormField(
                                controller: _password,
                                focusNode: _passwordFocus,
                                scrollPadding: const EdgeInsets.only(bottom: 120),
                                obscureText: _obscure,
                                textInputAction: TextInputAction.done,
                                autofillHints: const [AutofillHints.password],
                                style: AppTheme.body,
                                decoration: InputDecoration(
                                  labelText: 'পাসওয়ার্ড',
                                  prefixIcon: const Icon(Icons.lock_outline_rounded),
                                  suffixIcon: IconButton(
                                    tooltip: _obscure ? 'দেখুন' : 'লুকান',
                                    icon: Icon(_obscure
                                        ? Icons.visibility_outlined
                                        : Icons.visibility_off_outlined),
                                    onPressed: () =>
                                        setState(() => _obscure = !_obscure),
                                  ),
                                ),
                                validator: (v) => (v == null || v.isEmpty)
                                    ? 'পাসওয়ার্ড দিন'
                                    : null,
                                onFieldSubmitted: (_) => _submit(),
                              ),
                              AnimatedSize(
                                duration: const Duration(milliseconds: 220),
                                curve: Curves.easeOut,
                                child: _error == null
                                    ? const SizedBox(height: 20)
                                    : Padding(
                                        padding:
                                            const EdgeInsets.only(top: 14, bottom: 6),
                                        child: Row(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            const Icon(Icons.error_outline_rounded, color: AppTheme.gaveRed, size: 20),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: Text(
                                                _error!,
                                                style: AppTheme.bodySm.copyWith(color: AppTheme.gaveRed, height: 1.35),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                              ),
                              BigButton(
                                label: 'লগইন',
                                loading: _busy,
                                onPressed: _submit,
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      BigButton(
                        label: 'নতুন অ্যাকাউন্ট খুলুন',
                        icon: Icons.person_add_alt_1_outlined,
                        outlined: true,
                        onPressed: _busy
                            ? null
                            : () => Navigator.of(context).push(
                                  MaterialPageRoute(builder: (_) => const RegisterFlowScreen()),
                                ),
                      ),
                      const SizedBox(height: 14),
                      ListGroup(children: [
                        AppListRow(
                          onTap: callSupport,
                          leading: const Icon(Icons.support_agent_outlined, color: AppTheme.inkMuted, size: 22),
                          title: 'সমস্যা হচ্ছে? আমাদের কল করুন',
                          subtitle: bn(AppConfig.supportPhone),
                          trailing: const Icon(Icons.call_outlined, color: AppTheme.inkMuted, size: 22),
                        ),
                      ]),
                      const SizedBox(height: 24),
                      Text(
                        'আপনার হিসাবের সব তথ্য শুধু আপনার ফোনেই থাকে',
                        textAlign: TextAlign.center,
                        style: AppTheme.caption,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LogoMark extends StatelessWidget {
  const _LogoMark();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 80,
      height: 80,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white,
      ),
      child: ClipOval(
        child: Image.asset(
          'assets/icon/app_icon.png',
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => const Icon(
            Icons.storefront_rounded,
            size: 40,
            color: AppTheme.navy,
          ),
        ),
      ),
    );
  }
}
