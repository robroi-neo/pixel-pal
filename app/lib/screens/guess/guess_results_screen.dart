import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../models/drawing_submission.dart';
import '../../models/guess_progress.dart';
import '../../models/room_detail.dart';
import '../../models/round_info.dart';
import '../../models/round_score.dart';
import '../../services/drawing_service.dart';
import '../../services/guess_service.dart';
import '../../services/room_service.dart';
import '../../services/round_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_dimens.dart';
import '../../theme/app_tokens.dart';
import '../../utils/seeded_order.dart';
import '../../widgets/deadline_chip.dart';
import '../../widgets/drawing_art.dart';
import '../../widgets/profile_avatar.dart';
import '../../widgets/reveal_chrome.dart';

/// Guessing flow, screen E — round [GuessResultsScreen.round]'s reveal.
/// Once the round its drawings were guessed in has ended, the group
/// results play as a sequence rather than a table: one stage
/// per drawing (word, chips, art, drawer, "3 of 4 got it", your star,
/// everyone's attempts), then your own drawing, then your points.
/// Design.md §5 "Reveal": chrome goes near-black; the canvas doesn't move.
///
/// The leaderboard shift that would end the sequence doesn't exist yet.
/// Stars are given here and never touch the score.
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

  PageController? _pager;
  int _page = 0;
  int _stageCount = 0;

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
    try {
      await _guessService.setStarred(
        roomId: widget.roomId,
        round: widget.round,
        authorUid: authorUid,
        starred: starred,
      );
    } on GuessServiceException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message)));
    }
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
        leading: IconButton(
          icon: Icon(Icons.arrow_back_outlined, color: accent),
          onPressed: () => context.pop(),
        ),
        title: Text(
          'Round ${widget.round} · results',
          style: theme.textTheme.titleMedium?.copyWith(color: accent),
        ),
        actions: [
          if (_stageCount > 0)
            Padding(
              padding: const EdgeInsets.only(right: AppSpacing.lg),
              child: Center(
                child: Text(
                  '${_page + 1} of $_stageCount',
                  style: theme.textTheme.bodySmall?.copyWith(color: accent),
                ),
              ),
            ),
        ],
      ),
      body: SafeArea(
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
                  return Center(
                    child: CircularProgressIndicator(color: accent),
                  );
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
                        ? 'Round ${widget.round} results land at '
                              '${clockTime(endsAt)}. Until then, who got '
                              'what stays hidden.'
                        : "Round ${widget.round} results aren't out yet.",
                  );
                }
                if (drawingsSnapshot.hasError) {
                  return const _Message("Couldn't load the results.");
                }
                if (!drawingsSnapshot.hasData) {
                  return Center(
                    child: CircularProgressIndicator(color: accent),
                  );
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
                              return Center(
                                child: CircularProgressIndicator(color: accent),
                              );
                            }
                            return _buildSequence(
                              room,
                              drawingsSnapshot.data!,
                              guessesSnapshot.data!,
                              starsSnapshot.data ?? const {},
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

    // Who could have guessed: everyone the guessing round waited for,
    // plus anyone who joined since and guessed anyway. You first, then
    // everyone else in join order.
    final pool = {...?guessRound?.requiredUids, ...guesses.keys};
    final order = [...room.memberUids, ...pool];
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

    int? drawingHalf;
    if (mine != null) {
      final eligible = guessersOf(mine);
      final on = guessesOn(mine);
      drawingHalf = RoundScore.drawingHalf(
        solvers: eligible.where((uid) => on[uid]?.solved ?? false).length,
        eligible: eligible.length,
        multiplier: mine.multiplier,
      );
    }

    final myGuesses = guesses[myUid] ?? const {};
    final stages = <Widget>[
      for (final d in others)
        _DrawingStage(
          drawing: d,
          guesserUids: guessersOf(d),
          guesses: guessesOn(d),
          myUid: myUid,
          starred: stars.contains(d.authorUid),
          onStar: (starred) => _toggleStar(d.authorUid, starred),
        ),
      if (mine != null)
        _DrawingStage(
          drawing: mine,
          guesserUids: guessersOf(mine),
          guesses: guessesOn(mine),
          myUid: myUid,
          drawingHalf: drawingHalf,
        ),
      _PointsStage(
        drawings: others,
        myGuesses: myGuesses,
        drawingHalf: drawingHalf,
      ),
    ];

    final pager = _pager ??= () {
      final start = widget.startAt == null
          ? 0
          : [...others, ?mine].indexWhere((d) => d.authorUid == widget.startAt);
      _page = start < 0 ? 0 : start;
      return PageController(initialPage: _page);
    }();
    if (_stageCount != stages.length) {
      // The app bar's "1 of 5" reads this; update it after this frame.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _stageCount = stages.length);
      });
    }
    final isLast = _page >= stages.length - 1;

    return Column(
      children: [
        if (guessRound?.closedEarly ?? false)
          const Padding(
            padding: EdgeInsets.only(bottom: AppSpacing.md),
            child: _EarlyChip(),
          ),
        Expanded(
          child: PageView(
            controller: pager,
            onPageChanged: (page) => setState(() => _page = page),
            children: stages,
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Row(
            children: [
              if (_page > 0) ...[
                AccentOutlineButton(
                  label: 'Back',
                  onPressed: () => _goTo(_page - 1),
                ),
                const SizedBox(width: AppSpacing.sm),
              ],
              Expanded(
                child: AccentButton(
                  label: isLast ? 'Done' : 'Next',
                  onPressed: isLast
                      ? () => context.pop()
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

/// One drawing's stage. For your own drawing ([drawingHalf] set) it also
/// shows your drawing half, and there's no star.
class _DrawingStage extends StatelessWidget {
  const _DrawingStage({
    required this.drawing,
    required this.guesserUids,
    required this.guesses,
    required this.myUid,
    this.starred = false,
    this.onStar,
    this.drawingHalf,
  });

  final DrawingSubmission drawing;
  final List<String> guesserUids;
  final Map<String, GuessProgress> guesses;
  final String myUid;
  final bool starred;
  final ValueChanged<bool>? onStar;
  final int? drawingHalf;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;
    final tokens = theme.extension<AppTokens>()!;
    final accent = theme.colorScheme.primary;
    final isMine = drawing.authorUid == myUid;
    final solvers = guesserUids
        .where((uid) => guesses[uid]?.solved ?? false)
        .length;
    final gotIt = '$solvers of ${guesserUids.length} got it';
    final artistStyle = textTheme.bodyMedium?.copyWith(
      fontWeight: FontWeight.w600,
      color: accent,
    );

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (isMine)
            Text(
              'your drawing',
              textAlign: TextAlign.center,
              style: textTheme.bodySmall?.copyWith(
                color: accent.withValues(alpha: 0.7),
              ),
            ),
          Text(
            drawing.word,
            textAlign: TextAlign.center,
            style: textTheme.headlineMedium?.copyWith(
              fontSize: 34,
              color: accent,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: AppSpacing.xs,
            children: [
              if (drawing.category.isNotEmpty) DarkChip(drawing.category),
              DarkChip(difficultyLabel(drawing).toLowerCase()),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          DrawingArt(drawing: drawing, frameColor: accent, maxWidth: 200),
          const SizedBox(height: AppSpacing.md),
          if (isMine)
            Text(
              'You drew this · $gotIt',
              textAlign: TextAlign.center,
              style: artistStyle,
            )
          else
            ProfileBuilder(
              uid: drawing.authorUid,
              builder: (context, author) => Text(
                '${author?.displayName ?? drawing.authorDisplayName} drew '
                'this · $gotIt',
                textAlign: TextAlign.center,
                style: artistStyle,
              ),
            ),
          if (onStar != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Center(
              child: _StarButton(
                starred: starred,
                onPressed: () => onStar!(!starred),
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          if (guesserUids.isEmpty)
            Text(
              'Nobody else was in the room to guess it.',
              textAlign: TextAlign.center,
              style: textTheme.bodyMedium?.copyWith(
                color: AppColors.cream.withValues(alpha: 0.7),
              ),
            ),
          for (final uid in guesserUids)
            _PlayerRow(uid: uid, isMe: uid == myUid, progress: guesses[uid]),
          if (drawingHalf != null) ...[
            const SizedBox(height: AppSpacing.lg),
            _ScoreLine(
              label: 'drawing half',
              value: drawingHalf!,
              numeral: tokens.scoreNumeral,
            ),
            Text(
              '$solvers of ${guesserUids.length} solved it × 100 × '
              'x${drawing.multiplier.toStringAsFixed(1)}',
              style: textTheme.bodySmall?.copyWith(
                color: accent.withValues(alpha: 0.6),
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
        ],
      ),
    );
  }
}

/// The last stage: your points per drawing, the guessing half as their
/// mean, your drawing half, and the round total.
class _PointsStage extends StatelessWidget {
  const _PointsStage({
    required this.drawings,
    required this.myGuesses,
    required this.drawingHalf,
  });

  final List<DrawingSubmission> drawings;
  final Map<String, GuessProgress> myGuesses;
  final int? drawingHalf;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;
    final tokens = theme.extension<AppTokens>()!;
    final accent = theme.colorScheme.primary;
    final muted = accent.withValues(alpha: 0.6);

    final points = [
      for (final d in drawings)
        RoundScore.guessPoints(myGuesses[d.authorUid], d.multiplier),
    ];
    final guessingHalf = RoundScore.guessingHalf(points);
    final total = guessingHalf + (drawingHalf ?? 0);

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'your guessing',
            style: textTheme.headlineMedium?.copyWith(
              fontSize: 24,
              color: accent,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          if (drawings.isEmpty)
            Text(
              'Nobody else drew this round, so there was nothing to guess.',
              style: textTheme.bodyMedium?.copyWith(color: muted),
            ),
          for (var i = 0; i < drawings.length; i++)
            Container(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: AppColors.cream.withValues(alpha: 0.15),
                  ),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: drawings[i].word,
                            style: textTheme.bodyMedium?.copyWith(
                              color: accent,
                            ),
                          ),
                          TextSpan(
                            text: _attemptNote(drawings[i]),
                            style: textTheme.bodySmall?.copyWith(color: muted),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Text(
                    '${points[i]}',
                    style: tokens.scoreNumeral.copyWith(
                      fontSize: 16,
                      color: accent,
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: AppSpacing.xl),
          _ScoreLine(
            label: 'guessing half · mean',
            value: guessingHalf,
            numeral: tokens.scoreNumeral,
          ),
          if (drawingHalf != null) ...[
            const SizedBox(height: AppSpacing.sm),
            _ScoreLine(
              label: 'drawing half',
              value: drawingHalf!,
              numeral: tokens.scoreNumeral,
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          Divider(color: accent.withValues(alpha: 0.4)),
          const SizedBox(height: AppSpacing.md),
          _ScoreLine(
            label: 'round total',
            value: total,
            numeral: tokens.scoreNumeral,
            large: true,
          ),
          const SizedBox(height: AppSpacing.lg),
        ],
      ),
    );
  }

  String _attemptNote(DrawingSubmission d) {
    final p = myGuesses[d.authorUid];
    final multiplier = 'x${d.multiplier.toStringAsFixed(1)}';
    if (p == null || !p.solved) return '  no solve';
    return '  attempt ${p.attempts} · $multiplier';
  }
}

class _ScoreLine extends StatelessWidget {
  const _ScoreLine({
    required this.label,
    required this.value,
    required this.numeral,
    this.large = false,
  });

  final String label;
  final int value;

  /// Silkscreen — score numerals are the one pixelated type in the UI.
  final TextStyle numeral;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Text(
            label,
            style: theme.textTheme.titleMedium?.copyWith(color: accent),
          ),
        ),
        Text(
          '$value',
          style: numeral.copyWith(fontSize: large ? 34 : 26, color: accent),
        ),
      ],
    );
  }
}

/// "★ starred" — filled once given, outlined before.
class _StarButton extends StatelessWidget {
  const _StarButton({required this.starred, required this.onPressed});

  final bool starred;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;
    final fg = starred ? AppColors.ink : accent;
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        constraints: const BoxConstraints(minHeight: 32),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        decoration: BoxDecoration(
          color: starred ? accent : Colors.transparent,
          borderRadius: AppRadius.chipRadius,
          border: Border.all(color: accent, width: AppBorders.thin),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(starred ? Icons.star : Icons.star_border, size: 16, color: fg),
            const SizedBox(width: AppSpacing.xs),
            Text(
              starred ? 'starred' : 'star it',
              style: theme.chipTheme.labelStyle?.copyWith(color: fg),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlayerRow extends StatelessWidget {
  const _PlayerRow({
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
    final p = progress;
    final solved = p != null && p.solved;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: AppColors.cream.withValues(alpha: 0.15)),
        ),
      ),
      child: Row(
        children: [
          // Accent ring so ink avatars still read on the ink background.
          ProfileAvatar(
            uid: uid,
            fallbackInitials: '?',
            size: 30,
            ringColor: accent,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: isMe
                ? Text(
                    'you',
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
          Text(
            solved ? 'attempt ${p.attempts}' : 'no solve',
            style: textTheme.bodyMedium?.copyWith(
              color: solved ? accent : accent.withValues(alpha: 0.55),
              fontWeight: solved ? FontWeight.w700 : FontWeight.w600,
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
        horizontal: AppSpacing.md,
        vertical: 5,
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
