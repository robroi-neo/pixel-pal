import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../models/drawing_submission.dart';
import '../../models/guess_progress.dart';
import '../../models/membership.dart';
import '../../models/room_detail.dart';
import '../../models/round_info.dart';
import '../../models/round_scores.dart';
import '../../router/app_router.dart';
import '../../services/drawing_service.dart';
import '../../services/guess_service.dart';
import '../../services/room_service.dart';
import '../../services/round_service.dart';
import '../../services/score_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_dimens.dart';
import '../../theme/app_tokens.dart';
import '../../utils/seeded_order.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_chip.dart';
import '../../widgets/deadline_chip.dart';
import '../../widgets/loading_view.dart';
import '../../widgets/pixel_canvas.dart';
import '../../widgets/profile_avatar.dart';
import '../../widgets/rank_delta.dart';
import 'round_transition_view.dart';

/// Design.md §5 "Round home (hub)": the room's current round n. Draw
/// round n's prompt, guess round n−1's drawings (round 1 is draw-only),
/// and — from round 3 — open round n−2's results, which landed when this
/// round opened. One primary button, on whichever card needs you; the
/// card that needs you carries the shadow.
///
/// The round changing over is its own moment, not a quiet number change:
/// the first time a player opens a round, [RoundStartView] takes over the
/// screen, and once a deadline passes [RoundClosingView] holds it while
/// the room moves on. Opening this screen [RoundService.checkIn]s, which
/// is also what moves the room on — there's no scheduler on Spark to do
/// it on the dot — and it keeps retrying while the round is closing.
class RoundHomeScreen extends StatefulWidget {
  const RoundHomeScreen({super.key, required this.roomId});

  final String roomId;

  @override
  State<RoundHomeScreen> createState() => _RoundHomeScreenState();
}

class _RoundHomeScreenState extends State<RoundHomeScreen> {
  late final Stream<RoomDetail?> _room = RoomService().watchRoom(widget.roomId);
  late final Stream<Membership> _membership = RoomService().watchMembership(
    widget.roomId,
  );

  Timer? _ticker;
  RoomDetail? _latestRoom;
  bool _checkingIn = false;

  /// The round whose start was just dismissed here — hides the takeover
  /// straight away, before the member doc write round-trips.
  int? _startedRound;

