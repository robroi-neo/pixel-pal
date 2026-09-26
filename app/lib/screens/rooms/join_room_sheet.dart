import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../models/room_lookup.dart';
import '../../router/app_router.dart';
import '../../services/room_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_dimens.dart';
import '../../widgets/app_avatar.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_sheet.dart';

/// The "join a room" bottom sheet reached from the room list's "New room
/// or join code" button. Design.md marks create/join room as not designed
/// (§5) — this follows the mockup directly.
///
/// A code doesn't join outright — [RoomService.previewRoomByCode] reads
/// the room read-only first, and the sheet shows one of four outcomes
/// (matched / full / already a member / not found) before anything is
/// written. Only [RoomLookupJoinable] actually calls the mutating
/// [RoomService.joinRoom].
class JoinRoomSheet extends StatefulWidget {
  const JoinRoomSheet({super.key});

  static Future<void> show(BuildContext context) {
    return AppSheet.show<void>(
      context,
      builder: (context) => const JoinRoomSheet(),
    );
  }

  @override
  State<JoinRoomSheet> createState() => _JoinRoomSheetState();
}

class _JoinRoomSheetState extends State<JoinRoomSheet> {
  final _roomService = RoomService();
  String _code = '';
  RoomLookupResult? _result;

  // Bumped on "try a different code" to force a fresh _InviteCodeInput —
  // its controllers hold their own text, so reusing the same instance
  // wouldn't clear the boxes.
  int _resetTick = 0;

  bool get _isNotFound => _result is RoomLookupNotFound;

  Future<void> _findRoom() async {
    if (_code.length != 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter the full 6-character code.')),
      );
      return;
    }
    try {
      final result = await _roomService.previewRoomByCode(_code);
      if (!mounted) return;
      setState(() => _result = result);
    } on RoomServiceException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _confirmJoin() async {
    try {
      final joined = await _roomService.joinRoom(_code);
      if (!mounted) return;
      context.pop();
      context.push('${AppRoutes.rooms}/${joined.roomId}');
    } on RoomServiceException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message)));
      // The room's state may have moved since the preview (e.g. it just
      // filled up) — refresh so the sheet reflects what's actually true.
      unawaited(_findRoom());
    }
  }

  void _goToRoom(String roomId) {
    context.pop();
    context.push('${AppRoutes.rooms}/$roomId');
  }

  void _tryDifferentCode() {
    setState(() {
      _result = null;
      _code = '';
      _resetTick++;
    });
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;

    return AppSheet(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.topRight,
            child: IconButton(
              icon: const Icon(Icons.close),
              onPressed: () => context.pop(),
            ),
          ),
          switch (result) {
            RoomLookupJoinable(:final preview) => _JoinablePanel(
              code: _code,
              preview: preview,
              onJoin: _confirmJoin,
              onTryDifferentCode: _tryDifferentCode,
            ),
            RoomLookupFull(:final preview) => _FullPanel(
              preview: preview,
              onTryDifferentCode: _tryDifferentCode,
            ),
            RoomLookupAlreadyMember(:final preview) => _AlreadyMemberPanel(
              preview: preview,
              onGoToRoom: () => _goToRoom(preview.roomId),
            ),
            RoomLookupNotFound() || null => _EnteringPanel(
              key: ValueKey(_resetTick),
              isError: _isNotFound,
              onChanged: (code) => _code = code,
              onFindRoom: _findRoom,
            ),
          },
        ],
      ),
    );
  }
}

/// The default state: type a code, or start a new room instead.
class _EnteringPanel extends StatelessWidget {
  const _EnteringPanel({
    super.key,
    required this.isError,
    required this.onChanged,
    required this.onFindRoom,
  });

  final bool isError;
  final ValueChanged<String> onChanged;
  final Future<void> Function() onFindRoom;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Join a room', style: textTheme.headlineMedium),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'Six characters from whoever set the room up. Rooms hold '
          '2 to 8 players.',
          style: textTheme.bodyMedium,
        ),
        const SizedBox(height: AppSpacing.lg),
        Text(
          'Invite code',
          style: textTheme.bodySmall?.copyWith(
            color: AppColors.ink.withValues(alpha: 0.6),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        _InviteCodeInput(isError: isError, onChanged: onChanged),
        if (isError) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(
            'No room uses this code. Codes never contain O, I, or 0.',
            style: textTheme.bodySmall?.copyWith(color: AppColors.error),
          ),
        ],
        const SizedBox(height: AppSpacing.lg),
        AppButton(label: 'Find the room', onPressed: onFindRoom),
        const SizedBox(height: AppSpacing.md),
        Row(
          children: [
            const Expanded(child: Divider(color: AppColors.ink)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
              child: Text(
                'or',
                style: textTheme.bodySmall?.copyWith(
                  color: AppColors.ink.withValues(alpha: 0.6),
                ),
              ),
            ),
            const Expanded(child: Divider(color: AppColors.ink)),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        AppButton(
          label: 'Start a new room',
          secondary: true,
          onPressed: () async {
            context.pop();
            context.push(AppRoutes.createRoom);
          },
        ),
      ],
    );
  }
}

