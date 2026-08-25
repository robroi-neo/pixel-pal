import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Design tokens that don't have a natural home in Flutter's [ColorScheme]
/// — income/expense semantics, warning/error surface pairs, and the
/// transaction-amount text style. Registered on `ThemeData.extensions` in
/// `app_theme.dart`. Read it like this from any widget:
///
/// ```dart
/// final tokens = Theme.of(context).extension<AppTokens>()!;
/// Text('+ ₱400', style: tokens.amount.copyWith(color: tokens.income));
/// ```
///
/// Being a real `ThemeExtension` (not just a static class) means it lerps
/// correctly if this app ever animates between themes, and it's the right
/// place to add `AppTokens.dark` later without touching call sites.
@immutable
class AppTokens extends ThemeExtension<AppTokens> {
  const AppTokens({
    required this.income,
    required this.expense,
    required this.warningBg,
    required this.warningFg,
    required this.errorBg,
    required this.errorFg,
    required this.chipBg,
    required this.chipFg,
    required this.hairline,
    required this.iconMuted,
    required this.iconActive,
    required this.amount,
  });

  /// Income amounts only.
  final Color income;

  /// Regular expense amounts. Deliberately neutral (gray/900), **not red**
  /// — see style.md: coloring every grocery run red makes the whole feed
  /// read as a wall of alarms by day 2. Red is reserved for real errors.
  final Color expense;

  final Color warningBg;
  final Color warningFg;
  final Color errorBg;
  final Color errorFg;

  /// Category chip fill/text (pill shape).
  final Color chipBg;
  final Color chipFg;

  /// 0.5dp row dividers — rows separate with hairlines, not shadows.
  final Color hairline;

  final Color iconMuted;
  final Color iconActive;

  /// Transaction row amount — 15sp/500. The one text role in style.md
  /// that doesn't map cleanly onto Flutter's standard TextTheme slots.
  final TextStyle amount;

  static const light = AppTokens(
    income: AppColors.teal600,
    expense: AppColors.gray900,
    warningBg: AppColors.amber50,
    warningFg: AppColors.amber600,
    errorBg: AppColors.red50,
    errorFg: AppColors.red600,
    chipBg: AppColors.teal50,
    chipFg: AppColors.teal800,
    hairline: AppColors.gray100,
    iconMuted: AppColors.gray600,
    iconActive: AppColors.teal600,
    amount: TextStyle(
      fontSize: 15,
      fontWeight: FontWeight.w500,
      color: AppColors.gray900,
    ),
  );

  @override
  AppTokens copyWith({
    Color? income,
    Color? expense,
    Color? warningBg,
    Color? warningFg,
    Color? errorBg,
    Color? errorFg,
    Color? chipBg,
    Color? chipFg,
    Color? hairline,
    Color? iconMuted,
    Color? iconActive,
    TextStyle? amount,
  }) {
    return AppTokens(
      income: income ?? this.income,
      expense: expense ?? this.expense,
      warningBg: warningBg ?? this.warningBg,
      warningFg: warningFg ?? this.warningFg,
      errorBg: errorBg ?? this.errorBg,
      errorFg: errorFg ?? this.errorFg,
      chipBg: chipBg ?? this.chipBg,
      chipFg: chipFg ?? this.chipFg,
      hairline: hairline ?? this.hairline,
      iconMuted: iconMuted ?? this.iconMuted,
      iconActive: iconActive ?? this.iconActive,
      amount: amount ?? this.amount,
    );
  }

  @override
  AppTokens lerp(ThemeExtension<AppTokens>? other, double t) {
    if (other is! AppTokens) return this;
    return AppTokens(
      income: Color.lerp(income, other.income, t)!,
      expense: Color.lerp(expense, other.expense, t)!,
      warningBg: Color.lerp(warningBg, other.warningBg, t)!,
      warningFg: Color.lerp(warningFg, other.warningFg, t)!,
      errorBg: Color.lerp(errorBg, other.errorBg, t)!,
      errorFg: Color.lerp(errorFg, other.errorFg, t)!,
      chipBg: Color.lerp(chipBg, other.chipBg, t)!,
      chipFg: Color.lerp(chipFg, other.chipFg, t)!,
      hairline: Color.lerp(hairline, other.hairline, t)!,
      iconMuted: Color.lerp(iconMuted, other.iconMuted, t)!,
      iconActive: Color.lerp(iconActive, other.iconActive, t)!,
      amount: TextStyle.lerp(amount, other.amount, t)!,
    );
  }
}
