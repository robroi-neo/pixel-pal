import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../models/prompt.dart';
import '../../router/app_router.dart';
import '../../services/prompt_service.dart';
import '../../services/room_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_dimens.dart';
import '../../theme/app_tokens.dart';
import '../../widgets/app_button.dart';

/// Design.md §5 "Prompt pick": three cards, selection state, no-reroll
/// stated on screen.
///
/// Real word/difficulty/multiplier data (seeded — see
/// firebase/scripts/seed-prompts.js). The 3 offered are also real and
/// stable now: the first visit persists them to this member's
/// `rooms/{roomId}/members/{uid}.issuedPromptIds`, and firestore.rules
/// refuses to ever change that field once set — so leaving and coming
/// back shows the same 3, and "no swapping once you start" is an actual
/// guarantee, not just copy. What's still not real: per-round scoping
/// (Implementations.md Phase 3 doesn't exist, so there's one persistent
/// set per member rather than one per round). "Start drawing" opens
/// [DrawingScreen] with the picked prompt.
class PromptPickScreen extends StatefulWidget {
  const PromptPickScreen({super.key, required this.roomId});

  final String roomId;

  @override
  State<PromptPickScreen> createState() => _PromptPickScreenState();
}

class _PromptPickScreenState extends State<PromptPickScreen> {
  final _roomService = RoomService();
  final _promptService = PromptService();
  late final Future<List<Prompt>> _prompts = _loadPrompts();
  String? _selectedId;

  Future<List<Prompt>> _loadPrompts() async {
    final uid = FirebaseAuth.instance.currentUser!.uid;

    final issuedIds = await _roomService.getIssuedPromptIds(
      widget.roomId,
      uid,
    );
    if (issuedIds != null && issuedIds.isNotEmpty) {
      return _promptService.getByIds(issuedIds);
    }

    final picked = await _promptService.pickRandom();
    await _roomService.setIssuedPromptIds(
      widget.roomId,
      uid,
      picked.map((p) => p.id).toList(),
    );
    // setIssuedPromptIds silently no-ops if something else already set
    // it first (a race) — re-read so a beaten write can't show prompts
    // that don't match what's actually persisted.
    final confirmedIds = await _roomService.getIssuedPromptIds(
      widget.roomId,
      uid,
    );
    return confirmedIds == null
        ? picked
        : _promptService.getByIds(confirmedIds);
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_outlined),
          onPressed: () => context.pop(),
        ),
        title: Text('Round 1', style: textTheme.titleMedium),
      ),
      body: SafeArea(
        child: FutureBuilder<List<Prompt>>(
          future: _prompts,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Center(
                child: Text(
                  "Couldn't load prompts.",
                  style: textTheme.bodyMedium,
                ),
              );
            }
            if (!snapshot.hasData) {
              return const Center(
                child: CircularProgressIndicator(color: AppColors.ink),
              );
            }
            final prompts = snapshot.data!;
            if (prompts.isEmpty) {
              return Center(
                child: Text(
                  'No prompts yet — seed some first.',
                  style: textTheme.bodyMedium,
                ),
              );
            }
            return SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Pick one to draw', style: textTheme.headlineMedium),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    'Harder words score more for everyone who solves them '
                    '— and for you, if enough people do.',
                    style: textTheme.bodyMedium,
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  for (final prompt in prompts) ...[
                    _PromptCard(
                      prompt: prompt,
                      selected: _selectedId == prompt.id,
                      onTap: () => setState(() => _selectedId = prompt.id),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                  ],
                  const SizedBox(height: AppSpacing.md),
                  AppButton(
                    label: 'Start drawing',
                    enabled: _selectedId != null,
                    onPressed: () async {
                      final selected = prompts.firstWhere(
                        (p) => p.id == _selectedId,
                      );
                      final submitted = await context.push<bool>(
                        '${AppRoutes.rooms}/${widget.roomId}/draw',
                        extra: selected,
                      );
                      // Replace (not push) so Back from guessing returns
                      // to the hub rather than to this prompt list.
                      if (submitted == true && context.mounted) {
                        context.pushReplacement(
                          '${AppRoutes.rooms}/${widget.roomId}/guess',
                        );
                      }
                    },
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Center(
                    child: Text(
                      'No swapping once you start',
                      style: textTheme.bodySmall?.copyWith(
                        color: AppColors.ink.withValues(alpha: 0.6),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _PromptCard extends StatelessWidget {
  const _PromptCard({
    required this.prompt,
    required this.selected,
    required this.onTap,
  });

  final Prompt prompt;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<AppTokens>()!;
    final accent = theme.colorScheme.onSecondary;
    final textColor = selected ? accent : AppColors.ink;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.cardRadius,
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: selected ? AppColors.ink : AppColors.white,
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
                      prompt.word,
                      style: theme.textTheme.titleLarge?.copyWith(
                        color: textColor,
                      ),
                    ),
                    Text(
                      prompt.difficulty.label,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: selected
                            ? accent.withValues(alpha: 0.85)
                            : AppColors.ink.withValues(alpha: 0.6),
                      ),
                    ),
                  ],
                ),
              ),
              // Design.md §2/§4: multipliers are the one non-score place
              // Silkscreen is allowed — nowhere else on this screen.
              Text(
                '×${prompt.multiplier.toStringAsFixed(1)}',
                style: tokens.scoreNumeral.copyWith(color: textColor),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
