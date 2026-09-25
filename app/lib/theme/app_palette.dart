import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Design.md §5 "Draw / editor": "fixed 16-colour palette", and §4 "The
/// palette may not sit on raw yellow": the palette's own yellow-ish swatch
/// sits a few shades off the app's actual yellow so the two are never
/// confused. Design.md doesn't pin exact hex values for the 16 (only that
/// there are 16, fixed, on cream) — these are a reasonable pixel-art set
/// consistent with that constraint.
class AppPalette {
  AppPalette._();

  static const List<Color> colors = [
    AppColors.ink,
    Color(0xFF4B4B52),
    Color(0xFF9A9AA0),
    AppColors.white,
    Color(0xFF8B5E3C),
    Color(0xFFC0392B),
    Color(0xFFE67E52),
    Color(0xFFE0A526), // off-yellow — see the class doc above
    Color(0xFFD9C48F),
    Color(0xFF1F6F3D),
    Color(0xFF4CAF50),
    Color(0xFF1D4E89),
    Color(0xFF4A9FE0),
    Color(0xFF7B4FA0),
    Color(0xFFD94F82),
    Color(0xFFF2A6C4),
  ];
}
