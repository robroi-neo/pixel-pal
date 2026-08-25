import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_dimens.dart';
import 'app_tokens.dart';

/// The expense tracker's design system, assembled from style.md.
///
/// Wire it up in `main.dart`:
/// ```dart
/// MaterialApp(theme: AppTheme.light, ...)
/// ```
///
/// To retune the whole app, edit [AppColors] (the palette) or the
/// ColorScheme / component themes below — screens and widgets should
/// never need to change as long as they read colors and text styles from
/// `Theme.of(context)` instead of hardcoding values. That's the whole
/// point: one file to tweak, every screen updates.
class AppTheme {
  AppTheme._();

  // style.md recommends Inter, but as a *bundled* asset font (a `fonts:`
  // block in pubspec.yaml + local .ttf files) — not the google_fonts
  // package's runtime-fetch API. That API downloads the font over the
  // network on first use and caches it to disk via path_provider, which
  // is what crashed (MissingPluginException: getApplicationSupportDirectory).
  // More importantly, the TextStyle objects it returns are `inherit: false`,
  // while every other TextStyle in a default Flutter theme is
  // `inherit: true` — Flutter cannot lerp between the two, which is
  // exactly the "Failed to interpolate TextStyles with different inherit
  // values" crash. It fires the instant anything animates a text style —
  // a TextFormField's floating label, in this case — so it isn't
  // cosmetic, it's a hard crash on any screen with a text field.
  //
  // Until real Inter .ttf files are bundled as assets, this theme uses
  // the platform default font (San Francisco / Roboto / Segoe UI) — the
  // exact offline fallback style.md itself specifies. To switch to Inter
  // later: download the 400 + 500 weight .ttf files into e.g.
  // assets/fonts/, declare them under a `fonts:` block in pubspec.yaml,
  // and set this to 'Inter'.
  static const String? _fontFamily = null;

  static final ColorScheme _colorScheme = ColorScheme.fromSeed(
    seedColor: AppColors.teal600,
    brightness: Brightness.light,
  ).copyWith(
    primary: AppColors.teal600,
    onPrimary: AppColors.white,
    primaryContainer: AppColors.teal50,
    onPrimaryContainer: AppColors.teal800,
    secondary: AppColors.blue600,
    onSecondary: AppColors.white,
    secondaryContainer: AppColors.blue50,
    onSecondaryContainer: AppColors.blue800,
    tertiary: AppColors.teal400,
    onTertiary: AppColors.white,
    error: AppColors.red600,
    onError: AppColors.white,
    errorContainer: AppColors.red50,
    onErrorContainer: AppColors.red600,
    surface: AppColors.white,
    onSurface: AppColors.gray900,
    surfaceContainerHighest: AppColors.gray50,
    onSurfaceVariant: AppColors.gray600,
    outline: AppColors.gray100,
    outlineVariant: AppColors.gray100,
    // Material 3 tints elevated surfaces (cards, app bars) with the
    // primary color by default. style.md calls for flat surfaces and no
    // drop shadows, so we neutralize that tint app-wide here.
    surfaceTint: Colors.transparent,
  );

  static TextTheme _textTheme(ColorScheme scheme) {
    // ThemeData.light().textTheme is fully populated and inherit: true
    // on every slot — the safe, crash-free base to override sizes/weights
    // on top of. .apply() is a no-op here since _fontFamily is null; flip
    // _fontFamily above once Inter is bundled as an asset and this
    // picks it up automatically.
    var base = ThemeData.light().textTheme;
    if (_fontFamily != null) {
      base = base.apply(fontFamily: _fontFamily);
    }
    // style.md: two weights only (400 regular, 500 medium), sentence
    // case everywhere. Sentence case is a copy rule enforced at the call
    // site (the string you pass in), not something a TextTheme controls.
    return base.copyWith(
      // Display — 28sp/500 — the balance figure on the home screen.
      headlineMedium: base.headlineMedium?.copyWith(
        fontSize: 28,
        fontWeight: FontWeight.w500,
        color: scheme.onSurface,
      ),
      // Title — 20sp/500 — screen titles.
      titleLarge: base.titleLarge?.copyWith(
        fontSize: 20,
        fontWeight: FontWeight.w500,
        color: scheme.onSurface,
      ),
      // Heading — 16sp/500 — section headers ("Recent", "This month").
      titleMedium: base.titleMedium?.copyWith(
        fontSize: 16,
        fontWeight: FontWeight.w500,
        color: scheme.onSurface,
      ),
      // Body — 14sp/400 — transaction labels, form values.
      bodyMedium: base.bodyMedium?.copyWith(
        fontSize: 14,
        fontWeight: FontWeight.w400,
        color: scheme.onSurface,
      ),
      // Caption — 12sp/400 — timestamps, hints, subtext.
      bodySmall: base.bodySmall?.copyWith(
        fontSize: 12,
        fontWeight: FontWeight.w400,
        color: AppColors.gray400,
      ),
      // Button labels.
      labelLarge: base.labelLarge?.copyWith(
        fontSize: 14,
        fontWeight: FontWeight.w500,
      ),
    );
  }

