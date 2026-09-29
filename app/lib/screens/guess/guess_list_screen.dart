import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../models/drawing_submission.dart';
import '../../models/guess_progress.dart';
import '../../models/room_detail.dart';
import '../../router/app_router.dart';
import '../../services/drawing_service.dart';
import '../../services/guess_service.dart';
import '../../services/room_service.dart';
import '../../services/round_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_dimens.dart';
import '../../theme/app_tokens.dart';
import '../../utils/seeded_order.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_chip.dart';
import '../../widgets/attempt_dots.dart';
import '../../widgets/deadline_chip.dart';
import '../../widgets/drawing_art.dart';
import '../../widgets/loading_view.dart';
import '../../widgets/profile_avatar.dart';
import '../../widgets/segmented_progress.dart';

/// Guessing flow, screen A — the grid hub for round [GuessListScreen.round]'s
/// drawings, guessed during the round after it. Every other player's
/// drawing as a numbered tile, in a seeded per-player order; players pick their
/// own order. Tiles show only your own progress, never whether anyone
/// else has finished, and the drawer's name only once you've finished
/// that card. A progress bar and "3 of 4 drawings left" are the pace cue,
/// not a timer.
///
/// Tapping a tile opens [GuessScreen] on it. Once the round's results are
/// out, the tiles open the reveal ([GuessResultsScreen]) instead.
class GuessListScreen extends StatefulWidget {
  const GuessListScreen({super.key, required this.roomId, required this.round});

  final String roomId;

  /// The round the drawings were made in.
  final int round;

  @override
  State<GuessListScreen> createState() => _GuessListScreenState();
}

class _GuessListScreenState extends State<GuessListScreen> {
  late final Stream<RoomDetail?> _room = RoomService().watchRoom(widget.roomId);
  late final Stream<List<DrawingSubmission>> _drawings = DrawingService()
      .watchOthersDrawings(widget.roomId, widget.round);
  late final Stream<Map<String, GuessProgress>> _myGuesses = GuessService()
      .watchMyGuesses(widget.roomId, widget.round);

  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    // Catches an early close someone else's app missed.
    RoundService().checkIn(widget.roomId);
    // Keeps "18h left" fresh and notices the deadline passing.
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
    final textTheme = Theme.of(context).textTheme;

    return StreamBuilder<RoomDetail?>(
      stream: _room,
      builder: (context, roomSnapshot) {
        final room = roomSnapshot.data;
        // The deadline that matters here is the guessing round's.
        final endsAt = room?.currentRound == widget.round + 1
            ? room?.roundEndsAt
            : null;
        return Scaffold(
          appBar: AppBar(
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_outlined),
              onPressed: () => context.pop(),
            ),
            title: Text(room?.name ?? '', style: textTheme.titleMedium),
            actions: [
              if (endsAt != null)
                Padding(
                  padding: const EdgeInsets.only(right: AppSpacing.lg),
                  child: Center(child: DeadlineChip(endsAt: endsAt)),
                ),
            ],
          ),
          body: SafeArea(
            child: StreamBuilder<List<DrawingSubmission>>(
              stream: _drawings,
              builder: (context, drawingsSnapshot) {
                return StreamBuilder<Map<String, GuessProgress>>(
                  stream: _myGuesses,
                  builder: (context, guessesSnapshot) {
                    if (roomSnapshot.hasError ||
                        drawingsSnapshot.hasError ||
                        guessesSnapshot.hasError) {
                      return Center(
                        child: Text(
                          "Couldn't load the drawings.",
                          style: textTheme.bodyMedium,
                        ),
                      );
                    }
                    if (!roomSnapshot.hasData ||
                        !drawingsSnapshot.hasData ||
                        !guessesSnapshot.hasData) {
                      return const LoadingView();
                    }
                    if (room == null) {
                      return Center(
                        child: Text(
                          'This room no longer exists.',
                          style: textTheme.bodyMedium,
                        ),
                      );
                    }
                    return _GridBody(
                      room: room,
                      round: widget.round,
                      drawings: drawingsSnapshot.data!,
                      myGuesses: guessesSnapshot.data!,
                    );
                  },
                );
              },
            ),
          ),
        );
      },
    );
  }
}

class _GridBody extends StatelessWidget {
  const _GridBody({
    required this.room,
    required this.round,
    required this.drawings,
    required this.myGuesses,
  });

  final RoomDetail room;
  final int round;
  final List<DrawingSubmission> drawings;
  final Map<String, GuessProgress> myGuesses;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final myUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final open = room.isGuessingOpen(round);
    final revealed = room.isRevealed(round);

    final ordered = seededOrder(
      drawings,
      seed: '$myUid:${room.id}:$round',
      idOf: (d) => d.authorUid,
    );
    final doneCount = ordered
        .where((d) => myGuesses[d.authorUid]?.isDone ?? false)
        .length;
    final left = ordered.length - doneCount;

