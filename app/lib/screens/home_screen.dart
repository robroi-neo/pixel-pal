import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_dimens.dart';
import '../theme/app_tokens.dart';
import '../widgets/app_avatar.dart';

/// Design.md §5 "Room list": three states, each encoded three ways (chip /
/// shadow / tint) — needs you, all in and waiting, paused. No member
/// scores; this is a to-do list, not a scoreboard.
enum _RoomStatus { needsYou, waiting, paused }

class _RoomSummary {
  const _RoomSummary({
    required this.title,
    required this.subtitle,
    required this.status,
    this.timeLabel,
    this.members = const [],
    this.overflowCount,
    this.footer,
  });

  final String title;
  final String subtitle;
  final _RoomStatus status;

  /// e.g. "18h left", "2d left" — null for a paused room (shows a pause
  /// icon instead).
  final String? timeLabel;

  final List<String> members;

  /// Extra members beyond the shown avatars, rendered as a "+N" chip.
  final int? overflowCount;

  /// e.g. "draw · 4 to guess", "all in, waiting" — null when paused.
  final String? footer;
}

/// Static content only — no room data comes from Firestore yet. Wiring
/// this up to real rooms, and making "New room or join code" and each
/// room card actually navigate, is future work.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  static const _rooms = [
    _RoomSummary(
      title: 'Pixel pals',
      subtitle: 'Round 12 · 5 players',
      status: _RoomStatus.needsYou,
      timeLabel: '18h left',
      members: ['MR', 'JS', 'PF', 'TK'],
      footer: 'draw · 4 to guess',
    ),
    _RoomSummary(
      title: 'Work lot',
      subtitle: 'Round 3 · 8 players',
      status: _RoomStatus.waiting,
      timeLabel: '2d left',
      members: ['DN', 'SH'],
      overflowCount: 6,
      footer: 'all in, waiting',
    ),
    _RoomSummary(
      title: 'Sunday sketch',
      subtitle: 'Paused by Nico',
      status: _RoomStatus.paused,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final needsYouCount = _rooms
        .where((r) => r.status == _RoomStatus.needsYou)
        .length;

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Your rooms', style: textTheme.headlineMedium),
                        const SizedBox(height: 4),
                        Text(
                          needsYouCount == 0
                              ? "You're all caught up"
                              : '$needsYouCount room${needsYouCount == 1 ? '' : 's'} '
                                    'need${needsYouCount == 1 ? 's' : ''} you today',
                          style: textTheme.bodySmall?.copyWith(
                            color: AppColors.ink.withValues(alpha: 0.6),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  GestureDetector(
                    // Sign out has no visible affordance in the mockup —
                    // a long-press keeps it reachable for dev/testing
                    // without adding UI the design doesn't call for.
                    onLongPress: () => AuthService().signOut(),
                    child: const AppAvatar(initials: 'AL', size: 40),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xl),
              for (final room in _rooms) ...[
                _RoomCard(room: room, onTap: () {}),
                const SizedBox(height: AppSpacing.md),
              ],
              _DashedBorderButton(label: 'New room or join code', onTap: () {}),
            ],
          ),
        ),
      ),
    );
  }
}

class _RoomCard extends StatelessWidget {
  const _RoomCard({required this.room, required this.onTap});

  final _RoomSummary room;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<AppTokens>()!;
    final isNeedsYou = room.status == _RoomStatus.needsYou;
    final isPaused = room.status == _RoomStatus.paused;

    // §4 "Shadow is a call to action": only the room that needs you gets
    // the shadow. §5: settled rooms flatten — a paused room recedes all
    // the way to the screen's own background; a waiting room stays a
    // step above it on cream.
    final background = switch (room.status) {
      _RoomStatus.needsYou => AppColors.white,
      _RoomStatus.waiting => AppColors.cream,
      _RoomStatus.paused => theme.colorScheme.primary,
    };