/// A matched, joinable room — shows enough to decide before committing.
class _JoinablePanel extends StatelessWidget {
  const _JoinablePanel({
    required this.code,
    required this.preview,
    required this.onJoin,
    required this.onTryDifferentCode,
  });

  final String code;
  final RoomPreview preview;
  final VoidCallback onJoin;
  final VoidCallback onTryDifferentCode;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Invite code',
          style: textTheme.bodySmall?.copyWith(
            color: AppColors.ink.withValues(alpha: 0.6),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        _CodeDisplay(code: code),
        const SizedBox(height: AppSpacing.lg),
        _RoomPreviewCard(preview: preview),
        const SizedBox(height: AppSpacing.sm),
        Text(
          "You'll join as a new member — nothing about the room changes "
          'until you do.',
          style: textTheme.bodySmall?.copyWith(
            color: AppColors.ink.withValues(alpha: 0.7),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        AppButton(
          label: 'Join ${preview.name}',
          onPressed: () async => onJoin(),
        ),
        const SizedBox(height: AppSpacing.sm),
        Center(
          child: TextButton(
            onPressed: onTryDifferentCode,
            child: const Text('Try a different code'),
          ),
        ),
      ],
    );
  }
}

class _FullPanel extends StatelessWidget {
  const _FullPanel({required this.preview, required this.onTryDifferentCode});

  final RoomPreview preview;
  final VoidCallback onTryDifferentCode;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(AppSpacing.lg),
          decoration: BoxDecoration(
            color: AppColors.white,
            borderRadius: AppRadius.cardRadius,
            border: Border.all(color: AppColors.ink, width: AppBorders.thick),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(preview.name, style: textTheme.titleMedium),
                  ),
                  _NeutralChip('${preview.memberCount} of 8'),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'This room is at its eight-player limit. Someone has to '
                'leave, or ask ${preview.ownerDisplayName} to start a '
                'second room.',
                style: textTheme.bodySmall?.copyWith(
                  color: AppColors.ink.withValues(alpha: 0.7),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        AppButton(
          label: 'Try a different code',
          secondary: true,
          onPressed: () async => onTryDifferentCode(),
        ),
      ],
    );
  }
}

class _AlreadyMemberPanel extends StatelessWidget {
  const _AlreadyMemberPanel({required this.preview, required this.onGoToRoom});

  final RoomPreview preview;
  final VoidCallback onGoToRoom;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(AppSpacing.lg),
          decoration: BoxDecoration(
            color: AppColors.white,
            borderRadius: AppRadius.cardRadius,
            border: Border.all(color: AppColors.ink, width: AppBorders.thick),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "You're already in ${preview.name}",
                style: textTheme.titleMedium,
              ),
              const SizedBox(height: 4),
              Text(
                'You can jump back in any time.',
                style: textTheme.bodySmall?.copyWith(
                  color: AppColors.ink.withValues(alpha: 0.7),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        AppButton(label: 'Go to the room', onPressed: () async => onGoToRoom()),
      ],
    );
  }
}

class _RoomPreviewCard extends StatelessWidget {
  const _RoomPreviewCard({required this.preview});

