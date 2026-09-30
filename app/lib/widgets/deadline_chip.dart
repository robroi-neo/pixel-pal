import 'package:flutter/material.dart';

import 'app_chip.dart';

/// "9:00 AM" — the local clock time a round locks at.
String clockTime(DateTime dt) {
  final hour12 = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
  final minute = dt.minute.toString().padLeft(2, '0');
  final period = dt.hour < 12 ? 'AM' : 'PM';
  return '$hour12:$minute $period';
}

/// "today · 9:00 AM", "tomorrow · 9:00 AM", or "Sun · 9:00 AM" — when a
/// round locks, for "Everything locks …".
String lockTime(DateTime dt) {
  final now = DateTime.now();
  final days = DateTime(
    dt.year,
    dt.month,
    dt.day,
  ).difference(DateTime(now.year, now.month, now.day)).inDays;
  const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  final day = switch (days) {
    0 => 'today',
    1 => 'tomorrow',
    _ => weekdays[dt.weekday - 1],
  };
  return '$day · ${clockTime(dt)}';
}

/// "4d 23h left", "18h left", "45m left". Neutral above 12h, filled below
/// — never red; deadlines aren't errors (Design.md §4).
class DeadlineChip extends StatelessWidget {
  const DeadlineChip({super.key, required this.endsAt});

  final DateTime endsAt;

  @override
  Widget build(BuildContext context) {
    final remaining = endsAt.difference(DateTime.now());
    if (remaining.isNegative) return const AttentionChip('locked');
    final label = remaining.inDays >= 1
        ? '${remaining.inDays}d ${remaining.inHours % 24}h left'
        : remaining.inHours >= 1
        ? '${remaining.inHours}h left'
        : '${remaining.inMinutes.clamp(0, 59)}m left';
    return remaining.inHours >= 12 ? NeutralChip(label) : AttentionChip(label);
  }
}
