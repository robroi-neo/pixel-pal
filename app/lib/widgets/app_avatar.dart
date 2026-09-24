import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Design.md §3 "Avatar": 22–31px circle, ink fill, yellow initials. Grey
/// fill when inactive or on vacation.
class AppAvatar extends StatelessWidget {
  const AppAvatar({
    super.key,
    required this.initials,
    this.size = 28,
    this.inactive = false,
    this.ringColor,
  });

  final String initials;
  final double size;

  /// Inactive / on-vacation members get a grey fill instead of ink.
  final bool inactive;

  /// A thin ring in the surrounding card's background color, so
  /// overlapping avatars in a stack read as separate circles rather than
  /// merging into one shape.
  final Color? ringColor;

  @override
  Widget build(BuildContext context) {
    final onInk = Theme.of(context).colorScheme.onSecondary;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: inactive ? AppColors.grey : AppColors.ink,
        border: ringColor == null
            ? null
            : Border.all(color: ringColor!, width: 2),
      ),
      alignment: Alignment.center,
      child: Text(
        initials,
        style: TextStyle(
          color: inactive ? AppColors.white : onInk,
          fontSize: size * 0.36,
          fontWeight: FontWeight.w700,
        ),
        maxLines: 1,
        overflow: TextOverflow.clip,
      ),
    );
  }
}