  @override
  void initState() {
    super.initState();
    _checkIn();
    // Keeps "18h left" fresh, notices the deadline passing, and keeps
    // retrying the move to the next round while this one is closing.
    _ticker = Timer.periodic(const Duration(seconds: 20), (_) {
      if (!mounted) return;
      setState(() {});
      if (_latestRoom?.isRoundLocked ?? false) _checkIn();
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _checkIn() async {
    if (_checkingIn) return;
    _checkingIn = true;
    try {
      await RoundService().checkIn(widget.roomId);
    } finally {
      _checkingIn = false;
    }
  }

  void _startRound(int round) {
    HapticFeedback.mediumImpact();
    setState(() => _startedRound = round);
    RoomService().markSeen(widget.roomId, round: round);
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<RoomDetail?>(
      stream: _room,
      builder: (context, roomSnapshot) {
        return StreamBuilder<Membership>(
          stream: _membership,
          builder: (context, memberSnapshot) {
            return AnimatedSwitcher(
              duration: MediaQuery.of(context).disableAnimations
                  ? Duration.zero
                  : const Duration(milliseconds: 400),
              child: _screenFor(roomSnapshot, memberSnapshot),
            );
          },
        );
      },
    );
  }

  Widget _screenFor(
    AsyncSnapshot<RoomDetail?> roomSnapshot,
    AsyncSnapshot<Membership> memberSnapshot,
  ) {
    final room = roomSnapshot.data;
    _latestRoom = room;

    if (roomSnapshot.hasError) {
      return _PlainScaffold(
        key: const ValueKey('error'),
        child: _Message("Couldn't load this room."),
      );
    }
    // A deleted room arrives as null data, not as "still loading".
    if (roomSnapshot.connectionState == ConnectionState.waiting) {
      return const _PlainScaffold(
        key: ValueKey('loading'),
        child: LoadingView(message: 'Opening the room…'),
      );
    }
    if (room == null) {
      return _PlainScaffold(
        key: const ValueKey('gone'),
        child: _Message('This room no longer exists.'),
      );
    }
    final round = room.currentRound;
    if (round == null) {
      return _PlainScaffold(
        key: const ValueKey('legacy'),
        title: room.name,
        child: _Message(
          "This room started before rounds were added, so it can't move "
          'on to round 2. Delete it and start a new one.',
        ),
      );
    }

    if (room.isRoundLocked) {
      return RoundClosingView(
        key: ValueKey('closing-$round'),
        round: round,
        onRetry: _checkIn,
      );
    }

    // If the member doc can't be read, skip the one-time moments rather
    // than block the hub on them.
    final membership = memberSnapshot.hasError
        ? Membership(seenRound: round, seenResultsRound: round)
        : memberSnapshot.data;
    if (membership == null) {
      return const _PlainScaffold(
        key: ValueKey('loading'),
        child: LoadingView(message: 'Opening the room…'),
      );
    }
    if (membership.seenRound < round && _startedRound != round) {
      return RoundStartView(
        key: ValueKey('start-$round'),
        room: room,
        round: round,
        onStart: () => _startRound(round),
      );
    }

    final isOwner = room.isOwnedBy(
      FirebaseAuth.instance.currentUser?.uid ?? '',
    );
    return Scaffold(
      key: const ValueKey('hub'),
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_outlined),
          onPressed: () => context.pop(),
        ),
        title: Text(room.name, style: Theme.of(context).textTheme.titleMedium),
        actions: [
          PopupMenuButton<void>(
            icon: const Icon(Icons.more_horiz),
            itemBuilder: (_) => [
              // Owner-only: the invite screen is otherwise unreachable
              // now that owners land here too.
              if (isOwner)
                PopupMenuItem(
                  onTap: () => context.push('${AppRoutes.rooms}/${room.id}'),
                  child: const Text('Invite players'),
                ),
              PopupMenuItem(
                onTap: () => context.push(
                  AppRoutes.howToPlayPath(room.roundLengthHours),
                ),
                child: const Text('How to play'),
              ),
            ],
          ),
        ],
      ),
      body: SafeArea(
        // A fresh body per round, so its per-round streams follow the
        // room when it moves on.
        child: _RoundHomeBody(
          key: ValueKey(round),
          room: room,
          round: round,
          membership: membership,
        ),
      ),
    );
  }
}

class _RoundHomeBody extends StatefulWidget {
  const _RoundHomeBody({
    super.key,
    required this.room,
    required this.round,
    required this.membership,
  });

  final RoomDetail room;
  final int round;
  final Membership membership;

  @override
  State<_RoundHomeBody> createState() => _RoundHomeBodyState();
}

class _RoundHomeBodyState extends State<_RoundHomeBody> {
  // Created once and reused, not inline in build() — StreamBuilder treats
  // a freshly-created Stream as "changed" on every rebuild and
  // resubscribes, which would reset these cards to their loading state.
  late final Stream<DrawingSubmission?> _myDrawing = DrawingService()
      .watchMyDrawing(widget.room.id, widget.round);
  late final Stream<List<String>?> _issuedPromptIds = RoomService()
      .watchIssuedPromptIds(
        widget.room.id,
        widget.round,
        FirebaseAuth.instance.currentUser!.uid,
      );
  late final Stream<RoundInfo?> _roundInfo = RoundService().watchRound(
    widget.room.id,
    widget.round,
  );
  late final Stream<List<RoundScores>> _scores = ScoreService().watchLatest(
    widget.room.id,
  );

