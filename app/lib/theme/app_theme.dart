import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_colors.dart';
import 'app_dimens.dart';
import 'app_tokens.dart';

/// Pixel Guess's design system, assembled from Design.md.
///
/// Wire it up in `main.dart`, rebuilding whenever the accent changes:
/// ```dart
/// ValueListenableBuilder<Color>(
///   valueListenable: AppAccent.notifier,
///   builder: (context, accent, _) =>
///       MaterialApp.router(theme: AppTheme.build(accent), ...),
/// )
/// ```
///
/// Every fixed Design.md token (`ink`, `cream`, `white`, `canvas`, `grey`,
/// `error`) lives in [AppColors] and never changes here. The one thing
/// that does change is [accent] — Design.md's "yellow" role — which this
/// method threads through the screen background, primary button text,
/// avatar initials, and the attention-chip token in [AppTokens]. To retune
/// anything else, edit [AppColors] or the component themes below; screens
/// and widgets should never need to change as long as they read colors
/// and text styles from `Theme.of(context)`.
class AppTheme {
  AppTheme._();

  static TextTheme _textTheme(ColorScheme scheme) {
    final base = ThemeData.light().textTheme;

    // Display — Space Grotesk 700, tight tracking. Screen titles (25–30)
    // and card titles (16–19) per Design.md §2 "Type".
    TextStyle display(TextStyle? style) => GoogleFonts.spaceGrotesk(
      textStyle: style,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.02 * (style?.fontSize ?? 16),
      color: scheme.onSurface,
    );

    // UI — Plus Jakarta Sans, 400/500/600. Body (13–14), secondary (12),
    // caption (10).
    TextStyle ui(TextStyle? style, {FontWeight weight = FontWeight.w400}) =>
        GoogleFonts.plusJakartaSans(
          textStyle: style,
          fontWeight: weight,
          color: scheme.onSurface,
        );

    return base.copyWith(
      // Screen title, 25–30sp.
      headlineMedium: display(base.headlineMedium?.copyWith(fontSize: 28)),
      // Card title, 16–19sp.
      titleLarge: display(base.titleLarge?.copyWith(fontSize: 19)),
      titleMedium: display(base.titleMedium?.copyWith(fontSize: 16)),
      // Body, 13–14sp.
      bodyMedium: ui(
        base.bodyMedium?.copyWith(fontSize: 14),
        weight: FontWeight.w500,
      ),
      // Secondary, 12sp.
      bodySmall: ui(base.bodySmall?.copyWith(fontSize: 12)),
      // Caption, 10sp.
      labelSmall: ui(base.labelSmall?.copyWith(fontSize: 10)),
      // Button labels — Space Grotesk 700/16, per §3 "Primary button".
      labelLarge: display(base.labelLarge?.copyWith(fontSize: 16)),
    );
  }

  static ThemeData build(Color accent) {
    final scheme = ColorScheme.fromSeed(
      seedColor: accent,
      brightness: Brightness.light,
    ).copyWith(
      primary: accent,
      onPrimary: AppColors.ink,
      secondary: AppColors.ink,
      onSecondary: accent,
      error: AppColors.error,
      onError: AppColors.white,
      surface: AppColors.white,
      onSurface: AppColors.ink,
      surfaceContainerHighest: AppColors.cream,
      outline: AppColors.ink,
      outlineVariant: AppColors.ink,
      // Design.md is flat and hard-edged throughout — no Material 3
      // elevation tint on cards/app bars.
      surfaceTint: Colors.transparent,
    );
    final textTheme = _textTheme(scheme);

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: scheme,
      // §2 "Surfaces": screen background is yellow everywhere.
      scaffoldBackgroundColor: accent,
      textTheme: textTheme,

      extensions: [AppTokens.build(accent)],

      appBarTheme: AppBarTheme(
        backgroundColor: accent,
        foregroundColor: AppColors.ink,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: textTheme.headlineMedium,
        iconTheme: const IconThemeData(
          color: AppColors.ink,
          size: AppSizes.icon,
        ),
      ),

      // §3 "Card": white fill, 3px ink border, 14px radius. Shadow is
      // opt-in per widget (AppTokens.hardShadow) — "shadow means this
      // needs you", never a blanket default (§4).
      cardTheme: CardThemeData(
        color: AppColors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.cardRadius,
          side: const BorderSide(color: AppColors.ink, width: AppBorders.thick),
        ),
      ),

