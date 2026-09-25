import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../router/app_router.dart';
import '../../services/auth_service.dart';
import '../../theme/app_dimens.dart';
import '../../widgets/app_button.dart';
import '../../widgets/auth_error_banner.dart';
import '../../widgets/pixel_mark.dart';

/// Design.md §5 "Sign in": pixel-art mark, wordmark, Google primary /
/// email secondary. The only pixel art outside a canvas frame is the app
/// mark — a logo, not user artwork. Tagline carries the premise:
/// unhurried, low-stakes.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _authService = AuthService();
  String? _errorMessage;

  Future<void> _continueWithGoogle() async {
    setState(() => _errorMessage = null);
    try {
      await _authService.signInWithGoogle();
      // GoRouter's redirect (driven by authStateChanges) takes it from
      // here — no manual navigation needed on success.
    } on AuthException catch (e) {
      setState(() => _errorMessage = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: constraints.maxHeight - AppSpacing.lg * 2,
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 400),
                    // IntrinsicHeight gives the Column a concrete (tight)
                    // height to lay `Spacer` out against — without it,
                    // `Spacer`/`Expanded` throw inside the unbounded
                    // height a SingleChildScrollView otherwise provides.
                    child: IntrinsicHeight(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const SizedBox(height: AppSpacing.xl),
                          const Center(child: PixelMark(size: 96)),
                          const SizedBox(height: AppSpacing.lg),
                          Text(
                            'Pixel\nGuess',
                            textAlign: TextAlign.center,
                            style: textTheme.headlineMedium,
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          Text(
                            'Draw badly. Guess worse. Take all day.',
                            textAlign: TextAlign.center,
                            style: textTheme.bodyMedium,
                          ),
                          const Spacer(),
                          const SizedBox(height: AppSpacing.xl),
                          if (_errorMessage != null) ...[
                            AuthErrorBanner(message: _errorMessage!),
                            const SizedBox(height: AppSpacing.md),
                          ],
                          AppButton(
                            label: 'Continue with Google',
                            onPressed: _continueWithGoogle,
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          AppButton(
                            label: 'Sign up with email',
                            secondary: true,
                            onPressed: () async =>
                                context.push(AppRoutes.register),
                          ),
                          const SizedBox(height: AppSpacing.md),
                          Wrap(
                            alignment: WrapAlignment.center,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Text(
                                'Already have an account?',
                                style: textTheme.bodySmall,
                              ),
                              TextButton(
                                onPressed: () =>
                                    context.push(AppRoutes.emailLogin),
                                child: const Text('Log in'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
