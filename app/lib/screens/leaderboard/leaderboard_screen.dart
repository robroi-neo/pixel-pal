import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../models/room_detail.dart';
import '../../models/round_scores.dart';
import '../../services/guess_service.dart';
import '../../services/room_service.dart';
import '../../services/score_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_dimens.dart';
import '../../theme/app_tokens.dart';
import '../../widgets/loading_view.dart';
import '../../widgets/profile_avatar.dart';
import '../../widgets/rank_delta.dart';

/// Design.md §5 "Leaderboard": ranked on mean round score, with the round
/// count stated so late joiners understand the ranking; stars in their own
/// card, never touching the score; players on a run of missed rounds
/// tinted and grey-avatared, not hidden.
///
/// Reads the newest two scored rounds (see [ScoreService]) — the second
/// only for the ▲/▼ since last time — and counts stars per player.
class LeaderboardScreen extends StatefulWidget {
  const LeaderboardScreen({super.key, required this.roomId});

  final String roomId;

  @override
  State<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends State<LeaderboardScreen> {
  late final Stream<RoomDetail?> _room = RoomService().watchRoom(widget.roomId);
  late final Stream<List<RoundScores>> _scores = ScoreService().watchLatest(
    widget.roomId,
  );

  // Recounted only when the room's members change. Known gap, parked for
  // now: a star given while this screen is open (or since it was built)
  // doesn't show in "Most starred" until it's reopened.
  Future<Map<String, int>>? _stars;
  String? _starsKey;

  bool _roundOnly = false;

  @override
  void initState() {
    super.initState();
    // Scores any results that are out but not tallied yet.
    ScoreService().ensureScored(widget.roomId);
  }

  Future<Map<String, int>> _starsFor(RoomDetail room) {
    final key = room.memberUids.join(',');
    if (key != _starsKey) {
      _starsKey = key;
      _stars = GuessService().countStarsReceived(room.id, room.memberUids);
    }
    return _stars!;
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return StreamBuilder<RoomDetail?>(
      stream: _room,
      builder: (context, roomSnapshot) {
        final room = roomSnapshot.data;
        return Scaffold(
          appBar: AppBar(
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_outlined),
              onPressed: () => context.pop(),
            ),
            title: Text(room?.name ?? '', style: textTheme.titleMedium),
          ),
          body: SafeArea(
            child: StreamBuilder<List<RoundScores>>(
              stream: _scores,
              builder: (context, scoresSnapshot) {
                if (roomSnapshot.hasError || scoresSnapshot.hasError) {
                  return _Message("Couldn't load the table.");
                }
                if (!roomSnapshot.hasData || !scoresSnapshot.hasData) {
                  return const LoadingView(message: 'Loading the table…');
                }
                if (room == null) {
                  return _Message('This room no longer exists.');
                }
                final scores = scoresSnapshot.data!;
                if (scores.isEmpty) {
                  return _Message(
                    "No table yet. It starts once round 1's results are "
                    'in — when round 2 ends.',
                  );
                }
                return _buildTable(room, scores);
              },
            ),
          ),
        );
      },
    );
  }

  Widget _buildTable(RoomDetail room, List<RoundScores> scores) {
    final textTheme = Theme.of(context).textTheme;
    final latest = scores.first;
    final table = latest.standings(room.memberUids, roundOnly: _roundOnly);
    final deltas = _roundOnly || scores.length < 2
        ? const <String, int>{}
        : rankDeltas(
            {
              for (final s in scores[1].standings(room.memberUids))
                s.uid: s.rank,
            },
            {for (final s in table) s.uid: s.rank},
          );
    final myUid = FirebaseAuth.instance.currentUser?.uid ?? '';

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        Text('Leaderboard', style: textTheme.headlineMedium),
        Text(
          _roundOnly
              ? 'Round ${latest.round} scores'
              : 'Average round score · ${latest.round} '
                    '${latest.round == 1 ? 'round' : 'rounds'} counted',
          style: textTheme.bodySmall?.copyWith(
            color: AppColors.ink.withValues(alpha: 0.7),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        _Toggle(
          left: 'Season',
          right: 'Round ${latest.round} only',
          rightSelected: _roundOnly,
          onChanged: (roundOnly) {
            HapticFeedback.selectionClick();
            setState(() => _roundOnly = roundOnly);
          },
        ),
        const SizedBox(height: AppSpacing.xl),
        _Podium(
          standings: table.take(3).toList(),
          deltas: deltas,
          myUid: myUid,
        ),
        const SizedBox(height: AppSpacing.md),
        Container(height: AppBorders.thick, color: AppColors.ink),
        const SizedBox(height: AppSpacing.md),
        for (final s in table.skip(3))
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: _TableRow(
              standing: s,
              isMe: s.uid == myUid,
              roundOnly: _roundOnly,
              roundsSoFar: latest.round,
            ),
          ),
        const SizedBox(height: AppSpacing.sm),
        FutureBuilder<Map<String, int>>(
          future: _starsFor(room),
          builder: (context, snapshot) =>
              _MostStarred(counts: snapshot.data, myUid: myUid),
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          'Stars never count toward score. Skipped rounds count as 0.',
          style: textTheme.bodySmall?.copyWith(
            color: AppColors.ink.withValues(alpha: 0.7),
          ),
        ),
      ],
    );
  }
}

