import 'package:flutter/material.dart';

import 'app_chip.dart';

/// "9:00 AM" — the local clock time a round locks at.
String clockTime(DateTime dt) {
  final hour12 = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
  final minute = dt.minute.toString().padLeft(2, '0');
  final period = dt.hour < 12 ? 'AM' : 'PM';
  return '$hour12:$minute $period';
}

/// "18h left". Neutral above 12h, filled below — never red; deadlines
/// aren't errors.
class DeadlineChip extends StatelessWidget {
  const DeadlineChip({super.key, required this.endsAt});

  final DateTime endsAt;

  @override
  Widget build(BuildContext context) {
    final remaining = endsAt.difference(DateTime.now());
    if (remaining.isNegative) return const AttentionChip('locked');
    final label = remaining.inHours >= 1
        ? '${remaining.inHours}h left'
        : '${remaining.inMinutes.clamp(0, 59)}m left';
    return remaining.inHours >= 12 ? NeutralChip(label) : AttentionChip(label);
  }
}
