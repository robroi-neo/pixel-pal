import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../models/drawing_submission.dart';
import '../../models/guess_progress.dart';
import '../../models/room_detail.dart';
import '../../models/round_info.dart';
import '../../router/app_router.dart';
import '../../services/drawing_service.dart';
import '../../services/guess_service.dart';
import '../../services/room_service.dart';
import '../../services/round_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_dimens.dart';
import '../../theme/app_tokens.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_chip.dart';
import '../../widgets/deadline_chip.dart';
import '../../widgets/loading_view.dart';
import '../../widgets/segmented_progress.dart';

/// Design.md §5 "Round home (hub)": one primary button, the other routes
/// are text links; two task cards (drawing, guessing) with the one that
/// needs you carrying the shadow.
///
/// Always shows the room's current round n: draw round n's prompt, guess
/// round n−1's drawings (round 1 is draw-only), and a link to the newest
/// results (round n−2's, which landed when round n opened). Opening this
/// screen [RoundService.checkIn]s, which is also what moves the room on
/// to its next round once this one is over — there's no scheduler on
/// Spark to do it.
///
/// Reached by tapping a room whose round 1 has started (see
/// `RoomDetail.isRoundStarted`). Before that, tapping the room opens
/// [RoomScreen] (the lobby); the owner can still get back there from this
/// screen's app bar menu, e.g. to invite more players. "Leaderboard" is
/// still a deliberate no-op — round scores aren't stored yet.
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
              // Owner-only: the invite screen is otherwise unreachable now
              // that owners land here too.
              if (room != null &&
                  room.isOwnedBy(FirebaseAuth.instance.currentUser?.uid ?? ''))
                PopupMenuButton<void>(
                  icon: const Icon(Icons.more_horiz),
                  itemBuilder: (_) => [
                    PopupMenuItem(
                      onTap: () => context.push('${AppRoutes.rooms}/$roomId'),
                      child: const Text('Invite players'),
                    ),
                  ],
                ),
            ],
          ),
          body: SafeArea(
            child: Builder(
              builder: (context) {
                if (snapshot.hasError) {
                  return _Message("Couldn't load this room.");
                }
                if (!snapshot.hasData) {
                  return const LoadingView();
                }
                if (room == null) {
                  return _Message('This room no longer exists.');
                }
                final round = room.currentRound;
                if (round == null) {
                  return _Message(
                    'This room started before rounds were added, so it '
                    "can't move on to round 2. Delete it and start a new "
                    'one.',
                  );
                }
                // A fresh body per round, so its per-round streams follow
                // the room when it moves on.
                return _RoundHomeBody(
                  key: ValueKey(round),
                  room: room,
                  round: round,
                );
              },
            ),
          ),
        );
      },
    );
  }
}

class _RoundHomeBody extends StatefulWidget {
  const _RoundHomeBody({super.key, required this.room, required this.round});

  final RoomDetail room;
  final int round;

  @override
  State<_RoundHomeBody> createState() => _RoundHomeBodyState();
}

class _RoundHomeBodyState extends State<_RoundHomeBody> {
  Timer? _ticker;

  // Created once and reused, not inline in build() — StreamBuilder treats
  // a freshly-created Stream as "changed" on every rebuild and
  // resubscribes, which would otherwise reset these cards to their
  // loading state on every minute-tick from _ticker below.
  late final Stream<List<String>?> _issuedPromptIds = RoomService()
      .watchIssuedPromptIds(
        widget.room.id,
        widget.round,
        FirebaseAuth.instance.currentUser!.uid,
      );
  late final Stream<bool> _hasSubmitted = DrawingService().watchHasSubmitted(
    widget.room.id,
    widget.round,
  );
  late final Stream<RoundInfo?> _roundInfo = RoundService().watchRound(
    widget.room.id,
    widget.round,
  );

  // Last round's drawings — the ones to guess now. Round 1 has none.
  late final Stream<List<DrawingSubmission>> _toGuess = widget.round > 1
      ? DrawingService().watchOthersDrawings(widget.room.id, widget.round - 1)
      : Stream.value(const []);
  late final Stream<Map<String, GuessProgress>> _myGuesses = widget.round > 1
      ? GuessService().watchMyGuesses(widget.room.id, widget.round - 1)
      : Stream.value(const {});