    void openResults([String? startAt]) =>
        context.push(AppRoutes.resultsPath(room.id, round, startAt: startAt));

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Guess round $round', style: textTheme.headlineMedium),
          const SizedBox(height: AppSpacing.xs),
          Text(
            ordered.isEmpty
                ? 'Nobody else drew in round $round.'
                : revealed
                ? 'The results are in'
                : !open
                ? 'Guessing is closed'
                : left == 0
                ? 'all ${ordered.length} drawings guessed'
                : '$left of ${ordered.length} drawings left',
            style: textTheme.bodySmall?.copyWith(
              color: AppColors.ink.withValues(alpha: 0.7),
            ),
          ),
          if (ordered.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            SegmentedProgress(total: ordered.length, done: doneCount),
            const SizedBox(height: AppSpacing.lg),
            _TileGrid(
              children: [
                for (var i = 0; i < ordered.length; i++)
                  _GuessTile(
                    number: i + 1,
                    drawing: ordered[i],
                    progress: myGuesses[ordered[i].authorUid],
                    onTap: () => revealed
                        ? openResults(ordered[i].authorUid)
                        : context.push(
                            AppRoutes.guessDrawingPath(
                              room.id,
                              round,
                              ordered[i].authorUid,
                            ),
                          ),
                  ),
              ],
            ),
          ],
          if (!open || (ordered.isNotEmpty && left == 0)) ...[
            const SizedBox(height: AppSpacing.xl),
            _AllInPanel(
              open: open,
              revealed: revealed,
              endsAt: room.roundEndsAt,
              onSeeResults: openResults,
            ),
          ],
        ],
      ),
    );
  }
}

/// Two tiles per row.
class _TileGrid extends StatelessWidget {
  const _TileGrid({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = (constraints.maxWidth - AppSpacing.md) / 2;
        return Wrap(
          spacing: AppSpacing.md,
          runSpacing: AppSpacing.md,
          children: [
            for (final child in children) SizedBox(width: width, child: child),
          ],
        );
      },
    );
  }
}

/// Tile states: new (muted "new"), in progress (attempt dots), solved
/// (cream, no shadow, "solved · by Maya"), missed (as solved, art at 50%).
class _GuessTile extends StatelessWidget {
  const _GuessTile({
    required this.number,
    required this.drawing,
    required this.progress,
    required this.onTap,
  });

  final int number;
  final DrawingSubmission drawing;
  final GuessProgress? progress;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<AppTokens>()!;
    final p = progress ?? GuessProgress.initial;
    final done = p.isDone;

    final Widget status;
    if (done) {
      // The drawer's name only appears once you've finished the card.
      status = ProfileBuilder(
        uid: drawing.authorUid,
        builder: (context, author) => Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: p.solved ? 'solved' : 'missed',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              TextSpan(
                text:
                    ' · by ${author?.displayName ?? drawing.authorDisplayName}',
              ),
            ],
          ),
          style: theme.textTheme.bodySmall,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      );
    } else if (p.attempts > 0) {
      status = AttemptDots(attempts: p.attempts, size: 9);
    } else {
      status = Text(
        'new',
        style: theme.textTheme.bodySmall?.copyWith(
          color: AppColors.ink.withValues(alpha: 0.5),
        ),
      );
    }

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.sm),
        decoration: BoxDecoration(
          color: done ? AppColors.cream : AppColors.white,
          borderRadius: AppRadius.cardRadius,
          border: Border.all(color: AppColors.ink, width: AppBorders.thick),
          // Shadow means "this needs you" — settled tiles stay flat.
          boxShadow: done ? null : tokens.hardShadow,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  '#$number',
                  style: tokens.scoreNumeral.copyWith(fontSize: 12),
                ),
                const Spacer(),
                AttentionChip(drawing.difficulty.label),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Opacity(
              opacity: p.isOutOfAttempts ? 0.5 : 1,
              child: DrawingArt(drawing: drawing),
            ),
            const SizedBox(height: AppSpacing.sm),
            SizedBox(
              height: 18,
              child: Align(alignment: Alignment.centerLeft, child: status),
            ),
          ],
        ),
      ),
    );
  }
}

/// Under the grid once you've guessed everything ("All in"), once
/// guessing has closed, and once the results are out (the way into the
/// reveal).
class _AllInPanel extends StatelessWidget {
  const _AllInPanel({
    required this.open,
    required this.revealed,
    required this.endsAt,
    required this.onSeeResults,
  });

  final bool open;
  final bool revealed;
  final DateTime? endsAt;
  final VoidCallback onSeeResults;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<AppTokens>()!;
    final at = endsAt == null ? 'the deadline' : clockTime(endsAt!);

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.cream,
        borderRadius: AppRadius.cardRadius,
        border: Border.all(color: AppColors.ink, width: AppBorders.thick),
        boxShadow: revealed ? tokens.hardShadow : null,
      ),
      child: Column(
        children: [
          Text(
            revealed
                ? 'Results are in'
                : open
                ? 'All in'
                : 'Guessing is closed',
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            revealed
                ? 'See who got each one, and how your round scored.'
                : !open
                ? 'The results are on their way.'
                : 'Who else got each one lands with the results at $at, '
                      'or sooner if everyone finishes.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppColors.ink.withValues(alpha: 0.7),
            ),
          ),
          if (revealed) ...[
            const SizedBox(height: AppSpacing.md),
            AppButton(
              label: 'See the results',
              onPressed: () async => onSeeResults(),
            ),
          ],
        ],
      ),
    );
  }
}
