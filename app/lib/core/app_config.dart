/// Central runtime configuration for the Dukandar app.
class AppConfig {
  AppConfig._();

  /// Backend base URL (FastAPI). Change for production deploy.
  static const String baseUrl = String.fromEnvironment(
    'DUKANDAR_API',
    defaultValue: 'https://dukandar.fastapicloud.dev/api/v1',
  );

  /// Expected release signing certificate SHA-256 (hex, lowercase, no colons).
  /// Filled after creating the release keystore. Debug builds skip the check.
  static const String expectedSignatureSha256 = String.fromEnvironment(
    'DUKANDAR_SIG',
    defaultValue: '',
  );

  /// Demo build: no login, no server, seeded sample data (see core/demo/demo_mode.dart).
  static const bool isDemo = bool.fromEnvironment('DUKANDAR_DEMO', defaultValue: false);

  static const int graceDays = 10;
  static const Duration licenseRefreshInterval = Duration(hours: 6);
  static const Duration offlineLicenseTolerance = Duration(days: 7);
  static const String supportPhone = '01700000000';
}