  // Last round's drawings — the ones to guess now. Round 1 has none.
  late final Stream<List<DrawingSubmission>> _toGuess = widget.round > 1
      ? DrawingService().watchOthersDrawings(widget.room.id, widget.round - 1)
      : Stream.value(const []);
  late final Stream<Map<String, GuessProgress>> _myGuesses = widget.round > 1
      ? GuessService().watchMyGuesses(widget.room.id, widget.round - 1)
      : Stream.value(const {});

  @override
  Widget build(BuildContext context) {
    final room = widget.room;
    final n = widget.round;
    final myUid = FirebaseAuth.instance.currentUser?.uid ?? '';

    return StreamBuilder<DrawingSubmission?>(
      stream: _myDrawing,
      builder: (context, mineSnapshot) {
        return StreamBuilder<List<DrawingSubmission>>(
          stream: _toGuess,
          builder: (context, drawingsSnapshot) {
            return StreamBuilder<Map<String, GuessProgress>>(
              stream: _myGuesses,
              builder: (context, guessesSnapshot) {
                return StreamBuilder<List<RoundScores>>(
                  stream: _scores,
                  builder: (context, scoresSnapshot) {
                    if (!mineSnapshot.hasData &&
                        mineSnapshot.connectionState ==
                            ConnectionState.waiting) {
                      return const LoadingView();
                    }
                    final mine = mineSnapshot.data;
                    final submitted = mine != null;
                    // The same per-player order as the guess grid.
                    final drawings = seededOrder(
                      drawingsSnapshot.data ?? const <DrawingSubmission>[],
                      seed: '$myUid:${room.id}:${n - 1}',
                      idOf: (d) => d.authorUid,
                    );
                    final guesses = guessesSnapshot.data ?? const {};
                    final done = drawings
                        .where((d) => guesses[d.authorUid]?.isDone ?? false)
                        .length;
                    final guessingLeft = n > 1 && done < drawings.length;
                    final todo = (submitted ? 0 : 1) + (guessingLeft ? 1 : 0);
                    final scores = scoresSnapshot.data ?? const [];
                    final resultsRound = room.latestResultsRound;

                    return ListView(
                      padding: const EdgeInsets.all(AppSpacing.lg),
                      children: [
                        StreamBuilder<RoundInfo?>(
                          stream: _roundInfo,
                          builder: (context, snapshot) =>
                              _Header(room: room, round: snapshot.data),
                        ),
                        if (resultsRound != null) ...[
                          const SizedBox(height: AppSpacing.lg),
                          _ResultsBanner(
                            round: resultsRound,
                            words: _wordsToReveal(scores, resultsRound, myUid),
                            isNew:
                                widget.membership.seenResultsRound <
                                resultsRound,
                            onTap: () => context.push(
                              AppRoutes.resultsPath(room.id, resultsRound),
                            ),
                          ),
                        ],
                        const SizedBox(height: AppSpacing.xl),
                        _SectionLabel(
                          todo == 0
                              ? 'All done for round $n'
                              : 'To do this round · $todo',
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        _DrawingCard(
                          room: room,
                          round: n,
                          mine: mine,
                          issuedPromptIds: _issuedPromptIds,
                        ),
                        const SizedBox(height: AppSpacing.md),
                        _GuessCard(
                          room: room,
                          round: n,
                          drawings: drawings,
                          guesses: guesses,
                          primary: submitted && guessingLeft,
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        _LeaderboardCard(room: room, round: n, scores: scores),
                      ],
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }

  /// Other players' drawings in the results round — from its scores doc,
  /// once it's been scored.
  int? _wordsToReveal(List<RoundScores> scores, int round, String myUid) {
    final forRound = scores.where((s) => s.round == round).firstOrNull;
    if (forRound == null) return null;
    return forRound.entries.entries
        .where((e) => e.value.drew && e.key != myUid)
        .length;
  }
}

/// "Round 5" and when it locks, with the deadline chip; under it, the
/// early-close count — how many of the players this round waits for are
/// done. A count only, never who's missing: that's the pressure the game
/// avoids.
class _Header extends StatelessWidget {
  const _Header({required this.room, required this.round});

  final RoomDetail room;
  final RoundInfo? round;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final muted = textTheme.bodySmall?.copyWith(
      color: AppColors.ink.withValues(alpha: 0.7),
    );
    final endsAt = room.roundEndsAt;
    final myUid = FirebaseAuth.instance.currentUser?.uid;
    final required = round?.requiredUids ?? const <String>[];
    final doneUids = round?.doneUids ?? const <String>[];
    final done = doneUids.where(required.contains).length;

    String? doneLine;
    if (endsAt != null && done > 0) {
      doneLine = doneUids.contains(myUid) && done < required.length
          ? "You're done. Results at ${clockTime(endsAt)}, or sooner if "
                'everyone finishes.'
          : '$done of ${required.length} done · results come early once '
                "everyone's in";
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Round ${room.currentRound}',
                    style: textTheme.headlineMedium?.copyWith(fontSize: 34),
                  ),
                  if (endsAt != null)
                    Text('Everything locks ${lockTime(endsAt)}', style: muted),
                ],
              ),
            ),
            if (endsAt != null) DeadlineChip(endsAt: endsAt),
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

/// The newest results. Loud (ink, "NEW") until the player has opened
/// them, then a quiet cream way back in.
class _ResultsBanner extends StatelessWidget {
  const _ResultsBanner({
    required this.round,
    required this.words,
    required this.isNew,
    required this.onTap,
  });

  final int round;

  /// Other players' drawings to reveal — null until the round's scored.
  final int? words;
  final bool isNew;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;
    final accent = theme.colorScheme.primary;
    final fg = isNew ? accent : AppColors.ink;
    final w = words;

    return Material(
      color: isNew ? AppColors.ink : AppColors.cream,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.cardRadius,
        side: const BorderSide(color: AppColors.ink, width: AppBorders.thick),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: isNew ? accent : AppColors.ink,
                  borderRadius: AppRadius.controlRadius,
                ),
                child: Text(
                  '$round',
                  style: textTheme.titleLarge?.copyWith(
                    color: isNew ? AppColors.ink : accent,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (isNew)
                      Row(
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              color: accent,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.xs),
                          Text(
                            'NEW',
                            style: textTheme.labelSmall?.copyWith(
                              color: accent,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1.2,
                            ),
                          ),
                        ],
                      ),
                    Text(
                      isNew
                          ? 'Round $round results are in'
                          : 'Round $round results',
                      style: textTheme.titleMedium?.copyWith(color: fg),
                    ),
                    Text(
                      !isNew
                          ? 'See how everyone did'
                          : w == null || w == 0
                          ? 'Reveal them one at a time'
                          : '$w ${w == 1 ? 'word' : 'words'} to reveal, one '
                                'at a time',
                      style: textTheme.bodySmall?.copyWith(
                        color: isNew
                            ? AppColors.cream.withValues(alpha: 0.75)
                            : AppColors.ink.withValues(alpha: 0.7),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.arrow_forward_rounded, color: fg),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: 1.2,
        color: AppColors.ink.withValues(alpha: 0.75),
      ),
    );
  }
}

/// White with the shadow while it needs you (Design.md §4), cream and
/// flat once it's settled.
class _TaskCard extends StatelessWidget {
  const _TaskCard({required this.needsYou, required this.child});

  final bool needsYou;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    return AnimatedContainer(
      duration: AppMotion.duration,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: needsYou ? AppColors.white : AppColors.cream,
        borderRadius: AppRadius.cardRadius,
        border: Border.all(color: AppColors.ink, width: AppBorders.thick),
        boxShadow: needsYou ? tokens.hardShadow : null,
      ),
      child: child,
    );
  }
}

class _DrawingCard extends StatelessWidget {
  const _DrawingCard({
    required this.room,
    required this.round,
    required this.mine,
    required this.issuedPromptIds,
  });

  final RoomDetail room;
  final int round;
  final DrawingSubmission? mine;
  final Stream<List<String>?> issuedPromptIds;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final muted = textTheme.bodySmall?.copyWith(
      color: AppColors.ink.withValues(alpha: 0.7),
    );
    final drawing = mine;
    final canvas = '${room.canvasSize} × ${room.canvasSize} canvas';

    return _TaskCard(
      needsYou: drawing == null,
      child: StreamBuilder<List<String>?>(
        stream: issuedPromptIds,
        builder: (context, snapshot) {
          final hasPrompts = snapshot.data?.isNotEmpty ?? false;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text('Your drawing', style: textTheme.titleMedium),
                  ),
                  drawing != null
                      ? const NeutralChip('submitted')
                      : hasPrompts
                      ? const NeutralChip('prompts picked')
                      : const AttentionChip('not started'),
                ],
              ),
              const SizedBox(height: 4),
              if (drawing == null) ...[
                Text(
                  hasPrompts
                      ? 'Your 3 prompts are saved · $canvas'
                      : '3 prompts waiting · $canvas',
                  style: muted,
                ),
                const SizedBox(height: AppSpacing.md),
                AppButton(
                  label: 'Pick your prompt',
                  onPressed: () async =>
                      context.push(AppRoutes.promptPickPath(room.id, round)),
                ),
              ] else
                Row(
                  children: [
                    _Thumb(drawing: drawing, size: 56),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(drawing.word, style: textTheme.titleMedium),
                          Text(
                            'Everyone guesses it in round ${round + 1}.',
                            style: muted,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
            ],
          );
        },
      ),
    );
  }
}

/// Last round's drawings as a strip of thumbnails, in the player's own
/// order. The drawer's name only shows under a card once it's finished —
/// the guessing flow keeps the drawer hidden until then.
class _GuessCard extends StatelessWidget {
  const _GuessCard({
    required this.room,
    required this.round,
    required this.drawings,
    required this.guesses,
    required this.primary,
  });

  final RoomDetail room;
  final int round;
  final List<DrawingSubmission> drawings;
  final Map<String, GuessProgress> guesses;

  /// Guessing is the only thing left — its action is the screen's one
  /// primary button rather than a text link.
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final muted = textTheme.bodySmall?.copyWith(
      color: AppColors.ink.withValues(alpha: 0.7),
    );

    if (round == 1) {
      return _TaskCard(
        needsYou: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Guessing', style: textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              "Round 1 is draw-only. Everyone's round 1 drawings open for "
              'guessing in round 2.',
              style: muted,
            ),
          ],
        ),
      );
    }

    final guessRound = round - 1;
    bool isDone(DrawingSubmission d) => guesses[d.authorUid]?.isDone ?? false;
    final done = drawings.where(isDone).length;
    final upNext = drawings.indexWhere((d) => !isDone(d));
    final endsAt = room.roundEndsAt;

    void openCard(DrawingSubmission d) => context.push(
      AppRoutes.guessDrawingPath(room.id, guessRound, d.authorUid),
    );

    return _TaskCard(
      needsYou: upNext >= 0,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Guess round $guessRound',
                  style: textTheme.titleMedium,
                ),
              ),
              Text(
                '$done of ${drawings.length} done',
                style: muted?.copyWith(fontWeight: FontWeight.w600),
              ),
            ],
          ),
          if (drawings.isEmpty) ...[
            const SizedBox(height: 4),
            Text(
              "Nobody else drew in round $guessRound, so there's nothing to "
              'guess.',
              style: muted,
            ),
          ] else ...[
            const SizedBox(height: AppSpacing.md),
            SizedBox(
              height: 104,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                clipBehavior: Clip.none,
                itemCount: drawings.length,
                separatorBuilder: (_, _) =>
                    const SizedBox(width: AppSpacing.sm),
                itemBuilder: (context, i) => _GuessThumb(
                  drawing: drawings[i],
                  number: i + 1,
                  progress: guesses[drawings[i].authorUid],
                  upNext: i == upNext,
                  onTap: () => openCard(drawings[i]),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Divider(color: AppColors.ink.withValues(alpha: 0.15)),
            const SizedBox(height: AppSpacing.sm),
            if (upNext >= 0 && primary) ...[
              Text('Up next: drawing #${upNext + 1}', style: muted),
              const SizedBox(height: AppSpacing.sm),
              AppButton(
                label: 'Keep guessing',
                onPressed: () async => openCard(drawings[upNext]),
              ),
            ] else
              Row(
                children: [
                  Expanded(
                    child: Text(
                      upNext >= 0
                          ? 'Up next: drawing #${upNext + 1}'
                          : endsAt == null
                          ? 'All guessed'
                          : 'All guessed · results ${lockTime(endsAt)}',
                      style: muted,
                    ),
                  ),
                  TextButton(
                    onPressed: () => upNext >= 0
                        ? openCard(drawings[upNext])
                        : context.push(
                            AppRoutes.guessPath(room.id, guessRound),
                          ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(upNext >= 0 ? 'Keep guessing' : 'Your guesses'),
                        const SizedBox(width: AppSpacing.xs),
                        const Icon(Icons.arrow_forward_rounded, size: 16),
                      ],
                    ),
                  ),
                ],
              ),
          ],
        ],
      ),
    );
  }
}

