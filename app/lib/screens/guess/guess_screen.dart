import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../models/drawing_submission.dart';
import '../../models/guess_progress.dart';
import '../../services/drawing_service.dart';
import '../../services/guess_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_dimens.dart';
import '../../utils/initials.dart';
import '../../widgets/app_avatar.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_chip.dart';
import '../../widgets/loading_view.dart';
import '../../widgets/pixel_canvas.dart';

/// Design.md §5 "Guess": letter tiles, attempt markers, fuzzy submit.
/// Drawer avatar and difficulty above the art; category chip, attempt
/// markers and letter tiles below.
///
/// Real, live data throughout: which drawings exist
/// (`DrawingService.watchOthersDrawings`) and this member's own attempts
/// at each (`GuessService.watchMyGuesses`). One drawing shown at a time,
/// per Design.md §7's stated assumption ("one-at-a-time with
/// auto-advance") — though advancing here is a manual "Next drawing"
/// rather than timed, since Design.md doesn't specify a delay and a
/// button is easier to test against.
///
/// The trade-off worth remembering: matching happens client-side against
/// the drawing doc's plaintext `word` (see the long comment on
/// [DrawingSubmission]) — there's no Cloud Function on Spark to check a
/// guess without exposing the answer to *someone*.
class GuessScreen extends StatefulWidget {
  const GuessScreen({super.key, required this.roomId});

  final String roomId;

  @override
  State<GuessScreen> createState() => _GuessScreenState();
}

class _GuessScreenState extends State<GuessScreen> {
  final _drawingService = DrawingService();
  final _guessService = GuessService();
  final _guessController = TextEditingController();

  late final Stream<List<DrawingSubmission>> _othersDrawings = _drawingService
      .watchOthersDrawings(widget.roomId);
  late final Stream<Map<String, GuessProgress>> _myGuesses = _guessService
      .watchMyGuesses(widget.roomId);

  String? _currentAuthorUid;
  bool _submitting = false;

  @override
  void dispose() {
    _guessController.dispose();
    super.dispose();
  }

  /// Picks which drawing to show. Sticky on purpose: once a drawing is
  /// current, it stays current across unrelated stream updates (e.g.
  /// someone else's guess progress changing) — only advancing when the
  /// current one is actually done, so a new submission popping up
  /// mid-guess can't yank the screen out from under a half-typed answer.
  DrawingSubmission? _pickCurrent(
    List<DrawingSubmission> drawings,
    Map<String, GuessProgress> guesses,
  ) {
    final undone =
        drawings.where((d) => !(guesses[d.authorUid]?.isDone ?? false)).toList()
          ..sort((a, b) => a.authorUid.compareTo(b.authorUid));
    if (undone.isEmpty) {
      _currentAuthorUid = null;
      return null;
    }
    final stillValid = undone.where((d) => d.authorUid == _currentAuthorUid);
    if (stillValid.isNotEmpty) return stillValid.first;

    final next = undone.first;
    _currentAuthorUid = next.authorUid;
    _guessController.clear();
    return next;
  }

  void _advance() {
    setState(() {
      _currentAuthorUid = null;
      _guessController.clear();
    });
  }

