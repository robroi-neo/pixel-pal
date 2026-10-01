import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../models/room_detail.dart';
import '../../router/app_router.dart';
import '../../services/room_service.dart';
import '../../services/round_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_dimens.dart';
import '../../utils/clipboard.dart';
import '../../utils/dashed_path.dart';
import '../../widgets/app_avatar.dart';
import '../../widgets/app_button.dart';
import '../../widgets/loading_view.dart';
import '../../widgets/profile_avatar.dart';
import '../../widgets/app_snackbar.dart';

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
  bool _startingRound = false;

  Future<void> _startRound(BuildContext context, RoomDetail room) async {
    setState(() => _startingRound = true);
    try {
      await RoundService().startFirstRound(
        roomId: room.id,
        roundLengthHours: room.roundLengthHours,
      );
      // Same landing spot every other member gets bounced to once the
      // round starts — see _maybeNavigateToHub, which skips the owner.
      if (context.mounted) {
        context.pushReplacement('${AppRoutes.rooms}/${room.id}/round');
      }
    } on RoundServiceException catch (e) {
      if (mounted) setState(() => _startingRound = false);
      if (context.mounted) {
        AppSnackBar.show(context, e.message);
      }
    }
  }

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
            // Deleting a room lives on the room list's ⋯ menu only, behind
            // the dialog that names what everyone loses.
            title: Text(room?.name ?? '', style: textTheme.titleMedium),
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
                  return const LoadingView();
                }
                if (room == null) {
                  return Center(
                    child: Text(
                      'This room no longer exists.',
                      style: textTheme.bodyMedium,
                    ),
                  );
                }
                // A full-screen takeover, not just the button's own
                // spinner — the transition covers a real write, and this
                // makes the wait unmistakable rather than leaving the
                // rest of the lobby looking idle.
                if (_startingRound) {
                  return const LoadingView(message: 'Starting the round…');
                }
                return _RoomBody(
                  room: room,
                  isOwner: isOwner,
                  onStartRound: () => _startRound(context, room),
                );
              },
            ),
          ),
        );
      },
    );
  }
}

class _RoomBody extends StatelessWidget {
  const _RoomBody({
    required this.room,
    required this.isOwner,
    required this.onStartRound,
  });

  final RoomDetail room;
  final bool isOwner;
  final VoidCallback onStartRound;

  static const _slotCount = 4;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final emptySlots = (_slotCount - room.memberCount).clamp(0, _slotCount);
    final shownUids = room.memberUids.take(_slotCount).toList();
    // Rooms hold 8: anyone past the first 4 shows as "+N", same as the
    // avatar stack on the room list.
    final overflow = room.memberCount - shownUids.length;
    final started = room.isRoundStarted;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            started
                ? 'Round ${room.currentRound ?? 1} is underway'
                : room.memberCount == 1
                ? 'Just you so far'
                : '${room.memberCount} players so far',
            style: textTheme.headlineMedium,
          ),
          const SizedBox(height: AppSpacing.xs),
          ProfileBuilder(
            uid: room.ownerUid,
            builder: (context, owner) => Text(
              started
                  ? 'Share the code below to bring in more players.'
                  : isOwner
                  ? "Start whenever you're ready."
                  : 'Waiting for ${owner?.displayName ?? room.ownerDisplayName} '
                        'to start round 1.',
              style: textTheme.bodyMedium,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Row(
            children: [
              for (var i = 0; i < shownUids.length; i++) ...[
                ProfileAvatar(
                  uid: shownUids[i],
                  // Same join order as memberUids — only used until that
                  // player has a profile doc.
                  fallbackInitials: i < room.memberPreview.length
                      ? room.memberPreview[i]
                      : '?',
                  size: 40,
                ),
                const SizedBox(width: AppSpacing.sm),
              ],
              if (overflow > 0) AppAvatar(initials: '+$overflow', size: 40),
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
            if (isOwner) ...[
              AppButton(
                label: 'Start round 1',
                onPressed: () async => onStartRound(),
              ),
              const SizedBox(height: AppSpacing.sm),
              // The only round anyone starts by hand.
              Text(
                'You only do this once. After that, a new round starts on '
                'its own every ${room.roundLengthHours}h — or sooner, once '
                "everyone's drawn and guessed.",
                style: textTheme.bodySmall?.copyWith(
                  color: AppColors.ink.withValues(alpha: 0.6),
                ),
                textAlign: TextAlign.center,
              ),
            ] else
              Center(
                child: ProfileBuilder(
                  uid: room.ownerUid,
                  builder: (context, owner) => Text(
                    'Waiting for ${owner?.displayName ?? room.ownerDisplayName} '
                    'to start the round…',
                    style: textTheme.bodySmall?.copyWith(
                      color: AppColors.ink.withValues(alpha: 0.6),
                    ),
                    textAlign: TextAlign.center,
                  ),
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