  @override
  void initState() {
    super.initState();
    // Marks you done if you are, and moves the room on if this round is
    // over — including an early close someone else's app missed.
    RoundService().checkIn(widget.room.id);
    // "Xh left" should still look fresh if this screen is left open, and
    // the deadline passing should be noticed.
    _ticker = Timer.periodic(const Duration(minutes: 1), (_) {
      if (!mounted) return;
      setState(() {});
      if (widget.room.isRoundLocked) RoundService().checkIn(widget.room.id);
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
    final n = widget.round;
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;
    final tokens = theme.extension<AppTokens>()!;
    final resultsRound = room.latestResultsRound;

    return StreamBuilder<bool>(
      stream: _hasSubmitted,
      builder: (context, submittedSnapshot) {
        final submitted = submittedSnapshot.data ?? false;
        return StreamBuilder<List<DrawingSubmission>>(
          stream: _toGuess,
          builder: (context, drawingsSnapshot) {
            return StreamBuilder<Map<String, GuessProgress>>(
              stream: _myGuesses,
              builder: (context, guessesSnapshot) {
                final drawings = drawingsSnapshot.data ?? const [];
                final guesses = guessesSnapshot.data ?? const {};
                final total = drawings.length;
                final done = drawings
                    .where((d) => guesses[d.authorUid]?.isDone ?? false)
                    .length;
                final guessingLeft = n > 1 && done < total;

                return SingleChildScrollView(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text('Round $n', style: textTheme.headlineMedium),
                      const SizedBox(height: AppSpacing.sm),
                      StreamBuilder<RoundInfo?>(
                        stream: _roundInfo,
                        builder: (context, snapshot) =>
                            _RoundDeadlineRow(room: room, round: snapshot.data),
                      ),
                      const SizedBox(height: AppSpacing.lg),

                      // §4 "Shadow is a call to action": the task still
                      // ahead of you gets the shadow — drawing until it's
                      // submitted, then guessing while any is left.
                      _TaskCard(
                        settled: submitted,
                        shadow: !submitted ? tokens.hardShadow : null,
                        child: StreamBuilder<List<String>?>(
                          stream: _issuedPromptIds,
                          builder: (context, snapshot) {
                            final hasPrompt =
                                snapshot.data?.isNotEmpty ?? false;
                            return _CardText(
                              title: 'Your drawing',
                              chip: submitted
                                  ? const NeutralChip('submitted')
                                  : hasPrompt
                                  ? const NeutralChip('prompt picked')
                                  : const AttentionChip('not started'),
                              body: submitted
                                  ? n > 1
                                        ? "Submitted. It's guessed next round."
                                        : 'Submitted. Everyone guesses it in '
                                              'round 2.'
                                  : hasPrompt
                                  ? 'Prompt locked in. ${room.canvasSize} × '
                                        '${room.canvasSize} canvas this round.'
                                  : 'Your prompt is waiting. '
                                        '${room.canvasSize} × '
                                        '${room.canvasSize} canvas this '
                                        'round.',
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      _TaskCard(
                        settled: !guessingLeft,
                        shadow: submitted && guessingLeft
                            ? tokens.hardShadow
                            : null,
                        child: n == 1
                            ? const _CardText(
                                title: 'Guessing',
                                body:
                                    'Round 1 is draw-only. Its drawings open '
                                    'for guessing in round 2.',
                              )
                            : Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _CardText(
                                    title: 'Guessing round ${n - 1}',
                                    trailing: '$done of $total done',
                                    body: total == 0
                                        ? 'Nobody else drew in round '
                                              '${n - 1}.'
                                        : null,
                                  ),
                                  if (total > 0) ...[
                                    const SizedBox(height: AppSpacing.sm),
                                    SegmentedProgress(total: total, done: done),
                                  ],
                                ],
                              ),
                      ),
                      const SizedBox(height: AppSpacing.xl),
                      ..._actions(
                        context,
                        submitted: submitted,
                        guessingLeft: guessingLeft,
                      ),
                      if (resultsRound != null)
                        Center(
                          child: TextButton(
                            onPressed: () => context.push(
                              AppRoutes.resultsPath(room.id, resultsRound),
                            ),
                            child: Text('Round $resultsRound results'),
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
              },
            );
          },
        );
      },
    );
  }

  /// Design.md §5: one primary button — whatever's next for you.
  List<Widget> _actions(
    BuildContext context, {
    required bool submitted,
    required bool guessingLeft,
  }) {
    final room = widget.room;
    final n = widget.round;
    final textTheme = Theme.of(context).textTheme;

    if (room.isRoundLocked) {
      // The deadline's passed; the check-in in initState (or the ticker)
      // is opening the next round. This is the manual retry.
      return [
        Text(
          'Round $n is over.',
          textAlign: TextAlign.center,
          style: textTheme.bodyMedium,
        ),
        const SizedBox(height: AppSpacing.sm),
        AppButton(
          label: 'Open round ${n + 1}',
          onPressed: () => RoundService().checkIn(room.id),
        ),
        const SizedBox(height: AppSpacing.md),
      ];
    }
    if (!submitted) {
      return [
        AppButton(
          label: 'Pick your prompt',
          onPressed: () async =>
              context.push(AppRoutes.promptPickPath(room.id, n)),
        ),
        const SizedBox(height: AppSpacing.md),
        if (n > 1)
          Center(
            child: TextButton(
              onPressed: () =>
                  context.push(AppRoutes.guessPath(room.id, n - 1)),
              child: const Text('Carry on guessing'),
            ),
          ),
      ];
    }
    if (n > 1) {
      return [
        AppButton(
          label: guessingLeft ? 'Guess drawings' : 'See your guesses',
          secondary: !guessingLeft,
          onPressed: () async =>
              context.push(AppRoutes.guessPath(room.id, n - 1)),
        ),
        const SizedBox(height: AppSpacing.md),
      ];
    }
    return const [];
  }
}

class _TaskCard extends StatelessWidget {
  const _TaskCard({
    required this.settled,
    required this.shadow,
    required this.child,
  });

  /// Nothing left to do here — cream rather than white.
  final bool settled;
  final List<BoxShadow>? shadow;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: settled ? AppColors.cream : AppColors.white,
        borderRadius: AppRadius.cardRadius,
        border: Border.all(color: AppColors.ink, width: AppBorders.thick),
        boxShadow: shadow,
      ),
      child: child,
    );
  }
}

class _CardText extends StatelessWidget {
  const _CardText({required this.title, this.chip, this.trailing, this.body});

  final String title;
  final Widget? chip;
  final String? trailing;
  final String? body;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text(title, style: textTheme.titleMedium)),
            ?chip,
            if (trailing != null)
              Text(
                trailing!,
                style: textTheme.bodySmall?.copyWith(
                  color: AppColors.ink.withValues(alpha: 0.6),
                ),
              ),
          ],
        ),
        if (body != null) ...[
          const SizedBox(height: 4),
          Text(
            body!,
            style: textTheme.bodySmall?.copyWith(
              color: AppColors.ink.withValues(alpha: 0.7),
            ),
          ),
        ],
      ],
    );
  }
}

