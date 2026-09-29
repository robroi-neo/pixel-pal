import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_dimens.dart';

/// Pieces for the near-black reveal surfaces (Design.md §5 "Reveal"): the
/// result side of a guess card and the deadline reveal. The light-mode
/// components are ink-on-white; these invert to accent-on-ink.

/// The one primary button, inverted: accent fill, ink label.
class AccentButton extends StatelessWidget {
  const AccentButton({super.key, required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: AppColors.ink,
        ),
        child: Text(label),
      ),
    );
  }
}

/// Secondary button on ink: accent outline and label.
class AccentOutlineButton extends StatelessWidget {
  const AccentOutlineButton({
    super.key,
    required this.label,
    required this.onPressed,
  });

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: accent,
        side: BorderSide(color: accent, width: AppBorders.thick),
      ),
      child: Text(label),
    );
  }
}

/// Outlined accent chip.
class DarkChip extends StatelessWidget {
  const DarkChip(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 4,
      ),
      decoration: BoxDecoration(
        borderRadius: AppRadius.chipRadius,
        border: Border.all(color: accent, width: AppBorders.thin),
      ),
      child: Text(
        label,
        style: theme.chipTheme.labelStyle?.copyWith(color: accent),
      ),
    );
  }
}