class _GuessThumb extends StatelessWidget {
  const _GuessThumb({
    required this.drawing,
    required this.number,
    required this.progress,
    required this.upNext,
    required this.onTap,
  });

  final DrawingSubmission drawing;
  final int number;
  final GuessProgress? progress;
  final bool upNext;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.onSecondary;
    final p = progress ?? GuessProgress.initial;
    final labelStyle = theme.textTheme.bodySmall?.copyWith(
      fontWeight: upNext ? FontWeight.w700 : FontWeight.w500,
      color: upNext ? AppColors.ink : AppColors.ink.withValues(alpha: 0.7),
    );

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 72,
        child: Column(
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Opacity(
                  opacity: p.isOutOfAttempts ? 0.5 : 1,
                  child: _Thumb(drawing: drawing, size: 72, emphasis: upNext),
                ),
                if (p.isDone)
                  Positioned(
                    top: -4,
                    right: -4,
                    child: Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        color: AppColors.ink,
                        shape: BoxShape.circle,
                        border: Border.all(color: AppColors.white, width: 2),
                      ),
                      child: Icon(
                        p.solved ? Icons.check_rounded : Icons.close_rounded,
                        size: 13,
                        color: accent,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            // The drawer stays hidden until the card is finished.
            p.isDone
                ? ProfileBuilder(
                    uid: drawing.authorUid,
                    builder: (context, author) => Text(
                      author?.displayName ?? drawing.authorDisplayName,
                      style: labelStyle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  )
                : Text('#$number', style: labelStyle),
          ],
        ),
      ),
    );
  }
}

