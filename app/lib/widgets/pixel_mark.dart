import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// The app's pixel-art mark — a blocky smiley face, ink on transparent.
///
/// Design.md §4: "The UI must not be pixelated. The pixel art is the only
/// pixelated thing on screen." The sign-in mark is the one named exception
/// (§5: "the only pixel art outside a canvas frame is the app mark, which
/// is a logo, not user artwork"), so this is drawn as a fixed grid rather
/// than a smooth vector icon.
class PixelMark extends StatelessWidget {
  const PixelMark({super.key, this.size = 96, this.color = AppColors.ink});

  final double size;
  final Color color;

  /// 9x9 grid, row-major. Ring outline + two eyes + an upturned mouth —
  /// every stroke exactly one pixel thick.
  static const List<String> _grid = [
    '..#####..',
    '.#.....#.',
    '#.......#',
    '#..#.#..#',
    '#.......#',
    '#.#...#.#',
    '#..###..#',
    '.#.....#.',
    '..#####..',
  ];

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _PixelMarkPainter(color)),
    );
  }
}

class _PixelMarkPainter extends CustomPainter {
  const _PixelMarkPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final rows = PixelMark._grid.length;
    final cols = PixelMark._grid.first.length;
    final cell = Size(size.width / cols, size.height / rows);
    final paint = Paint()..color = color;

    for (var y = 0; y < rows; y++) {
      final row = PixelMark._grid[y];
      for (var x = 0; x < cols; x++) {
        if (row[x] != '#') continue;
        canvas.drawRect(
          Rect.fromLTWH(x * cell.width, y * cell.height, cell.width, cell.height),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _PixelMarkPainter oldDelegate) =>
      oldDelegate.color != color;
}
