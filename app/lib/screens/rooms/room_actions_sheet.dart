import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../models/room_summary.dart';
import '../../services/drawing_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_dimens.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_sheet.dart';
import '../../widgets/profile_avatar.dart';

enum RoomAction { copyCode, delete, leave }

/// The room card's ⋯ menu. Owners get "Delete this room", members get
/// "Leave room" — two different acts, so never one shared icon on the
/// card itself. Room settings aren't designed yet (Design.md §5), so the
/// mockup's "Room settings" row is left out rather than shipped as a
/// dead button.
class RoomActionsSheet extends StatelessWidget {
  const RoomActionsSheet({super.key, required this.room});

  final RoomSummary room;

  static Future<RoomAction?> show(BuildContext context, RoomSummary room) {
    return AppSheet.show<RoomAction>(
      context,
      builder: (_) => RoomActionsSheet(room: room),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final danger = theme.colorScheme.error;

    return AppSheet(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            room.title,
            style: theme.textTheme.titleLarge,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: AppSpacing.md),
          // No share-sheet package in the app yet, so this copies rather
          // than claiming to "share".
          _ActionRow(
            icon: Icons.copy_outlined,
            label: 'Copy the invite code',
            onTap: () => Navigator.of(context).pop(RoomAction.copyCode),
          ),
          const SizedBox(height: AppSpacing.md),
          Container(
            height: 3,
            decoration: BoxDecoration(
              color: AppColors.ink.withValues(alpha: 0.1),
              borderRadius: AppRadius.chipRadius,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          if (room.isOwner)
            _ActionRow(
              icon: Icons.delete_outline,
              label: 'Delete this room',
              detail: room.isRoundStarted
                  ? 'Everyone in it loses what they played'
                  : 'Nothing has been played yet',
              color: danger,
              onTap: () => Navigator.of(context).pop(RoomAction.delete),
            )
          else
            _ActionRow(
              icon: Icons.logout_rounded,
              label: 'Leave room',
              detail: 'Rejoin any time with the invite code',
              color: danger,
              onTap: () => Navigator.of(context).pop(RoomAction.leave),
            ),
          const SizedBox(height: AppSpacing.sm),
          Center(
            child: TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.icon,
    required this.label,
    required this.onTap,
    this.detail,
    this.color = AppColors.ink,
  });

  final IconData icon;
  final String label;
  final String? detail;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Material(
      color: AppColors.white,
      borderRadius: AppRadius.controlRadius,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.controlRadius,
        child: Container(
          constraints: const BoxConstraints(minHeight: 56),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.md,
          ),
          decoration: BoxDecoration(
            borderRadius: AppRadius.controlRadius,
            border: Border.all(color: color, width: AppBorders.thick),
          ),
          child: Row(
            children: [
              Icon(icon, size: AppSizes.iconMax, color: color),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      label,
                      style: textTheme.bodyMedium?.copyWith(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: color,
                      ),
                    ),
                    if (detail != null)
                      Text(
                        detail!,
                        style: textTheme.bodySmall?.copyWith(
                          color: AppColors.ink.withValues(alpha: 0.6),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Confirmation for deleting a room that has been played. Names the cost
/// — how much disappears and for whom — rather than a generic "are you
/// sure". Resolves true only on "Delete everything".
class DeleteRoomDialog extends StatefulWidget {
  const DeleteRoomDialog({super.key, required this.room});

  final RoomSummary room;

  static Future<bool> show(BuildContext context, RoomSummary room) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => DeleteRoomDialog(room: room),
    );
    return confirmed ?? false;
  }

  @override
  State<DeleteRoomDialog> createState() => _DeleteRoomDialogState();
}

class _DeleteRoomDialogState extends State<DeleteRoomDialog> {
  late final Future<int> _drawingCount = DrawingService().countDrawings(
    widget.room.id,
  );

  String _costText(int? drawings) {
    final players = widget.room.memberCount;
    // No round engine yet (Implementations.md Phase 3) — a started room
    // has only ever played round 1.
    final what = drawings == null
        ? '1 round and its drawings'
        : '1 round and $drawings drawing${drawings == 1 ? '' : 's'}';
    final whom = players > 1 ? ' for all $players players, not just you' : '';
    return '${what[0].toUpperCase()}${what.substring(1)} disappear$whom. '
        'Nobody can get them back.';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;
    final danger = theme.colorScheme.error;
    final myUid = FirebaseAuth.instance.currentUser?.uid;
    final others = widget.room.memberUids
        .where((uid) => uid != myUid)
        .take(4)
        .toList();
    final otherCount = widget.room.memberCount - 1;

    return Dialog(
      backgroundColor: AppColors.cream,
      insetPadding: const EdgeInsets.all(AppSpacing.lg),
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.cardRadius,
        side: const BorderSide(color: AppColors.ink, width: AppBorders.thick),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Delete ${widget.room.title}?',
              style: textTheme.headlineMedium,
            ),
            const SizedBox(height: AppSpacing.md),
            FutureBuilder<int>(
              future: _drawingCount,
              builder: (context, snapshot) => Text(
                _costText(snapshot.data),
                style: textTheme.bodyMedium?.copyWith(
                  color: AppColors.ink.withValues(alpha: 0.75),
                ),
              ),
            ),
            if (otherCount > 0) ...[
              const SizedBox(height: AppSpacing.lg),
              Container(
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: AppColors.white,
                  borderRadius: AppRadius.controlRadius,
                  border: Border.all(
                    color: AppColors.ink,
                    width: AppBorders.thick,
                  ),
                ),
                child: Row(
                  children: [
                    for (var i = 0; i < others.length; i++)
                      Align(
                        widthFactor: i == others.length - 1 ? 1 : 0.75,
                        child: ProfileAvatar(
                          uid: others[i],
                          fallbackInitials: '?',
                          size: 32,
                          ringColor: AppColors.white,
                        ),
                      ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Text(
                        otherCount == 1
                            ? '1 other person loses this'
                            : '$otherCount other people lose this',
                        style: textTheme.bodyMedium,
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.xl),
            AppButton(
              label: 'Keep the room',
              onPressed: () async => Navigator.of(context).pop(false),
            ),
            const SizedBox(height: AppSpacing.md),
            OutlinedButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: OutlinedButton.styleFrom(
                backgroundColor: AppColors.white,
                foregroundColor: danger,
                side: BorderSide(color: danger, width: AppBorders.thick),
              ),
              child: const Text('Delete everything'),
            ),
          ],
        ),
      ),
    );
  }
}
