import 'dart:async';
import 'dart:math';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import '../../widgets/reveal_chrome.dart';

/// Guessing flow, screens B–D — one of round [GuessScreen.round]'s
/// drawings per card (guessed during the round after it), in a horizontal
/// stack you swipe through (or use the arrows / ← →). Opened from the
/// grid hub ([GuessListScreen]) on the tile you tapped.
///
/// The front of a card has no drawer name or avatar: difficulty, the art,
/// category and length, attempt dots, letter tiles (one more flips in per
/// wrong guess, in an order fixed per word), then the input. Finishing a
/// card flips it over to its result — the word, your attempt, and only
/// then who drew it. Everything about other players waits for the
/// deadline reveal.
///
/// Matching happens client-side against the drawing doc's plaintext
/// `word` (see [DrawingSubmission]) — there's no Cloud Function on Spark
/// to check a guess without exposing the answer to *someone*.
class GuessScreen extends StatefulWidget {
  const GuessScreen({
    super.key,
    required this.roomId,
    required this.round,
    required this.authorUid,
  });

  final String roomId;

  /// The round the drawings were made in.
  final int round;

  /// The card to open on — whose drawing it is, also its doc id.
  final String authorUid;

  @override
  State<GuessScreen> createState() => _GuessScreenState();
}

class _GuessScreenState extends State<GuessScreen> {
  static const _snap = Duration(milliseconds: 320);

  final _guessService = GuessService();
  final _input = TextEditingController();
  final _inputFocus = FocusNode();

  late final Stream<RoomDetail?> _room = RoomService().watchRoom(widget.roomId);
  late final Stream<List<DrawingSubmission>> _drawings = DrawingService()
      .watchOthersDrawings(widget.roomId, widget.round);
  late final Stream<Map<String, GuessProgress>> _myGuesses = _guessService
      .watchMyGuesses(widget.roomId, widget.round);

  Timer? _ticker;
  PageController? _pager;
  int _page = 0;

  /// Author uids in card order, fixed for this visit so a drawing that
  /// arrives mid-visit goes on the end instead of shifting the cards.
  List<String> _order = const [];

  bool _submitting = false;

  /// Per card: the message line under the input, and a counter that
  /// shakes the letter tiles each time it goes up.
  final _messages = <String, String>{};
  final _shakes = <String, int>{};

  /// Finished cards flipped back to the drawing ("See the drawing again").
  final _showingArt = <String>{};

  @override
  void initState() {
    super.initState();
    // Swiping pauses while you type.
    _inputFocus.addListener(() => setState(() {}));
    _ticker = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _pager?.dispose();
    _input.dispose();
    _inputFocus.dispose();
    super.dispose();
  }

  List<DrawingSubmission> _ordered(List<DrawingSubmission> drawings) {
    final byUid = {for (final d in drawings) d.authorUid: d};
    final fresh = seededOrder(
      drawings.where((d) => !_order.contains(d.authorUid)),
      seed:
          '${FirebaseAuth.instance.currentUser?.uid}:${widget.roomId}:'
          '${widget.round}',
      idOf: (d) => d.authorUid,
    );
    _order = [
      ..._order.where(byUid.containsKey),
      ...fresh.map((d) => d.authorUid),
    ];
    return [for (final uid in _order) byUid[uid]!];
  }

  void _goTo(int page, int count) {
    final pager = _pager;
    if (pager == null || page < 0 || page >= count) return;
    if (MediaQuery.of(context).disableAnimations) {
      pager.jumpToPage(page);
    } else {
      pager.animateToPage(page, duration: _snap, curve: Curves.easeOutCubic);
    }
  }

  /// The next card you haven't finished after [from], wrapping round —
  /// or null when they're all done.
  int? _nextUnfinished(
    List<DrawingSubmission> drawings,
    Map<String, GuessProgress> guesses,
    int from,
  ) {
    for (var step = 1; step < drawings.length; step++) {
      final i = (from + step) % drawings.length;
      if (!(guesses[drawings[i].authorUid]?.isDone ?? false)) return i;
    }
    return null;
  }