/// A drawing at thumbnail size, still in its full frame (Design.md §4):
/// cream band → white card with an ink border → locked canvas.
class _Thumb extends StatelessWidget {
  const _Thumb({
    required this.drawing,
    required this.size,
    this.emphasis = false,
  });

  final DrawingSubmission drawing;
  final double size;
  final bool emphasis;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppColors.cream,
        borderRadius: BorderRadius.circular(AppRadius.control),
      ),
      child: Container(
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(AppRadius.control - 2),
          border: Border.all(
            color: AppColors.ink,
            width: emphasis ? AppBorders.thick : AppBorders.thin,
          ),
        ),
        child: ColoredBox(
          color: AppColors.canvas,
          child: PixelPreview(
            canvasSize: drawing.canvasSize,
            pixels: drawing.pixels,
          ),
        ),
      ),
    );
  }
}

/// The top of the table — quiet and cream (Design.md §5 keeps rank from
/// competing with the round's tasks), with the player's own row picked
/// out, and "See all" to the full leaderboard.
class _LeaderboardCard extends StatelessWidget {
  const _LeaderboardCard({
    required this.room,
    required this.round,
    required this.scores,
  });

  final RoomDetail room;
  final int round;

  /// Newest first: the latest table, and the one before for rank moves.
  final List<RoundScores> scores;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final myUid = FirebaseAuth.instance.currentUser?.uid;

