import 'package:flutter/material.dart';

/// Dukandar design system — clean, minimal, professional green.
///
/// Deep green for the two hero headers (home, login), near-white background,
/// flat white cards with a 1px hairline, emerald for money in, a soft red used
/// sparingly for dues, amber only for small badges. Radii 16–20.
class AppTheme {
  AppTheme._();

  // Brand palette (names kept for compatibility; values are the green system)
  static const Color navy = Color(0xFF14532D); // deep green
  static const Color indigo = Color(0xFF166534); // primary mid green
  static const Color indigoMid = Color(0xFF15803D); // green-700
  static const Color indigoSoft = Color(0xFFECFDF5); // mint tint

  static const Color cream = Color(0xFFF7FAF8); // near-white background
  static const Color paper = Color(0xFFFFFFFF);
  static const Color hairline = Color(0xFFE5EBE7);
  static const Color sand = Color(0xFFF1F5F2); // muted surface

  static const Color saffron = Color(0xFFD97706); // amber — small badges only
  static const Color saffronDeep = Color(0xFFB45309);
  static const Color saffronSoft = Color(0xFFFFFBEB);

  static const Color emerald = Color(0xFF059669); // money in
  static const Color emeraldDeep = Color(0xFF047857);
  static const Color emeraldSoft = Color(0xFFECFDF5);

  static const Color coral = Color(0xFFDC2626); // money out / due — sparingly
  static const Color coralDeep = Color(0xFFB91C1C);
  static const Color coralSoft = Color(0xFFFEF2F2);

  static const Color ink = Color(0xFF0F1F17);
  static const Color inkMuted = Color(0xFF5B6B62);
  static const Color inkHint = Color(0xFF9AA8A0);

  /// Accent emerald (CTA highlights, selected states on dark surfaces).
  static const Color accentEmerald = Color(0xFF10B981);
  static const Color slate = Color(0xFF64748B); // neutral chart series

  // Semantic aliases
  static const Color primary = indigo;
  static const Color primaryDeep = navy;
  static const Color primarySoft = indigoSoft;
  static const Color accent = accentEmerald;
  static const Color accentSoft = emeraldSoft;
  static const Color success = emerald;
  static const Color successSoft = emeraldSoft;
  static const Color danger = coral;
  static const Color dangerSoft = coralSoft;
  static const Color warning = saffron;
  static const Color warningSoft = saffronSoft;
  static const Color info = indigoMid;
  static const Color infoSoft = indigoSoft;
  static const Color textPrimary = ink;
  static const Color textSecondary = inkMuted;
  static const Color textHint = inkHint;
  static const Color surfaceTint = sand;
  static const Color surfaceMuted = sand;

  // Legacy names (kept – referenced across the codebase)
  static const Color slateDark = ink;
  static const Color slateMuted = inkMuted;
  static const Color background = cream;
  static const Color surface = paper;
  static const Color border = hairline;
  static const Color gaveRed = coral;
  static const Color gaveRedLight = coralSoft;
  static const Color gotGreen = emerald;
  static const Color gotGreenLight = emeraldSoft;
  static const Color primaryBlue = indigo;
  static const Color primaryBlueLight = indigoSoft;