  Future<void> _handleGuess(
    DrawingSubmission drawing,
    GuessProgress progress,
  ) async {
    final text = _input.text.trim();
    if (text.isEmpty || _submitting) return;
    final uid = drawing.authorUid;

    setState(() => _submitting = true);
    try {
      final outcome = await _guessService.submitGuess(
        roomId: widget.roomId,
        round: widget.round,
        authorUid: uid,
        answer: drawing.word,
        guessText: text,
        progress: progress,
      );
      if (!mounted) return;
      _input.clear();
      setState(() {
        if (outcome == GuessOutcome.incorrect) {
          final left = GuessProgress.maxAttempts - (progress.attempts + 1);
          final letters = drawing.word.replaceAll(' ', '').length;
          final newLetter = progress.revealedCount < letters;
          _messages[uid] =
              'Not it · $left left${newLetter ? ' · one more letter shown' : ''}';
          _shakes[uid] = (_shakes[uid] ?? 0) + 1;
        } else {
          // Solved or out of attempts: the stream update flips the card.
          _messages.remove(uid);
          _inputFocus.unfocus();
        }
      });
      if (outcome != GuessOutcome.incorrect) {
        // Finishing a card might finish the round.
        unawaited(RoundService().checkIn(widget.roomId));
      }
    } on GuessServiceException catch (e) {
      if (!mounted) return;
      setState(() => _messages[uid] = e.message);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
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
            title: Text(
              'Guess round ${widget.round}',
              style: textTheme.titleMedium,
            ),
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
                      return _Message("Couldn't load the drawings.");
                    }
                    if (!roomSnapshot.hasData ||
                        !drawingsSnapshot.hasData ||
                        !guessesSnapshot.hasData) {
                      return const LoadingView();
                    }
                    if (room == null) {
                      return _Message('This room no longer exists.');
                    }
                    final drawings = _ordered(drawingsSnapshot.data!);
                    if (drawings.isEmpty) {
                      return _Message(
                        'Nobody else has drawn yet — check back soon.',
                      );
                    }
                    return _buildStack(room, drawings, guessesSnapshot.data!);
                  },
                );
              },
            ),
          ),
        );
      },
    );
  }

  Widget _buildStack(
    RoomDetail room,
    List<DrawingSubmission> drawings,
    Map<String, GuessProgress> guesses,
  ) {
    final textTheme = Theme.of(context).textTheme;
    final count = drawings.length;
    final pager = _pager ??= () {
      final start = drawings.indexWhere((d) => d.authorUid == widget.authorUid);
      _page = max(start, 0);
      return PageController(viewportFraction: 0.88, initialPage: _page);
    }();
    _page = _page.clamp(0, count - 1);

    bool isDone(DrawingSubmission d) => guesses[d.authorUid]?.isDone ?? false;
    final left = drawings.where((d) => !isDone(d)).length;
    final locked = !room.isGuessingOpen(widget.round);
    final revealed = room.isRevealed(widget.round);
    final at = room.roundEndsAt == null ? '' : clockTime(room.roundEndsAt!);
    final typing = _inputFocus.hasFocus;

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.arrowLeft): () =>
            _goTo(_page - 1, count),
        const SingleActivator(LogicalKeyboardKey.arrowRight): () =>
            _goTo(_page + 1, count),
      },
      child: Focus(
        autofocus: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              child: Text(
                locked
                    ? revealed
                          ? 'Guessing is closed · the results are in'
                          : 'Guessing is closed · results on their way'
                    : left == 0
                    ? 'all $count guessed · results at $at'
                    : '$left of $count drawings left this round',
                style: textTheme.bodySmall?.copyWith(
                  color: AppColors.ink.withValues(alpha: 0.7),
                ),
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: pager,
                itemCount: count,
                physics: typing
                    ? const NeverScrollableScrollPhysics()
                    : const PageScrollPhysics(),
                onPageChanged: (page) => setState(() {
                  _page = page;
                  // Leaving a card mid-typing only drops the unsent text.
                  _input.clear();
                }),
                itemBuilder: (context, i) => _SwipeTransform(
                  controller: pager,
                  index: i,
                  child: _buildCard(
                    room: room,
                    drawings: drawings,
                    guesses: guesses,
                    index: i,
                  ),
                ),
              ),
            ),
            SizedBox(
              height: 20,
              child: typing
                  ? Text(
                      'swiping pauses while you type',
                      textAlign: TextAlign.center,
                      style: textTheme.bodySmall?.copyWith(
                        color: AppColors.ink.withValues(alpha: 0.6),
                      ),
                    )
                  : null,
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                0,
                AppSpacing.lg,
                AppSpacing.md,
              ),
              child: _Pager(
                page: _page,
                done: [for (final d in drawings) isDone(d)],
                onPrevious: () => _goTo(_page - 1, count),
                onNext: () => _goTo(_page + 1, count),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCard({
    required RoomDetail room,
    required List<DrawingSubmission> drawings,
    required Map<String, GuessProgress> guesses,
    required int index,
  }) {
    final drawing = drawings[index];
    final uid = drawing.authorUid;
    final progress = guesses[uid] ?? GuessProgress.initial;
    final isCurrent = index == _page;
    final locked = !room.isGuessingOpen(widget.round);
    final next = locked ? null : _nextUnfinished(drawings, guesses, index);

    // Only once this round's results are out.
    final VoidCallback? seeResults = room.isRevealed(widget.round)
        ? () => context.push(
            AppRoutes.resultsPath(room.id, widget.round, startAt: uid),
          )
        : null;

    final card = Padding(
      // Room on the right and bottom for the hard shadow.
      padding: const EdgeInsets.fromLTRB(4, AppSpacing.sm, 8, AppSpacing.md),
      child: _FlipSwitcher(
        showBack: progress.isDone && !_showingArt.contains(uid),
        front: _CardFront(
          key: ValueKey('front-$uid'),
          drawing: drawing,
          number: index + 1,
          total: drawings.length,
          progress: progress,
          locked: locked,
          active: isCurrent,
          input: _input,
          inputFocus: _inputFocus,
          submitting: _submitting,
          message: _messages[uid],
          shakes: _shakes[uid] ?? 0,
          onGuess: () => _handleGuess(drawing, progress),
          onSeeResults: seeResults,
          onBackToResult: () => setState(() => _showingArt.remove(uid)),
        ),
        back: _CardBack(
          key: ValueKey('back-$uid'),
          drawing: drawing,
          progress: progress,
          locked: locked,
          endsAt: locked ? null : room.roundEndsAt,
          hasNext: next != null,
          onNext: () =>
              next == null ? context.pop() : _goTo(next, drawings.length),
          onSeeResults: seeResults,
          onSeeDrawing: () => setState(() => _showingArt.add(uid)),
        ),
      ),
    );

    // A neighbour peeking in from the side: tapping it brings it forward.
    if (isCurrent) return card;
    return GestureDetector(
      onTap: () => _goTo(index, drawings.length),
      behavior: HitTestBehavior.opaque,
      child: IgnorePointer(child: card),
    );
  }
}