  final RoomPreview preview;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final memberCount = preview.memberCount;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: AppRadius.cardRadius,
        border: Border.all(color: AppColors.ink, width: AppBorders.thick),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(preview.name, style: textTheme.titleMedium),
                    Text(
                      'Round 1 · $memberCount '
                      '${memberCount == 1 ? 'player' : 'players'} · made by '
                      '${preview.ownerDisplayName}',
                      style: textTheme.bodySmall?.copyWith(
                        color: AppColors.ink.withValues(alpha: 0.6),
                      ),
                    ),
                  ],
                ),
              ),
              _NeutralChip('${preview.roundLengthHours}h rounds'),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              for (final initials in preview.memberPreview) ...[
                AppAvatar(initials: initials, size: 28),
                const SizedBox(width: 6),
              ],
              const Spacer(),
              Text(
                '${preview.canvasSize} × ${preview.canvasSize} canvas',
                style: textTheme.bodySmall?.copyWith(
                  color: AppColors.ink.withValues(alpha: 0.6),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// §3 "Chip": white fill, neutral — informational, not an "attention"
/// state (nothing here needs the ink-fill/accent-text treatment).
class _NeutralChip extends StatelessWidget {
  const _NeutralChip(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final labelStyle = Theme.of(context).chipTheme.labelStyle;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: AppRadius.chipRadius,
        border: Border.all(color: AppColors.ink, width: AppBorders.thin),
      ),
      child: Text(label, style: labelStyle?.copyWith(color: AppColors.ink)),
    );
  }
}

/// A single-line, read-only rendering of an already-matched code — same
/// visual language as the invite code shown on RoomScreen/RoomCreatedScreen.
class _CodeDisplay extends StatelessWidget {
  const _CodeDisplay({required this.code});

  final String code;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: AppRadius.controlRadius,
        border: Border.all(color: AppColors.ink, width: AppBorders.thick),
      ),
      child: Text(
        code.split('').join(' '),
        style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontSize: 20),
      ),
    );
  }
}

class _UpperCaseTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    return newValue.copyWith(text: newValue.text.toUpperCase());
  }
}

/// Six single-character boxes with auto-advance on entry and auto-back on
/// backspace — the invite code is alphanumeric, not numeric, so this is a
/// hand-rolled OTP-style input rather than a package built for PIN codes.
class _InviteCodeInput extends StatefulWidget {
  const _InviteCodeInput({
    required this.isError,
    required this.onChanged,
  });

  final bool isError;

  /// Fires with the combined code every time any box changes — including
  /// a backspace clearing one, so the parent's tracked code stays in sync.
  final ValueChanged<String> onChanged;

  @override
  State<_InviteCodeInput> createState() => _InviteCodeInputState();
}

class _InviteCodeInputState extends State<_InviteCodeInput> {
  static const _length = 6;

  late final _controllers = List.generate(
    _length,
    (_) => TextEditingController(),
  );
  late final _focusNodes = List.generate(_length, (_) => FocusNode());

  @override
  void dispose() {
    for (final controller in _controllers) {
      controller.dispose();
    }
    for (final node in _focusNodes) {
      node.dispose();
    }
    super.dispose();
  }

  void _notifyChanged() {
    widget.onChanged(_controllers.map((c) => c.text).join());
  }

  void _handleChanged(int index, String value) {
    if (value.isNotEmpty && index < _length - 1) {
      _focusNodes[index + 1].requestFocus();
    }
    _notifyChanged();
  }

  void _handleBackspaceOnEmpty(int index) {
    if (index == 0) return;
    _controllers[index - 1].clear();
    _focusNodes[index - 1].requestFocus();
    _notifyChanged();
  }

  @override
  Widget build(BuildContext context) {
    final borderColor = widget.isError ? AppColors.error : AppColors.ink;

    return Row(
      children: [
        for (var i = 0; i < _length; i++) ...[
          if (i > 0) const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Focus(
              onKeyEvent: (node, event) {
                if (event is KeyDownEvent &&
                    event.logicalKey == LogicalKeyboardKey.backspace &&
                    _controllers[i].text.isEmpty) {
                  _handleBackspaceOnEmpty(i);
                  return KeyEventResult.handled;
                }
                return KeyEventResult.ignored;
              },
              child: TextField(
                controller: _controllers[i],
                focusNode: _focusNodes[i],
                textAlign: TextAlign.center,
                textCapitalization: TextCapitalization.characters,
                maxLength: 1,
                style: Theme.of(context).textTheme.titleLarge,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp('[a-zA-Z0-9]')),
                  _UpperCaseTextFormatter(),
                ],
                decoration: InputDecoration(
                  counterText: '',
                  enabledBorder: OutlineInputBorder(
                    borderRadius: AppRadius.controlRadius,
                    borderSide: BorderSide(
                      color: borderColor,
                      width: AppBorders.thin,
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: AppRadius.controlRadius,
                    borderSide: BorderSide(
                      color: borderColor,
                      width: AppBorders.thick,
                    ),
                  ),
                ),
                onChanged: (value) => _handleChanged(i, value),
              ),
            ),
          ),
        ],
      ],
    );
  }
}