      dividerTheme: const DividerThemeData(
        color: AppColors.ink,
        thickness: 1,
        space: 0,
      ),

      iconTheme: const IconThemeData(
        color: AppColors.ink,
        size: AppSizes.icon,
      ),

      // §3 "Primary button": full width, ink fill, accent text, Space
      // Grotesk 700/16. §4: one primary button per screen (a UI-usage
      // rule, not something the theme enforces).
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.ink,
          foregroundColor: accent,
          disabledBackgroundColor: AppColors.grey,
          disabledForegroundColor: AppColors.white,
          minimumSize: const Size.fromHeight(AppSizes.minTouchTarget),
          shape: RoundedRectangleBorder(borderRadius: AppRadius.controlRadius),
          elevation: 0,
          textStyle: textTheme.labelLarge,
        ),
      ),

      // Bordered secondary control, for the rare case an outlined button
      // is needed. §3's actual "secondary action" is an underlined text
      // link — see textButtonTheme below.
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          backgroundColor: Colors.transparent,
          foregroundColor: AppColors.ink,
          side: const BorderSide(
            color: AppColors.ink,
            width: AppBorders.thick,
          ),
          minimumSize: const Size.fromHeight(AppSizes.minTouchTarget),
          shape: RoundedRectangleBorder(borderRadius: AppRadius.controlRadius),
          textStyle: textTheme.labelLarge,
        ),
      ),

      // §3 "Secondary action": underlined text link, 13px/600 — not a
      // button, keeps the single-primary rule honest.
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.ink,
          textStyle: GoogleFonts.plusJakartaSans(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            decoration: TextDecoration.underline,
          ),
        ),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.white,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
        ),
        constraints: const BoxConstraints(minHeight: AppSizes.inputHeight),
        border: OutlineInputBorder(
          borderRadius: AppRadius.controlRadius,
          borderSide: const BorderSide(
            color: AppColors.ink,
            width: AppBorders.thin,
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: AppRadius.controlRadius,
          borderSide: const BorderSide(
            color: AppColors.ink,
            width: AppBorders.thin,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: AppRadius.controlRadius,
          borderSide: const BorderSide(
            color: AppColors.ink,
            width: AppBorders.thick,
          ),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: AppRadius.controlRadius,
          borderSide: const BorderSide(color: AppColors.error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: AppRadius.controlRadius,
          borderSide: const BorderSide(color: AppColors.error, width: 1.5),
        ),
        labelStyle: textTheme.bodyMedium,
        hintStyle: textTheme.bodyMedium?.copyWith(color: AppColors.grey),
      ),

      // §3 "Chip": neutral state — white fill, 2px ink border, 999
      // radius, 11px/600. The ink-fill/accent-text "attention" variant
      // lives in AppTokens.chipBg/chipFg for widgets that need it.
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.white,
        labelStyle: GoogleFonts.plusJakartaSans(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: AppColors.ink,
        ),
        side: const BorderSide(color: AppColors.ink, width: AppBorders.thin),
        shape: const StadiumBorder(),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xs,
        ),
      ),

      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.ink,
        contentTextStyle: textTheme.bodyMedium?.copyWith(
          color: AppColors.cream,
        ),
        shape: RoundedRectangleBorder(borderRadius: AppRadius.controlRadius),
        behavior: SnackBarBehavior.floating,
      ),

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

  // Dark mode is explicitly deferred past v1 per Design.md §6. When it's
  // picked up: `canvas` never changes, the rest of the chrome inverts
  // yellow/ink. Revisit after the palette question in Design.md §7/§8 is
  // settled, since the swatch grid changes answer under an inverted bg.
  // static ThemeData dark(Color accent) => ...
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