/// Two-way switch: ink fill marks the selected side.
class _Toggle extends StatelessWidget {
  const _Toggle({
    required this.left,
    required this.right,
    required this.rightSelected,
    required this.onChanged,
  });

  final String left;
  final String right;
  final bool rightSelected;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    Widget side(String label, bool selected, bool value) {
      final theme = Theme.of(context);
      return Expanded(
        child: GestureDetector(
          onTap: selected ? null : () => onChanged(value),
          behavior: HitTestBehavior.opaque,
          child: AnimatedContainer(
            duration: AppMotion.duration,
            height: AppSizes.minTouchTarget,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected ? AppColors.ink : Colors.transparent,
              borderRadius: BorderRadius.circular(AppRadius.control - 3),
            ),
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: selected ? theme.colorScheme.onSecondary : AppColors.ink,
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppColors.cream,
        borderRadius: AppRadius.controlRadius,
        border: Border.all(color: AppColors.ink, width: AppBorders.thick),
      ),
      child: Row(
        children: [
          side(left, !rightSelected, false),
          side(right, rightSelected, true),
        ],
      ),
    );
  }
}

/// The top three: first in the middle and tallest, on ink.
class _Podium extends StatelessWidget {
  const _Podium({
    required this.standings,
    required this.deltas,
    required this.myUid,
  });

  final List<Standing> standings;
  final Map<String, int> deltas;
  final String myUid;

  @override
  Widget build(BuildContext context) {
    Widget spot(int index) {
      if (index >= standings.length) return const Expanded(child: SizedBox());
      final s = standings[index];
      return Expanded(
        child: _PodiumSpot(
          standing: s,
          place: index + 1,
          delta: deltas[s.uid],
          isMe: s.uid == myUid,
        ),
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        spot(1),
        const SizedBox(width: AppSpacing.sm),
        spot(0),
        const SizedBox(width: AppSpacing.sm),
        spot(2),
      ],
    );
  }
}

class _PodiumSpot extends StatelessWidget {
  const _PodiumSpot({
    required this.standing,
    required this.place,
    required this.delta,
    required this.isMe,
  });

  final Standing standing;

  /// Position on the podium (1–3) — not always the rank, when tied.
  final int place;
  final int? delta;
  final bool isMe;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<AppTokens>()!;
    final accent = theme.colorScheme.onSecondary;
    final first = place == 1;
    final height = switch (place) {
      1 => 124.0,
      2 => 92.0,
      _ => 80.0,
    };
    final fill = switch (place) {
      1 => AppColors.ink,
      2 => AppColors.white,
      _ => AppColors.cream,
    };

