import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../models/room_detail.dart';
import '../../models/round_info.dart';
import '../../services/round_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_dimens.dart';
import '../../widgets/deadline_chip.dart';
import '../../widgets/reveal_chrome.dart';

/// A round changing over, made unmissable. Shown once per round when the
/// hub opens on a round the player hasn't seen start yet (see
/// `Membership.seenRound`), on near-black like the reveal: how the last
/// round ended — at its deadline, or early because everyone finished —
/// then the new round's number, big, and what's in it.
class RoundStartView extends StatefulWidget {
  const RoundStartView({
    super.key,
    required this.room,
    required this.round,
    required this.onStart,
  });

  final RoomDetail room;
  final int round;
  final VoidCallback onStart;

  @override
  State<RoundStartView> createState() => _RoundStartViewState();
}

class _RoundStartViewState extends State<RoundStartView>
    with SingleTickerProviderStateMixin {
  late final Stream<RoundInfo?> _previous = widget.round > 1
      ? RoundService().watchRound(widget.room.id, widget.round - 1)
      : Stream.value(null);

  // One timeline for the whole entrance: last round, then the number, then
  // the to-do list and the button.
  late final AnimationController _intro = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_intro.isAnimating || _intro.isCompleted) return;
    if (MediaQuery.of(context).disableAnimations) {
      _intro.value = 1;
    } else {
      _intro.forward();
    }
  }

  @override
  void dispose() {
    _intro.dispose();
    super.dispose();
  }

  Animation<double> _step(double begin, double end, [Curve? curve]) =>
      CurvedAnimation(
        parent: _intro,
        curve: Interval(begin, end, curve: curve ?? Curves.easeOutCubic),
      );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;
    final accent = theme.colorScheme.primary;
    final n = widget.round;
    final endsAt = widget.room.roundEndsAt;
    final results = widget.room.latestResultsRound;

    return Scaffold(
      backgroundColor: AppColors.ink,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: IconButton(
                  icon: Icon(Icons.arrow_back_outlined, color: accent),
                  onPressed: () => context.pop(),
                ),
              ),
              Expanded(
                child: Center(
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (n > 1) ...[
                          _Entrance(
                            animation: _step(0, 0.35),
                            child: StreamBuilder<RoundInfo?>(
                              stream: _previous,
                              builder: (context, snapshot) =>
                                  _RoundOver(round: n - 1, info: snapshot.data),
                            ),
                          ),
                          const SizedBox(height: AppSpacing.xl),
                        ],
                        _Entrance(
                          animation: _step(0.2, 0.7, Curves.easeOutBack),
                          grow: true,
                          child: Column(
                            children: [
                              Text(
                                'ROUND',
                                style: textTheme.titleMedium?.copyWith(
                                  color: accent.withValues(alpha: 0.8),
                                  letterSpacing: 6,
                                ),
                              ),
                              Text(
                                '$n',
                                style: textTheme.headlineMedium?.copyWith(
                                  fontSize: 132,
                                  height: 1,
                                  color: accent,
                                ),
                              ),
                              Text(
                                'starts now',
                                style: textTheme.titleLarge?.copyWith(
                                  color: AppColors.cream,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xl),
                        _Entrance(
                          animation: _step(0.55, 0.95),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const _Todo(
                                icon: Icons.brush_outlined,
                                text: 'Draw one of 3 new prompts',
                              ),
                              if (n > 1)
                                _Todo(
                                  icon: Icons.grid_view_rounded,
                                  text: "Guess round ${n - 1}'s drawings",
                                ),
                              if (results != null)
                                _Todo(
                                  icon: Icons.emoji_events_outlined,
                                  text: 'Round $results results are in',
                                ),
                              if (n == 1)
                                const _Todo(
                                  icon: Icons.hourglass_empty_rounded,
                                  text:
                                      'Nothing to guess yet — that starts '
                                      'in round 2',
                                ),
                              if (endsAt != null) ...[
                                const SizedBox(height: AppSpacing.md),
                                Text(
                                  'Everything locks ${lockTime(endsAt)}',
                                  textAlign: TextAlign.center,
                                  style: textTheme.bodySmall?.copyWith(
                                    color: accent.withValues(alpha: 0.75),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              _Entrance(
                animation: _step(0.7, 1),
                child: AccentButton(
                  label: 'Start round $n',
                  onPressed: widget.onStart,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Fades and lifts [child] in as [animation] runs; [grow] also scales it
/// up from 60%, overshooting slightly with an easeOutBack curve.
class _Entrance extends StatelessWidget {
  const _Entrance({
    required this.animation,
    required this.child,
    this.grow = false,
  });

  final Animation<double> animation;
  final Widget child;
  final bool grow;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      child: child,
      builder: (context, child) {
        final t = animation.value;
        Widget result = Transform.translate(
          offset: Offset(0, (1 - t) * 16),
          child: child,
        );
        if (grow) {
          result = Transform.scale(scale: 0.6 + 0.4 * t, child: result);
        }
        return Opacity(opacity: t.clamp(0.0, 1.0), child: result);
      },
    );
  }
}

/// How the last round ended.
class _RoundOver extends StatelessWidget {
  const _RoundOver({required this.round, required this.info});

  final int round;
  final RoundInfo? info;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;
    final accent = theme.colorScheme.primary;
    final i = info;
    final how = i == null
        ? ''
        : i.closedEarly
        ? 'Everyone finished early.'
        : i.deadline != null
        ? 'It locked at ${clockTime(i.deadline!)}.'
        : 'Its deadline passed.';

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        borderRadius: AppRadius.cardRadius,
        border: Border.all(
          color: accent.withValues(alpha: 0.4),
          width: AppBorders.thin,
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.flag_rounded, color: accent),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Round $round is over',
                  style: textTheme.titleMedium?.copyWith(color: accent),
                ),
                if (how.isNotEmpty)
                  Text(
                    how,
                    style: textTheme.bodySmall?.copyWith(
                      color: AppColors.cream.withValues(alpha: 0.75),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Todo extends StatelessWidget {
  const _Todo({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        children: [
          Icon(icon, size: AppSizes.icon, color: accent),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: AppColors.cream,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The round's deadline has passed and the room is moving on — a moment,
/// until someone's check-in opens the next round (Spark has no scheduler
/// to do it on the dot). The hub retries on its own; [onRetry] is the
/// manual nudge.
class RoundClosingView extends StatelessWidget {
  const RoundClosingView({
    super.key,
    required this.round,
    required this.onRetry,
  });

  final int round;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;
    final accent = theme.colorScheme.primary;

    return Scaffold(
      backgroundColor: AppColors.ink,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: IconButton(
                  icon: Icon(Icons.arrow_back_outlined, color: accent),
                  onPressed: () => context.pop(),
                ),
              ),
              const Spacer(),
              Text(
                'Round $round',
                textAlign: TextAlign.center,
                style: textTheme.headlineMedium?.copyWith(
                  fontSize: 44,
                  color: accent,
                ),
              ),
              Text(
                'is over',
                textAlign: TextAlign.center,
                style: textTheme.titleLarge?.copyWith(color: AppColors.cream),
              ),
              const SizedBox(height: AppSpacing.xl),
              Center(child: CircularProgressIndicator(color: accent)),
              const SizedBox(height: AppSpacing.md),
              Text(
                'Locking in the drawings and opening round ${round + 1}…',
                textAlign: TextAlign.center,
                style: textTheme.bodySmall?.copyWith(
                  color: AppColors.cream.withValues(alpha: 0.75),
                ),
              ),
              const Spacer(),
              Center(
                child: TextButton(
                  onPressed: onRetry,
                  style: TextButton.styleFrom(foregroundColor: accent),
                  child: const Text('Taking a while? Try again'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