  Future<void> _handleGuess(
    DrawingSubmission drawing,
    GuessProgress progress,
  ) async {
    final text = _guessController.text.trim();
    if (text.isEmpty) return;

    setState(() => _submitting = true);
    try {
      final outcome = await _guessService.submitGuess(
        roomId: widget.roomId,
        authorUid: drawing.authorUid,
        answer: drawing.word,
        guessText: text,
        progress: progress,
      );
      if (!mounted) return;
      if (outcome == GuessOutcome.incorrect) {
        _guessController.clear();
      }
    } on GuessServiceException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_outlined),
          onPressed: () => context.pop(),
        ),
        title: Text('Guess', style: textTheme.titleMedium),
      ),
      body: SafeArea(
        child: StreamBuilder<List<DrawingSubmission>>(
          stream: _othersDrawings,
          builder: (context, drawingsSnapshot) {
            if (drawingsSnapshot.hasError) {
              return Center(
                child: Text(
                  "Couldn't load drawings.",
                  style: textTheme.bodyMedium,
                ),
              );
            }
            if (!drawingsSnapshot.hasData) {
              return const LoadingView();
            }
            final drawings = drawingsSnapshot.data!;

            return StreamBuilder<Map<String, GuessProgress>>(
              stream: _myGuesses,
              builder: (context, guessesSnapshot) {
                final guesses = guessesSnapshot.data ?? const {};
                final remaining = drawings
                    .where((d) => !(guesses[d.authorUid]?.isDone ?? false))
                    .length;
                final current = _pickCurrent(drawings, guesses);

                if (drawings.isEmpty) {
                  return Center(
                    child: Text(
                      'Nobody in this room has submitted a drawing yet.',
                      style: textTheme.bodyMedium,
                      textAlign: TextAlign.center,
                    ),
                  );
                }
                if (current == null) {
                  return Center(
                    child: Text(
                      "You've guessed everything you can for now.",
                      style: textTheme.bodyMedium,
                      textAlign: TextAlign.center,
                    ),
                  );
                }

                final progress =
                    guesses[current.authorUid] ?? GuessProgress.initial;
                return _GuessBody(
                  drawing: current,
                  progress: progress,
                  remaining: remaining,
                  total: drawings.length,
                  controller: _guessController,
                  submitting: _submitting,
                  onGuess: () => _handleGuess(current, progress),
                  onNext: _advance,
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _GuessBody extends StatelessWidget {
  const _GuessBody({
    required this.drawing,
    required this.progress,
    required this.remaining,
    required this.total,
    required this.controller,
    required this.submitting,
    required this.onGuess,
    required this.onNext,
  });

  final DrawingSubmission drawing;
  final GuessProgress progress;
  final int remaining;
  final int total;
  final TextEditingController controller;
  final bool submitting;
  final VoidCallback onGuess;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;
    final accent = theme.colorScheme.onSecondary;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '$remaining of $total drawings left this round',
            style: textTheme.bodyMedium?.copyWith(
              color: AppColors.ink.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              AppAvatar(
                initials: initialsFor(drawing.authorDisplayName),
                size: 32,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  '${drawing.authorDisplayName} drew this',
                  style: textTheme.bodyMedium,
                ),
              ),
              AttentionChip(drawing.difficulty.label),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          // Same three-layer canvas frame as the editor — Design.md §4:
          // "never fewer than these layers."
          Container(
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: BoxDecoration(
              color: AppColors.cream,
              borderRadius: AppRadius.cardRadius,
            ),
            child: Container(
              padding: const EdgeInsets.all(AppSpacing.sm),
              decoration: BoxDecoration(
                color: AppColors.white,
                borderRadius: AppRadius.cardRadius,
                border: Border.all(
                  color: AppColors.ink,
                  width: AppBorders.thick,
                ),
              ),
              child: AspectRatio(
                aspectRatio: 1,
                child: Container(
                  color: AppColors.canvas,
                  child: PixelPreview(
                    canvasSize: drawing.canvasSize,
                    pixels: drawing.pixels,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              NeutralChip(drawing.category),
              const Spacer(),
              _AttemptMarkers(attempts: progress.attempts),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: [
              for (var i = 0; i < drawing.word.length; i++)
                _LetterTile(
                  letter: drawing.word[i].toUpperCase(),
                  revealed: progress.solved || i < progress.revealedCount,
                  solved: progress.solved,
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          if (progress.solved) ...[
            Text(
              'Solved! ×${drawing.multiplier.toStringAsFixed(1)}',
              style: textTheme.titleMedium?.copyWith(color: AppColors.ink),
            ),
            const SizedBox(height: AppSpacing.sm),
            AppButton(label: 'Next drawing', onPressed: () async => onNext()),
          ] else if (progress.isOutOfAttempts) ...[
            Text(
              "Out of guesses — it was '${drawing.word}'.",
              style: textTheme.bodyMedium,
            ),
            const SizedBox(height: AppSpacing.sm),
            AppButton(label: 'Next drawing', onPressed: () async => onNext()),
          ] else
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: controller,
                    textCapitalization: TextCapitalization.none,
                    decoration: const InputDecoration(hintText: 'your guess'),
                    onSubmitted: (_) => onGuess(),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                SizedBox(
                  height: AppSizes.inputHeight,
                  child: ElevatedButton(
                    onPressed: submitting ? null : onGuess,
                    child: submitting
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
            ),
        ],
      ),
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

/// Design.md §3 "Attempt marker": 11px dot, 2px ink border. Filled =
/// spent, hollow = remaining.
class _AttemptMarkers extends StatelessWidget {
  const _AttemptMarkers({required this.attempts});

  final int attempts;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < GuessProgress.maxAttempts; i++) ...[
          if (i > 0) const SizedBox(width: 4),
          Container(
            width: 11,
            height: 11,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: i < attempts ? AppColors.ink : Colors.transparent,
              border: Border.all(color: AppColors.ink, width: AppBorders.thin),
            ),
          ),
        ],
      ],
    );
  }
}
