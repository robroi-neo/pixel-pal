import 'package:flutter/material.dart';

/// Spacing tokens (in logical pixels / dp).
class AppSpacing {
  AppSpacing._();

  static const xs = 4.0; // icon-to-label gap
  static const sm = 8.0; // within a row
  static const md = 12.0; // between rows
  static const lg = 16.0; // card padding, screen margins
  static const xl = 24.0; // between sections
}

/// Corner radius tokens.
class AppRadius {
  AppRadius._();

  static const control = 8.0; // buttons, inputs, chips
  static const card = 12.0; // cards, sheets

  static const controlRadius = BorderRadius.all(Radius.circular(control));
  static const cardRadius = BorderRadius.all(Radius.circular(card));
}

/// Fixed component sizes.
class AppSizes {
  AppSizes._();

  /// Minimum tappable area for any control — buttons, chips, icon buttons.
  static const minTouchTarget = 44.0;

  /// The record/mic button. Never let this shrink below [minTouchTarget],
  /// even under system font scaling.
  static const micButton = 56.0;

  /// Transaction row leading icon chip.
  static const txIconChip = 32.0;

  /// Standard icon size; use [iconMax] only for decorative/large icons.
  static const icon = 20.0;
  static const iconMax = 24.0;

  /// Text input height.
  static const inputHeight = 40.0;
}

/// Motion tokens. Style.md: "minimal and functional only... no
/// bouncy/overshoot easing — keep it calm."
class AppMotion {
  AppMotion._();

  static const duration = Duration(milliseconds: 180);
  static const curve = Curves.easeOut;
}
