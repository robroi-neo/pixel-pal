import 'package:flutter/material.dart';

import '../models/user_profile.dart';
import '../services/profile_service.dart';
import '../theme/app_colors.dart';
import '../utils/initials.dart';
import 'app_avatar.dart';
import 'pixel_canvas.dart';

/// Rebuilds with a player's live `profiles/{uid}` doc — null until it
/// loads, or if that player has no profile doc yet.
class ProfileBuilder extends StatefulWidget {
  const ProfileBuilder({super.key, required this.uid, required this.builder});

  final String uid;
  final Widget Function(BuildContext context, UserProfile? profile) builder;

  @override
  State<ProfileBuilder> createState() => _ProfileBuilderState();
}

class _ProfileBuilderState extends State<ProfileBuilder> {
  late Stream<UserProfile?> _profile = ProfileService().watch(widget.uid);

  @override
  void didUpdateWidget(ProfileBuilder oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.uid != widget.uid) {
      _profile = ProfileService().watch(widget.uid);
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<UserProfile?>(
      stream: _profile,
      builder: (context, snapshot) => widget.builder(context, snapshot.data),
    );
  }
}

/// A player's avatar from their live profile: their drawn icon if they
/// have one, else their initials. [fallbackName]/[fallbackInitials] cover
/// the moment before the profile loads, or a player with no profile doc.
class ProfileAvatar extends StatelessWidget {
  const ProfileAvatar({
    super.key,
    required this.uid,
    this.fallbackName,
    this.fallbackInitials,
    this.size = 28,
    this.ringColor,
    this.inactive = false,
  });

  final String uid;
  final String? fallbackName;
  final String? fallbackInitials;
  final double size;
  final Color? ringColor;

  /// Design.md §3: grey when inactive — the drawn icon goes greyscale.
  final bool inactive;

  static const _greyscale = ColorFilter.matrix([
    0.2126, 0.7152, 0.0722, 0, 0, //
    0.2126, 0.7152, 0.0722, 0, 0, //
    0.2126, 0.7152, 0.0722, 0, 0, //
    0, 0, 0, 1, 0,
  ]);

  @override
  Widget build(BuildContext context) {
    return ProfileBuilder(
      uid: uid,
      builder: (context, profile) {
        final icon = profile?.icon;
        if (icon != null) {
          final avatar = PixelIconAvatar(
            pixels: icon,
            size: size,
            ringColor: ringColor,
          );
          return inactive
              ? ColorFiltered(colorFilter: _greyscale, child: avatar)
              : avatar;
        }
        return AppAvatar(
          initials: profile != null
              ? initialsFor(profile.displayName)
              : fallbackInitials ?? initialsFor(fallbackName),
          size: size,
          ringColor: ringColor,
          inactive: inactive,
        );
      },
    );
  }
}

/// A 16×16 pixel icon as a round avatar. The ink border does the job the
/// canvas frame does elsewhere (Design.md §4) — the art never touches the
/// yellow directly, and empty pixels sit on the locked `canvas` fill.
class PixelIconAvatar extends StatelessWidget {
  const PixelIconAvatar({
    super.key,
    required this.pixels,
    this.size = 28,
    this.ringColor,
  });

  final List<Color> pixels;
  final double size;
  final Color? ringColor;

  @override
  Widget build(BuildContext context) {
    final inkBorder = size >= 64 ? 3.0 : 2.0;
    final art = DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.canvas,
        border: Border.all(color: AppColors.ink, width: inkBorder),
      ),
      child: Padding(
        padding: EdgeInsets.all(inkBorder),
        child: ClipOval(
          child: PixelPreview(canvasSize: UserProfile.iconSize, pixels: pixels),
        ),
      ),
    );

    // Container already insets the child by the ring's border width.
    return Container(
      width: size,
      height: size,
      decoration: ringColor == null
          ? null
          : BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: ringColor!, width: 2),
            ),
      child: art,
    );
  }
}