/// The stack's physical feel, per the motion spec: each card tilts
/// `d × 5°` about a point below it, shrinks `min(|d|, 1.5) × 8%`, and
/// fades `min(|d|, 1) × 25%`, where d is how far it sits from the middle.
/// Reduced motion drops the tilt and scale.
class _SwipeTransform extends StatelessWidget {
  const _SwipeTransform({
    required this.controller,
    required this.index,
    required this.child,
  });

  final PageController controller;
  final int index;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    return AnimatedBuilder(
      animation: controller,
      child: child,
      builder: (context, child) {
        var position = controller.initialPage.toDouble();
        if (controller.hasClients && controller.position.haveDimensions) {
          position = controller.page ?? position;
        }
        final d = index - position;
        final distance = d.abs();
        if (distance > 1.7) return const SizedBox.shrink();

        final faded = Opacity(
          opacity: 1 - min(distance, 1) * 0.25,
          child: child,
        );
        if (reduceMotion) return faded;
        return Transform.rotate(
          angle: d * 5 * pi / 180,
          // Origin 50% 130%: a pivot below the card.
          alignment: const Alignment(0, 1.6),
          child: Transform.scale(
            scale: 1 - min(distance, 1.5) * 0.08,
            child: faded,
          ),
        );
      },
    );
  }
}

/// Finishing a card flips it over: rotateY 180° over 550ms. Each face
/// shows only on its own half of the turn. Instant under reduced motion.
class _FlipSwitcher extends StatelessWidget {
  const _FlipSwitcher({
    required this.showBack,
    required this.front,
    required this.back,
  });

  final bool showBack;
  final Widget front;
  final Widget back;

  static const _curve = Cubic(0.3, 0.8, 0.3, 1);

