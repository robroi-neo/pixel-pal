import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../models/prompt.dart';
import '../../models/room_detail.dart';
import '../../services/drawing_service.dart';
import '../../services/room_service.dart';
import '../../services/round_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_dimens.dart';
import '../../theme/app_palette.dart';
import '../../utils/pixel_codec.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_chip.dart';
import '../../widgets/app_sheet.dart';
import '../../widgets/app_snackbar.dart';
import '../../widgets/deadline_chip.dart';
import '../../widgets/drawing_art.dart';
import '../../widgets/loading_view.dart';
import '../../widgets/pixel_canvas.dart';
import '../../widgets/pixel_editor.dart';

/// Design.md §5 "Draw / editor" — reached from prompt pick's "Start
/// drawing". Implementations.md calls this the longest client phase
/// (5-8 weeks) for good reason; this covers the part that's actually
/// tractable in one pass — real pixel painting (pencil/fill/eraser/undo)
/// against the fixed 16-colour palette, matching the mockup exactly, and
/// a real (if simplified) `submitDrawing` — and deliberately does not
/// attempt the two things Implementations.md itself flags as the hard,
/// multi-week remainder:
///
/// - Real pinch-zoom/pan — no zoom control at all for now, not even a
///   stand-in button. Implementations.md budgets a full week on its own
///   for the draw/pinch gesture conflicts alone.
/// - Local draft persistence surviving app restart (Hive/sqflite). The
///   canvas lives only in this screen's memory — force-quitting loses an
///   unsubmitted drawing.
///
/// Submitting is the one irreversible thing in a round, so it's staged:
/// a confirmation sheet with the drawing on it, a "Sending…" hold while
/// the write lands, then a "Drawing in!" screen that points at what's
/// next. Pops `true` to go on to guessing, `false` to go back to the hub.
class DrawingScreen extends StatefulWidget {
  const DrawingScreen({
    super.key,
    required this.roomId,
    required this.round,
    required this.prompt,
  });

  final String roomId;
  final int round;
  final Prompt prompt;

  @override
  State<DrawingScreen> createState() => _DrawingScreenState();
}

enum _SubmitStage { editing, sending, sent }

class _DrawingScreenState extends State<DrawingScreen> {
  final _drawingService = DrawingService();
  var _stage = _SubmitStage.editing;
  // Cached — the submit stages rebuild this screen, and a fresh stream
  // each time would resubscribe.
  late final Stream<RoomDetail?> _room = RoomService().watchRoom(widget.roomId);
  late final Stream<bool> _hasSubmitted = _drawingService.watchHasSubmitted(
    widget.roomId,
    widget.round,
  );

  // Created once the room (and so its canvas size) is known.
  PixelEditorController? _editor;

  @override
  void dispose() {
    _editor?.dispose();
    super.dispose();
  }

