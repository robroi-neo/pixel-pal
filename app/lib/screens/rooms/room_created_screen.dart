import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../router/app_router.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_dimens.dart';
import '../../utils/clipboard.dart';
import '../../widgets/app_button.dart';

class RoomCreatedArgs {
  const RoomCreatedArgs({
    required this.roomId,
    required this.roomName,
    required this.canvasLabel,
    required this.roundLabel,
    required this.inviteCode,
  });

  final String roomId;
  final String roomName;
  final String canvasLabel;
  final String roundLabel;
  final String inviteCode;
}

/// Shown right after "Create room". Design.md marks create/join room as
/// not designed (§5) — this follows the mockup directly.
///
/// Sharing is "Copy code" — there's no share-sheet package in the app.
class RoomCreatedScreen extends StatelessWidget {
  const RoomCreatedScreen({super.key, required this.args});

  final RoomCreatedArgs args;

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
                // IntrinsicHeight gives the Column a concrete height for
                // `Spacer` to lay out against inside an otherwise unbounded
                // SingleChildScrollView — see login_screen.dart for the
                // same pattern.
                child: IntrinsicHeight(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        '${args.roomName} is yours',
                        style: textTheme.headlineMedium,
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        '${args.canvasLabel} canvas · ${args.roundLabel} '
                        "rounds · you're the owner",
                        style: textTheme.bodyMedium,
                      ),
                      const SizedBox(height: AppSpacing.xl),
                      Container(
                        padding: const EdgeInsets.all(AppSpacing.lg),
                        decoration: BoxDecoration(
                          color: AppColors.white,
                          borderRadius: AppRadius.cardRadius,
                          border: Border.all(
                            color: AppColors.ink,
                            width: AppBorders.thick,
                          ),
                        ),
                        child: Column(
                          children: [
                            Text(
                              'Anyone with this code can join',
                              style: textTheme.bodySmall?.copyWith(
                                color: AppColors.ink.withValues(alpha: 0.6),
                              ),
                            ),
                            const SizedBox(height: AppSpacing.md),
                            _CodeDisplay(code: args.inviteCode),
                            const SizedBox(height: AppSpacing.md),
                            OutlinedButton.icon(
                              onPressed: () => copyToClipboard(
                                context,
                                args.inviteCode,
                                confirmation: 'Code copied',
                              ),
                              icon: const Icon(Icons.copy_outlined, size: 16),
                              label: const Text('Copy code'),
                              style: OutlinedButton.styleFrom(
                                shape: const StadiumBorder(),
                                side: const BorderSide(
                                  color: AppColors.ink,
                                  width: AppBorders.thick,
                                ),
                                foregroundColor: AppColors.ink,
                                minimumSize: Size.zero,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: AppSpacing.lg,
                                  vertical: AppSpacing.sm,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      Container(
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
                            Text(
                              'Round 1 is drawing only',
                              style: textTheme.titleMedium,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Everyone draws first. Guessing starts in '
                              'round 2, when round 1 ends — or sooner, '
                              'once everyone has drawn.',
                              style: textTheme.bodySmall?.copyWith(
                                color: AppColors.ink.withValues(alpha: 0.7),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Spacer(),
                      const SizedBox(height: AppSpacing.xl),
                      AppButton(
                        label: 'Go to the room',
                        onPressed: () async => context.pushReplacement(
                          '${AppRoutes.rooms}/${args.roomId}',
                        ),
                      ),
                    ],
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

class _CodeDisplay extends StatelessWidget {
  const _CodeDisplay({required this.code});

  final String code;

  @override
  Widget build(BuildContext context) {
    final chars = code.split('');
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < chars.length; i++) ...[
          if (i > 0) const SizedBox(width: AppSpacing.xs),
          Container(
            width: 40,
            height: 48,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.white,
              borderRadius: AppRadius.controlRadius,
              border: Border.all(color: AppColors.ink, width: AppBorders.thick),
            ),
            child: Text(
              chars[i],
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
        ],
      ],
    );
  }
}
