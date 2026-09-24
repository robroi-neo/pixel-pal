import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../router/app_router.dart';
import '../services/room_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_dimens.dart';
import '../widgets/app_button.dart';

/// The "join a room" bottom sheet reached from the room list's "New room
/// or join code" button. Design.md marks create/join room as not designed
/// (§5) — this follows the mockup directly.
///
/// "Find the room" calls the `joinRoom` Cloud Functions callable — the
/// client never writes `rooms/**` directly (Implementations.md "Standing
/// rules"). There's no per-room screen yet, so success lands back on the
/// room list, where the newly joined room now appears live.
class JoinRoomSheet extends StatefulWidget {
  const JoinRoomSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const JoinRoomSheet(),
    );
  }

  @override
  State<JoinRoomSheet> createState() => _JoinRoomSheetState();
}

class _JoinRoomSheetState extends State<JoinRoomSheet> {
  final _roomService = RoomService();
  String _code = '';

  Future<void> _findRoom() async {
    if (_code.length != 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter the full 6-character code.')),
      );
      return;
    }
    try {
      await _roomService.joinRoom(_code);
      if (!mounted) return;
      context.pop();
      context.go(AppRoutes.home);
    } on RoomServiceException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          // A non-uniform Border (e.g. omitting the bottom side, which sits
          // off-screen anyway) throws — BoxDecoration only allows
          // borderRadius together with a uniform border on all four sides.
          border: Border.all(color: AppColors.ink, width: AppBorders.thick),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.sm,
              AppSpacing.lg,
              AppSpacing.lg,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Center(
                        child: Container(
                          width: 36,
                          height: 4,
                          decoration: BoxDecoration(
                            color: AppColors.ink.withValues(alpha: 0.25),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                Align(
                  alignment: Alignment.topRight,
                  child: IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => context.pop(),
                  ),
                ),
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
                _InviteCodeInput(onChanged: (code) => _code = code),
                const SizedBox(height: AppSpacing.lg),
                AppButton(label: 'Find the room', onPressed: _findRoom),
                const SizedBox(height: AppSpacing.md),
                Row(
                  children: [
                    const Expanded(child: Divider(color: AppColors.ink)),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.sm,
                      ),
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
            ),
          ),
        ),
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
  const _InviteCodeInput({required this.onChanged});

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
                decoration: const InputDecoration(counterText: ''),
                onChanged: (value) => _handleChanged(i, value),
              ),
            ),
          ),
        ],
      ],
    );
  }
}
