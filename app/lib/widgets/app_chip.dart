import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_dimens.dart';

/// Design.md §3 "Chip": white fill = neutral.
class NeutralChip extends StatelessWidget {
  const NeutralChip(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    final labelStyle = Theme.of(context).chipTheme.labelStyle;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: AppRadius.chipRadius,
        border: Border.all(color: AppColors.ink, width: AppBorders.thin),
      ),
      child: Text(label, style: labelStyle?.copyWith(color: AppColors.ink)),
    );
  }
}

/// Design.md §3 "Chip": ink fill with accent text = attention — the
/// state that needs you, per §4.
class AttentionChip extends StatelessWidget {
  const AttentionChip(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final onInk = theme.colorScheme.onSecondary;
    final labelStyle = theme.chipTheme.labelStyle;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.ink,
        borderRadius: AppRadius.chipRadius,
      ),
      child: Text(label, style: labelStyle?.copyWith(color: onInk)),
    );
  }
}
