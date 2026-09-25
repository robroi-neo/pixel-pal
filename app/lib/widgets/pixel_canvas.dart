import 'package:flutter/material.dart';

/// An interactive pixel grid — Design.md §5 "Draw / editor". Pure
/// rendering + gesture geometry: it knows how to turn a touch point into
/// a cell index and how to interpolate a line between two cells so a fast
/// drag doesn't leave gaps (Implementations.md's "pointer handling that
/// survives fast drags"), but has no opinion on what a touch *means* —
/// that's the screen's job (pencil vs. eraser vs. fill), since it's the
/// screen that owns pixel state and undo history.
///
/// Deliberately square (`canvasSize` × `canvasSize`) and always rendered
/// at whatever size it's given — there's no pinch-zoom here.
/// Implementations.md's own plan calls the prototype's zoom button "a
/// stand-in" for real pinch/pan (budgeted a week on its own for gesture
/// conflicts); this hasn't built that yet either.
class PixelCanvas extends StatefulWidget {
  const PixelCanvas({
    super.key,
    required this.canvasSize,
    required this.pixels,
    required this.onStrokeStart,
    required this.onPaintCell,
    required this.onTapCell,
  });

  final int canvasSize;

  /// Flat, row-major, length `canvasSize * canvasSize`.
  final List<Color> pixels;

  /// Fired once when a drag or tap begins, before any cell callback —
  /// the screen should snapshot undo history here.
  final VoidCallback onStrokeStart;

  /// Fired for every cell touched during a drag (including interpolated
  /// cells between two points), and once for a plain tap.
  final ValueChanged<int> onPaintCell;

  /// Fired once for a clean tap (not a drag) — the fill tool's signal,
  /// distinct from [onPaintCell] so a tool that only makes sense as a
  /// single action (fill) doesn't have to ignore a stream of drag calls.
  final ValueChanged<int> onTapCell;

  @override
  State<PixelCanvas> createState() => _PixelCanvasState();
}

class _PixelCanvasState extends State<PixelCanvas> {
  int? _lastCell;

  int? _cellAt(Offset local, Size size) {
    final cellExtent = size.width / widget.canvasSize;
    final col = (local.dx / cellExtent).floor();
    final row = (local.dy / cellExtent).floor();
    if (col < 0 || col >= widget.canvasSize || row < 0 || row >= widget.canvasSize) {
      return null;
    }
    return row * widget.canvasSize + col;
  }

  /// Bresenham's line, walking cell-to-cell rather than pixel-to-pixel —
  /// this is what keeps a fast drag from leaving unpainted gaps between
  /// two touch events that landed several cells apart.
  void _paintLine(int fromIndex, int toIndex) {
    final n = widget.canvasSize;
    var x0 = fromIndex % n;
    var y0 = fromIndex ~/ n;
    final x1 = toIndex % n;
    final y1 = toIndex ~/ n;
    final dx = (x1 - x0).abs();
    final dy = -(y1 - y0).abs();
    final sx = x0 < x1 ? 1 : -1;
    final sy = y0 < y1 ? 1 : -1;
    var err = dx + dy;

    while (true) {
      widget.onPaintCell(y0 * n + x0);
      if (x0 == x1 && y0 == y1) break;
      final e2 = 2 * err;
      if (e2 >= dy) {
        err += dy;
        x0 += sx;
      }
      if (e2 <= dx) {
        err += dx;
        y0 += sy;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        return GestureDetector(
          onPanStart: (details) {
            final cell = _cellAt(details.localPosition, size);
            if (cell == null) return;
            widget.onStrokeStart();
            widget.onPaintCell(cell);
            _lastCell = cell;
          },
          onPanUpdate: (details) {
            final cell = _cellAt(details.localPosition, size);
            if (cell == null) return;
            if (_lastCell != null && _lastCell != cell) {
              _paintLine(_lastCell!, cell);
            } else {
              widget.onPaintCell(cell);
            }
            _lastCell = cell;
          },
          onPanEnd: (_) => _lastCell = null,
          // Not calling onStrokeStart here too: onPanStart above already
          // fires for every touch-down, taps included (a pan recognizer
          // accepts immediately, before it's known whether the pointer
          // will move) — calling it again here would double-fire it for
          // the same gesture.
          onTapUp: (details) {
            final cell = _cellAt(details.localPosition, size);
            if (cell == null) return;
            widget.onTapCell(cell);
          },
          child: CustomPaint(
            size: size,
            painter: PixelPainter(
              canvasSize: widget.canvasSize,
              pixels: widget.pixels,
            ),
          ),
        );
      },
    );
  }
}

/// A static, non-interactive render of the same pixel data — the
/// gallery-size thumbnail preview.
class PixelPreview extends StatelessWidget {
  const PixelPreview({super.key, required this.canvasSize, required this.pixels});

  final int canvasSize;
  final List<Color> pixels;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(painter: PixelPainter(canvasSize: canvasSize, pixels: pixels));
  }
}

class PixelPainter extends CustomPainter {
  const PixelPainter({required this.canvasSize, required this.pixels});

  final int canvasSize;
  final List<Color> pixels;

  @override
  void paint(Canvas canvas, Size size) {
    final cellExtent = size.width / canvasSize;
    final paint = Paint();
    for (var row = 0; row < canvasSize; row++) {
      for (var col = 0; col < canvasSize; col++) {
        paint.color = pixels[row * canvasSize + col];
        canvas.drawRect(
          Rect.fromLTWH(col * cellExtent, row * cellExtent, cellExtent, cellExtent),
          paint,
        );
      }
    }
  }

  // The pixel list is mutated in place by the owning screen rather than
  // replaced, so there's no cheap way to detect "did anything change" —
  // and repainting a <=64x64 grid of flat-colored rects every frame is
  // trivially cheap regardless.
  @override
  bool shouldRepaint(covariant PixelPainter oldDelegate) => true;
}