    final titleColor = isPaused
        ? AppColors.ink.withValues(alpha: 0.55)
        : AppColors.ink;
    final subtitleColor = AppColors.ink.withValues(alpha: isPaused ? 0.5 : 0.6);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.cardRadius,
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.lg),
          decoration: BoxDecoration(
            color: background,
            borderRadius: AppRadius.cardRadius,
            border: Border.all(color: AppColors.ink, width: AppBorders.thick),
            boxShadow: isNeedsYou ? tokens.hardShadow : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          room.title,
                          style: theme.textTheme.titleLarge?.copyWith(
                            color: titleColor,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          room.subtitle,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: subtitleColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  if (isPaused)
                    const Icon(Icons.pause_rounded, color: AppColors.ink)
                  else if (room.timeLabel != null)
                    _TimeChip(label: room.timeLabel!, attention: isNeedsYou),
                ],
              ),
              if (!isPaused) ...[
                const SizedBox(height: AppSpacing.md),
                Row(
                  children: [
                    _AvatarStack(
                      members: room.members,
                      overflowCount: room.overflowCount,
                      ringColor: background,
                    ),
                    const Spacer(),
                    if (room.footer != null)
                      Text(
                        room.footer!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: AppColors.ink.withValues(alpha: 0.6),
                        ),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _TimeChip extends StatelessWidget {
  const _TimeChip({required this.label, required this.attention});

  final String label;

  /// §3 "Chip": white fill = neutral. Ink fill with accent text =
  /// attention — used here for the room that needs you.
  final bool attention;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final onInk = theme.colorScheme.onSecondary;
    final labelStyle = theme.chipTheme.labelStyle;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 5),
      decoration: BoxDecoration(
        color: attention ? AppColors.ink : AppColors.white,
        borderRadius: AppRadius.chipRadius,
        border: attention
            ? null
            : Border.all(color: AppColors.ink, width: AppBorders.thin),
      ),
      child: Text(
        label,
        style: labelStyle?.copyWith(color: attention ? onInk : AppColors.ink),
      ),
    );
  }
}

class _AvatarStack extends StatelessWidget {
  const _AvatarStack({
    required this.members,
    required this.ringColor,
    this.overflowCount,
  });

  final List<String> members;
  final int? overflowCount;
  final Color ringColor;

  static const _avatarSize = 28.0;
  static const _overlap = 10.0;

  @override
  Widget build(BuildContext context) {
    final items = [...members, if (overflowCount != null) '+$overflowCount'];
    if (items.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      height: _avatarSize,
      width: _avatarSize + (items.length - 1) * (_avatarSize - _overlap),
      child: Stack(
        children: [
          for (var i = 0; i < items.length; i++)
            Positioned(
              left: i * (_avatarSize - _overlap),
              child: AppAvatar(
                initials: items[i],
                size: _avatarSize,
                ringColor: ringColor,
              ),
            ),
        ],
      ),
    );
  }
}

/// The "New room or join code" entry point — dashed border, no fill, so it
/// reads as an add-slot rather than a fourth room card.
class _DashedBorderButton extends StatelessWidget {
  const _DashedBorderButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.cardRadius,
        child: CustomPaint(
          painter: const _DashedRRectPainter(radius: AppRadius.card),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
            alignment: Alignment.center,
            child: Text(label, style: Theme.of(context).textTheme.labelLarge),
          ),
        ),
      ),
    );
  }
}

class _DashedRRectPainter extends CustomPainter {
  const _DashedRRectPainter({required this.radius});

  final double radius;

  static const _strokeWidth = AppBorders.thick;
  static const _dashWidth = 8.0;
  static const _gapWidth = 6.0;

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        _strokeWidth / 2,
        _strokeWidth / 2,
        size.width - _strokeWidth,
        size.height - _strokeWidth,
      ),
      Radius.circular(radius),
    );
    final paint = Paint()
      ..color = AppColors.ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = _strokeWidth;

    for (final metric in (Path()..addRRect(rrect)).computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final next = distance + _dashWidth;
        canvas.drawPath(
          metric.extractPath(distance, next.clamp(0, metric.length)),
          paint,
        );
        distance = next + _gapWidth;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedRRectPainter oldDelegate) => false;
}
