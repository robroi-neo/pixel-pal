import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../router/app_router.dart';
import '../../services/room_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_dimens.dart';
import '../../widgets/app_button.dart';
import 'room_created_screen.dart';
import '../../widgets/app_snackbar.dart';

enum _CanvasSize {
  size16(16, '16 × 16', 'Fast and blunt, peak abstraction'),
  size32(32, '32 × 32', 'Just big enough.');

  const _CanvasSize(this.value, this.label, this.subtitle);
  final int value;
  final String label;
  final String subtitle;
}

enum _RoundLength {
  h12(12, '12h'),
  h24(24, '24h');

  const _RoundLength(this.value, this.label);
  final int value;
  final String label;
}

/// Design.md marks "Create/join room" as not designed (§5) — this screen
/// follows the mockup directly rather than an existing spec section.
///
/// "Create room" writes the room straight from the client
/// ([RoomService.createRoom]) — Spark has no Cloud Functions, so
/// firestore.rules does the validating.
class CreateRoomScreen extends StatefulWidget {
  const CreateRoomScreen({super.key});

  @override
  State<CreateRoomScreen> createState() => _CreateRoomScreenState();
}

class _CreateRoomScreenState extends State<CreateRoomScreen> {
  final _nameController = TextEditingController();
  final _roomService = RoomService();
  _CanvasSize _canvasSize = _CanvasSize.size32;
  _RoundLength _roundLength = _RoundLength.h24;

  String get _name => _nameController.text.trim();
  bool get _nameTooLong => _name.length > RoomService.maxNameLength;

  @override
  void initState() {
    super.initState();
    // Live counter and the too-long error as you type.
    _nameController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _createRoom() async {
    final name = _name;
    if (_nameTooLong) return; // The field is already showing why.
    try {
      final room = await _roomService.createRoom(
        name: name.isEmpty ? 'Pixel pals' : name,
        canvasSize: _canvasSize.value,
        roundLengthHours: _roundLength.value,
      );
      if (!mounted) return;
      context.pushReplacement(
        AppRoutes.roomCreated,
        extra: RoomCreatedArgs(
          roomId: room.roomId,
          roomName: name.isEmpty ? 'Pixel pals' : name,
          canvasLabel: _canvasSize.label,
          roundLabel: _roundLength.label,
          inviteCode: room.code,
        ),
      );
    } on RoomServiceException catch (e) {
      if (!mounted) return;
      AppSnackBar.show(context, e.message);
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
        title: Text('New room', style: textTheme.titleMedium),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Set up your room', style: textTheme.headlineMedium),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Settings cannot be changed for now. '
                'Perhaps in future iterations.',
                style: textTheme.bodyMedium,
              ),
              const SizedBox(height: AppSpacing.xl),
              _FieldLabel('Room name'),
              const SizedBox(height: AppSpacing.sm),
              // Not hard-capped with maxLength: a paste that runs over is
              // kept and explained, rather than silently cut off.
              TextField(
                controller: _nameController,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(
                  hintText: 'Pixel pals',
                  counterText: '${_name.length}/${RoomService.maxNameLength}',
                  errorText: _nameTooLong
                      ? RoomService.nameTooLongMessage
                      : null,
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              _FieldLabel('Canvas size'),
              const SizedBox(height: AppSpacing.sm),
              for (final size in _CanvasSize.values) ...[
                _OptionCard(
                  title: size.label,
                  subtitle: size.subtitle,
                  selected: _canvasSize == size,
                  onTap: () => setState(() => _canvasSize = size),
                ),
                if (size != _CanvasSize.values.last)
                  const SizedBox(height: AppSpacing.sm),
              ],
              const SizedBox(height: AppSpacing.xl),
              _FieldLabel('How long a round lasts'),
              const SizedBox(height: AppSpacing.sm),
              Row(
                children: [
                  for (final length in _RoundLength.values) ...[
                    if (length != _RoundLength.values.first)
                      const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: _SegmentOption(
                        label: length.label,
                        selected: _roundLength == length,
                        onTap: () => setState(() => _roundLength = length),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: AppSpacing.xl),
              AppButton(
                label: 'Create room',
                enabled: !_nameTooLong,
                onPressed: _createRoom,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
        color: AppColors.ink.withValues(alpha: 0.6),
      ),
    );
  }
}

/// A stacked, selectable option — Canvas size's three rows. Selection
/// follows the same ink-fill / accent-text pattern as a primary button and
/// an "attention" chip elsewhere in the theme.
class _OptionCard extends StatelessWidget {
  const _OptionCard({
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.onSecondary;
    final titleColor = selected ? accent : AppColors.ink;
    final subtitleColor = selected
        ? accent.withValues(alpha: 0.85)
        : AppColors.ink.withValues(alpha: 0.6);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.controlRadius,
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: selected ? AppColors.ink : AppColors.white,
            borderRadius: AppRadius.controlRadius,
            border: Border.all(color: AppColors.ink, width: AppBorders.thick),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: titleColor,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: subtitleColor,
                      ),
                    ),
                  ],
                ),
              ),
              if (selected) Icon(Icons.check, color: accent),
            ],
          ),
        ),
      ),
    );
  }
}

/// One segment of the round-length row.
class _SegmentOption extends StatelessWidget {
  const _SegmentOption({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.onSecondary;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.controlRadius,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? AppColors.ink : AppColors.white,
            borderRadius: AppRadius.controlRadius,
            border: Border.all(color: AppColors.ink, width: AppBorders.thick),
          ),
          child: Text(
            label,
            style: theme.textTheme.labelLarge?.copyWith(
              color: selected ? accent : AppColors.ink,
            ),
          ),
        ),
      ),
    );
  }
}
