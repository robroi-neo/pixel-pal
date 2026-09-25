import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../models/room_detail.dart';
import '../router/app_router.dart';
import '../services/room_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_dimens.dart';
import '../theme/app_tokens.dart';
import '../widgets/app_button.dart';
import '../widgets/app_chip.dart';

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
/// "Round 1" and the guess-progress numerator are placeholders — but room
/// name, canvas size, the round deadline (`RoomDetail.roundEndsAt`), and
/// the drawing-status chip (`RoomDetail`'s member doc `issuedPromptIds`)
/// are real, live data. "Pick your prompt" opens [PromptPickScreen] and
/// disables once the round's locked; "Carry on guessing" and
/// "Leaderboard" are still deliberate no-ops.
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

class _RoundHomeBody extends StatefulWidget {
  const _RoundHomeBody({required this.room});

  final RoomDetail room;

  @override
  State<_RoundHomeBody> createState() => _RoundHomeBodyState();
}

class _RoundHomeBodyState extends State<_RoundHomeBody> {
  Timer? _ticker;

  // Created once and reused, not inline in build() — StreamBuilder treats
  // a freshly-created Stream as "changed" on every rebuild and
  // resubscribes, which would otherwise reset this card to its loading
  // state on every minute-tick from _ticker below.
  late final Stream<List<String>?> _issuedPromptIds = RoomService()
      .watchIssuedPromptIds(widget.room.id, FirebaseAuth.instance.currentUser!.uid);

  @override
  void initState() {
    super.initState();
    // The deadline itself doesn't change, but "Xh left" should still look
    // fresh if this screen is left open — hourly granularity doesn't need
    // anything faster than a once-a-minute rebuild.
    _ticker = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final room = widget.room;
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
          _RoundDeadlineRow(roundEndsAt: room.roundEndsAt),
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
            child: StreamBuilder<List<String>?>(
              stream: _issuedPromptIds,
              builder: (context, snapshot) {
                final hasPrompt = snapshot.data?.isNotEmpty ?? false;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Your drawing',
                            style: textTheme.titleMedium,
                          ),
                        ),
                        hasPrompt
                            ? NeutralChip('prompt picked')
                            : AttentionChip('not started'),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      hasPrompt
                          ? 'Prompt locked in. ${room.canvasSize} × '
                                '${room.canvasSize} canvas this round.'
                          : 'Your prompt is waiting. ${room.canvasSize} × '
                                '${room.canvasSize} canvas this round.',
                      style: textTheme.bodySmall?.copyWith(
                        color: AppColors.ink.withValues(alpha: 0.7),
                      ),
                    ),
                  ],
                );
              },
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
            enabled: !room.isRoundLocked,
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

/// The deadline chip + adjoining text from the mockup — "18h left,
/// everything locks at 9:00" — computed from the room's real
/// `roundEndsAt` instead of shown as fixed copy. Renders nothing (not
/// even a placeholder) for a room created before this field existed,
/// rather than claiming a deadline that was never actually set.
class _RoundDeadlineRow extends StatelessWidget {
  const _RoundDeadlineRow({required this.roundEndsAt});

  final DateTime? roundEndsAt;

  static String _clockTime(DateTime dt) {
    final hour12 = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final minute = dt.minute.toString().padLeft(2, '0');
    final period = dt.hour < 12 ? 'AM' : 'PM';
    return '$hour12:$minute $period';
  }

  @override
  Widget build(BuildContext context) {
    final endsAt = roundEndsAt;
    if (endsAt == null) return const SizedBox.shrink();

    final textTheme = Theme.of(context).textTheme;
    final locked = DateTime.now().isAfter(endsAt);

    return Row(
      children: [
        locked ? const AttentionChip('locked') : _hoursLeftChip(endsAt),
        const SizedBox(width: AppSpacing.sm),
        Flexible(
          child: Text(
            locked
                ? 'this round has ended'
                : 'everything locks at ${_clockTime(endsAt)}',
            style: textTheme.bodySmall?.copyWith(
              color: AppColors.ink.withValues(alpha: 0.6),
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _hoursLeftChip(DateTime endsAt) {
    final remaining = endsAt.difference(DateTime.now());
    final label = remaining.inHours >= 1
        ? '${remaining.inHours}h left'
        : '${remaining.inMinutes.clamp(0, 59)}m left';
    return NeutralChip(label);
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
