import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../models/room_detail.dart';
import '../../router/app_router.dart';
import '../../services/room_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_dimens.dart';
import '../../utils/clipboard.dart';
import '../../utils/dashed_path.dart';
import '../../widgets/app_avatar.dart';
import '../../widgets/app_button.dart';

/// The room's lobby — reached by tapping a room that hasn't started its
/// round yet (any member, not just the owner: everyone waits here until
/// the owner taps "Start round"), or by the owner from [RoundHomeScreen]'s
/// menu afterwards, to view/share the code. Design.md marks create/join
/// room as not designed (§5), so this follows the mockup directly rather
/// than an existing spec section.
///
/// Non-owners currently sitting here are bounced to [RoundHomeScreen] the
/// moment the owner starts the round (`roundEndsAt` going from null to
/// set) — the owner isn't, since they may have opened this screen
/// deliberately, mid-round, just to share the code with more players.
class RoomScreen extends StatefulWidget {
  const RoomScreen({super.key, required this.roomId});

  final String roomId;

  @override
  State<RoomScreen> createState() => _RoomScreenState();
}

class _RoomScreenState extends State<RoomScreen> {
  late final Stream<RoomDetail?> _room = RoomService().watchRoom(widget.roomId);
  bool _navigatedToHub = false;

  void _maybeNavigateToHub(RoomDetail? room) {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (_navigatedToHub ||
        room == null ||
        !room.isRoundStarted ||
        room.isOwnedBy(uid)) {
      return;
    }
    _navigatedToHub = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.pushReplacement('${AppRoutes.rooms}/${widget.roomId}/round');
    });
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return StreamBuilder<RoomDetail?>(
      stream: _room,
      builder: (context, snapshot) {
        final room = snapshot.data;
        _maybeNavigateToHub(room);
        final isOwner =
            room != null &&
            room.isOwnedBy(FirebaseAuth.instance.currentUser?.uid ?? '');

        return Scaffold(
          appBar: AppBar(
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_outlined),
              onPressed: () => context.pop(),
            ),
            title: Text(room?.name ?? '', style: textTheme.titleMedium),
            actions: [
              if (isOwner)
                PopupMenuButton<void>(
                  icon: const Icon(Icons.more_horiz),
                  itemBuilder: (_) => [
                    PopupMenuItem(
                      onTap: () => _confirmDelete(context, room),
                      child: const Text('Delete room'),
                    ),
                  ],
                ),
            ],
          ),
          body: SafeArea(
            child: Builder(
              builder: (context) {
                if (snapshot.hasError) {
                  return Center(
                    child: Text(
                      "Couldn't load this room.",
                      style: textTheme.bodyMedium,
                    ),
                  );
                }
                if (!snapshot.hasData) {
                  return const Center(
                    child: CircularProgressIndicator(color: AppColors.ink),
                  );
                }
                if (room == null) {
                  return Center(
                    child: Text(
                      'This room no longer exists.',
                      style: textTheme.bodyMedium,
                    ),
                  );
                }
                return _RoomBody(room: room, isOwner: isOwner);
              },
            ),
          ),
        );
      },
    );
  }

  Future<void> _confirmDelete(BuildContext context, RoomDetail room) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete this room?'),
        content: Text(
          '"${room.name}" will be removed for everyone in it. '
          "This can't be undone.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    try {
      await RoomService().deleteRoom(roomId: room.id, code: room.code);
      if (context.mounted) context.pop();
    } on RoomServiceException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }
}

class _RoomBody extends StatelessWidget {
  const _RoomBody({required this.room, required this.isOwner});

  final RoomDetail room;
  final bool isOwner;

