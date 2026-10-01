import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../models/drawing_submission.dart';
import '../../models/guess_progress.dart';
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
import '../../widgets/app_snackbar.dart';
import '../../widgets/deadline_chip.dart';
import '../../widgets/drawing_art.dart';
import '../../widgets/profile_avatar.dart';
import '../../widgets/reveal_chrome.dart';

/// Guessing flow, screen E — round [GuessResultsScreen.round]'s reveal,
/// once the round its drawings were guessed in has ended. Design.md §5:
/// sequenced, not tabulated — each word in turn (the drawing, who drew
/// it, who solved it on which try, and your star), then your own drawing,
/// then your round score and where it leaves you, then the table. Chrome
/// goes near-black for the payoff; the canvas doesn't move.
class GuessResultsScreen extends StatefulWidget {
  const GuessResultsScreen({
    super.key,
    required this.roomId,
    required this.round,
    this.startAt,
  });

  final String roomId;

  /// The round the drawings were made in.
  final int round;

  /// Author uid of the drawing whose stage to open on.
  final String? startAt;

  @override
  State<GuessResultsScreen> createState() => _GuessResultsScreenState();
}

enum _StageKind { word, mine, score }

class _Stage {
  const _Stage(this.kind, [this.drawing]);

  final _StageKind kind;
  final DrawingSubmission? drawing;
}

class _GuessResultsScreenState extends State<GuessResultsScreen> {
  final _guessService = GuessService();
  late final Stream<RoomDetail?> _room = RoomService().watchRoom(widget.roomId);
  late final Stream<List<DrawingSubmission>> _drawings = DrawingService()
      .watchDrawings(widget.roomId, widget.round);
  late final Stream<Set<String>> _stars = _guessService.watchMyStars(
    widget.roomId,
    widget.round,
  );
  late final Stream<Map<String, Map<String, GuessProgress>>> _guesses =
      _guessService.watchAllGuesses(widget.roomId, widget.round);

  /// The round these drawings were guessed in — who it waited for, and
  /// whether it closed early.
  late final Stream<RoundInfo?> _guessRound = RoundService().watchRound(
    widget.roomId,
    widget.round + 1,
  );
  late final Stream<RoundScores?> _scores = ScoreService().watchRound(
    widget.roomId,
    widget.round,
  );

  /// Null in round 1 — there's no table before it. Not a one-shot
  /// `Stream.value(null)`: the pager rebuilds the score stage each time
  /// it's swiped back to, and a single-subscription stream can't be
  /// listened to twice.
  late final Stream<RoundScores?>? _previousScores = widget.round > 1
      ? ScoreService().watchRound(widget.roomId, widget.round - 1)
      : null;

  PageController? _pager;
  int _page = 0;
  bool _markedSeen = false;

  /// Stars toggled here, shown before the write round-trips.
  final _starOverrides = <String, bool>{};

  @override
  void initState() {
    super.initState();
    // The score stage needs this round tallied; usually it already is.
    ScoreService().ensureScored(widget.roomId);
  }

  @override
  void dispose() {
    _pager?.dispose();
    super.dispose();
  }

  void _goTo(int page) {
    final pager = _pager;
    if (pager == null) return;
    if (MediaQuery.of(context).disableAnimations) {
      pager.jumpToPage(page);
    } else {
      pager.animateToPage(
        page,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
      );
    }
  }

  Future<void> _toggleStar(String authorUid, bool starred) async {
    HapticFeedback.selectionClick();
    setState(() => _starOverrides[authorUid] = starred);
    try {
      await _guessService.setStarred(
        roomId: widget.roomId,
        round: widget.round,
        authorUid: authorUid,
        starred: starred,
      );
    } on GuessServiceException catch (e) {
      if (!mounted) return;
      setState(() => _starOverrides.remove(authorUid));
      AppSnackBar.show(context, e.message);
    }
  }