  // Gradients — only the home / login header should use one.
  static const LinearGradient brandGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [navy, indigo],
  );
  static const LinearGradient heroGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF14532D), Color(0xFF166534)],
  );
  static const LinearGradient saffronGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF10B981), Color(0xFF059669)],
  );
  static const LinearGradient emeraldGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF10B981), Color(0xFF047857)],
  );

  // Soft palette for avatars (deterministic by name hash) — calm greens/neutrals
  static const List<Color> pastels = [
    Color(0xFFDCFCE7), Color(0xFFD1FAE5), Color(0xFFE2E8F0), Color(0xFFFEF3C7),
    Color(0xFFCCFBF1), Color(0xFFE5E7EB), Color(0xFFECFCCB), Color(0xFFE0F2FE),
  ];
  static const List<Color> pastelInks = [
    Color(0xFF166534), Color(0xFF047857), Color(0xFF475569), Color(0xFFB45309),
    Color(0xFF0F766E), Color(0xFF4B5563), Color(0xFF4D7C0F), Color(0xFF0369A1),
  ];

  // Shape & elevation
  static const double radiusSm = 10;
  static const double radiusMd = 12;
  static const double radiusLg = 16;
  static const double radiusXl = 24;

  // Spacing scale (4 / 8 / 12 / 16 / 20 / 24). Every screen uses [gutter]
  // as its horizontal page padding.
  static const double s4 = 4;
  static const double s8 = 8;
  static const double s12 = 12;
  static const double s16 = 16;
  static const double s20 = 20;
  static const double s24 = 24;
  static const double gutter = 16;
  static const EdgeInsets pagePadding = EdgeInsets.symmetric(horizontal: gutter);

  /// Dialogs are capped at this width on tablets; sheets a little wider.
  static const double dialogMaxWidth = 440;
  static const double sheetMaxWidth = 560;
  /// Tablet breakpoint.
  static const double tabletWidth = 600;

  /// Grid columns by available width: 2 on narrow phones, 3 on phones,
  /// 4 on tablets.
  static int gridColumns(double width) => width < 360 ? 2 : (width < tabletWidth ? 3 : 4);

  /// Icon sizes: 20 inside list rows / tinted circles, 24 for actions.
  static const double iconList = 20;
  static const double iconAction = 24;

  /// Only used on the hero card.
  static List<BoxShadow> get heroShadow => [
        BoxShadow(color: navy.withValues(alpha: 0.10), blurRadius: 20, offset: const Offset(0, 8)),
      ];

  /// Barely-there lift for floating elements (nav bar, FAB).
  static List<BoxShadow> get floatShadow => [
        BoxShadow(color: ink.withValues(alpha: 0.06), blurRadius: 16, offset: const Offset(0, 6)),
      ];

  static List<BoxShadow> get softShadow => const [];
  static List<BoxShadow> get liftedShadow => floatShadow;

  // Typography
  /// Bundled font family (see pubspec `fonts:`), with Noto Sans Bengali as a
  /// fallback for any glyph Hind Siliguri lacks. No runtime download.
  static const String fontFamily = 'NotoSansBengali';
  static const List<String> fontFallback = [];

  static TextStyle _hs(double size, FontWeight w, Color c, {double? height, double? ls}) => TextStyle(
        fontFamily: fontFamily,
        fontFamilyFallback: fontFallback,
        fontSize: size,
        fontWeight: w,
        color: c,
        height: height,
        letterSpacing: ls,
      );

  static const List<FontFeature> tabular = [FontFeature.tabularFigures()];

  // The single type scale. Three weights only: w400 body, w600 titles and
  // amounts, w700 for hero amounts / display. No letter-spacing except on
  // the two large amount styles.
  //   display 28 · headline 22 · title 17 · body 15 · bodySm 13 · caption 12 · label 11.5
  //   amountXl 32 · amountLg 24 · amountMd 18 · amountSm 16
  static TextStyle get display => _hs(28, FontWeight.w700, ink, height: 1.15);
  static TextStyle get headline => _hs(22, FontWeight.w600, ink, height: 1.2);
  static TextStyle get title => _hs(17, FontWeight.w600, ink, height: 1.3);
  static TextStyle get body => _hs(15, FontWeight.w400, ink, height: 1.45);
  static TextStyle get bodyStrong => _hs(15, FontWeight.w600, ink, height: 1.45);
  static TextStyle get bodySm => _hs(13, FontWeight.w400, ink, height: 1.4);
  static TextStyle get bodySmStrong => _hs(13, FontWeight.w600, ink, height: 1.4);
  static TextStyle get caption => _hs(12, FontWeight.w400, inkMuted, height: 1.3);
  static TextStyle get label => _hs(11.5, FontWeight.w600, inkMuted);
  /// Section heading: 13px, muted, w600. Used by SectionHeader / SectionTitle.
  static TextStyle get sectionHeader => _hs(13, FontWeight.w600, inkMuted, height: 1.3);
  static TextStyle get amountXl => _hs(32, FontWeight.w700, ink, height: 1.0, ls: -0.8).copyWith(fontFeatures: tabular);
  static TextStyle get amountLg => _hs(24, FontWeight.w700, ink, height: 1.0, ls: -0.5).copyWith(fontFeatures: tabular);
  static TextStyle get amountMd => _hs(18, FontWeight.w600, ink, height: 1.0).copyWith(fontFeatures: tabular);
  static TextStyle get amountSm => _hs(16, FontWeight.w600, ink, height: 1.0).copyWith(fontFeatures: tabular);

  /// Numeric font sizes of the amount scale, for widgets that take a `size`.
  static const double amountXlSize = 32;
  static const double amountLgSize = 24;
  static const double amountMdSize = 18;
  static const double amountSmSize = 16;

  /// Standard control height (buttons, inputs).
  static const double controlHeight = 48;

  /// google_fonts 9 builds its TextTheme against `material_ui`, which is a
  /// different type from Flutter's material TextTheme; map style-by-style.
  static TextTheme _hindSiliguriTheme(TextTheme t) {
    TextStyle? f(TextStyle? s) => s?.copyWith(fontFamily: fontFamily, fontFamilyFallback: fontFallback);
    return TextTheme(
      displayLarge: f(t.displayLarge),
      displayMedium: f(t.displayMedium),
      displaySmall: f(t.displaySmall),
      headlineLarge: f(t.headlineLarge),
      headlineMedium: f(t.headlineMedium),
      headlineSmall: f(t.headlineSmall),
      titleLarge: f(t.titleLarge),
      titleMedium: f(t.titleMedium),
      titleSmall: f(t.titleSmall),
      bodyLarge: f(t.bodyLarge),
      bodyMedium: f(t.bodyMedium),
      bodySmall: f(t.bodySmall),
      labelLarge: f(t.labelLarge),
      labelMedium: f(t.labelMedium),
      labelSmall: f(t.labelSmall),
    );
  }

  static ThemeData get lightTheme {
    final base = ThemeData(useMaterial3: true, brightness: Brightness.light, fontFamily: fontFamily);
    final textTheme = _hindSiliguriTheme(base.textTheme).apply(bodyColor: ink, displayColor: ink);

    const scheme = ColorScheme.light(
      primary: indigo,
      onPrimary: Colors.white,
      primaryContainer: indigoSoft,
      onPrimaryContainer: navy,
      secondary: accentEmerald,
      onSecondary: Colors.white,
      secondaryContainer: emeraldSoft,
      onSecondaryContainer: emeraldDeep,
      tertiary: emerald,
      tertiaryContainer: emeraldSoft,
      onTertiaryContainer: emeraldDeep,
      surface: paper,
      onSurface: ink,
      onSurfaceVariant: inkMuted,
      outline: hairline,
      outlineVariant: hairline,
      error: coral,
      onError: Colors.white,
      errorContainer: coralSoft,
      onErrorContainer: coralDeep,
    );

    RoundedRectangleBorder rr(double r) => RoundedRectangleBorder(borderRadius: BorderRadius.circular(r));
    OutlineInputBorder ob(Color c, [double w = 1]) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(radiusMd), borderSide: BorderSide(color: c, width: w));

    return base.copyWith(
      colorScheme: scheme,
      scaffoldBackgroundColor: cream,
      primaryColor: indigo,
      textTheme: textTheme,
      splashFactory: InkSparkle.splashFactory,
      splashColor: indigo.withValues(alpha: 0.08),
      highlightColor: indigo.withValues(alpha: 0.04),
      appBarTheme: AppBarTheme(
        backgroundColor: cream,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        iconTheme: const IconThemeData(color: ink),
        titleTextStyle: _hs(19, FontWeight.w600, ink),
      ),
      cardTheme: CardThemeData(
        color: paper,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusMd), side: const BorderSide(color: hairline)),
        margin: EdgeInsets.zero,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: paper,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: ob(hairline),
        enabledBorder: ob(hairline),
        focusedBorder: ob(indigo, 1.5),
        errorBorder: ob(coral),
        focusedErrorBorder: ob(coral, 1.5),
        labelStyle: _hs(15, FontWeight.w400, inkMuted),
        hintStyle: _hs(15, FontWeight.w400, inkHint),
        prefixIconColor: inkMuted,
        suffixIconColor: inkMuted,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: indigo,
          foregroundColor: Colors.white,
          disabledBackgroundColor: const Color(0xFFCBD5D0),
          disabledForegroundColor: Colors.white,
          elevation: 0,
          minimumSize: const Size(64, controlHeight),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          shape: rr(radiusMd),
          textStyle: _hs(15, FontWeight.w600, Colors.white),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: indigo,
          foregroundColor: Colors.white,
          minimumSize: const Size(64, controlHeight),
          shape: rr(radiusMd),
          textStyle: _hs(15, FontWeight.w600, Colors.white),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: ink,
          minimumSize: const Size(64, controlHeight),
          side: const BorderSide(color: hairline),
          shape: rr(radiusMd),
          textStyle: _hs(15, FontWeight.w600, ink),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: indigo,
          minimumSize: const Size(48, 44),
          textStyle: _hs(15, FontWeight.w600, indigo),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(style: IconButton.styleFrom(minimumSize: const Size(48, 48))),
      chipTheme: ChipThemeData(
        backgroundColor: paper,
        selectedColor: indigo,
        side: const BorderSide(color: hairline),
        shape: const StadiumBorder(),
        labelStyle: _hs(13, FontWeight.w500, ink),
        secondaryLabelStyle: _hs(13, FontWeight.w600, Colors.white),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        showCheckmark: false,
      ),
      dividerTheme: const DividerThemeData(color: hairline, thickness: 1, space: 1),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        indicatorColor: indigoSoft,
        elevation: 0,
        height: 72,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return _hs(12.5, selected ? FontWeight.w600 : FontWeight.w400, selected ? indigo : inkMuted);
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(color: selected ? indigo : inkMuted, size: 24);
        }),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: paper,
        surfaceTintColor: Colors.transparent,
        showDragHandle: false,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(radiusXl))),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: paper,
        surfaceTintColor: Colors.transparent,
        shape: rr(radiusLg),
        titleTextStyle: _hs(19, FontWeight.w600, ink),
        contentTextStyle: _hs(15, FontWeight.w400, inkMuted, height: 1.5),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: ink,
        behavior: SnackBarBehavior.floating,
        shape: rr(radiusSm),
        contentTextStyle: _hs(14, FontWeight.w400, Colors.white),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: indigo,
        foregroundColor: Colors.white,
        elevation: 0,
        shape: rr(radiusLg),
        extendedTextStyle: _hs(15, FontWeight.w600, Colors.white),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: inkMuted,
        minVerticalPadding: 10,
        titleTextStyle: _hs(15, FontWeight.w600, ink),
        subtitleTextStyle: _hs(13, FontWeight.w400, inkMuted),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.all(Colors.white),
        trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
        trackColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? indigo : const Color(0xFFCBD5D0)),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? indigo : Colors.transparent),
        side: const BorderSide(color: inkHint, width: 1.6),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: indigo,
        unselectedLabelColor: inkMuted,
        indicatorColor: indigo,
        indicatorSize: TabBarIndicatorSize.label,
        dividerColor: Colors.transparent,
        labelStyle: _hs(15, FontWeight.w600, indigo),
        unselectedLabelStyle: _hs(15, FontWeight.w400, inkMuted),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          backgroundColor: paper,
          selectedBackgroundColor: indigo,
          selectedForegroundColor: Colors.white,
          foregroundColor: inkMuted,
          side: const BorderSide(color: hairline),
          textStyle: _hs(14, FontWeight.w600, ink),
          shape: rr(radiusSm),
        ),
      ),
      datePickerTheme: DatePickerThemeData(
          backgroundColor: paper, surfaceTintColor: Colors.transparent, shape: rr(radiusLg)),
      progressIndicatorTheme: const ProgressIndicatorThemeData(color: indigo),
    );
  }
}
