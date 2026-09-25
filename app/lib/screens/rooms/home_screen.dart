import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../models/room_summary.dart';
import '../../router/app_router.dart';
import '../../services/auth_service.dart';
import '../../services/room_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_dimens.dart';
import '../../theme/app_tokens.dart';
import '../../utils/clipboard.dart';
import '../../utils/dashed_path.dart';
import '../../utils/initials.dart';
import '../../widgets/app_avatar.dart';
import '../../widgets/app_chip.dart';
import '../../widgets/loading_view.dart';
import 'join_room_sheet.dart';
import 'room_actions_sheet.dart';

/// Reads the signed-in user's rooms live from Firestore — every room the
/// user is a member of, whether they created it or joined it by code
/// (`memberUids` doesn't distinguish the two). Room creation and joining
/// happen client-side in `RoomService` (Spark plan has no Cloud
/// Functions — see CLAUDE.md); this screen only ever reads.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  /// Rooms deleted with an undo window still open — hidden from the list
  /// now, only actually deleted once the undo snackbar closes.
  final Set<String> _pendingDeleteIds = {};

  @override
  Widget build(BuildContext context) {
    final user = AuthService().currentUser;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text('Your rooms', style: textTheme.headlineMedium),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  GestureDetector(
                    // Sign out has no visible affordance in the mockup —
                    // a long-press keeps it reachable for dev/testing
                    // without adding UI the design doesn't call for.
                    onLongPress: () => AuthService().signOut(),
                    child: AppAvatar(
                      initials: initialsFor(user?.displayName),
                      size: 40,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xl),
              if (user == null)
                Text('Sign in to see your rooms.', style: textTheme.bodyMedium)
              else
                StreamBuilder<List<RoomSummary>>(
                  // A fresh Stream instance every build (nothing here is
                  // cached), so a bare setState is enough on its own to
                  // make StreamBuilder detect the changed stream identity
                  // and resubscribe.
                  stream: RoomService().watchMyRooms(user.uid),
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "Couldn't load your rooms.",
                            style: textTheme.bodyMedium,
                          ),
                          TextButton(
                            onPressed: () => setState(() {}),
                            child: const Text('Try again'),
                          ),
                        ],
                      );
                    }
                    if (!snapshot.hasData) {
                      return const Padding(
                        padding: EdgeInsets.symmetric(vertical: AppSpacing.xl),
                        child: LoadingView(),
                      );
                    }
                    final rooms = snapshot.data!
                        .where((r) => !_pendingDeleteIds.contains(r.id))
                        .toList();
                    if (rooms.isEmpty) {
                      return Text(
                        'No rooms yet — start one below.',
                        style: textTheme.bodyMedium,
                      );
                    }
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final room in rooms) ...[
                          _RoomCard(
                            room: room,
                            // Lobby until the owner starts the round —
                            // then everyone, owner included, goes to the
                            // hub instead.
                            onTap: () => context.push(
                              room.isRoundStarted
                                  ? '${AppRoutes.rooms}/${room.id}/round'
                                  : '${AppRoutes.rooms}/${room.id}',
                            ),
                            onMore: () => _openRoomActions(room),
                          ),
                          const SizedBox(height: AppSpacing.md),
                        ],
                      ],
                    );
                  },
                ),
              const SizedBox(height: AppSpacing.sm),
              _DashedBorderButton(
                label: 'New room or join code',
                onTap: () => JoinRoomSheet.show(context),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openRoomActions(RoomSummary room) async {
    final action = await RoomActionsSheet.show(context, room);
    if (action == null || !mounted) return;

    switch (action) {
      case RoomAction.copyCode:
        await copyToClipboard(context, room.code, confirmation: 'Code copied');
      case RoomAction.leave:
        await _confirmLeave(room);
      case RoomAction.delete:
        if (room.isRoundStarted) {
          if (await DeleteRoomDialog.show(context, room)) {
            await _runRemoval(
              () => RoomService().deleteRoom(roomId: room.id, code: room.code),
            );
          }
        } else {
          _deleteWithUndo(room);
        }
    }
  }

  /// Never played, so nothing is lost — no dialog, just an undo window.
  /// The card hides immediately; the real delete only runs once the
  /// snackbar closes without "Undo" (timeout, swipe, or being replaced).
  /// If the app dies mid-window the room survives, which is the safe way
  /// round.
  void _deleteWithUndo(RoomSummary room) {
    setState(() => _pendingDeleteIds.add(room.id));
    final messenger = ScaffoldMessenger.of(context)..hideCurrentSnackBar();
    final controller = messenger.showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 5),
        content: _UndoDeleteContent(
          title: '${room.title} deleted',
          onUndo: () => messenger.hideCurrentSnackBar(
            reason: SnackBarClosedReason.action,
          ),
        ),
      ),
    );

    controller.closed.then((reason) async {
      if (reason != SnackBarClosedReason.action) {
        try {
          await RoomService().deleteRoom(roomId: room.id, code: room.code);
        } on RoomServiceException catch (e) {
          messenger.showSnackBar(SnackBar(content: Text(e.message)));
        }
      }
      if (mounted) setState(() => _pendingDeleteIds.remove(room.id));
    });
  }

  Future<void> _confirmLeave(RoomSummary room) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Leave this room?'),
        content: Text(
          "You'll need the invite code to rejoin \"${room.title}\".",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Leave'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _runRemoval(() => RoomService().leaveRoom(room.id));
    }
  }

  Future<void> _runRemoval(Future<void> Function() removal) async {
    try {
      await removal();
    } on RoomServiceException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }
}

class _UndoDeleteContent extends StatelessWidget {
  const _UndoDeleteContent({required this.title, required this.onUndo});

