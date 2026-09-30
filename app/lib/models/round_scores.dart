import 'package:cloud_firestore/cloud_firestore.dart';

import 'drawing_submission.dart';
import 'guess_progress.dart';
import 'round_score.dart';

/// One player's score for one round: the two halves from [RoundScore],
/// added.
class RoundEntry {
  const RoundEntry({
    required this.guessing,
    required this.drawing,
    required this.drew,
    required this.guessed,
  });

  static const zero = RoundEntry(
    guessing: 0,
    drawing: 0,
    drew: false,
    guessed: 0,
  );

  final int guessing;
  final int drawing;
  final bool drew;

  /// How many drawings they tried at least once.
  final int guessed;

  int get total => guessing + drawing;

  /// Did anything at all this round — a skipped round still counts, as 0.
  bool get played => drew || guessed > 0;

  Map<String, dynamic> toMap() => {
    'guessing': guessing,
    'drawing': drawing,
    'drew': drew,
    'guessed': guessed,
  };

  factory RoundEntry.fromMap(Map<String, dynamic> map) => RoundEntry(
    guessing: (map['guessing'] as num?)?.toInt() ?? 0,
    drawing: (map['drawing'] as num?)?.toInt() ?? 0,
    drew: map['drew'] as bool? ?? false,
    guessed: (map['guessed'] as num?)?.toInt() ?? 0,
  );
}

/// A player's running totals up to and including some round.
class SeasonEntry {
  const SeasonEntry({
    required this.total,
    required this.rounds,
    required this.missStreak,
  });

  static const zero = SeasonEntry(total: 0, rounds: 0, missStreak: 0);

  final int total;

  /// Rounds counted: every round they were around for, skipped ones too.
  final int rounds;

  /// Consecutive rounds, up to this one, where they did nothing at all.
  final int missStreak;

  /// What the leaderboard ranks on — the mean round score.
  int get average => rounds == 0 ? 0 : (total / rounds).round();

  Map<String, dynamic> toMap() => {
    'total': total,
    'rounds': rounds,
    'missStreak': missStreak,
  };

  factory SeasonEntry.fromMap(Map<String, dynamic> map) => SeasonEntry(
    total: (map['total'] as num?)?.toInt() ?? 0,
    rounds: (map['rounds'] as num?)?.toInt() ?? 0,
    missStreak: (map['missStreak'] as num?)?.toInt() ?? 0,
  );
}

/// A row on the table.
class Standing {
  const Standing({
    required this.uid,
    required this.score,
    required this.rank,
    required this.rounds,
    required this.missStreak,
  });

  final String uid;

  /// Season average, or that round's total when ranking one round only.
  final int score;

  /// 1-based; tied scores share a rank.
  final int rank;
  final int rounds;
  final int missStreak;
}

/// `rooms/{roomId}/scores/{r}` — round r's scores, and everyone's season
/// totals after it. Written once, by whichever member's app first finds
/// round r's results out (see `ScoreService.ensureScored`), and read by the
/// reveal and the leaderboard. Spark has no server to score a round, so
/// this is computed client-side from the (by then frozen, member-readable)
/// drawings and guesses — a stored cache anyone could recompute, but not
/// one the rules can check.
class RoundScores {
  const RoundScores({
    required this.round,
    required this.entries,
    required this.season,
  });

  final int round;

  /// This round only, for everyone it counts for.
  final Map<String, RoundEntry> entries;

  /// Everyone's running totals after this round.
  final Map<String, SeasonEntry> season;

  /// Who could have guessed round r's drawings: everyone round r+1 waited
  /// for, plus anyone who joined since and guessed anyway.
  static Set<String> guessPool({
    required List<String> nextRoundRequired,
    required Map<String, Map<String, GuessProgress>> guesses,
  }) => {...nextRoundRequired, ...guesses.keys};

