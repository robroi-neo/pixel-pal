import 'package:flutter/material.dart';

import '../theme/app_dimens.dart';
import '../theme/app_tokens.dart';

/// Inline error banner for auth screens. Message text comes from
/// [AuthException], which is already plain and actionable per style.md's
/// voice guidance — this widget just gives it the red/error surface
/// style.md reserves for real failures (not routine validation nagging).
class AuthErrorBanner extends StatelessWidget {
  const AuthErrorBanner({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: tokens.errorBg,
        borderRadius: AppRadius.controlRadius,
      ),
      child: Text(
        message,
        style: Theme.of(
          context,
        ).textTheme.bodyMedium?.copyWith(color: tokens.errorFg),
      ),
    );
  }
}
