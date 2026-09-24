import 'package:flutter/material.dart';

/// Spacing tokens (in logical pixels / dp). Not specified numerically by
/// Design.md — kept as a generic scale for screens/widgets to compose
/// with the fixed tokens below.
class AppSpacing {
  AppSpacing._();

  static const xs = 4.0; // icon-to-label gap
  static const sm = 8.0; // within a row
  static const md = 12.0; // between rows
  static const lg = 16.0; // card padding, screen margins
  static const xl = 24.0; // between sections
}

/// Border widths. Design.md §2 "Structure": 3px on cards, buttons, tiles,
/// tools, swatches; 2px on chips and small pills.
class AppBorders {
  AppBorders._();

  static const thick = 3.0;
  static const thin = 2.0;
}

/// Corner radius tokens, per Design.md §2 "Structure".
class AppRadius {
  AppRadius._();

  static const card = 14.0;
  static const control = 10.0; // buttons and tools (10–11px)
  static const tile = 5.0; // letter tiles and swatches
  static const chip = 999.0;
  static const phoneScreen = 22.0;

  static const cardRadius = BorderRadius.all(Radius.circular(card));
  static const controlRadius = BorderRadius.all(Radius.circular(control));
  static const tileRadius = BorderRadius.all(Radius.circular(tile));
  static const chipRadius = BorderRadius.all(Radius.circular(chip));
}

/// Fixed component sizes.
class AppSizes {
  AppSizes._();

  /// Minimum tappable area for any control — buttons, chips, icon buttons.
  static const minTouchTarget = 44.0;

  /// Standard icon size; use [iconMax] only for decorative/large icons.
  static const icon = 20.0;
  static const iconMax = 24.0;

  /// Text input height.
  static const inputHeight = 44.0;

  /// Letter tile, per Design.md §3 ("Letter tile").
  static const letterTileWidth = 33.0;
  static const letterTileHeight = 40.0;
}

/// Motion tokens.
class AppMotion {
  AppMotion._();

  static const duration = Duration(milliseconds: 180);
  static const curve = Curves.easeOut;
}