  /// Scores round [round]. [guesses] is `{guesserUid: {authorUid:
  /// progress}}`; [roundRequired]/[nextRoundRequired] are who rounds r and
  /// r+1 waited for. A player counts for the round if they had a real
  /// chance at either half of it — skipped rounds score 0 and still count.
  factory RoundScores.compute({
    required int round,
    required List<DrawingSubmission> drawings,
    required Map<String, Map<String, GuessProgress>> guesses,
    required List<String> roundRequired,
    required List<String> nextRoundRequired,
    RoundScores? previous,
  }) {
    final pool = guessPool(
      nextRoundRequired: nextRoundRequired,
      guesses: guesses,
    );
    final players = {
      ...roundRequired,
      ...pool,
      for (final d in drawings) d.authorUid,
    };

    final entries = <String, RoundEntry>{};
    for (final uid in players) {
      final mine = guesses[uid] ?? const {};
      final others = drawings.where((d) => d.authorUid != uid).toList();
      final points = [
        for (final d in others)
          RoundScore.guessPoints(mine[d.authorUid], d.multiplier),
      ];
      final drawing = drawings.where((d) => d.authorUid == uid).firstOrNull;
      var drawingHalf = 0;
      if (drawing != null) {
        final eligible = pool.where((g) => g != uid);
        drawingHalf = RoundScore.drawingHalf(
          solvers: eligible
              .where((g) => guesses[g]?[uid]?.solved ?? false)
              .length,
          eligible: eligible.length,
          multiplier: drawing.multiplier,
        );
      }
      entries[uid] = RoundEntry(
        guessing: RoundScore.guessingHalf(points),
        drawing: drawingHalf,
        drew: drawing != null,
        guessed: others
            .where((d) => (mine[d.authorUid]?.attempts ?? 0) > 0)
            .length,
      );
    }

    final season = {...?previous?.season};
    entries.forEach((uid, entry) {
      final before = season[uid] ?? SeasonEntry.zero;
      season[uid] = SeasonEntry(
        total: before.total + entry.total,
        rounds: before.rounds + 1,
        missStreak: entry.played ? 0 : before.missStreak + 1,
      );
    });

    return RoundScores(round: round, entries: entries, season: season);
  }

  /// The table for [memberUids] (people who've left aren't on it): by
  /// season average, or by this round's totals when [roundOnly].
  List<Standing> standings(List<String> memberUids, {bool roundOnly = false}) {
    final rows = <Standing>[];
    for (final uid in memberUids) {
      final s = season[uid];
      if (s == null || s.rounds == 0) continue;
      if (roundOnly && !entries.containsKey(uid)) continue;
      rows.add(
        Standing(
          uid: uid,
          score: roundOnly ? entries[uid]!.total : s.average,
          rank: 0,
          rounds: s.rounds,
          missStreak: s.missStreak,
        ),
      );
    }
    rows.sort((a, b) {
      final byScore = b.score.compareTo(a.score);
      return byScore != 0 ? byScore : a.uid.compareTo(b.uid);
    });

    final ranked = <Standing>[];
    for (var i = 0; i < rows.length; i++) {
      final tied = i > 0 && rows[i].score == rows[i - 1].score;
      ranked.add(
        Standing(
          uid: rows[i].uid,
          score: rows[i].score,
          rank: tied ? ranked[i - 1].rank : i + 1,
          rounds: rows[i].rounds,
          missStreak: rows[i].missStreak,
        ),
      );
    }
    return ranked;
  }

  Map<String, dynamic> toMap() => {
    'round': round,
    'entries': {for (final e in entries.entries) e.key: e.value.toMap()},
    'season': {for (final e in season.entries) e.key: e.value.toMap()},
  };

  factory RoundScores.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const {};
    Map<String, T> mapOf<T>(
      Object? raw,
      T Function(Map<String, dynamic>) parse,
    ) => {
      for (final e in (raw as Map<String, dynamic>? ?? const {}).entries)
        e.key: parse(Map<String, dynamic>.from(e.value as Map)),
    };
    return RoundScores(
      round: (data['round'] as num?)?.toInt() ?? int.tryParse(doc.id) ?? 0,
      entries: mapOf(data['entries'], RoundEntry.fromMap),
      season: mapOf(data['season'], SeasonEntry.fromMap),
    );
  }
}

/// "1st", "2nd", "3rd", "4th", … "11th", "12th", "13th", "21st".
String ordinal(int n) {
  final lastTwo = n % 100;
  if (lastTwo >= 11 && lastTwo <= 13) return '${n}th';
  return switch (n % 10) {
    1 => '${n}st',
    2 => '${n}nd',
    3 => '${n}rd',
    _ => '${n}th',
  };
}