  @override
  Widget build(BuildContext context) {
    final current = showBack ? back : front;
    return AnimatedSwitcher(
      duration: MediaQuery.of(context).disableAnimations
          ? Duration.zero
          : const Duration(milliseconds: 550),
      switchInCurve: _curve,
      switchOutCurve: _curve.flipped,
      layoutBuilder: (currentChild, previousChildren) => Stack(
        fit: StackFit.expand,
        children: [...previousChildren, ?currentChild],
      ),
      transitionBuilder: (child, animation) {
        final incoming = child.key == current.key;
        return AnimatedBuilder(
          animation: animation,
          child: child,
          builder: (context, child) {
            // Incoming turns in from -90°, outgoing turns away to +90°.
            final turn = (1 - animation.value) * pi;
            final angle = incoming ? -turn : turn;
            if (angle.abs() > pi / 2) return const SizedBox.shrink();
            return Transform(
              alignment: Alignment.center,
              transform: Matrix4.identity()
                ..setEntry(3, 2, 0.0015)
                ..rotateY(angle),
              child: child,
            );
          },
        );
      },
      child: current,
    );
  }
}

/// Screen B — the guessing side of a card.
class _CardFront extends StatelessWidget {
  const _CardFront({
    super.key,
    required this.drawing,
    required this.number,
    required this.total,
    required this.progress,
    required this.locked,
    required this.active,
    required this.input,
    required this.inputFocus,
    required this.submitting,
    required this.message,
    required this.shakes,
    required this.onGuess,
    required this.onSeeResults,
    required this.onBackToResult,
  });

  final DrawingSubmission drawing;
  final int number;
  final int total;
  final GuessProgress progress;
  final bool locked;

  /// The card in the middle of the stack — the only one with a live input
  /// (one controller can't back several text fields at once).
  final bool active;
  final TextEditingController input;
  final FocusNode inputFocus;
  final bool submitting;
  final String? message;
  final int shakes;
  final VoidCallback onGuess;

  /// Null until this round's results are out.
  final VoidCallback? onSeeResults;
  final VoidCallback onBackToResult;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;
    final tokens = theme.extension<AppTokens>()!;
    final open = !progress.isDone && !locked;

    final Widget action;
    if (progress.isDone) {
      action = Center(
        child: TextButton(
          onPressed: onBackToResult,
          child: const Text('Back to your result'),
        ),
      );
    } else if (locked) {
      action = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            onSeeResults == null
                ? 'Guessing is closed. The results are on their way.'
                : 'Guessing is closed for this round.',
            textAlign: TextAlign.center,
            style: textTheme.bodyMedium,
          ),
          if (onSeeResults != null) ...[
            const SizedBox(height: AppSpacing.sm),
            AppButton(
              label: 'See the results',
              onPressed: () async => onSeeResults!(),
            ),
          ],
        ],
      );
    } else {
      action = _GuessInput(
        controller: active ? input : null,
        focusNode: active ? inputFocus : null,
        submitting: submitting,
        onGuess: onGuess,
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: AppRadius.cardRadius,
        border: Border.all(color: AppColors.ink, width: AppBorders.thick),
        boxShadow: open && active ? tokens.hardShadow : null,
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Drawing $number of $total',
                    style: textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                AttentionChip(difficultyLabel(drawing)),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            DrawingArt(drawing: drawing),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Flexible(child: NeutralChip(categoryLabel(drawing))),
                const SizedBox(width: AppSpacing.sm),
                const Spacer(),
                AttemptDots(attempts: progress.attempts),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            _Shake(
              trigger: shakes,
              child: _LetterTiles(word: drawing.word, progress: progress),
            ),
            const SizedBox(height: AppSpacing.md),
            action,
            if (message != null && open) ...[
              const SizedBox(height: AppSpacing.sm),
              // Dark red for errors only — never for deadlines.
              Text(
                message!,
                textAlign: TextAlign.center,
                style: textTheme.bodySmall?.copyWith(
                  color: tokens.errorFg,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _GuessInput extends StatelessWidget {
  const _GuessInput({
    required this.controller,
    required this.focusNode,
    required this.submitting,
    required this.onGuess,
  });

  /// Null on the cards either side of the middle, which show the input
  /// without taking text.
  final TextEditingController? controller;
  final FocusNode? focusNode;
  final bool submitting;
  final VoidCallback onGuess;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.onSecondary;
    final live = controller != null;
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: controller,
            focusNode: focusNode,
            readOnly: !live,
            textCapitalization: TextCapitalization.none,
            textInputAction: TextInputAction.done,
            decoration: const InputDecoration(hintText: 'your guess'),
            // Enter submits, and keeps the keyboard up for the next try.
            onSubmitted: (_) {
              onGuess();
              focusNode?.requestFocus();
            },
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        SizedBox(
          height: AppSizes.inputHeight,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              minimumSize: const Size(88, AppSizes.inputHeight),
            ),
            onPressed: (submitting || !live) ? () {} : onGuess,
            child: submitting && live
                ? SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: accent,
                    ),
                  )
                : const Text('Guess'),
          ),
        ),
      ],
    );
  }
}