  static ThemeData get light {
    final scheme = _colorScheme;
    final textTheme = _textTheme(scheme);

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.gray50,
      textTheme: textTheme,
      fontFamily: _fontFamily,

      // Custom semantic tokens — see app_tokens.dart.
      extensions: const [AppTokens.light],

      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.white,
        foregroundColor: AppColors.gray900,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: textTheme.titleLarge,
        iconTheme: const IconThemeData(
          color: AppColors.gray600,
          size: AppSizes.icon,
        ),
      ),

      // NOTE: renamed CardTheme -> CardThemeData in newer Flutter SDKs.
      // If your SDK predates that split, swap this back to CardTheme —
      // same fields, same values.
      cardTheme: CardThemeData(
        color: AppColors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.cardRadius,
          side: const BorderSide(color: AppColors.gray100, width: 0.5),
        ),
      ),

      dividerTheme: const DividerThemeData(
        color: AppColors.gray100,
        thickness: 0.5,
        space: 0,
      ),

      iconTheme: const IconThemeData(
        color: AppColors.gray600,
        size: AppSizes.icon,
      ),

      // Primary button — teal/600 fill, white text. style.md: avoid more
      // than one primary button per screen (a UI-usage rule, not
      // something the theme enforces).
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.teal600,
          foregroundColor: AppColors.white,
          disabledBackgroundColor: AppColors.gray200,
          disabledForegroundColor: AppColors.gray400,
          minimumSize: const Size.fromHeight(AppSizes.minTouchTarget),
          shape: RoundedRectangleBorder(borderRadius: AppRadius.controlRadius),
          elevation: 0,
          textStyle: textTheme.labelLarge,
        ),
      ),

      // Secondary button — transparent bg, gray/100 border, gray/900 text.
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          backgroundColor: Colors.transparent,
          foregroundColor: AppColors.gray900,
          side: const BorderSide(color: AppColors.gray100),
          minimumSize: const Size.fromHeight(AppSizes.minTouchTarget),
          shape: RoundedRectangleBorder(borderRadius: AppRadius.controlRadius),
          textStyle: textTheme.labelLarge,
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.blue600, // links/info accent
          textStyle: textTheme.labelLarge,
        ),
      ),

      // Inputs — 40dp height, gray/100 border at rest, teal/400 on focus.
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.white,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
        ),
        constraints: const BoxConstraints(minHeight: AppSizes.inputHeight),
        border: OutlineInputBorder(
          borderRadius: AppRadius.controlRadius,
          borderSide: const BorderSide(color: AppColors.gray100),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: AppRadius.controlRadius,
          borderSide: const BorderSide(color: AppColors.gray100),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: AppRadius.controlRadius,
          borderSide: const BorderSide(color: AppColors.teal400, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: AppRadius.controlRadius,
          borderSide: const BorderSide(color: AppColors.red600),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: AppRadius.controlRadius,
          borderSide: const BorderSide(color: AppColors.red600, width: 1.5),
        ),
        hintStyle: textTheme.bodyMedium?.copyWith(color: AppColors.gray400),
      ),

      // Category chips — pill shape, teal/50 bg, teal/800 text.
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.teal50,
        labelStyle: textTheme.bodySmall?.copyWith(
          color: AppColors.teal800,
          fontWeight: FontWeight.w500,
        ),
        side: BorderSide.none,
        shape: const StadiumBorder(),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xs,
        ),
      ),

      // Mic / record button, when built as a FAB — 56dp circle, teal/600
      // fill, white icon. The one element allowed a filled treatment.
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: AppColors.teal600,
        foregroundColor: AppColors.white,
        elevation: 4,
        shape: CircleBorder(),
      ),

      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: AppColors.white,
        selectedItemColor: AppColors.teal600,
        unselectedItemColor: AppColors.gray400,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
        selectedLabelStyle: textTheme.bodySmall,
        unselectedLabelStyle: textTheme.bodySmall,
      ),

      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.gray900,
        contentTextStyle: textTheme.bodyMedium?.copyWith(
          color: AppColors.white,
        ),
        shape: RoundedRectangleBorder(borderRadius: AppRadius.controlRadius),
        behavior: SnackBarBehavior.floating,
      ),

      // 150-200ms ease-out screen transitions, no bouncy/overshoot easing.
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: _CalmPageTransitionsBuilder(),
          TargetPlatform.iOS: _CalmPageTransitionsBuilder(),
          TargetPlatform.windows: _CalmPageTransitionsBuilder(),
          TargetPlatform.macOS: _CalmPageTransitionsBuilder(),
          TargetPlatform.linux: _CalmPageTransitionsBuilder(),
        },
      ),
    );
  }

  // Dark mode is explicitly out of MVP scope per plan_firebase.md. When
  // it's picked up: invert the neutral ramp, swap teal/600 -> teal/400 as
  // the dark-mode primary (lighter, more saturated, for contrast against
  // a dark background), keep expense text on gray/100 rather than pure
  // white, and add a matching AppTokens.dark in app_tokens.dart.
  // static ThemeData get dark => ...
}

class _CalmPageTransitionsBuilder extends PageTransitionsBuilder {
  const _CalmPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final curved = CurvedAnimation(parent: animation, curve: AppMotion.curve);
    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.02),
          end: Offset.zero,
        ).animate(curved),
        child: child,
      ),
    );
  }
}