  final String title;
  final VoidCallback onUndo;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;

    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: accent,
                ),
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                'Nothing had been played',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppColors.cream.withValues(alpha: 0.75),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        OutlinedButton(
          onPressed: onUndo,
          style: OutlinedButton.styleFrom(
            foregroundColor: accent,
            side: BorderSide(color: accent, width: AppBorders.thick),
            shape: const StadiumBorder(),
            // The theme's outlined button is full-width; inside a
            // snackbar row it has to size to its label.
            minimumSize: const Size(
              AppSizes.minTouchTarget,
              AppSizes.minTouchTarget,
            ),
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          ),
          child: const Text('Undo'),
        ),
      ],
    );
  }
}

class _RoomCard extends StatelessWidget {
  const _RoomCard({
    required this.room,
    required this.onTap,
    required this.onMore,
  });

  final RoomSummary room;
  final VoidCallback onTap;

  /// Opens [RoomActionsSheet] — delete vs. leave is decided there, not by
  /// a different icon on the card.
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<AppTokens>()!;
    final isNeedsYou = room.status == RoomStatus.needsYou;
    final isPaused = room.status == RoomStatus.paused;

    // §4 "Shadow is a call to action": only the room that needs you gets
    // the shadow. §5: settled rooms flatten — a paused room recedes all
    // the way to the screen's own background; a waiting room stays a
    // step above it on cream.
    final background = switch (room.status) {
      RoomStatus.needsYou => AppColors.white,
      RoomStatus.waiting => AppColors.cream,
      RoomStatus.paused => theme.colorScheme.primary,
    };

    final titleColor = isPaused
        ? AppColors.ink.withValues(alpha: 0.55)
        : AppColors.ink;
    final subtitleColor = AppColors.ink.withValues(alpha: isPaused ? 0.5 : 0.6);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.cardRadius,
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.lg),
          decoration: BoxDecoration(
            color: background,
            borderRadius: AppRadius.cardRadius,
            border: Border.all(color: AppColors.ink, width: AppBorders.thick),
            boxShadow: isNeedsYou ? tokens.hardShadow : null,
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
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                room.title,
                                style: theme.textTheme.titleLarge?.copyWith(
                                  color: titleColor,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (room.isOwner) ...[
                              const SizedBox(width: AppSpacing.xs),
                              Icon(
                                Icons.star_rounded,
                                size: 18,
                                color: titleColor,
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          room.subtitle,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: subtitleColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  if (isPaused)
                    const Icon(Icons.pause_rounded, color: AppColors.ink)
                  else if (room.timeLabel != null)
                    isNeedsYou
                        ? AttentionChip(room.timeLabel!)
                        : NeutralChip(room.timeLabel!),
                  // Full 44px target, nudged into the card's corner padding
                  // so the dots line up with the title rather than sitting
                  // inset from it.
                  Transform.translate(
                    offset: const Offset(AppSpacing.sm, -AppSpacing.sm),
                    child: IconButton(
                      onPressed: onMore,
                      tooltip: 'Room options',
                      icon: Icon(Icons.more_horiz, color: titleColor),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: AppSizes.minTouchTarget,
                        minHeight: AppSizes.minTouchTarget,
                      ),
                    ),
                  ),
                ],
              ),
              if (!isPaused) ...[
                const SizedBox(height: AppSpacing.md),
                Row(
                  children: [
                    _AvatarStack(
                      members: room.members,
                      overflowCount: room.overflowCount,
                      ringColor: background,
                    ),
                    const Spacer(),
                    if (room.footer != null)
                      Text(
                        room.footer!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: AppColors.ink.withValues(alpha: 0.6),
                        ),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _AvatarStack extends StatelessWidget {
  const _AvatarStack({
    required this.members,
    required this.ringColor,
    this.overflowCount,
  });

  final List<String> members;
  final int? overflowCount;
  final Color ringColor;

  static const _avatarSize = 28.0;
  static const _overlap = 10.0;

  @override
  Widget build(BuildContext context) {
    final items = [...members, if (overflowCount != null) '+$overflowCount'];
    if (items.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      height: _avatarSize,
      width: _avatarSize + (items.length - 1) * (_avatarSize - _overlap),
      child: Stack(
        children: [
          for (var i = 0; i < items.length; i++)
            Positioned(
              left: i * (_avatarSize - _overlap),
              child: AppAvatar(
                initials: items[i],
                size: _avatarSize,
                ringColor: ringColor,
              ),
            ),
        ],
      ),
    );
  }
}

/// The "New room or join code" entry point — dashed border, no fill, so it
/// reads as an add-slot rather than a fourth room card.
class _DashedBorderButton extends StatelessWidget {
  const _DashedBorderButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.cardRadius,
        child: CustomPaint(
          painter: const _DashedRRectPainter(radius: AppRadius.card),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
            alignment: Alignment.center,
            child: Text(label, style: Theme.of(context).textTheme.labelLarge),
          ),
        ),
      ),
    );
  }
}

class _DashedRRectPainter extends CustomPainter {
  const _DashedRRectPainter({required this.radius});

  final double radius;

  static const _strokeWidth = AppBorders.thick;
  static const _dashWidth = 8.0;
  static const _gapWidth = 6.0;

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        _strokeWidth / 2,
        _strokeWidth / 2,
        size.width - _strokeWidth,
        size.height - _strokeWidth,
      ),
      Radius.circular(radius),
    );
    final paint = Paint()
      ..color = AppColors.ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = _strokeWidth;

    paintDashedPath(
      canvas,
      Path()..addRRect(rrect),
      paint,
      dashWidth: _dashWidth,
      gapWidth: _gapWidth,
    );
  }

  @override
  bool shouldRepaint(covariant _DashedRRectPainter oldDelegate) => false;
}
