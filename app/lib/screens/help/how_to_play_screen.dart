import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../models/guess_progress.dart';
import '../../models/round_score.dart';
import '../../router/app_router.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_dimens.dart';
import '../../theme/app_tokens.dart';
import '../../widgets/app_button.dart';

/// "How to play", from the round hub's ⋯ menu: four short pages — the
/// daily rhythm, guessing, the reveal, scoring — each with a small
/// illustration built from the app's own components, then "Got it". The
/// last page links to [FullMathsScreen] for every number.
class HowToPlayScreen extends StatefulWidget {
  const HowToPlayScreen({super.key, required this.roundLengthHours});

  /// The room's round length, so the explainer quotes its own rhythm.
  final int roundLengthHours;

  @override
  State<HowToPlayScreen> createState() => _HowToPlayScreenState();
}

class _HowToPlayScreenState extends State<HowToPlayScreen> {
  final _pager = PageController();
  int _page = 0;

  static const _pageCount = 4;

  @override
  void dispose() {
    _pager.dispose();
    super.dispose();
  }

  void _next() {
    if (_page == _pageCount - 1) {
      context.pop();
      return;
    }
    if (MediaQuery.of(context).disableAnimations) {
      _pager.jumpToPage(_page + 1);
    } else {
      _pager.nextPage(
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final h = widget.roundLengthHours;

    final pages = [
      _HelpPage(
        illustration: _Panel(
          children: [
            const _JobCard(
              label: "TODAY'S ROUND",
              title: 'Draw one prompt',
              icon: Icons.edit_outlined,
            ),
            const SizedBox(height: AppSpacing.md),
            const _JobCard(
              label: "YESTERDAY'S ROUND",
              title: "Guess everyone else's",
              icon: Icons.search_rounded,
            ),
            const SizedBox(height: AppSpacing.md),
            _DeadlineCard(hours: h),
          ],
        ),
        title: 'Two small jobs a day',
        body:
            'Everyone draws every round, and guesses the drawings from the '
            "round before. Do it whenever you're free. When the deadline "
            'passes, everything locks and the results land.',
        note: "Round 1 is drawing only, since there's nothing to guess yet.",
      ),
      const _HelpPage(
        illustration: _Panel(children: [_GuessIllustration()]),
        title: 'One card at a time',
        body:
            'Each drawing comes with its category and how many letters the '
            'word has. You get five tries, and every miss flips in one more '
            "letter. Who drew it stays hidden until you're done with it.",
        note:
            'Every guess saves as you send it, so you can stop and come '
            'back any time before the deadline.',
      ),
      _HelpPage(
        illustration: const _Panel(children: [_RevealIllustration()]),
        title: 'Then the reveal',
        body:
            "When the round ends, everyone's results open together: who "
            'solved each drawing and on which try, your round score, and the '
            'table. Give a star to the drawings you loved.',
        note:
            'If everyone finishes early, the round ends early and the next '
            'one starts straight away, with a full ${h}h of its own.',
      ),
      _HelpPage(
        illustration: const _Panel(children: [_PointsRow()]),
        title: 'Scoring, in short',
        body:
            'Solve a drawing sooner, score more — times its difficulty. Draw '
            'something your friends can solve, and you score too. Your place '
            'on the table is your average round score.',
        note: 'Stars are just for fun. They never touch the score.',
        link: TextButton(
          onPressed: () => context.push(AppRoutes.howToPlayMaths),
          child: const Text('See the full maths'),
        ),
      ),
    ];

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Close',
          icon: const Icon(Icons.close_rounded),
          onPressed: () => context.pop(),
        ),
        centerTitle: true,
        title: Text('How to play', style: textTheme.titleMedium),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: AppSpacing.lg),
            child: Center(
              child: Text(
                '${_page + 1} of $_pageCount',
                style: textTheme.bodyMedium,
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: PageView(
                controller: _pager,
                onPageChanged: (page) => setState(() => _page = page),
                children: pages,
              ),
            ),
            _Dots(count: _pageCount, current: _page),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: AppButton(
                label: _page == _pageCount - 1 ? 'Got it' : 'Next',
                onPressed: () async => _next(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HelpPage extends StatelessWidget {
  const _HelpPage({
    required this.illustration,
    required this.title,
    required this.body,
    required this.note,
    this.link,
  });

  final Widget illustration;
  final String title;
  final String body;
  final String note;
  final Widget? link;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          illustration,
          const SizedBox(height: AppSpacing.xl),
          Text(title, style: textTheme.headlineMedium),
          const SizedBox(height: AppSpacing.sm),
          Text(body, style: textTheme.bodyMedium?.copyWith(fontSize: 16)),
          const SizedBox(height: AppSpacing.md),
          Text(
            note,
            style: textTheme.bodyMedium?.copyWith(
              color: AppColors.ink.withValues(alpha: 0.7),
            ),
          ),
          if (link != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Align(alignment: Alignment.centerLeft, child: link),
          ],
        ],
      ),
    );
  }
}

/// The cream band each illustration sits in.
class _Panel extends StatelessWidget {
  const _Panel({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.cream,
        borderRadius: AppRadius.cardRadius,
        border: Border.all(color: AppColors.ink, width: AppBorders.thick),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }
}

class _JobCard extends StatelessWidget {
  const _JobCard({
    required this.label,
    required this.title,
    required this.icon,
  });

