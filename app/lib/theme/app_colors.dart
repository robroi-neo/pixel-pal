import 'package:flutter/material.dart';

/// Raw color palette for Pixel Guess, per Design.md §2 ("Tokens").
///
/// Design.md calls these "the app's palette, not a theme" — every value
/// here except [yellowDefault] is fixed and does not respond to user
/// choice or light/dark mode, ever (`canvas` most of all — see Design.md
/// §4, "the canvas ignores the app theme"). Nothing outside `lib/theme/`
/// should reference these directly; screens and widgets should read colors
/// from `Theme.of(context)` (via [ColorScheme] for chrome, or `AppTokens`
/// for the roles that don't map onto a ColorScheme slot).
///
/// [yellowDefault] is the one exception: it's the starting value for the
/// app's accent color, which is user-changeable (see `app_accent.dart`).
/// Everywhere Design.md calls for "yellow" — screen background, primary
/// button text, avatar initials, the attention chip fill's text — the
/// theme should read the current accent, not this constant directly.
class AppColors {
  AppColors._();

  /// Every border, all body text, filled buttons, avatars.
  static const ink = Color(0xFF17171A);

  /// Design.md's default accent. The accent itself is changeable at
  /// runtime (see [AppAccent] in `app_accent.dart`) — this is only the
  /// seed value new installs start with.
  static const yellowDefault = Color(0xFFFFC93C);

  /// Band behind artwork; secondary/settled card fill.
  static const cream = Color(0xFFFFF6DC);

  /// Card fill.
  static const white = Color(0xFFFFFFFF);

  /// Locked. Empty pixel, in every mode, forever — never theme this.
  /// White, the same as the palette's white swatch: an empty pixel and a
  /// white-painted one look and behave the same (erase, fill, "is the
  /// canvas empty"). Old drawings store empty as a marker, not a colour,
  /// so they pick this up too.
  static const canvas = Color(0xFFFFFFFF);

  /// Inactive and vacation avatars only.
  static const grey = Color(0xFF8A8A94);

  /// Inline form validation text only — never a deadline, never a score.
  static const error = Color(0xFF8A2B2B);
}