  Future<void> _handleSubmit() async {
    final editor = _editor!;
    if (PixelCodec.isEmpty(editor.pixels)) {
      HapticFeedback.lightImpact();
      AppSnackBar.show(context, 'Draw something first.');
      return;
    }
    final confirmed = await _ConfirmSubmitSheet.show(
      context,
      prompt: widget.prompt,
      round: widget.round,
      canvasSize: editor.canvasSize,
      pixels: editor.pixels,
    );
    if (confirmed != true || !mounted) return;

    HapticFeedback.mediumImpact();
    setState(() => _stage = _SubmitStage.sending);
    try {
      await _drawingService.submitDrawing(
        roomId: widget.roomId,
        round: widget.round,
        prompt: widget.prompt,
        canvasSize: editor.canvasSize,
        pixels: editor.pixels,
      );
      // Might be the last thing the round was waiting for.
      unawaited(RoundService().checkIn(widget.roomId));
      if (!mounted) return;
      HapticFeedback.heavyImpact();
      setState(() => _stage = _SubmitStage.sent);
    } on DrawingServiceException catch (e) {
      if (!mounted) return;
      setState(() => _stage = _SubmitStage.editing);
      AppSnackBar.show(context, e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return StreamBuilder<RoomDetail?>(
      stream: _room,
      builder: (context, snapshot) {
        final room = snapshot.data;
        if (room != null) {
          _editor ??= PixelEditorController(canvasSize: room.canvasSize);
        }

        final sent = _stage == _SubmitStage.sent;
        return PopScope(
          // Nothing to go back to once it's in: Back means "to the hub".
          canPop: !sent && _stage != _SubmitStage.sending,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop && sent) context.pop(false);
          },
          child: Scaffold(
            appBar: AppBar(
              leading: IconButton(
                icon: const Icon(Icons.arrow_back_outlined),
                onPressed: _stage == _SubmitStage.sending
                    ? null
                    : () => context.pop(sent ? false : null),
              ),
              title: Row(
                children: [
                  Flexible(
                    child: Text(
                      widget.prompt.word,
                      style: textTheme.titleMedium,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  AttentionChip(widget.prompt.difficulty.label),
                ],
              ),
              actions: [
                if (room?.roundEndsAt != null && !sent) ...[
                  Center(child: DeadlineChip(endsAt: room!.roundEndsAt!)),
                  const SizedBox(width: AppSpacing.md),
                ],
              ],
            ),
            body: SafeArea(
              child: !snapshot.hasData
                  ? const LoadingView()
                  : room == null
                  ? Center(
                      child: Text(
                        'This room no longer exists.',
                        style: textTheme.bodyMedium,
                      ),
                    )
                  : switch (_stage) {
                      _SubmitStage.sending => const LoadingView(
                        message: 'Sending your drawing…',
                      ),
                      _SubmitStage.sent => _SubmittedView(
                        prompt: widget.prompt,
                        round: widget.round,
                        canvasSize: _editor!.canvasSize,
                        pixels: _editor!.pixels,
                        onGuess: () => context.pop(true),
                        onHome: () => context.pop(false),
                      ),
                      // The submission check comes after the stage: the
                      // local write flips this stream before the send
                      // finishes, which would otherwise flash "already
                      // drawn" mid-submit.
                      _SubmitStage.editing => StreamBuilder<bool>(
                        stream: _hasSubmitted,
                        builder: (context, submittedSnapshot) {
                          if (submittedSnapshot.data == true) {
                            return _AlreadySubmitted(word: widget.prompt.word);
                          }
                          return _EditorBody(
                            editor: _editor!,
                            onSubmit: _handleSubmit,
                          );
                        },
                      ),
                    },
            ),
          ),
        );
      },
    );
  }
}

class _AlreadySubmitted extends StatelessWidget {
  const _AlreadySubmitted({required this.word});

  final String word;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              "You've already drawn $word",
              style: textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              "One drawing per round, and it can't be changed once it's in.",
              style: textTheme.bodySmall?.copyWith(
                color: AppColors.ink.withValues(alpha: 0.6),
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _EditorBody extends StatelessWidget {
  const _EditorBody({required this.editor, required this.onSubmit});

  final PixelEditorController editor;
  final Future<void> Function() onSubmit;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final canvasSize = editor.canvasSize;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PixelEditor(
            controller: editor,
            previewBuilder: (context, pixels) => Column(
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: AppColors.canvas,
                    borderRadius: AppRadius.controlRadius,
                    border: Border.all(
                      color: AppColors.ink,
                      width: AppBorders.thin,
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(
                      AppRadius.control - AppBorders.thin,
                    ),
                    child: PixelPreview(canvasSize: canvasSize, pixels: pixels),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'in the gallery',
                  style: textTheme.bodySmall?.copyWith(
                    color: AppColors.ink.withValues(alpha: 0.6),
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          AppButton(label: 'Submit drawing', onPressed: onSubmit),
          const SizedBox(height: AppSpacing.sm),
          Center(
            child: Text(
              '$canvasSize×$canvasSize · fixed ${AppPalette.colors.length}-colour palette',
              style: textTheme.bodySmall?.copyWith(
                color: AppColors.ink.withValues(alpha: 0.6),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// "Send it in?" — the drawing as everyone will see it, with the one
/// thing to know: it can't be changed after this.
class _ConfirmSubmitSheet extends StatelessWidget {
  const _ConfirmSubmitSheet({
    required this.prompt,
    required this.round,
    required this.canvasSize,
    required this.pixels,
  });

  final Prompt prompt;
  final int round;
  final int canvasSize;
  final List<Color> pixels;

  static Future<bool?> show(
    BuildContext context, {
    required Prompt prompt,
    required int round,
    required int canvasSize,
    required List<Color> pixels,
  }) {
    return AppSheet.show<bool>(
      context,
      builder: (_) => _ConfirmSubmitSheet(
        prompt: prompt,
        round: round,
        canvasSize: canvasSize,
        pixels: pixels,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return AppSheet(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Send it in?', style: textTheme.headlineMedium),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Everyone guesses your ${prompt.word} in round ${round + 1}. '
            "It can't be changed after this.",
            style: textTheme.bodyMedium?.copyWith(
              color: AppColors.ink.withValues(alpha: 0.75),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          DrawingArt.pixels(
            pixels: pixels,
            canvasSize: canvasSize,
            maxWidth: 180,
          ),
          const SizedBox(height: AppSpacing.lg),
          AppButton(
            label: 'Submit drawing',
            onPressed: () async => Navigator.of(context).pop(true),
          ),
          const SizedBox(height: AppSpacing.xs),
          Center(
            child: TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Keep drawing'),
            ),
          ),
        ],
      ),
    );
  }
}

/// The moment after submitting: a stamp, the drawing in its frame, and
/// what's next — last round's drawings to guess, or back to the hub in
/// round 1.
class _SubmittedView extends StatelessWidget {
  const _SubmittedView({
    required this.prompt,
    required this.round,
    required this.canvasSize,
    required this.pixels,
    required this.onGuess,
    required this.onHome,
  });

  final Prompt prompt;
  final int round;
  final int canvasSize;
  final List<Color> pixels;
  final VoidCallback onGuess;
  final VoidCallback onHome;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;
    final accent = theme.colorScheme.onSecondary;
    final reduceMotion = MediaQuery.of(context).disableAnimations;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: 1),
                duration: reduceMotion
                    ? Duration.zero
                    : const Duration(milliseconds: 500),
                curve: Curves.easeOutBack,
                builder: (context, t, child) => Transform.scale(
                  scale: 0.4 + 0.6 * t,
                  child: Opacity(opacity: t.clamp(0.0, 1.0), child: child),
                ),
                child: Container(
                  width: 72,
                  height: 72,
                  decoration: const BoxDecoration(
                    color: AppColors.ink,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.check_rounded, size: 44, color: accent),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              'Drawing in!',
              textAlign: TextAlign.center,
              style: textTheme.headlineMedium,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Everyone guesses your ${prompt.word} in round ${round + 1}.',
              textAlign: TextAlign.center,
              style: textTheme.bodyMedium?.copyWith(
                color: AppColors.ink.withValues(alpha: 0.75),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            // Design.md §4: cream band → white card → canvas.
            Center(
              child: Container(
                padding: const EdgeInsets.all(AppSpacing.sm),
                decoration: BoxDecoration(
                  color: AppColors.cream,
                  borderRadius: AppRadius.cardRadius,
                ),
                child: DrawingArt.pixels(
                  pixels: pixels,
                  canvasSize: canvasSize,
                  maxWidth: 200,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            if (round > 1) ...[
              AppButton(
                label: 'Guess round ${round - 1}',
                onPressed: () async => onGuess(),
              ),
              const SizedBox(height: AppSpacing.xs),
              Center(
                child: TextButton(
                  onPressed: onHome,
                  child: Text('Back to round $round'),
                ),
              ),
            ] else ...[
              Text(
                'Round 1 is draw-only — guessing starts in round 2.',
                textAlign: TextAlign.center,
                style: textTheme.bodySmall?.copyWith(
                  color: AppColors.ink.withValues(alpha: 0.6),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              AppButton(
                label: 'Back to round 1',
                onPressed: () async => onHome(),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