  final String label;
  final String title;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      decoration: BoxDecoration(
        color: AppColors.white,
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
                  label,
                  style: textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1,
                    color: AppColors.ink.withValues(alpha: 0.7),
                  ),
                ),
                Text(title, style: textTheme.titleLarge),
              ],
            ),
          ),
          Icon(icon, size: 26, color: AppColors.ink),
        ],
      ),
    );
  }
}

class _DeadlineCard extends StatelessWidget {
  const _DeadlineCard({required this.hours});

  final int hours;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.onSecondary;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      decoration: BoxDecoration(
        color: AppColors.ink,
        borderRadius: AppRadius.cardRadius,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Deadline, then the reveal',
              style: theme.textTheme.titleLarge?.copyWith(color: accent),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: 3,
            ),
            decoration: BoxDecoration(
              borderRadius: AppRadius.chipRadius,
              border: Border.all(color: accent, width: AppBorders.thin),
            ),
            child: Text(
              '${hours}h',
              style: theme.chipTheme.labelStyle?.copyWith(color: accent),
            ),
          ),
        ],
      ),
    );
  }
}

/// A guess card in miniature: two letters shown after two misses, and the
/// attempt dots.
class _GuessIllustration extends StatelessWidget {
  const _GuessIllustration();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const letters = ['R', '', '', '', 'T'];
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: AppRadius.cardRadius,
        border: Border.all(color: AppColors.ink, width: AppBorders.thick),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: 3,
                ),
                decoration: BoxDecoration(
                  borderRadius: AppRadius.chipRadius,
                  border: Border.all(
                    color: AppColors.ink,
                    width: AppBorders.thin,
                  ),
                ),
                child: Text(
                  'things · 5 letters',
                  style: theme.chipTheme.labelStyle,
                ),
              ),
              const Spacer(),
              for (var i = 0; i < GuessProgress.maxAttempts; i++) ...[
                if (i > 0) const SizedBox(width: 4),
                Container(
                  width: 11,
                  height: 11,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: i < 2 ? AppColors.ink : Colors.transparent,
                    border: Border.all(
                      color: AppColors.ink,
                      width: AppBorders.thin,
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < letters.length; i++) ...[
                if (i > 0) const SizedBox(width: AppSpacing.xs),
                Container(
                  width: AppSizes.letterTileWidth,
                  height: AppSizes.letterTileHeight,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.white,
                    borderRadius: AppRadius.tileRadius,
                    border: Border.all(
                      color: AppColors.ink,
                      width: AppBorders.thick,
                    ),
                  ),
                  child: Text(
                    letters[i],
                    style: theme.textTheme.titleLarge?.copyWith(fontSize: 19),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// A slice of the reveal, on its near-black chrome.
class _RevealIllustration extends StatelessWidget {
  const _RevealIllustration();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.onSecondary;

    Widget row(String who, String result, {bool solved = true}) {
      return Padding(
        padding: const EdgeInsets.only(top: AppSpacing.xs),
        child: Row(
          children: [
            Expanded(
              child: Text(
                who,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: AppColors.cream,
                ),
              ),
            ),
            Text(
              result,
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: solved ? accent : accent.withValues(alpha: 0.55),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.ink,
        borderRadius: AppRadius.cardRadius,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'The word was',
            style: theme.textTheme.bodySmall?.copyWith(
              color: accent.withValues(alpha: 0.8),
            ),
          ),
          Text(
            'robot',
            style: theme.textTheme.headlineMedium?.copyWith(color: accent),
          ),
          const SizedBox(height: AppSpacing.xs),
          row('You', '2nd try'),
          row('Maya', '1st try'),
          row('Jonas', 'no solve', solved: false),
        ],
      ),
    );
  }
}

/// Points by the attempt you solved it on: 100 / 80 / 60 / 40 / 20, and 0
/// for a miss — straight from [RoundScore.attemptPoints].
class _PointsRow extends StatelessWidget {
  const _PointsRow();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<AppTokens>()!;
    final accent = theme.colorScheme.onSecondary;
    const labels = ['1st', '2nd', '3rd', '4th', '5th', 'miss'];
    final points = [...RoundScore.attemptPoints, 0];

    return Row(
      children: [
        for (var i = 0; i < points.length; i++) ...[
          if (i > 0) const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Column(
              children: [
                Text(
                  labels[i],
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Container(
                  height: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: i < 5 ? AppColors.ink : AppColors.white,
                    borderRadius: AppRadius.controlRadius,
                    border: Border.all(
                      color: AppColors.ink,
                      width: AppBorders.thin,
                    ),
                  ),
                  child: Text(
                    '${points[i]}',
                    style: tokens.scoreNumeral.copyWith(
                      fontSize: 12,
                      color: i < 5 ? accent : AppColors.ink,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// The page dots: a pill for the current page, rings for the rest.
class _Dots extends StatelessWidget {
  const _Dots({required this.count, required this.current});

  final int count;
  final int current;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < count; i++) ...[
          if (i > 0) const SizedBox(width: AppSpacing.md),
          AnimatedContainer(
            duration: AppMotion.duration,
            width: i == current ? 32 : 14,
            height: 14,
            decoration: BoxDecoration(
              color: i == current ? AppColors.ink : Colors.transparent,
              borderRadius: AppRadius.chipRadius,
              border: Border.all(color: AppColors.ink, width: AppBorders.thin),
            ),
          ),
        ],
      ],
    );
  }
}

/// "The full maths": every scoring rule, and a worked round computed with
/// the app's own [RoundScore] — so the example can't drift from the game.
class FullMathsScreen extends StatelessWidget {
  const FullMathsScreen({super.key});

  // Fixed per difficulty in the prompt pool (seed-prompts.js).
  static const _difficulties = [('Easy', 1.0), ('Medium', 1.4), ('Hard', 1.8)];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;
    final tokens = theme.extension<AppTokens>()!;
    final body = textTheme.bodyMedium?.copyWith(fontSize: 15);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_outlined),
          onPressed: () => context.pop(),
        ),
        title: Text('How to play', style: textTheme.titleMedium),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            Text('The full maths', style: textTheme.headlineMedium),
            const SizedBox(height: AppSpacing.lg),
            _MathsCard(
              title: 'Guessing',
              children: [
                Text(
                  'Points per drawing, by the attempt you solved it on.',
                  style: textTheme.bodySmall?.copyWith(
                    color: AppColors.ink.withValues(alpha: 0.7),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                const _PointsRow(),
                const SizedBox(height: AppSpacing.md),
                Text.rich(
                  TextSpan(
                    style: body,
                    children: const [
                      TextSpan(
                        text:
                            "Each one is multiplied by that drawing's "
                            'difficulty. Your guessing half is the ',
                      ),
                      TextSpan(
                        text: 'average',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      TextSpan(
                        text:
                            ' across every drawing you could guess — misses '
                            'and skips count as 0 — so small and big rooms '
                            'compare fairly.',
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            _MathsCard(
              title: 'Difficulty',
              children: [
                Row(
                  children: [
                    for (var i = 0; i < _difficulties.length; i++) ...[
                      if (i > 0) const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            vertical: AppSpacing.md,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.cream,
                            borderRadius: AppRadius.controlRadius,
                            border: Border.all(
                              color: AppColors.ink,
                              width: AppBorders.thick,
                            ),
                          ),
                          child: Column(
                            children: [
                              Text(
                                _difficulties[i].$1,
                                style: textTheme.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              Text(
                                'x${_difficulties[i].$2.toStringAsFixed(1)}',
                                style: tokens.scoreNumeral.copyWith(
                                  fontSize: 16,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            _MathsCard(
              title: 'Drawing',
              children: [
                Text(
                  "The share of friends who solved yours, times 100, times "
                  "your prompt's difficulty. Everyone solves an easy one: "
                  '100. Most people solve a hard one: more than that.',
                  style: body,
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            const _ExampleRound(),
            const SizedBox(height: AppSpacing.md),
            _MathsCard(
              title: 'Leaderboard',
              settled: true,
              children: [
                Text(
                  'Ranked by your average round score, not your total.',
                  style: body,
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'A round counts if you were in the room for it, even if '
                  'you skipped it — a skipped round scores 0.',
                  style: body,
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'Stars are counted separately and never touch the score.',
                  style: body,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MathsCard extends StatelessWidget {
  const _MathsCard({
    required this.title,
    required this.children,
    this.settled = false,
  });

  final String title;
  final List<Widget> children;

  /// Cream rather than white.
  final bool settled;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: settled ? AppColors.cream : AppColors.white,
        borderRadius: AppRadius.cardRadius,
        border: Border.all(color: AppColors.ink, width: AppBorders.thick),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: AppSpacing.sm),
          ...children,
        ],
      ),
    );
  }
}

/// Five players, so four drawings to guess, plus your own hard drawing
/// that three of the four solved.
class _ExampleRound extends StatelessWidget {
  const _ExampleRound();

  static GuessProgress _solvedOn(int attempt) =>
      GuessProgress(attempts: attempt, solved: true, revealedCount: 0);

  static const _missed = GuessProgress(
    attempts: GuessProgress.maxAttempts,
    solved: false,
    revealedCount: 0,
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;
    final tokens = theme.extension<AppTokens>()!;
    final accent = theme.colorScheme.onSecondary;
    final numeral = tokens.scoreNumeral.copyWith(fontSize: 13, color: accent);
    final label = textTheme.bodyMedium?.copyWith(color: accent);

    // (what happened, the guess, multiplier)
    final guesses = [
      ('medium, 1st try', _solvedOn(1), 1.4),
      ('hard, 3rd try', _solvedOn(3), 1.8),
      ('easy, 2nd try', _solvedOn(2), 1.0),
      ('medium, missed', _missed, 1.4),
    ];
    final points = [
      for (final g in guesses) RoundScore.guessPoints(g.$2, g.$3),
    ];
    final guessing = RoundScore.guessingHalf(points);
    final drawing = RoundScore.drawingHalf(
      solvers: 3,
      eligible: 4,
      multiplier: 1.8,
    );

    String working(int i) {
      final g = guesses[i];
      if (!g.$2.solved) return '0';
      final base = RoundScore.attemptPoints[g.$2.attempts - 1];
      return '$base x${g.$3.toStringAsFixed(1)} = ${points[i]}';
    }

    Widget line(String text, String value, {TextStyle? style}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(child: Text(text, style: style ?? label)),
          Text(value, style: numeral),
        ],
      ),
    );

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.ink,
        borderRadius: AppRadius.cardRadius,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Example round',
            style: textTheme.titleLarge?.copyWith(color: accent),
          ),
          Text(
            '5 players, so you guess 4 drawings',
            style: textTheme.bodySmall?.copyWith(
              color: AppColors.cream.withValues(alpha: 0.8),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          for (var i = 0; i < guesses.length; i++)
            line(guesses[i].$1, working(i)),
          Divider(color: accent.withValues(alpha: 0.3)),
          line(
            'guessing, average of ${guesses.length}',
            '$guessing',
            style: label?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text('your hard drawing, 3 of 4 solved', style: label),
          Align(
            alignment: Alignment.centerRight,
            child: Text('0.75 x100 x1.8 = $drawing', style: numeral),
          ),
          Divider(color: accent.withValues(alpha: 0.3)),
          Row(
            children: [
              Expanded(
                child: Text(
                  'round score',
                  style: textTheme.titleLarge?.copyWith(color: accent),
                ),
              ),
              Text(
                '${guessing + drawing}',
                style: tokens.scoreNumeral.copyWith(
                  fontSize: 34,
                  color: accent,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