/// The deadline chip + adjoining text from the mockup — "18h left,
/// everything locks at 9:00" — and, under it, the early-close count:
/// how many of the players this round waits for are done. A count only,
/// never who's missing — that's the pressure the game avoids.
class _RoundDeadlineRow extends StatelessWidget {
  const _RoundDeadlineRow({required this.room, required this.round});

  final RoomDetail room;
  final RoundInfo? round;

  @override
  Widget build(BuildContext context) {
    final endsAt = room.roundEndsAt;
    if (endsAt == null) return const SizedBox.shrink();

    final textTheme = Theme.of(context).textTheme;
    final muted = textTheme.bodySmall?.copyWith(
      color: AppColors.ink.withValues(alpha: 0.6),
    );
    final locked = room.isRoundLocked;
    final myUid = FirebaseAuth.instance.currentUser?.uid;
    final required = round?.requiredUids ?? const <String>[];
    final doneUids = round?.doneUids ?? const <String>[];
    final done = doneUids.where(required.contains).length;

    String? doneLine;
    if (!locked && done > 0) {
      doneLine = doneUids.contains(myUid) && done < required.length
          ? "You're done. Results at ${clockTime(endsAt)}, or sooner if "
                'everyone finishes.'
          : "$done of ${required.length} done · results come early once "
                "everyone's in";
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            DeadlineChip(endsAt: endsAt),
            const SizedBox(width: AppSpacing.sm),
            Flexible(
              child: Text(
                locked
                    ? 'opening the next round…'
                    : 'everything locks at ${clockTime(endsAt)}',
                style: muted,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        if (doneLine != null) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(doneLine, style: muted),
        ],
      ],
    );
  }
}

class _Message extends StatelessWidget {
  const _Message(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ),
    );
  }
}