/// Word length from attempt 1; one more letter per wrong guess, in the
/// word's fixed hint order. Solved inverts the tiles.
class _LetterTiles extends StatelessWidget {
  const _LetterTiles({required this.word, required this.progress});

  final String word;
  final GuessProgress progress;

  @override
  Widget build(BuildContext context) {
    final revealed = letterHintOrder(word).take(progress.revealedCount).toSet();
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: AppSpacing.xs,
      runSpacing: AppSpacing.xs,
      children: [
        for (var i = 0; i < word.length; i++)
          if (word[i] == ' ')
            const SizedBox(width: AppSpacing.md)
          else
            _LetterTile(
              letter: word[i].toUpperCase(),
              revealed: progress.solved || revealed.contains(i),
              solved: progress.solved,
            ),
      ],
    );
  }
}

class _LetterTile extends StatelessWidget {
  const _LetterTile({
    required this.letter,
    required this.revealed,
    required this.solved,
  });

  final String letter;
  final bool revealed;
  final bool solved;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.onSecondary;

    return Container(
      width: AppSizes.letterTileWidth,
      height: AppSizes.letterTileHeight,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: solved ? AppColors.ink : AppColors.white,
        borderRadius: AppRadius.tileRadius,
        border: Border.all(color: AppColors.ink, width: AppBorders.thick),
      ),
      child: Text(
        revealed ? letter : '',
        style: theme.textTheme.titleLarge?.copyWith(
          fontSize: 19,
          color: solved ? accent : AppColors.ink,
        ),
      ),
    );
  }
}

/// A wrong guess shakes the tiles for 380ms. Runs whenever [trigger] goes
/// up; still under reduced motion.
class _Shake extends StatefulWidget {
  const _Shake({required this.trigger, required this.child});

  final int trigger;
  final Widget child;

  @override
  State<_Shake> createState() => _ShakeState();
}

class _ShakeState extends State<_Shake> with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 380),
  );

  @override
  void didUpdateWidget(_Shake oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.trigger > oldWidget.trigger &&
        !MediaQuery.of(context).disableAnimations) {
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      child: widget.child,
      builder: (context, child) {
        final t = _controller.value;
        final dx = sin(t * pi * 6) * 8 * (1 - t);
        return Transform.translate(offset: Offset(dx, 0), child: child);
      },
    );
  }
}

/// Screen D — the result side: the word (even when missed), how you did,
/// then who drew it. Who else got it waits for the deadline.
class _CardBack extends StatelessWidget {
  const _CardBack({
    super.key,
    required this.drawing,
    required this.progress,
    required this.locked,
    required this.endsAt,
    required this.hasNext,
    required this.onNext,
    required this.onSeeResults,
    required this.onSeeDrawing,
  });

  final DrawingSubmission drawing;
  final GuessProgress progress;
  final bool locked;
  final DateTime? endsAt;

  /// Another card still to finish — otherwise the button goes back to the
  /// grid.
  final bool hasNext;
  final VoidCallback onNext;

  /// Null until this round's results are out.
  final VoidCallback? onSeeResults;
  final VoidCallback onSeeDrawing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;
    final accent = theme.colorScheme.primary;
    final at = endsAt == null ? 'the deadline' : clockTime(endsAt!);

