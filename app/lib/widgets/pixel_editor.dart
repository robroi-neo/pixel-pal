import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_dimens.dart';
import '../theme/app_palette.dart';
import 'pixel_canvas.dart';

enum PixelTool { pencil, fill, eraser }

/// The pixel editor's state — pixels, tool, colour, and a 20-deep undo
/// history. Owned by the screen (which needs [pixels] to submit/save),
/// rendered by [PixelEditor].
class PixelEditorController extends ChangeNotifier {
  PixelEditorController({required this.canvasSize, List<Color>? initialPixels})
    : _pixels =
          initialPixels != null &&
              initialPixels.length == canvasSize * canvasSize
          ? List<Color>.from(initialPixels)
          : List<Color>.filled(canvasSize * canvasSize, AppColors.canvas);

  static const _maxUndo = 20;

  final int canvasSize;
  List<Color> _pixels;
  final List<List<Color>> _undoStack = [];
  PixelTool _tool = PixelTool.pencil;
  Color _selectedColor = AppPalette.colors.first;

  /// Flat, row-major. Replaced (not mutated) on undo, so read it fresh
  /// rather than holding on to the list.
  List<Color> get pixels => _pixels;
  PixelTool get tool => _tool;
  Color get selectedColor => _selectedColor;
  bool get canUndo => _undoStack.isNotEmpty;

  void selectTool(PixelTool tool) {
    _tool = tool;
    notifyListeners();
  }

  void selectColor(Color color) {
    _selectedColor = color;
    notifyListeners();
  }

  void _pushUndoSnapshot() {
    _undoStack.add(List<Color>.from(_pixels));
    if (_undoStack.length > _maxUndo) _undoStack.removeAt(0);
  }

  void undo() {
    if (_undoStack.isEmpty) return;
    _pixels = _undoStack.removeLast();
    notifyListeners();
  }

  void strokeStart() {
    // Fill pushes its own snapshot in tapCell, once it knows a fill is
    // actually happening — not here, since strokeStart also fires for a
    // tap that a non-fill tool will ignore entirely.
    if (_tool == PixelTool.fill) return;
    _pushUndoSnapshot();
    notifyListeners();
  }

  void paintCell(int index) {
    if (_tool == PixelTool.fill) return;
    _pixels[index] = _tool == PixelTool.eraser
        ? AppColors.canvas
        : _selectedColor;
    notifyListeners();
  }

  void tapCell(int index) {
    if (_tool != PixelTool.fill) return;
    final target = _pixels[index];
    if (target == _selectedColor) return;
    _pushUndoSnapshot();
    _floodFill(index, target);
  }

  void _floodFill(int start, Color target) {
    final n = canvasSize;
    final visited = List<bool>.filled(_pixels.length, false);
    final stack = <int>[start];
    visited[start] = true;

    while (stack.isNotEmpty) {
      final i = stack.removeLast();
      _pixels[i] = _selectedColor;
      final row = i ~/ n;
      final col = i % n;
      for (final (dr, dc) in const [(-1, 0), (1, 0), (0, -1), (0, 1)]) {
        final nr = row + dr;
        final nc = col + dc;
        if (nr < 0 || nr >= n || nc < 0 || nc >= n) continue;
        final ni = nr * n + nc;
        if (visited[ni] || _pixels[ni] != target) continue;
        visited[ni] = true;
        stack.add(ni);
      }
    }
    notifyListeners();
  }
}

/// Design.md §5 "Draw / editor": framed canvas, tool row with a preview
/// beside it, and the 16-swatch palette. Shared by the round's drawing
/// screen and the profile icon editor, so both are the same editor.
class PixelEditor extends StatelessWidget {
  const PixelEditor({
    super.key,
    required this.controller,
    required this.previewBuilder,
  });

  final PixelEditorController controller;

  /// Sits right of the tool row — e.g. the gallery-size thumbnail, or the
  /// avatar crop. Rebuilt on every change.
  final Widget Function(BuildContext context, List<Color> pixels)
  previewBuilder;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Design.md §4 "canvas frame": cream band -> white card (3px
          // ink border) -> locked canvas fill -> pixel grid. Never fewer
          // than these layers, and `canvas` never changes for any theme.
          Container(
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: BoxDecoration(
              color: AppColors.cream,
              borderRadius: AppRadius.cardRadius,
            ),
            child: Container(
              padding: const EdgeInsets.all(AppSpacing.sm),
              decoration: BoxDecoration(
                color: AppColors.white,
                borderRadius: AppRadius.cardRadius,
                border: Border.all(
                  color: AppColors.ink,
                  width: AppBorders.thick,
                ),
              ),
              child: AspectRatio(
                aspectRatio: 1,
                child: Container(
                  color: AppColors.canvas,
                  child: PixelCanvas(
                    canvasSize: controller.canvasSize,
                    pixels: controller.pixels,
                    onStrokeStart: controller.strokeStart,
                    onPaintCell: controller.paintCell,
                    onTapCell: controller.tapCell,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Row(
                  children: [
                    _ToolButton(
                      icon: Icons.edit,
                      selected: controller.tool == PixelTool.pencil,
                      onTap: () => controller.selectTool(PixelTool.pencil),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    _ToolButton(
                      icon: Icons.format_color_fill,
                      selected: controller.tool == PixelTool.fill,
                      onTap: () => controller.selectTool(PixelTool.fill),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    _ToolButton(
                      icon: Icons.backspace_outlined,
                      selected: controller.tool == PixelTool.eraser,
                      onTap: () => controller.selectTool(PixelTool.eraser),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    _ToolButton(
                      icon: Icons.undo,
                      selected: false,
                      onTap: controller.canUndo ? controller.undo : null,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              previewBuilder(context, controller.pixels),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          Container(
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: BoxDecoration(
              color: AppColors.cream,
              borderRadius: AppRadius.cardRadius,
              border: Border.all(color: AppColors.ink, width: AppBorders.thick),
            ),
            child: Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                for (final color in AppPalette.colors)
                  _Swatch(
                    color: color,
                    selected: color == controller.selectedColor,
                    onTap: () => controller.selectColor(color),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ToolButton extends StatelessWidget {
  const _ToolButton({required this.icon, required this.selected, this.onTap});

  final IconData icon;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final iconColor = onTap == null
        ? AppColors.grey
        : (selected ? theme.colorScheme.onSecondary : AppColors.ink);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.controlRadius,
        child: Container(
          width: 44,
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? AppColors.ink : AppColors.white,
            borderRadius: AppRadius.controlRadius,
            border: Border.all(color: AppColors.ink, width: AppBorders.thick),
          ),
          child: Icon(icon, size: 20, color: iconColor),
        ),
      ),
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // §4 "The palette may not sit on raw yellow": the selection indicator
    // is an ink inset tick, not a yellow ring, precisely so it stays
    // legible on every swatch including the palette's own yellow-ish one.
    final tickColor = color.computeLuminance() > 0.5
        ? AppColors.ink
        : AppColors.white;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.tileRadius,
        child: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: color,
            borderRadius: AppRadius.tileRadius,
            border: Border.all(color: AppColors.ink, width: AppBorders.thin),
          ),
          child: selected
              ? Icon(Icons.check, size: 16, color: tickColor)
              : null,
        ),
      ),
    );
  }
}
