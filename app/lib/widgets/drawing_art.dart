import 'package:flutter/material.dart';

import '../models/drawing_submission.dart';
import '../theme/app_colors.dart';
import '../theme/app_dimens.dart';
import 'pixel_canvas.dart';

/// A submitted drawing in its frame: a white mat with a 3px border
/// ([frameColor] — ink normally, the accent on the dark reveal) around the
/// canvas. The canvas itself never follows the chrome (Design.md §4).
class DrawingArt extends StatelessWidget {
  const DrawingArt({
    super.key,
    required DrawingSubmission this.drawing,
    this.frameColor = AppColors.ink,
    this.maxWidth = 220,
  }) : pixels = null,
       canvasSize = null;

  /// Art that isn't a submitted drawing yet — e.g. the editor's canvas on
  /// the submit confirmation.
  const DrawingArt.pixels({
    super.key,
    required List<Color> this.pixels,
    required int this.canvasSize,
    this.frameColor = AppColors.ink,
    this.maxWidth = 220,
  }) : drawing = null;

  final DrawingSubmission? drawing;
  final List<Color>? pixels;
  final int? canvasSize;
  final Color frameColor;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.xs),
          decoration: BoxDecoration(
            color: AppColors.white,
            borderRadius: AppRadius.controlRadius,
            border: Border.all(color: frameColor, width: AppBorders.thick),
          ),
          child: AspectRatio(
            aspectRatio: 1,
            // Faint outline so the white canvas still reads on the mat.
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.canvas,
                border: Border.all(
                  color: AppColors.ink.withValues(alpha: 0.15),
                ),
              ),
              child: PixelPreview(
                canvasSize: canvasSize ?? drawing!.canvasSize,
                pixels: pixels ?? drawing!.pixels,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// "Medium · x1.4" — public, so guessers read ambiguous art charitably.
String difficultyLabel(DrawingSubmission drawing) =>
    '${drawing.difficulty.label} · x${drawing.multiplier.toStringAsFixed(1)}';

/// "things · 5 letters" — known from the first attempt.
String categoryLabel(DrawingSubmission drawing) {
  final letters = drawing.word.replaceAll(' ', '').length;
  return '${drawing.category} · $letters letters';
}
