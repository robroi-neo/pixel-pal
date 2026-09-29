import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_dimens.dart';

/// Design.md §4 "Progress replaces the timer": "3 of 7 done. Segmented
/// bars, not countdowns."
class SegmentedProgress extends StatelessWidget {
  const SegmentedProgress({super.key, required this.total, required this.done});

  final int total;
  final int done;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < total; i++) ...[
          if (i > 0) const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Container(
              height: 8,
              decoration: BoxDecoration(
                color: i < done ? AppColors.ink : AppColors.white,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: AppColors.ink,
                  width: AppBorders.thin,
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}
