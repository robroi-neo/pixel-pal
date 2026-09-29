import 'package:flutter/material.dart';

import '../models/guess_progress.dart';
import '../theme/app_colors.dart';
import '../theme/app_dimens.dart';

/// Design.md §3 "Attempt marker": 11px dot, 2px ink border. Filled =
/// spent, hollow = remaining. No score preview — the dots carry the state.
class AttemptDots extends StatelessWidget {
  const AttemptDots({super.key, required this.attempts, this.size = 11});

  final int attempts;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < GuessProgress.maxAttempts; i++) ...[
          if (i > 0) const SizedBox(width: 4),
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: i < attempts ? AppColors.ink : Colors.transparent,
              border: Border.all(color: AppColors.ink, width: AppBorders.thin),
            ),
          ),
        ],
      ],
    );
  }
}