    final table = scores.isEmpty
        ? const <Standing>[]
        : scores.first.standings(room.memberUids);
    final before = scores.length > 1
        ? {for (final s in scores[1].standings(room.memberUids)) s.uid: s.rank}
        : const <String, int>{};
    final deltas = rankDeltas(before, {for (final s in table) s.uid: s.rank});
    final me = table.where((s) => s.uid == myUid).firstOrNull;
    final rows = [
      ...table.take(3),
      if (me != null && table.indexOf(me) >= 3) me,
    ];

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.cream,
        borderRadius: AppRadius.cardRadius,
        border: Border.all(color: AppColors.ink, width: AppBorders.thick),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('Leaderboard', style: textTheme.titleMedium),
              ),
              if (table.isNotEmpty)
                TextButton(
                  onPressed: () =>
                      context.push(AppRoutes.leaderboardPath(room.id)),
                  child: const Text('See all'),
                ),
            ],
          ),
          if (table.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xs),
              child: Text(
                round < 3
                    ? "The table starts once round 1's results are in — "
                          'when round 2 ends.'
                    : 'Tallying the table…',
                style: textTheme.bodySmall?.copyWith(
                  color: AppColors.ink.withValues(alpha: 0.7),
                ),
              ),
            )
          else
            for (final s in rows)
              _StandingRow(
                standing: s,
                delta: deltas[s.uid],
                isMe: s.uid == myUid,
              ),
        ],
      ),
    );
  }
}

