import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../models/prompt.dart';
import '../models/room_detail.dart';
import '../services/drawing_service.dart';
import '../services/room_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_dimens.dart';
import '../theme/app_palette.dart';
import '../widgets/app_button.dart';
import '../widgets/app_chip.dart';
import '../widgets/pixel_canvas.dart';

enum _EditorTool { pencil, fill, eraser }

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
  const DrawingScreen({super.key, required this.roomId, required this.prompt});

  final String roomId;
  final Prompt prompt;

  @override
  State<DrawingScreen> createState() => _DrawingScreenState();
}

class _DrawingScreenState extends State<DrawingScreen> {
  static const _maxUndo = 20;

  final _drawingService = DrawingService();
  late final Stream<bool> _hasSubmitted = _drawingService.watchHasSubmitted(
    widget.roomId,
  );

  int? _canvasSize;
  late List<Color> _pixels;
  final List<List<Color>> _undoStack = [];

  _EditorTool _tool = _EditorTool.pencil;
  Color _selectedColor = AppPalette.colors.first;

  void _ensureInitialized(int canvasSize) {
    if (_canvasSize == canvasSize) return;
    _canvasSize = canvasSize;
    _pixels = List<Color>.filled(canvasSize * canvasSize, AppColors.canvas);
  }

  void _pushUndoSnapshot() {
    _undoStack.add(List<Color>.from(_pixels));
    if (_undoStack.length > _maxUndo) _undoStack.removeAt(0);
  }

  void _undo() {
    if (_undoStack.isEmpty) return;
    setState(() => _pixels = _undoStack.removeLast());
  }

  void _handleStrokeStart() {
    // Fill pushes its own snapshot in _handleTapCell, once it knows a
    // fill is actually happening — not here, since onStrokeStart also
    // fires for a tap that a non-fill tool will ignore entirely.
    if (_tool == _EditorTool.fill) return;
    _pushUndoSnapshot();
  }

  void _handlePaintCell(int index) {
    if (_tool == _EditorTool.fill) return;
    setState(() {
      _pixels[index] = _tool == _EditorTool.eraser
          ? AppColors.canvas
          : _selectedColor;
    });
  }

  void _handleTapCell(int index) {
    if (_tool != _EditorTool.fill) return;
    final target = _pixels[index];
    if (target == _selectedColor) return;
    _pushUndoSnapshot();
    _floodFill(index, target);
  }

  void _floodFill(int start, Color target) {
    final n = _canvasSize!;
    final visited = List<bool>.filled(_pixels.length, false);
    final stack = <int>[start];
    visited[start] = true;

    while (stack.isNotEmpty) {
      final i = stack.removeLast();
      _pixels[i] = _selectedColor;
      final row = i ~/ n;
      final col = i % n;
      for (final (dr, dc) in const [(-1, 0), (1, 0), (0, -1), (0, 1)]) {
        final nr = row + dr;
        final nc = col + dc;
        if (nr < 0 || nr >= n || nc < 0 || nc >= n) continue;
        final ni = nr * n + nc;
        if (visited[ni] || _pixels[ni] != target) continue;
        visited[ni] = true;
        stack.add(ni);
      }
    }
    setState(() {});
  }