  void _markSeen(RoomDetail room) {
    if (_markedSeen || room.latestResultsRound != widget.round) return;
    _markedSeen = true;
    RoomService().markSeen(widget.roomId, resultsRound: widget.round);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;

    return Scaffold(
      backgroundColor: AppColors.ink,
      appBar: AppBar(
        backgroundColor: AppColors.ink,
        foregroundColor: accent,
        automaticallyImplyLeading: false,
        titleSpacing: AppSpacing.lg,
        title: Text(
          'Round ${widget.round} results',
          style: theme.textTheme.titleMedium?.copyWith(color: accent),
        ),
        actions: [
          IconButton(
            tooltip: 'Close',
            icon: Icon(Icons.close_rounded, color: accent),
            onPressed: () => context.pop(),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: StreamBuilder<RoomDetail?>(
          stream: _room,
          builder: (context, roomSnapshot) {
            return StreamBuilder<List<DrawingSubmission>>(
              stream: _drawings,
              builder: (context, drawingsSnapshot) {
                if (roomSnapshot.hasError) {
                  return const _Message("Couldn't load the results.");
                }
                if (!roomSnapshot.hasData) {
                  return const _DarkLoading('Opening the results…');
                }
                final room = roomSnapshot.data;
                if (room == null) {
                  return const _Message('This room no longer exists.');
                }
                // Checked before the drawings: until then, other players'
                // drawings and guesses aren't readable at all.
                if (!room.isRevealed(widget.round)) {
                  final endsAt = room.roundEndsAt;
                  return _Message(
                    room.currentRound == widget.round + 1 && endsAt != null
                        ? 'Round ${widget.round} results land '
                              '${lockTime(endsAt)}. Until then, who got '
                              'what stays hidden.'
                        : "Round ${widget.round} results aren't out yet.",
                  );
                }
                _markSeen(room);
                if (drawingsSnapshot.hasError) {
                  return const _Message("Couldn't load the results.");
                }
                if (!drawingsSnapshot.hasData) {
                  return const _DarkLoading('Opening the results…');
                }
                return StreamBuilder<Set<String>>(
                  stream: _stars,
                  builder: (context, starsSnapshot) {
                    return StreamBuilder<
                      Map<String, Map<String, GuessProgress>>
                    >(
                      stream: _guesses,
                      builder: (context, guessesSnapshot) {
                        return StreamBuilder<RoundInfo?>(
                          stream: _guessRound,
                          builder: (context, roundSnapshot) {
                            if (guessesSnapshot.hasError) {
                              return const _Message(
                                "Couldn't load who got what.",
                              );
                            }
                            if (!guessesSnapshot.hasData ||
                                !roundSnapshot.hasData &&
                                    !roundSnapshot.hasError) {
                              return const _DarkLoading('Opening the results…');
                            }
                            final stars = {...?starsSnapshot.data};
                            _starOverrides.forEach((uid, starred) {
                              starred ? stars.add(uid) : stars.remove(uid);
                            });
                            return _buildSequence(
                              room,
                              drawingsSnapshot.data!,
                              guessesSnapshot.data!,
                              stars,
                              roundSnapshot.data,
                            );
                          },
                        );
                      },
                    );
                  },
                );
              },
            );
          },
        ),
      ),
    );
  }

  Widget _buildSequence(
    RoomDetail room,
    List<DrawingSubmission> drawings,
    Map<String, Map<String, GuessProgress>> guesses,
    Set<String> stars,
    RoundInfo? guessRound,
  ) {
    final myUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final others = seededOrder(
      drawings.where((d) => d.authorUid != myUid),
      seed: '$myUid:${room.id}:${widget.round}',
      idOf: (d) => d.authorUid,
    );
    final mine = drawings.where((d) => d.authorUid == myUid).firstOrNull;

    final pool = RoundScores.guessPool(
      nextRoundRequired: guessRound?.requiredUids ?? const [],
      guesses: guesses,
    );
    final order = [...room.memberUids, ...pool];
    // You first, then everyone else in join order.
    List<String> guessersOf(DrawingSubmission d) => [
      if (pool.contains(myUid) && myUid != d.authorUid) myUid,
      ...{
        for (final uid in order)
          if (pool.contains(uid) && uid != myUid && uid != d.authorUid) uid,
      },
    ];
    Map<String, GuessProgress> guessesOn(DrawingSubmission d) => {
      for (final entry in guesses.entries)
        if (entry.value[d.authorUid] != null)
          entry.key: entry.value[d.authorUid]!,
    };

    final stages = [
      for (final d in others) _Stage(_StageKind.word, d),
      if (mine != null) _Stage(_StageKind.mine, mine),
      const _Stage(_StageKind.score),
    ];

    final pager = _pager ??= () {
      final start = stages.indexWhere(
        (s) => s.drawing?.authorUid == widget.startAt,
      );
      _page = start < 0 ? 0 : start;
      return PageController(initialPage: _page);
    }();
    _page = _page.clamp(0, stages.length - 1);
    final current = stages[_page];
    final isLast = _page == stages.length - 1;

    String caption(_Stage stage) => switch (stage.kind) {
      _StageKind.word =>
        'Word ${stages.indexOf(stage) + 1} of ${others.length} · then your '
            'score · then the table',
      _StageKind.mine => 'Your drawing · then your score · then the table',
      _StageKind.score => 'Your round · then the table',
    };
    String nextLabel() {
      if (isLast) return 'See the table';
      return switch (stages[_page + 1].kind) {
        _StageKind.word => 'Next word',
        _StageKind.mine => 'Your drawing',
        _StageKind.score => 'Your score',
      };
    }

    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          // One segment per stage on this screen. The table isn't one —
          // "See the table" leaves for the leaderboard, so a segment for it
          // could never fill.
          child: _SegmentBar(count: stages.length, filled: _page + 1),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.xs,
            AppSpacing.lg,
            AppSpacing.md,
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  caption(current),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: accent.withValues(alpha: 0.75),
                  ),
                ),
              ),
              if (guessRound?.closedEarly ?? false) const _EarlyChip(),
            ],
          ),
        ),
        Expanded(
          child: PageView.builder(
            controller: pager,
            itemCount: stages.length,
            onPageChanged: (page) => setState(() => _page = page),
            itemBuilder: (context, i) {
              final stage = stages[i];
              final d = stage.drawing;
              if (d == null) {
                return _ScoreStage(
                  room: room,
                  round: widget.round,
                  scores: _scores,
                  previous: _previousScores,
                  others: others,
                  mine: mine,
                  myGuesses: guesses[myUid] ?? const {},
                  myUid: myUid,
                );
              }
              final guessers = guessersOf(d);
              return _WordStage(
                drawing: d,
                guesserUids: guessers,
                guesses: guessesOn(d),
                myUid: myUid,
                starred: stars.contains(d.authorUid),
                onStar: stage.kind == _StageKind.word
                    ? (starred) => _toggleStar(d.authorUid, starred)
                    : null,
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Row(
            children: [
              if (_page > 0) ...[
                Expanded(
                  flex: 2,
                  child: AccentOutlineButton(
                    label: 'Back',
                    onPressed: () => _goTo(_page - 1),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
              ],
              Expanded(
                flex: 3,
                child: AccentButton(
                  label: nextLabel(),
                  onPressed: isLast
                      ? () => context.pushReplacement(
                          AppRoutes.leaderboardPath(room.id),
                        )
                      : () => _goTo(_page + 1),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Where you are in the sequence.
class _SegmentBar extends StatelessWidget {
  const _SegmentBar({required this.count, required this.filled});

  final int count;
  final int filled;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return Row(
      children: [
        for (var i = 0; i < count; i++) ...[
          if (i > 0) const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: AnimatedContainer(
              duration: AppMotion.duration,
              height: 5,
              decoration: BoxDecoration(
                color: i < filled ? accent : accent.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// One word: the answer spelled out, the drawing and who drew it, how many
/// solved it, your star, and everyone's tries. Your own drawing gets the
/// same stage, without the star.
class _WordStage extends StatelessWidget {
  const _WordStage({
    required this.drawing,
    required this.guesserUids,
    required this.guesses,
    required this.myUid,
    required this.starred,
    required this.onStar,
  });

  final DrawingSubmission drawing;
  final List<String> guesserUids;
  final Map<String, GuessProgress> guesses;
  final String myUid;
  final bool starred;

  /// Null on your own drawing — you can't star yourself.
  final ValueChanged<bool>? onStar;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;
    final accent = theme.colorScheme.primary;
    final isMine = drawing.authorUid == myUid;
    final solvers = guesserUids
        .where((uid) => guesses[uid]?.solved ?? false)
        .length;
    final label = textTheme.labelSmall?.copyWith(
      fontWeight: FontWeight.w700,
      letterSpacing: 1.2,
      color: accent.withValues(alpha: 0.7),
    );

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            isMine ? 'You drew' : 'The word was',
            textAlign: TextAlign.center,
            style: textTheme.bodySmall?.copyWith(
              color: accent.withValues(alpha: 0.8),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          _WordTiles(word: drawing.word),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: AppSpacing.xs,
            children: [
              if (drawing.category.isNotEmpty) DarkChip(drawing.category),
              DarkChip(drawing.difficulty.label.toLowerCase()),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          Row(
            children: [
              Expanded(
                flex: 5,
                child: DrawingArt(
                  drawing: drawing,
                  frameColor: accent,
                  maxWidth: 180,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                flex: 6,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        ProfileAvatar(
                          uid: drawing.authorUid,
                          fallbackName: drawing.authorDisplayName,
                          size: 26,
                          ringColor: accent,
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        Expanded(
                          child: isMine
                              ? Text(
                                  'You drew this',
                                  style: textTheme.bodySmall?.copyWith(
                                    fontWeight: FontWeight.w700,
                                    color: accent,
                                  ),
                                )
                              : ProfileBuilder(
                                  uid: drawing.authorUid,
                                  builder: (context, author) => Text(
                                    '${author?.displayName ?? drawing.authorDisplayName} '
                                    'drew this',
                                    style: textTheme.bodySmall?.copyWith(
                                      fontWeight: FontWeight.w700,
                                      color: accent,
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      guesserUids.isEmpty
                          ? 'Nobody to\nguess it'
                          : '$solvers of ${guesserUids.length}\nsolved it',
                      style: textTheme.headlineMedium?.copyWith(
                        fontSize: 24,
                        height: 1.1,
                        color: accent,
                      ),
                    ),
                    if (onStar != null) ...[
                      const SizedBox(height: AppSpacing.md),
                      _StarButton(
                        starred: starred,
                        onPressed: () => onStar!(!starred),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          if (guesserUids.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.lg),
            Row(
              children: [
                Expanded(child: Text('WHO GOT IT', style: label)),
                Text('TRIES 1 → 5', style: label),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            for (final uid in guesserUids)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                child: _TriesRow(
                  uid: uid,
                  isMe: uid == myUid,
                  progress: guesses[uid],
                ),
              ),
          ],
          const SizedBox(height: AppSpacing.lg),
        ],
      ),
    );
  }
}

/// The answer as a row of accent letter tiles, sized to fit the width
/// (wrapping for long words).
class _WordTiles extends StatelessWidget {
  const _WordTiles({required this.word});

  final String word;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;
    const gap = 4.0;
    return LayoutBuilder(
      builder: (context, constraints) {
        final count = word.length;
        final fit = (constraints.maxWidth - gap * (count - 1)) / count;
        final width = fit.clamp(20.0, AppSizes.letterTileWidth);
        final height =
            width * AppSizes.letterTileHeight / AppSizes.letterTileWidth;
        return Wrap(
          alignment: WrapAlignment.center,
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final char in word.split(''))
              if (char == ' ')
                SizedBox(width: width / 2, height: height)
              else
                Container(
                  width: width,
                  height: height,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: accent,
                    borderRadius: AppRadius.tileRadius,
                  ),
                  child: Text(
                    char.toUpperCase(),
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontSize: width * 0.55,
                      color: AppColors.ink,
                    ),
                  ),
                ),
          ],
        );
      },
    );
  }
}

/// "★ Give a star" — filled once given. Stars never touch the score.
class _StarButton extends StatelessWidget {
  const _StarButton({required this.starred, required this.onPressed});

  final bool starred;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;
    final fg = starred ? AppColors.ink : accent;
    return Semantics(
      button: true,
      toggled: starred,
      child: GestureDetector(
        onTap: onPressed,
        child: AnimatedContainer(
          duration: AppMotion.duration,
          constraints: const BoxConstraints(minHeight: 40),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          decoration: BoxDecoration(
            color: starred ? accent : Colors.transparent,
            borderRadius: AppRadius.chipRadius,
            border: Border.all(color: accent, width: AppBorders.thin),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                starred ? Icons.star_rounded : Icons.star_outline_rounded,
                size: 18,
                color: fg,
              ),
              const SizedBox(width: AppSpacing.xs),
              Text(
                starred ? 'Starred' : 'Give a star',
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: fg,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One player on one word: tries as five squares — spent ones filled, the
/// solving one in the accent — and "2nd try" / "no solve".
class _TriesRow extends StatelessWidget {
  const _TriesRow({
    required this.uid,
    required this.isMe,
    required this.progress,
  });

  final String uid;
  final bool isMe;
  final GuessProgress? progress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;
    final accent = theme.colorScheme.primary;
    final attempts = progress?.attempts ?? 0;
    final solved = progress?.solved ?? false;
    final label = solved
        ? '${ordinal(attempts)} try'
        : attempts == 0
        ? 'no guess'
        : 'no solve';

    return Opacity(
      opacity: solved || isMe ? 1 : 0.55,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        decoration: BoxDecoration(
          borderRadius: AppRadius.controlRadius,
          border: Border.all(
            color: isMe ? accent : AppColors.cream.withValues(alpha: 0.2),
            width: AppBorders.thin,
          ),
        ),
        child: Row(
          children: [
            // Accent ring so ink avatars still read on the ink background.
            ProfileAvatar(
              uid: uid,
              fallbackInitials: '?',
              size: 26,
              ringColor: accent,
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: isMe
                  ? Text(
                      'You',
                      style: textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: accent,
                      ),
                    )
                  : ProfileBuilder(
                      uid: uid,
                      builder: (context, profile) => Text(
                        profile?.displayName ?? 'A player',
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.bodyMedium?.copyWith(
                          color: AppColors.cream,
                        ),
                      ),
                    ),
            ),
            for (var i = 0; i < GuessProgress.maxAttempts; i++) ...[
              if (i > 0) const SizedBox(width: 3),
              Container(
                width: 11,
                height: 11,
                decoration: BoxDecoration(
                  color: i >= attempts
                      ? Colors.transparent
                      : solved && i == attempts - 1
                      ? accent
                      : AppColors.cream.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(2),
                  border: i >= attempts
                      ? Border.all(
                          color: AppColors.cream.withValues(alpha: 0.35),
                          width: 1.5,
                        )
                      : null,
                ),
              ),
            ],
            const SizedBox(width: AppSpacing.md),
            SizedBox(
              width: 62,
              child: Text(
                label,
                textAlign: TextAlign.right,
                style: textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: solved ? accent : accent.withValues(alpha: 0.7),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Your round: the score, your two halves, and what it did to your place
/// on the table — then the next round's deadline, the habit hook.
class _ScoreStage extends StatelessWidget {
  const _ScoreStage({
    required this.room,
    required this.round,
    required this.scores,
    required this.previous,
    required this.others,
    required this.mine,
    required this.myGuesses,
    required this.myUid,
  });

  final RoomDetail room;
  final int round;
  final Stream<RoundScores?> scores;

  /// The table before this round — null when there isn't one.
  final Stream<RoundScores?>? previous;
  final List<DrawingSubmission> others;
  final DrawingSubmission? mine;

  /// Your progress on each of [others], by author.
  final Map<String, GuessProgress> myGuesses;
  final String myUid;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<RoundScores?>(
      stream: scores,
      builder: (context, scoresSnapshot) {
        return StreamBuilder<RoundScores?>(
          stream: previous,
          builder: (context, previousSnapshot) {
            final now = scoresSnapshot.data;
            if (now == null ||
                (previous != null &&
                    previousSnapshot.connectionState ==
                        ConnectionState.waiting)) {
              return _DarkLoading('Tallying round $round…');
            }
            return _scoreBody(context, now, previousSnapshot.data);
          },
        );
      },
    );
  }

  Widget _scoreBody(
    BuildContext context,
    RoundScores now,
    RoundScores? before,
  ) {
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;
    final tokens = theme.extension<AppTokens>()!;
    final accent = theme.colorScheme.primary;
    final entry = now.entries[myUid] ?? RoundEntry.zero;

    final table = now.standings(room.memberUids);
    final me = table.where((s) => s.uid == myUid).firstOrNull;
    final beforeTable = before?.standings(room.memberUids) ?? const [];
    final meBefore = beforeTable.where((s) => s.uid == myUid).firstOrNull;
    final usual = before?.season[myUid];
    final climbed = me != null && meBefore != null && me.rank < meBefore.rank;

    String comparison() {
      if (usual == null || usual.rounds == 0) {
        return 'Your first round on the table.';
      }
      final avg = usual.average;
      if (entry.total > avg) {
        return 'Up on your usual $avg${climbed ? ' — and you climbed.' : '.'}';
      }
      if (entry.total < avg) {
        return 'A quieter round than your usual $avg'
            '${climbed ? ' — still enough to climb.' : '.'}';
      }
      return 'Right on your usual $avg.';
    }

    final mineDrawing = mine;
    final endsAt = room.roundEndsAt;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Round score',
            textAlign: TextAlign.center,
            style: textTheme.bodySmall?.copyWith(
              color: accent.withValues(alpha: 0.8),
            ),
          ),
          _CountUp(
            value: entry.total,
            style: tokens.scoreNumeral.copyWith(
              fontSize: 72,
              height: 1.1,
              color: accent,
            ),
          ),
          Text(
            comparison(),
            textAlign: TextAlign.center,
            style: textTheme.bodySmall?.copyWith(
              color: AppColors.cream.withValues(alpha: 0.8),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          _HalfCard(
            title: 'Guessing',
            value: entry.guessing,
            subtitle: others.isEmpty
                ? 'Nobody else drew this round.'
                : 'Average across the ${others.length} '
                      '${others.length == 1 ? 'drawing' : 'drawings'} you '
                      'could guess',
            child: others.isEmpty
                ? null
                : _GuessTiles(drawings: others, progress: myGuesses),
          ),
          const SizedBox(height: AppSpacing.md),
          _HalfCard(
            title: 'Drawing',
            value: entry.drawing,
            leading: mineDrawing == null
                ? null
                : SizedBox(
                    width: 56,
                    child: DrawingArt(
                      drawing: mineDrawing,
                      frameColor: AppColors.white,
                      maxWidth: 56,
                    ),
                  ),
            subtitle: mineDrawing == null
                ? "You didn't draw in round $round."
                : '${mineDrawing.word} · '
                      '${mineDrawing.difficulty.label.toLowerCase()}',
          ),
          if (me != null) ...[
            const SizedBox(height: AppSpacing.md),
            _RankCard(
              rank: me.rank,
              rankBefore: meBefore?.rank,
              average: now.season[myUid]?.average ?? 0,
            ),
          ],
          if (endsAt != null && !room.isRoundLocked) ...[
            const SizedBox(height: AppSpacing.md),
            Text(
              'Round ${room.currentRound} is on now — it locks '
              '${lockTime(endsAt)}.',
              textAlign: TextAlign.center,
              style: textTheme.bodySmall?.copyWith(
                color: accent.withValues(alpha: 0.7),
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
        ],
      ),
    );
  }
}

/// The round score counting up from zero as the stage appears. Instant
/// under reduced motion.
class _CountUp extends StatelessWidget {
  const _CountUp({required this.value, required this.style});

  final int value;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: value.toDouble()),
      duration: MediaQuery.of(context).disableAnimations
          ? Duration.zero
          : const Duration(milliseconds: 900),
      curve: Curves.easeOutCubic,
      builder: (context, v, _) =>
          Text('${v.round()}', textAlign: TextAlign.center, style: style),
    );
  }
}

class _HalfCard extends StatelessWidget {
  const _HalfCard({
    required this.title,
    required this.value,
    required this.subtitle,
    this.leading,
    this.child,
  });

  final String title;
  final int value;
  final String subtitle;
  final Widget? leading;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<AppTokens>()!;
    final accent = theme.colorScheme.primary;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        borderRadius: AppRadius.cardRadius,
        border: Border.all(color: accent, width: AppBorders.thick),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              if (leading != null) ...[
                leading!,
                const SizedBox(width: AppSpacing.md),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: accent,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppColors.cream.withValues(alpha: 0.75),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                '$value',
                style: tokens.scoreNumeral.copyWith(
                  fontSize: 26,
                  color: accent,
                ),
              ),
            ],
          ),
          if (child != null) ...[const SizedBox(height: AppSpacing.md), child!],
        ],
      ),
    );
  }
}

/// Your try on each drawing you could guess: who drew it (revealed now),
/// its difficulty, and how you did.
class _GuessTiles extends StatelessWidget {
  const _GuessTiles({required this.drawings, required this.progress});

  final List<DrawingSubmission> drawings;
  final Map<String, GuessProgress> progress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;
    final accent = theme.colorScheme.primary;
    return LayoutBuilder(
      builder: (context, constraints) {
        final perRow = drawings.length.clamp(1, 4);
        final width =
            (constraints.maxWidth - AppSpacing.sm * (perRow - 1)) / perRow;
        return Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            for (final d in drawings)
              () {
                final p = progress[d.authorUid];
                final solved = p?.solved ?? false;
                final result = solved
                    ? '${ordinal(p!.attempts)} try'
                    : (p?.attempts ?? 0) == 0
                    ? 'skipped'
                    : 'missed';
                return Container(
                  width: width,
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  decoration: BoxDecoration(
                    color: solved ? accent.withValues(alpha: 0.12) : null,
                    borderRadius: AppRadius.controlRadius,
                    border: solved
                        ? null
                        : Border.all(
                            color: accent.withValues(alpha: 0.35),
                            width: 1.5,
                          ),
                  ),
                  child: Column(
                    children: [
                      ProfileBuilder(
                        uid: d.authorUid,
                        builder: (context, author) => Text(
                          author?.displayName ?? d.authorDisplayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: textTheme.bodySmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: AppColors.cream,
                          ),
                        ),
                      ),
                      Text(
                        d.difficulty.label.toLowerCase(),
                        style: textTheme.labelSmall?.copyWith(
                          color: accent.withValues(alpha: 0.7),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        result,
                        style: textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: solved
                              ? accent
                              : accent.withValues(alpha: 0.6),
                        ),
                      ),
                    ],
                  ),
                );
              }(),
          ],
        );
      },
    );
  }
}

/// Where the round leaves you on the table.
class _RankCard extends StatelessWidget {
  const _RankCard({
    required this.rank,
    required this.rankBefore,
    required this.average,
  });

  final int rank;
  final int? rankBefore;
  final int average;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<AppTokens>()!;
    final accent = theme.colorScheme.primary;
    final before = rankBefore;
    final moved = before == null ? 0 : before - rank;
    final headline = before == null
        ? "You're ${ordinal(rank)}"
        : moved > 0
        ? 'You moved up to ${ordinal(rank)}'
        : moved < 0
        ? 'You slipped to ${ordinal(rank)}'
        : 'You held ${ordinal(rank)}';
    final change = moved == 0
        ? ''
        : ' · ${moved > 0 ? '▲' : '▼'}${moved.abs()} '
              '${moved.abs() == 1 ? 'place' : 'places'}';

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: accent,
        borderRadius: AppRadius.cardRadius,
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.ink,
              borderRadius: AppRadius.controlRadius,
            ),
            child: Text(
              '$rank',
              style: tokens.scoreNumeral.copyWith(fontSize: 22, color: accent),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  headline,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: AppColors.ink,
                  ),
                ),
                Text(
                  'Season average $average$change',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppColors.ink.withValues(alpha: 0.75),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A nice moment, not a warning: the round closed because everyone
/// finished.
class _EarlyChip extends StatelessWidget {
  const _EarlyChip();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 3,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary,
        borderRadius: AppRadius.chipRadius,
      ),
      child: Text(
        'Everyone finished early',
        style: theme.chipTheme.labelStyle?.copyWith(color: AppColors.ink),
      ),
    );
  }
}

class _DarkLoading extends StatelessWidget {
  const _DarkLoading(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(color: accent),
          const SizedBox(height: AppSpacing.md),
          Text(
            message,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: AppColors.cream.withValues(alpha: 0.75),
            ),
          ),
        ],
      ),
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
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: AppColors.cream),
        ),
      ),
    );
  }
}
