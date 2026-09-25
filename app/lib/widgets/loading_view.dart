import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_dimens.dart';

/// A centered spinner for a screen's `body:` while its data loads —
/// every stream/future-backed screen in the app (room list, room lobby,
/// round hub, prompt pick, guess, drawing editor) was duplicating its own
/// `Center(child: CircularProgressIndicator(color: AppColors.ink))`.
///
/// [message], if given, sits below the spinner — cheap, well-understood
/// cover for a load with real, unavoidable latency (e.g. prompt pick's
/// first-time fetch, which is a few sequential Firestore round trips even
/// after PromptService's pool cache) rather than a bare, silent spinner.
class LoadingView extends StatelessWidget {
  const LoadingView({super.key, this.message});

  final String? message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(color: AppColors.ink),
          if (message != null) ...[
            const SizedBox(height: AppSpacing.md),
            Text(
              message!,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppColors.ink.withValues(alpha: 0.6),
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }
}
