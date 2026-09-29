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
    required this.drawing,
    this.frameColor = AppColors.ink,
    this.maxWidth = 220,
  });

  final DrawingSubmission drawing;
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
                canvasSize: drawing.canvasSize,
                pixels: drawing.pixels,
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
