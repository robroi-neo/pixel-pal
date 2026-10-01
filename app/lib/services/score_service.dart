import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/drawing_submission.dart';
import '../models/guess_progress.dart';
import '../models/room_detail.dart';
import '../models/round_info.dart';
import '../models/round_scores.dart';

/// Round scores and the season table, in `rooms/{roomId}/scores/{r}`.
///
/// There's no server on Spark to score a round when it closes, so the
/// first member's app to find a round's results out scores it —
/// [ensureScored], called from every check-in. By then that round's
/// drawings and guesses are frozen (the rules stop guessing when the round
/// after it ends) and readable by every member, so the result is the same
/// whoever computes it. Each doc also carries everyone's running season
/// totals, so the leaderboard reads one or two docs, not every round.
class ScoreService {
  ScoreService({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  DocumentReference<Map<String, dynamic>> _room(String roomId) =>
      _firestore.collection('rooms').doc(roomId);

  CollectionReference<Map<String, dynamic>> _scores(String roomId) =>
      _room(roomId).collection('scores');

  /// The newest [limit] scored rounds, newest first — the latest table,
  /// and the one before it for rank changes.
  Stream<List<RoundScores>> watchLatest(String roomId, {int limit = 2}) {
    return _scores(roomId)
        .orderBy('round', descending: true)
        .limit(limit)
        .snapshots()
        .map((snapshot) => snapshot.docs.map(RoundScores.fromDoc).toList());
  }

  Stream<RoundScores?> watchRound(String roomId, int round) {
    return _scores(roomId)
        .doc('$round')
        .snapshots()
        .map((doc) => doc.exists ? RoundScores.fromDoc(doc) : null);
  }

  /// How far each room is known to be scored, this app session. Scored
  /// rounds never change, so once a room is up to date, a check-in costs
  /// nothing here until its next results land.
  static final _scoredThrough = <String, int>{};

  /// Scores every round whose results are out but aren't scored yet, in
  /// order — each round's season totals build on the one before, and the
  /// rules only accept round r once round r−1 exists. If another app
  /// scores a round first, carries on from theirs. Best effort: anything
  /// failing just leaves it for the next check-in.
  ///
  /// [room], if the caller has just read it, saves reading it again.
  Future<void> ensureScored(String roomId, {RoomDetail? room}) async {
    try {
      var current = room;
      if (current == null) {
        final roomSnap = await _room(roomId).get();
        if (!roomSnap.exists) return;
        current = RoomDetail.fromDoc(roomSnap);
      }
      final latest = current.latestResultsRound;
      if (latest == null) return;
      if ((_scoredThrough[roomId] ?? 0) >= latest) return;

      final last = await _scores(
        roomId,
      ).orderBy('round', descending: true).limit(1).get();
      RoundScores? previous = last.docs.isEmpty
          ? null
          : RoundScores.fromDoc(last.docs.first);

      for (var r = (previous?.round ?? 0) + 1; r <= latest; r++) {
        final scores = await _compute(roomId, r, previous);
        final ref = _scores(roomId).doc('$r');
        try {
          await ref.set({
            ...scores.toMap(),
            'createdAt': FieldValue.serverTimestamp(),
          });
          previous = scores;
        } on FirebaseException {
          // Most likely someone else's app wrote it first (a second
          // write is an update, which the rules refuse).
          final existing = await ref.get();
          if (!existing.exists) return;
          previous = RoundScores.fromDoc(existing);
        }
      }
      if (previous != null) _scoredThrough[roomId] = previous.round;
    } on FirebaseException {
      // See the doc comment — the next check-in retries.
    }
  }

  Future<RoundScores> _compute(
    String roomId,
    int round,
    RoundScores? previous,
  ) async {
    final roundRef = _room(roomId).collection('rounds').doc('$round');
    final nextRef = _room(roomId).collection('rounds').doc('${round + 1}');
    final results = await Future.wait([
      roundRef.collection('drawings').get(),
      roundRef.collection('guesses').get(),
      roundRef.get(),
      nextRef.get(),
    ]);
    final drawings = (results[0] as QuerySnapshot<Map<String, dynamic>>).docs
        .map(DrawingSubmission.fromDoc)
        .toList();
    final guesses = <String, Map<String, GuessProgress>>{};
    for (final doc
        in (results[1] as QuerySnapshot<Map<String, dynamic>>).docs) {
      final guesser = doc.data()['guesserUid'] as String? ?? '';
      final author = doc.data()['authorUid'] as String? ?? '';
      (guesses[guesser] ??= {})[author] = GuessProgress.fromDoc(doc);
    }
    List<String> requiredOf(Object? snap) {
      final doc = snap as DocumentSnapshot<Map<String, dynamic>>;
      return doc.exists ? RoundInfo.fromDoc(doc).requiredUids : const [];
    }

    return RoundScores.compute(
      round: round,
      drawings: drawings,
      guesses: guesses,
      roundRequired: requiredOf(results[2]),
      nextRoundRequired: requiredOf(results[3]),
      previous: previous,
    );
  }
}