  static const _slotCount = 4;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final emptySlots = (_slotCount - room.memberCount).clamp(0, _slotCount);
    final started = room.isRoundStarted;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            started
                ? 'Round 1 is underway'
                : room.memberCount == 1
                ? 'Just you so far'
                : '${room.memberCount} players so far',
            style: textTheme.headlineMedium,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            started
                ? 'Share the code below to bring in more players.'
                : isOwner
                ? "Start whenever you're ready — solo is fine too."
                : 'Waiting for ${room.ownerDisplayName} to start round 1.',
            style: textTheme.bodyMedium,
          ),
          const SizedBox(height: AppSpacing.lg),
          Row(
            children: [
              for (final initials in room.memberPreview) ...[
                AppAvatar(initials: initials, size: 40),
                const SizedBox(width: AppSpacing.sm),
              ],
              for (var i = 0; i < emptySlots; i++) ...[
                const _EmptySlot(size: 40),
                if (i < emptySlots - 1) const SizedBox(width: AppSpacing.sm),
              ],
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: AppColors.white,
              borderRadius: AppRadius.cardRadius,
              border: Border.all(color: AppColors.ink, width: AppBorders.thick),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Invite code',
                        style: textTheme.bodySmall?.copyWith(
                          color: AppColors.ink.withValues(alpha: 0.6),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        room.code.split('').join(' '),
                        style: textTheme.headlineMedium?.copyWith(fontSize: 22),
                      ),
                    ],
                  ),
                ),
                _CopyCodeButton(code: room.code),
              ],
            ),
          ),
          if (room.memberCount < _slotCount) ...[
            const SizedBox(height: AppSpacing.md),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppSpacing.lg),
              decoration: BoxDecoration(
                color: AppColors.cream,
                borderRadius: AppRadius.cardRadius,
                border: Border.all(
                  color: AppColors.ink,
                  width: AppBorders.thick,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Two players is enough', style: textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text(
                    'It plays fine with two, though scores swing hard. '
                    'Four or five is where it settles down.',
                    style: textTheme.bodySmall?.copyWith(
                      color: AppColors.ink.withValues(alpha: 0.7),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (!started) ...[
            const SizedBox(height: AppSpacing.md),
            if (isOwner)
              AppButton(
                label: 'Start round',
                onPressed: () async {
                  try {
                    await RoomService().startRound(
                      roomId: room.id,
                      roundLengthHours: room.roundLengthHours,
                    );
                    // Same landing spot every other member gets bounced to
                    // once the round starts — see RoomScreen's own
                    // auto-navigate, which skips the owner deliberately.
                    if (context.mounted) {
                      context.pushReplacement(
                        '${AppRoutes.rooms}/${room.id}/round',
                      );
                    }
                  } on RoomServiceException catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(
                        context,
                      ).showSnackBar(SnackBar(content: Text(e.message)));
                    }
                  }
                },
              )
            else
              Center(
                child: Text(
                  'Waiting for ${room.ownerDisplayName} to start the round…',
                  style: textTheme.bodySmall?.copyWith(
                    color: AppColors.ink.withValues(alpha: 0.6),
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _CopyCodeButton extends StatelessWidget {
  const _CopyCodeButton({required this.code});

  final String code;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: AppRadius.controlRadius,
        onTap: () =>
            copyToClipboard(context, code, confirmation: 'Code copied'),
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.sm),
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.ink, width: AppBorders.thin),
            borderRadius: AppRadius.controlRadius,
          ),
          child: const Icon(
            Icons.copy_outlined,
            size: 20,
            color: AppColors.ink,
          ),
        ),
      ),
    );
  }
}

/// An open member slot — a dashed circle, so it reads as "not filled yet"
/// rather than another real avatar.
class _EmptySlot extends StatelessWidget {
  const _EmptySlot({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: const CustomPaint(painter: _DashedCirclePainter()),
    );
  }
}

class _DashedCirclePainter extends CustomPainter {
  const _DashedCirclePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.ink.withValues(alpha: 0.4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = AppBorders.thin;
    final path = Path()
      ..addOval(Rect.fromLTWH(1, 1, size.width - 2, size.height - 2));
    paintDashedPath(canvas, path, paint, dashWidth: 4, gapWidth: 3);
  }

  @override
  bool shouldRepaint(covariant _DashedCirclePainter oldDelegate) => false;
}
