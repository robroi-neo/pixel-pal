import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_dimens.dart';

/// The app's one bottom-sheet shell: full width, attached to the bottom,
/// cream surface, 3px ink border, 20px top corners, drag handle. Content
/// inside sits on white cards, same as a screen's cards sit on cream
/// bands. Every sheet uses this so they read as one family.
class AppSheet extends StatelessWidget {
  const AppSheet({super.key, required this.child});

  final Widget child;

  static Future<T?> show<T>(
    BuildContext context, {
    required WidgetBuilder builder,
  }) {
    return showModalBottomSheet<T>(
      context: context,
      // Lets a sheet with a text field grow above the keyboard rather than
      // being capped at half the screen.
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: builder,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.cream,
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
              AppSpacing.md,
              AppSpacing.lg,
              AppSpacing.md,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 48,
                    height: 5,
                    decoration: BoxDecoration(
                      color: AppColors.ink.withValues(alpha: 0.2),
                      borderRadius: AppRadius.chipRadius,
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                child,
              ],
            ),
          ),
        ),
      ),
    );
  }
}