  Future<void> _handleSubmit() async {
    try {
      await _drawingService.submitDrawing(
        roomId: widget.roomId,
        prompt: widget.prompt,
        canvasSize: _canvasSize!,
        pixels: _pixels,
      );
      if (!mounted) return;
      context.pop();
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
        if (room != null) _ensureInitialized(room.canvasSize);

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
                ? const Center(
                    child: CircularProgressIndicator(color: AppColors.ink),
                  )
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
                        canvasSize: _canvasSize!,
                        pixels: _pixels,
                        tool: _tool,
                        selectedColor: _selectedColor,
                        canUndo: _undoStack.isNotEmpty,
                        onToolSelected: (tool) => setState(() => _tool = tool),
                        onColorSelected: (color) =>
                            setState(() => _selectedColor = color),
                        onUndo: _undo,
                        onStrokeStart: _handleStrokeStart,
                        onPaintCell: _handlePaintCell,
                        onTapCell: _handleTapCell,
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
  const _EditorBody({
    required this.canvasSize,
    required this.pixels,
    required this.tool,
    required this.selectedColor,
    required this.canUndo,
    required this.onToolSelected,
    required this.onColorSelected,
    required this.onUndo,
    required this.onStrokeStart,
    required this.onPaintCell,
    required this.onTapCell,
    required this.onSubmit,
  });

  final int canvasSize;
  final List<Color> pixels;
  final _EditorTool tool;
  final Color selectedColor;
  final bool canUndo;
  final ValueChanged<_EditorTool> onToolSelected;
  final ValueChanged<Color> onColorSelected;
  final VoidCallback onUndo;
  final VoidCallback onStrokeStart;
  final ValueChanged<int> onPaintCell;
  final ValueChanged<int> onTapCell;
  final Future<void> Function() onSubmit;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Design.md §4 "canvas frame": cream band -> white card (3px
          // ink border) -> locked canvas fill -> pixel grid. Never fewer
          // than these layers, and `canvas` never changes for any theme.
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
                border: Border.all(color: AppColors.ink, width: AppBorders.thick),
              ),
              child: AspectRatio(
                aspectRatio: 1,
                child: Container(
                  color: AppColors.canvas,
                  child: PixelCanvas(
                    canvasSize: canvasSize,
                    pixels: pixels,
                    onStrokeStart: onStrokeStart,
                    onPaintCell: onPaintCell,
                    onTapCell: onTapCell,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Row(
                  children: [
                    _ToolButton(
                      icon: Icons.edit,
                      selected: tool == _EditorTool.pencil,
                      onTap: () => onToolSelected(_EditorTool.pencil),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    _ToolButton(
                      icon: Icons.format_color_fill,
                      selected: tool == _EditorTool.fill,
                      onTap: () => onToolSelected(_EditorTool.fill),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    _ToolButton(
                      icon: Icons.backspace_outlined,
                      selected: tool == _EditorTool.eraser,
                      onTap: () => onToolSelected(_EditorTool.eraser),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    _ToolButton(
                      icon: Icons.undo,
                      selected: false,
                      onTap: canUndo ? onUndo : null,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Column(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: AppColors.canvas,
                      borderRadius: AppRadius.controlRadius,
                      border: Border.all(color: AppColors.ink, width: AppBorders.thin),
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
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          Container(
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: BoxDecoration(
              color: AppColors.cream,
              borderRadius: AppRadius.cardRadius,
              border: Border.all(color: AppColors.ink, width: AppBorders.thick),
            ),
            child: Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                for (final color in AppPalette.colors)
                  _Swatch(
                    color: color,
                    selected: color == selectedColor,
                    onTap: () => onColorSelected(color),
                  ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          // Really submits to rooms/{roomId}/drawings/{uid} now — see
          // DrawingService. Still nothing downstream to consume it yet
          // (no guess/reveal screen), so a submitted drawing just sits
          // there until that's built.
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

class _ToolButton extends StatelessWidget {
  const _ToolButton({required this.icon, required this.selected, this.onTap});

  final IconData icon;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final iconColor = onTap == null
        ? AppColors.grey
        : (selected ? theme.colorScheme.onSecondary : AppColors.ink);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.controlRadius,
        child: Container(
          width: 44,
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? AppColors.ink : AppColors.white,
            borderRadius: AppRadius.controlRadius,
            border: Border.all(color: AppColors.ink, width: AppBorders.thick),
          ),
          child: Icon(icon, size: 20, color: iconColor),
        ),
      ),
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({required this.color, required this.selected, required this.onTap});

  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // §4 "The palette may not sit on raw yellow": the selection indicator
    // is an ink inset tick, not a yellow ring, precisely so it stays
    // legible on every swatch including the palette's own yellow-ish one.
    final tickColor = color.computeLuminance() > 0.5
        ? AppColors.ink
        : AppColors.white;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.tileRadius,
        child: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: color,
            borderRadius: AppRadius.tileRadius,
            border: Border.all(color: AppColors.ink, width: AppBorders.thin),
          ),
          child: selected
              ? Icon(Icons.check, size: 16, color: tickColor)
              : null,
        ),
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
