import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'core/app_config.dart';
import 'core/demo/demo_mode.dart';
import 'core/notifications/notification_service.dart';
import 'core/security/security_gate.dart';
import 'core/theme/app_theme.dart';
import 'providers/auth_provider.dart';
import 'providers/billing_provider.dart';
import 'providers/cash_drawer_provider.dart';
import 'providers/ledger_provider.dart';
import 'providers/license_provider.dart';
import 'providers/products_provider.dart';
import 'providers/reports_provider.dart';
import 'providers/shop_settings_provider.dart';
import 'screens/auth/login_screen.dart';
import 'screens/home_navigation_screen.dart';
import 'screens/lock/paywall_screen.dart';
import 'screens/lock/pending_verification_screen.dart';
import 'screens/lock/rejected_screen.dart';
import 'screens/lock/tamper_lock_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarIconBrightness: Brightness.dark,
  ));
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  try {
    if (DemoMode.enabled) {
      await DemoMode.ensureSeeded();
    } else {
      await DemoMode.purgeLeftovers();
    }
  } catch (_) {}
  runApp(const DukandarApp());
  // Deferred: nothing below is needed for the first frame.
  WidgetsBinding.instance.addPostFrameCallback((_) {
    Future.microtask(() async {
      try {
        await NotificationService.instance.init();
      } catch (_) {
        // Notifications are optional; never block startup.
      }
    });
  });
}

class DukandarApp extends StatelessWidget {
  const DukandarApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        // Checks run after the first frame; the cached lock state (if any)
        // is shown immediately by AppGate.
        ChangeNotifierProvider(create: (_) {
          final gate = SecurityGate();
          WidgetsBinding.instance.addPostFrameCallback((_) => gate.runChecks());
          return gate;
        }),
        ChangeNotifierProvider(create: (_) => LicenseProvider()),
        ChangeNotifierProvider(create: (_) => AuthProvider()..bootstrap()),
        ChangeNotifierProvider(create: (_) => ShopSettingsProvider()),
        ChangeNotifierProvider(create: (_) => LedgerProvider()),
        ChangeNotifierProvider(create: (_) => BillingProvider()),
        ChangeNotifierProvider(create: (_) => CashDrawerProvider()),
        ChangeNotifierProvider.value(value: ProductsProvider.instance),
        ChangeNotifierProvider.value(value: ReportsProvider.instance),
      ],
      child: MaterialApp(
        title: 'দোকানদার',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        // System font scaling is honoured but clamped so Bangla labels never
        // blow out of their rows on "huge text" settings.
        builder: (context, child) {
          final mq = MediaQuery.of(context);
          final scale = mq.textScaler.scale(1).clamp(0.9, 1.2);
          Widget body = MediaQuery(
            data: mq.copyWith(textScaler: TextScaler.linear(scale)),
            child: child ?? const SizedBox.shrink(),
          );
          if (AppConfig.isDemo) {
            body = Banner(
              message: 'DEMO',
              location: BannerLocation.topEnd,
              color: const Color(0xFFD97706),
              child: body,
            );
          }
          return body;
        },
        home: const AppGate(),
      ),
    );
  }
}

/// Root decision: tamper lock > login > KYC pending/rejected >
/// subscription paywall > main app.
class AppGate extends StatelessWidget {
  const AppGate({super.key});

  @override
  Widget build(BuildContext context) {
    final security = context.watch<SecurityGate>();
    final auth = context.watch<AuthProvider>();
    final license = context.watch<LicenseProvider>();

    if (security.isLocked) return const TamperLockScreen();
    if (auth.isBootstrapping) return const _SplashLoading();
    if (!auth.isLoggedIn) return const LoginScreen();
    if (!AppConfig.isDemo) {
      if (license.isPendingVerification) return const PendingVerificationScreen();
      if (license.isRejected) return const RejectedScreen();
    }
    if (license.isBlocked) return const PaywallScreen();
    // Seed the local shop profile from the server account on first run.
    final settings = context.read<ShopSettingsProvider>();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      settings.prefillFromAuth(
        shopName: auth.shopName,
        ownerName: auth.ownerName,
        phone: auth.phone,
      );
    });
    return const HomeNavigationScreen();
  }
}

class _SplashLoading extends StatelessWidget {
  const _SplashLoading();
  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: CircularProgressIndicator()));
}