class _StandingRow extends StatelessWidget {
  const _StandingRow({
    required this.standing,
    required this.delta,
    required this.isMe,
  });

  final Standing standing;
  final int? delta;
  final bool isMe;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<AppTokens>()!;
    return Container(
      margin: const EdgeInsets.only(top: AppSpacing.xs),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: isMe ? AppColors.white : null,
        borderRadius: AppRadius.controlRadius,
        border: isMe
            ? Border.all(color: AppColors.ink, width: AppBorders.thin)
            : null,
      ),
      child: Row(
        children: [
          SizedBox(
            width: 22,
            child: Text(
              '${standing.rank}',
              style: tokens.scoreNumeral.copyWith(fontSize: 14),
            ),
          ),
          ProfileAvatar(uid: standing.uid, fallbackInitials: '?', size: 28),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: isMe
                ? Text(
                    'You',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  )
                : ProfileBuilder(
                    uid: standing.uid,
                    builder: (context, profile) => Text(
                      profile?.displayName ?? 'A player',
                      style: theme.textTheme.bodyMedium,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
          ),
          RankDelta(delta: delta),
          const SizedBox(width: AppSpacing.md),
          SizedBox(
            width: 52,
            child: Text(
              '${standing.score}',
              textAlign: TextAlign.right,
              style: tokens.scoreNumeral.copyWith(fontSize: 18),
            ),
          ),
        ],
      ),
    );
  }
}

/// A loading/error/empty state with the hub's plain yellow chrome.
class _PlainScaffold extends StatelessWidget {
  const _PlainScaffold({super.key, required this.child, this.title});

  final Widget child;
  final String? title;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_outlined),
          onPressed: () => context.pop(),
        ),
        title: Text(
          title ?? '',
          style: Theme.of(context).textTheme.titleMedium,
        ),
      ),
      body: SafeArea(child: child),
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
