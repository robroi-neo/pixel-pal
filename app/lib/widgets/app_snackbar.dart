import 'package:flutter/material.dart';

import '../theme/app_dimens.dart';

typedef AppSnackBarController =
    ScaffoldFeatureController<SnackBar, SnackBarClosedReason>;

/// The app's one way to show a snackbar. Looks come from `snackBarTheme` in
/// theme/app_theme.dart; this just keeps every call consistent — each one
/// replaces whatever snackbar is already up rather than queueing behind
/// it.
///
/// Shown on the app-wide [ScaffoldMessenger], so a snackbar survives the
/// screen that showed it closing (e.g. "Drawing submitted!" while the
/// editor pops). The `*On` variants take a messenger captured earlier, for
/// callers that show one after an `await` or after leaving the screen.
class AppSnackBar {
  AppSnackBar._();

  /// A plain message — errors, notices.
  static AppSnackBarController show(BuildContext context, String message) =>
      showOn(ScaffoldMessenger.of(context), message);

  /// A confirmation: accent check icon and text.
  static AppSnackBarController success(BuildContext context, String message) =>
      successOn(ScaffoldMessenger.of(context), message);

  static AppSnackBarController showOn(
    ScaffoldMessengerState messenger,
    String message,
  ) => contentOn(messenger, Text(message));

  static AppSnackBarController successOn(
    ScaffoldMessengerState messenger,
    String message,
  ) {
    final theme = Theme.of(messenger.context);
    final accent = theme.colorScheme.primary;
    return contentOn(
      messenger,
      Row(
        children: [
          Icon(Icons.check_rounded, color: accent),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              message,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: accent,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Anything else — e.g. the room list's delete-with-undo row.
  static AppSnackBarController contentOn(
    ScaffoldMessengerState messenger,
    Widget content, {
    Duration? duration,
  }) {
    messenger.hideCurrentSnackBar();
    return messenger.showSnackBar(
      SnackBar(
        content: content,
        duration: duration ?? const Duration(milliseconds: 4000),
      ),
    );
  }
}
