import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../models/room_detail.dart';
import '../router/app_router.dart';
import '../services/room_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_dimens.dart';
import '../theme/app_tokens.dart';
import '../widgets/app_button.dart';

/// Design.md §5 "Round home (hub)": one primary button, the other routes
/// are text links; two task cards (drawing, guessing) with the unstarted
/// one carrying the shadow.
///
/// Reached by tapping a room you *didn't* create — the owner's tap still
/// goes to [RoomScreen] (the invite/waiting view) for now; giving the
/// owner this same hub once a room has real rounds running is follow-up
/// work, not done here.
///
/// The round engine doesn't exist yet (Implementations.md Phase 3), so
/// only room name and canvas size are real, live data — round number,
/// prompt count, and guess progress are placeholders, same spirit as
/// Design.md's own round-1-onboarding note ("a new room has no Round
/// N-1"). "Pick your prompt" opens [PromptPickScreen]; "Carry on
/// guessing" and "Leaderboard" are still deliberate no-ops.
class RoundHomeScreen extends StatelessWidget {
  const RoundHomeScreen({super.key, required this.roomId});

  final String roomId;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return StreamBuilder<RoomDetail?>(
      stream: RoomService().watchRoom(roomId),
      builder: (context, snapshot) {
        final room = snapshot.data;

        return Scaffold(
          appBar: AppBar(
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_outlined),
              onPressed: () => context.pop(),
            ),
            title: Text(room?.name ?? '', style: textTheme.titleMedium),
            actions: [
              IconButton(
                // Room settings / leave room aren't built yet.
                icon: const Icon(Icons.more_horiz),
                onPressed: () {},
              ),
            ],
          ),
          body: SafeArea(
            child: Builder(
              builder: (context) {
                if (snapshot.hasError) {
                  return Center(
                    child: Text(
                      "Couldn't load this room.",
                      style: textTheme.bodyMedium,
                    ),
                  );
                }
                if (!snapshot.hasData) {
                  return const Center(
                    child: CircularProgressIndicator(color: AppColors.ink),
                  );
                }
                if (room == null) {
                  return Center(
                    child: Text(
                      'This room no longer exists.',
                      style: textTheme.bodyMedium,
                    ),
                  );
                }
                return _RoundHomeBody(room: room);
              },
            ),
          ),
        );
      },
    );
  }
}

class _RoundHomeBody extends StatelessWidget {
  const _RoundHomeBody({required this.room});

  final RoomDetail room;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;
    final tokens = theme.extension<AppTokens>()!;
    // You guess everyone else's drawing, not your own.
    final othersToGuess = (room.memberCount - 1).clamp(0, room.memberCount);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Round 1', style: textTheme.headlineMedium),
          const SizedBox(height: AppSpacing.sm),
          _NeutralChip('${room.canvasSize} × ${room.canvasSize} canvas'),
          const SizedBox(height: AppSpacing.lg),

          // §4 "Shadow is a call to action": the task still ahead of you
          // gets the shadow. Drawing is the one "Pick your prompt" leads
          // to, so it's the white, shadowed card; guessing stays flat
          // cream until there's something real to act on.
          Container(
            padding: const EdgeInsets.all(AppSpacing.lg),
            decoration: BoxDecoration(
              color: AppColors.white,
              borderRadius: AppRadius.cardRadius,
              border: Border.all(color: AppColors.ink, width: AppBorders.thick),
              boxShadow: tokens.hardShadow,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text('Your drawing', style: textTheme.titleMedium),
                    ),
                    _AttentionChip('not started'),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Your prompt is waiting.',
                  style: textTheme.bodySmall?.copyWith(
                    color: AppColors.ink.withValues(alpha: 0.7),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Container(
            padding: const EdgeInsets.all(AppSpacing.lg),
            decoration: BoxDecoration(
              color: AppColors.cream,
              borderRadius: AppRadius.cardRadius,
              border: Border.all(color: AppColors.ink, width: AppBorders.thick),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text('Guessing', style: textTheme.titleMedium),
                    ),
                    Text(
                      '0 of $othersToGuess done',
                      style: textTheme.bodySmall?.copyWith(
                        color: AppColors.ink.withValues(alpha: 0.6),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                _SegmentedProgress(total: othersToGuess, done: 0),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          AppButton(
            label: 'Pick your prompt',
            onPressed: () async =>
                context.push('${AppRoutes.rooms}/${room.id}/prompt-pick'),
          ),
          const SizedBox(height: AppSpacing.md),
          Center(
            child: TextButton(
              onPressed: () {},
              child: const Text('Carry on guessing'),
            ),
          ),
          Center(
            child: TextButton(
              onPressed: () {},
              child: const Text('Leaderboard'),
            ),
          ),
        ],
      ),
    );
  }
}

/// §4 "Progress replaces the timer": "3 of 7 done. Segmented bars, not
/// countdowns."
class _SegmentedProgress extends StatelessWidget {
  const _SegmentedProgress({required this.total, required this.done});

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
                border: Border.all(color: AppColors.ink, width: AppBorders.thin),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// §3 "Chip": white fill, neutral.
class _NeutralChip extends StatelessWidget {
  const _NeutralChip(this.label);

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

/// §3 "Chip": ink fill with accent text — attention, for the task that
/// needs you.
class _AttentionChip extends StatelessWidget {
  const _AttentionChip(this.label);

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
