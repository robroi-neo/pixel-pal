import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_colors.dart';

/// Design tokens Design.md specifies that don't have a natural home in
/// Flutter's [ColorScheme] — the error banner surface, the "attention"
/// chip fill (ink fill + accent text, per §3 "Chip"), the hard offset
/// shadow (§2, "Shadow means 'this needs you'" — §4), and the Silkscreen
/// numeral style reserved for scores only (§4, "The UI must not be
/// pixelated"). Registered on `ThemeData.extensions` in `app_theme.dart`.
///
/// Read it like this from any widget:
/// ```dart
/// final tokens = Theme.of(context).extension<AppTokens>()!;
/// Container(decoration: BoxDecoration(boxShadow: tokens.hardShadow));
/// ```
///
/// Built per-accent by [AppTokens.build] rather than a single fixed
/// constant, since [chipFg] tracks the app's changeable accent color
/// (see `app_accent.dart`) — everywhere else Design.md's "yellow" role
/// shows up as text/foreground rather than the screen background.
@immutable
class AppTokens extends ThemeExtension<AppTokens> {
  const AppTokens({
    required this.errorBg,
    required this.errorFg,
    required this.chipBg,
    required this.chipFg,
    required this.scoreNumeral,
    required this.hardShadow,
  });

  /// Inline error banner fill — neutral, per Design.md §2: `error` is
  /// reserved for text only, "never a deadline, never a score" and never
  /// a flush background either.
  final Color errorBg;

  /// Inline error banner / validation text.
  final Color errorFg;

  /// "Attention" chip fill — ink, per §3 ("Ink fill with yellow text =
  /// attention").
  final Color chipBg;

  /// "Attention" chip text — tracks the current accent color.
  final Color chipFg;

  /// Score numerals only (ranks, points, multipliers) — Silkscreen 400,
  /// per §2 "Type" and §4 "The UI must not be pixelated". Nothing else in
  /// the app should use this style.
  final TextStyle scoreNumeral;

  /// The one hard offset shadow in the system — `4px 4px 0 ink`, never
  /// blurred. Apply it only to the card/tile that needs the user's
  /// action; settled surfaces stay flat (§4, "Shadow is a call to action,
  /// not decoration").
  final List<BoxShadow> hardShadow;

  static AppTokens build(Color accent) {
    return AppTokens(
      errorBg: AppColors.white,
      errorFg: AppColors.error,
      chipBg: AppColors.ink,
      chipFg: accent,
      scoreNumeral: GoogleFonts.silkscreen(
        fontSize: 19,
        fontWeight: FontWeight.w400,
        color: AppColors.ink,
      ),
      hardShadow: const [
        BoxShadow(color: AppColors.ink, offset: Offset(4, 4), blurRadius: 0),
      ],
    );
  }

  @override
  AppTokens copyWith({
    Color? errorBg,
    Color? errorFg,
    Color? chipBg,
    Color? chipFg,
    TextStyle? scoreNumeral,
    List<BoxShadow>? hardShadow,
  }) {
    return AppTokens(
      errorBg: errorBg ?? this.errorBg,
      errorFg: errorFg ?? this.errorFg,
      chipBg: chipBg ?? this.chipBg,
      chipFg: chipFg ?? this.chipFg,
      scoreNumeral: scoreNumeral ?? this.scoreNumeral,
      hardShadow: hardShadow ?? this.hardShadow,
    );
  }

  @override
  AppTokens lerp(ThemeExtension<AppTokens>? other, double t) {
    if (other is! AppTokens) return this;
    return AppTokens(
      errorBg: Color.lerp(errorBg, other.errorBg, t)!,
      errorFg: Color.lerp(errorFg, other.errorFg, t)!,
      chipBg: Color.lerp(chipBg, other.chipBg, t)!,
      chipFg: Color.lerp(chipFg, other.chipFg, t)!,
      scoreNumeral: TextStyle.lerp(scoreNumeral, other.scoreNumeral, t)!,
      // Hard offset shadows are a fixed design constant, not something
      // that's ever mid-transition — snap rather than interpolate.
      hardShadow: t < 0.5 ? hardShadow : other.hardShadow,
    );
  }
}