    return Container(
      decoration: BoxDecoration(
        color: AppColors.ink,
        borderRadius: AppRadius.cardRadius,
        border: Border.all(color: AppColors.ink, width: AppBorders.thick),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'the word was',
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
            const SizedBox(height: AppSpacing.md),
            DrawingArt(drawing: drawing, frameColor: accent, maxWidth: 150),
            const SizedBox(height: AppSpacing.md),
            Text(
              progress.solved
                  ? 'Solved on attempt ${progress.attempts}'
                  : 'Missed · all ${GuessProgress.maxAttempts} attempts used',
              textAlign: TextAlign.center,
              style: textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: accent,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Center(
              child: _PopIn(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: AppSpacing.sm,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: AppRadius.controlRadius,
                    border: Border.all(color: accent, width: AppBorders.thin),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ProfileAvatar(
                        uid: drawing.authorUid,
                        fallbackName: drawing.authorDisplayName,
                        size: 28,
                        ringColor: accent,
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'drawn by',
                            style: textTheme.labelSmall?.copyWith(
                              color: accent.withValues(alpha: 0.7),
                            ),
                          ),
                          ProfileBuilder(
                            uid: drawing.authorUid,
                            builder: (context, author) => Text(
                              author?.displayName ?? drawing.authorDisplayName,
                              style: textTheme.titleMedium?.copyWith(
                                color: accent,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              onSeeResults != null
                  ? 'The results are in — see who else got it.'
                  : locked
                  ? 'Who else got it shows with the results, any moment now.'
                  : 'Who else got it shows with the $at results.',
              textAlign: TextAlign.center,
              style: textTheme.bodySmall?.copyWith(
                color: accent.withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            onSeeResults != null
                ? AccentButton(
                    label: 'See the results',
                    onPressed: onSeeResults!,
                  )
                : AccentButton(
                    label: hasNext ? 'Next drawing' : 'Back to round',
                    onPressed: onNext,
                  ),
            Center(
              child: TextButton(
                onPressed: onSeeDrawing,
                style: TextButton.styleFrom(foregroundColor: accent),
                child: const Text(
                  'See the drawing again',
                  style: TextStyle(decoration: TextDecoration.underline),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The drawer's name pops in 450ms after the flip, scaling .6 → 1 with a
/// slight overshoot — the name is the payoff. Instant under reduced
/// motion.
class _PopIn extends StatefulWidget {
  const _PopIn({required this.child});

  final Widget child;

  @override
  State<_PopIn> createState() => _PopInState();
}

class _PopInState extends State<_PopIn> with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
  );
  late final _scale = Tween<double>(
    begin: 0.6,
    end: 1,
  ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutBack));
  Timer? _delay;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_controller.isAnimating || _controller.isCompleted || _delay != null) {
      return;
    }
    if (MediaQuery.of(context).disableAnimations) {
      _controller.value = 1;
    } else {
      _delay = Timer(const Duration(milliseconds: 450), () {
        if (mounted) _controller.forward();
      });
    }
  }

  @override
  void dispose() {
    _delay?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _controller,
      child: ScaleTransition(scale: _scale, child: widget.child),
    );
  }
}

/// Arrows either side of the pips; a filled pip means that card's done,
/// the ring is the one you're on.
class _Pager extends StatelessWidget {
  const _Pager({
    required this.page,
    required this.done,
    required this.onPrevious,
    required this.onNext,
  });

  final int page;
  final List<bool> done;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _ArrowButton(
          icon: Icons.chevron_left,
          enabled: page > 0,
          onTap: onPrevious,
        ),
        Expanded(
          child: Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 6,
            runSpacing: 6,
            children: [
              for (var i = 0; i < done.length; i++)
                Container(
                  width: i == page ? 12 : 8,
                  height: i == page ? 12 : 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: done[i] ? AppColors.ink : Colors.transparent,
                    border: Border.all(
                      color: AppColors.ink,
                      width: i == page ? AppBorders.thin : 1.5,
                    ),
                  ),
                ),
            ],
          ),
        ),
        _ArrowButton(
          icon: Icons.chevron_right,
          enabled: page < done.length - 1,
          onTap: onNext,
        ),
      ],
    );
  }
}

class _ArrowButton extends StatelessWidget {
  const _ArrowButton({
    required this.icon,
    required this.enabled,
    required this.onTap,
  });

  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = enabled
        ? AppColors.ink
        : AppColors.ink.withValues(alpha: 0.3);
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        width: AppSizes.minTouchTarget,
        height: AppSizes.minTouchTarget,
        decoration: BoxDecoration(
          color: enabled ? AppColors.white : Colors.transparent,
          borderRadius: AppRadius.controlRadius,
          border: Border.all(color: color, width: AppBorders.thick),
        ),
        child: Icon(icon, color: color, size: AppSizes.iconMax),
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
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ),
    );
  }
}
