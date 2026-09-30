import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// "▲1", "▼1" or "–": how many places a player moved since the last table.
/// Down is muted, never red (Design.md §2: `error` is for form validation
/// only).
class RankDelta extends StatelessWidget {
  const RankDelta({super.key, required this.delta, this.color = AppColors.ink});

  /// Places moved up (positive) or down (negative); null for someone who
  /// wasn't on the last table.
  final int? delta;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final d = delta;
    final style = Theme.of(context).textTheme.bodySmall?.copyWith(
      fontWeight: FontWeight.w700,
      color: d != null && d < 0 ? color.withValues(alpha: 0.5) : color,
    );
    final text = d == null || d == 0
        ? '–'
        : d > 0
        ? '▲$d'
        : '▼${-d}';
    return Text(text, style: style);
  }
}

/// Places each player moved between [previous] and [current] rankings
/// (uid → rank), keyed by uid. Missing = not on the previous table.
Map<String, int> rankDeltas(
  Map<String, int> previous,
  Map<String, int> current,
) => {
  for (final e in current.entries)
    if (previous[e.key] != null) e.key: previous[e.key]! - e.value,
};
