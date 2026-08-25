import 'package:flutter/material.dart';

/// Raw color palette for the expense tracker design system.
///
/// This is the single source of truth for every hex value in the app.
/// Nothing outside `lib/theme/` should reference these directly — screens
/// and widgets should read colors from `Theme.of(context)` (via
/// [ColorScheme] for UI chrome, or `AppTokens` for the income/expense/
/// warning/error tokens that don't map onto Material's ColorScheme roles).
/// That indirection is what makes "change the primary teal" a one-line
/// edit here instead of a find-and-replace across the whole app.
///
/// Source: style.md v1 ("Calm & trustworthy" direction), Expense Tracker
/// project.
class AppColors {
  AppColors._();

  // --- Primary — teal --------------------------------------------------
  static const teal50 = Color(0xFFE1F5EE); // icon chip bg, subtle fills
  static const teal100 = Color(0xFF9FE1CB); // hover/pressed fills
  static const teal200 = Color(0xFF5DCAA5); // secondary accents, chart fills
  static const teal400 = Color(0xFF1D9E75); // active states, input focus
  static const teal600 = Color(0xFF0F6E56); // primary buttons, mic, links
  static const teal800 = Color(0xFF085041); // text on teal/50-100 fills
  static const teal900 = Color(0xFF04342C); // text on teal/200+ fills

  // --- Secondary — blue (info/links only) -------------------------------
  static const blue50 = Color(0xFFE6F1FB);
  static const blue600 = Color(0xFF185FA5);
  static const blue800 = Color(0xFF0C447C);

  // --- Neutral — gray (structure) ----------------------------------------
  static const gray50 = Color(0xFFF1EFE8); // app background
  static const gray100 = Color(0xFFD3D1C7); // card borders, dividers
  static const gray200 = Color(0xFFB4B2A9); // disabled fills
  static const gray400 = Color(0xFF888780); // placeholder text, muted icons
  static const gray600 = Color(0xFF5F5E5A); // secondary text
  static const gray900 = Color(0xFF2C2C2A); // primary text
  static const white = Color(0xFFFFFFFF);

  // --- Semantic — use sparingly, only for real signals -------------------
  static const amber50 = Color(0xFFFAEEDA);
  static const amber600 = Color(0xFF854F0B);
  static const red50 = Color(0xFFFCEBEB);
  static const red600 = Color(0xFFA32D2D);
}