    return Column(
      children: [
        ProfileAvatar(
          uid: standing.uid,
          fallbackInitials: '?',
          size: first ? 52 : 40,
          ringColor: first ? AppColors.white : null,
        ),
        const SizedBox(height: AppSpacing.xs),
        isMe
            ? Text(
                'You',
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              )
            : ProfileBuilder(
                uid: standing.uid,
                builder: (context, profile) => Text(
                  profile?.displayName ?? 'A player',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
        RankDelta(delta: delta),
        const SizedBox(height: AppSpacing.xs),
        Container(
          height: height,
          width: double.infinity,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: fill,
            borderRadius: AppRadius.cardRadius,
            border: Border.all(color: AppColors.ink, width: AppBorders.thick),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${standing.score}',
                style: tokens.scoreNumeral.copyWith(
                  fontSize: first ? 26 : 20,
                  color: first ? accent : AppColors.ink,
                ),
              ),
              Text(
                ordinal(standing.rank),
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: first ? accent : AppColors.ink,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _TableRow extends StatelessWidget {
  const _TableRow({
    required this.standing,
    required this.isMe,
    required this.roundOnly,
    required this.roundsSoFar,
  });

  final Standing standing;
  final bool isMe;
  final bool roundOnly;
  final int roundsSoFar;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<AppTokens>()!;
    final missed = standing.missStreak;
    // Design.md §5: inactive players are tinted and grey, not hidden.
    final inactive = missed >= 2;
    final note = missed >= 2
        ? 'Missed the last $missed rounds'
        : missed == 1
        ? 'Missed last round'
        : !roundOnly && standing.rounds < roundsSoFar
        ? '${standing.rounds} ${standing.rounds == 1 ? 'round' : 'rounds'} '
              'counted'
        : null;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: isMe ? AppColors.white : AppColors.cream,
        borderRadius: AppRadius.cardRadius,
        border: Border.all(color: AppColors.ink, width: AppBorders.thick),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 24,
            child: Text(
              '${standing.rank}',
              style: tokens.scoreNumeral.copyWith(fontSize: 14),
            ),
          ),
          ProfileAvatar(
            uid: standing.uid,
            fallbackInitials: '?',
            size: 30,
            inactive: inactive,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                isMe
                    ? Text(
                        'You',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      )
                    : ProfileBuilder(
                        uid: standing.uid,
                        builder: (context, profile) => Text(
                          profile?.displayName ?? 'A player',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                if (note != null)
                  Text(
                    note,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppColors.ink.withValues(alpha: 0.6),
                    ),
                  ),
              ],
            ),
          ),
          Text(
            '${standing.score}',
            style: tokens.scoreNumeral.copyWith(fontSize: 18),
          ),
        ],
      ),
    );
  }
}

class _MostStarred extends StatelessWidget {
  const _MostStarred({required this.counts, required this.myUid});

  /// Null while counting.
  final Map<String, int>? counts;
  final String myUid;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;
    final accent = theme.colorScheme.onSecondary;
    final c = counts;
    MapEntry<String, int>? top;
    if (c != null) {
      for (final e in c.entries) {
        if (e.value > 0 && (top == null || e.value > top.value)) top = e;
      }
    }

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: AppRadius.cardRadius,
        border: Border.all(color: AppColors.ink, width: AppBorders.thick),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.ink,
              borderRadius: AppRadius.controlRadius,
            ),
            child: Icon(Icons.star_rounded, color: accent),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'MOST STARRED',
                  style: textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                    color: AppColors.ink.withValues(alpha: 0.7),
                  ),
                ),
                if (c == null)
                  Text('Counting…', style: textTheme.titleMedium)
                else if (top == null)
                  Text(
                    'No stars yet — give one at the reveal',
                    style: textTheme.bodyMedium,
                  )
                else
                  top.key == myUid
                      ? Text(
                          'You · ${_stars(top.value)}',
                          style: textTheme.titleMedium,
                        )
                      : ProfileBuilder(
                          uid: top.key,
                          builder: (context, profile) => Text(
                            '${profile?.displayName ?? 'A player'} · '
                            '${_stars(top!.value)}',
                            style: textTheme.titleMedium,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
              ],
            ),
          ),
          if (c != null && top != null && top.key != myUid)
            Text(
              'You · ${c[myUid] ?? 0}',
              style: textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
            ),
        ],
      ),
    );
  }

  static String _stars(int n) => '$n ${n == 1 ? 'star' : 'stars'}';
}

class _Message extends StatelessWidget {
  const _Message(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ),
    );
  }
}
