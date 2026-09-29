import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../models/prompt.dart';
import '../../models/room_detail.dart';
import '../../services/drawing_service.dart';
import '../../services/round_service.dart';
import '../../services/room_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_dimens.dart';
import '../../theme/app_palette.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_chip.dart';
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

class _DrawingScreenState extends State<DrawingScreen> {
  final _drawingService = DrawingService();
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
      // true = submitted; PromptPickScreen moves on to guessing.
      context.pop(true);
    } on DrawingServiceException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return StreamBuilder<RoomDetail?>(
      stream: RoomService().watchRoom(widget.roomId),
      builder: (context, snapshot) {
        final room = snapshot.data;
        if (room != null) {
          _editor ??= PixelEditorController(canvasSize: room.canvasSize);
        }

        return Scaffold(
          appBar: AppBar(
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_outlined),
              onPressed: () => context.pop(),
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
              if (room?.roundEndsAt != null) ...[
                _HoursLeftChip(roundEndsAt: room!.roundEndsAt!),
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
                : StreamBuilder<bool>(
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
              'Submissions can only happen once per room.',
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

class _HoursLeftChip extends StatelessWidget {
  const _HoursLeftChip({required this.roundEndsAt});

  final DateTime roundEndsAt;

  @override
  Widget build(BuildContext context) {
    if (DateTime.now().isAfter(roundEndsAt)) {
      return const AttentionChip('locked');
    }
    final remaining = roundEndsAt.difference(DateTime.now());
    final label = remaining.inHours >= 1
        ? '${remaining.inHours}h left'
        : '${remaining.inMinutes.clamp(0, 59)}m left';
    return NeutralChip(label);
  }
}
