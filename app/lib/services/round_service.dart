import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/guess_progress.dart';
import '../models/room_detail.dart';
import '../models/round_info.dart';
import 'score_service.dart';

/// Thrown by [RoundService] with copy that's already safe to show the
/// user — same pattern as the app's other `*ServiceException` types.
class RoundServiceException implements Exception {
  RoundServiceException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// The round engine. Rounds run back to back with no end: while round n
/// is current, everyone draws round n's prompt and guesses round n−1's
/// drawings (round 1 is draw-only); when round n ends, round n−1's
/// results land and round n+1 opens.
///
/// Spark has no scheduler or Cloud Functions, so nothing happens "at" a
/// deadline. Instead every app [checkIn]s — on opening the round hub or
/// the guess grid, after submitting a drawing, after finishing a card —
/// and the first one to find the round over moves the room on, in one
/// transaction that firestore.rules checks field by field.
///
/// A round is over at its deadline, or earlier once everyone it waits for
/// is done (early close). Done means your drawing for this round is in
/// and every card from last round is finished (solved, or all 5 attempts
/// used). Marking done is client-asserted: rules can check the drawing
/// exists, not that every guess is finished — which only ever forfeits
/// the cheater's own guesses.
///
/// No round ever runs longer than the room's round length. After a
/// deadline, the next one keeps the room's rhythm: the next slot on its
/// schedule that's still ahead, so results land at the usual hour even if
/// nobody opened the room for a while. After an early close it's a fresh
/// full round from now — building on the old, still-future deadline
/// instead would stack a round length on top for every early close. Round
/// numbers never skip, so every round's drawings still get their guessing
/// round.
class RoundService {
  RoundService({FirebaseFirestore? firestore, FirebaseAuth? auth})
    : _firestore = firestore ?? FirebaseFirestore.instance,
      _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  DocumentReference<Map<String, dynamic>> _roomRef(String roomId) =>
      _firestore.collection('rooms').doc(roomId);

  DocumentReference<Map<String, dynamic>> _roundRef(String roomId, int n) =>
      _roomRef(roomId).collection('rounds').doc('$n');

  Map<String, dynamic> _newRound(
    int n,
    Timestamp deadline,
    List<String> memberUids,
  ) => {
    'number': n,
    'opensAt': FieldValue.serverTimestamp(),
    'deadline': deadline,
    'requiredUids': memberUids,
    'doneUids': <String>[],
  };

  Stream<RoundInfo?> watchRound(String roomId, int n) {
    return _roundRef(
      roomId,
      n,
    ).snapshots().map((doc) => doc.exists ? RoundInfo.fromDoc(doc) : null);
  }

  /// Owner-only, one-shot: moves a room from the lobby into round 1. The
  /// deadline comes from the owner's own clock (no Cloud Function to stamp
  /// it), from *now*.
  Future<void> startFirstRound({
    required String roomId,
    required int roundLengthHours,
  }) async {
    if (_auth.currentUser == null) {
      throw RoundServiceException('Sign in to start the round.');
    }
    final roomRef = _roomRef(roomId);
    try {
      await _firestore.runTransaction((tx) async {
        final snap = await tx.get(roomRef);
        final data = snap.data();
        if (data == null || data['roundEndsAt'] != null) return;
        final deadline = Timestamp.fromDate(
          DateTime.now().add(Duration(hours: roundLengthHours)),
        );
        tx.update(roomRef, {'currentRound': 1, 'roundEndsAt': deadline});
        tx.set(
          _roundRef(roomId, 1),
          _newRound(
            1,
            deadline,
            List<String>.from(data['memberUids'] as List? ?? const []),
          ),
        );
      });
    } on FirebaseException {
      throw RoundServiceException("Couldn't start the round — try again.");
    }
  }

  /// Marks you done if you are, then advances the room if its current
  /// round is over. Best effort: if anything fails (offline, a race), the
  /// next check-in by anyone tries again.
  Future<void> checkIn(String roomId) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;

    try {
      final snap = await _roomRef(roomId).get();
      if (!snap.exists) return;
      final room = RoomDetail.fromDoc(snap);
      final n = room.currentRound;
      if (n == null) return;

      if (!room.isRoundLocked) {
        final roundRef = _roundRef(roomId, n);
        final roundSnap = await roundRef.get();
        if (roundSnap.exists) {
          final round = RoundInfo.fromDoc(roundSnap);
          if (round.requiredUids.contains(uid) &&
              !round.doneUids.contains(uid) &&
              await _isDone(roomId, uid, n)) {
            await roundRef.update({
              'doneUids': FieldValue.arrayUnion([uid]),
            });
          }
        }
      }

      await _tryAdvance(roomId);
    } on FirebaseException {
      // See the doc comment — the next check-in retries.
    }
    // Whichever round the room is on now, score any results that are out
    // so the reveal and the leaderboard have them.
    await ScoreService().ensureScored(roomId);
  }

  Future<bool> _isDone(String roomId, String uid, int n) async {
    final mine = await _roundRef(
      roomId,
      n,
    ).collection('drawings').doc(uid).get();
    if (!mine.exists) return false;
    if (n == 1) return true; // Round 1 is draw-only.

    final lastRound = _roundRef(roomId, n - 1);
    final drawings = await lastRound.collection('drawings').get();
    final guesses = await lastRound
        .collection('guesses')
        .where('guesserUid', isEqualTo: uid)
        .get();
    final progress = {
      for (final doc in guesses.docs)
        doc.data()['authorUid'] as String? ?? '': GuessProgress.fromDoc(doc),
    };
    return drawings.docs
        .where((d) => d.id != uid)
        .every((d) => progress[d.id]?.isDone ?? false);
  }

  /// Idempotent: if two players get here at once, the transaction retries
  /// and the second one finds the room already moved on.
  Future<void> _tryAdvance(String roomId) {
    final roomRef = _roomRef(roomId);
    return _firestore.runTransaction((tx) async {
      final roomSnap = await tx.get(roomRef);
      if (!roomSnap.exists) return;
      final room = RoomDetail.fromDoc(roomSnap);
      final n = room.currentRound;
      final endsAt = room.roundEndsAt;
      if (n == null || endsAt == null) return;

      final roundRef = _roundRef(roomId, n);
      final roundSnap = await tx.get(roundRef);
      final round = roundSnap.exists ? RoundInfo.fromDoc(roundSnap) : null;
      final allDone =
          round != null &&
          round.requiredUids.isNotEmpty &&
          round.requiredUids.every(round.doneUids.contains);
      final now = DateTime.now();
      if (!allDone && !now.isAfter(endsAt)) return;

      final length = Duration(hours: room.roundLengthHours);
      DateTime next;
      if (now.isAfter(endsAt)) {
        // Deadline: keep the room's rhythm — the next slot on its
        // schedule that's still ahead (at most one round length away).
        next = endsAt.add(length);
        while (!next.isAfter(now)) {
          next = next.add(length);
        }
      } else {
        // Early close: a fresh full round from now. Stacking onto the old,
        // still-future deadline would grow every round past its length.
        next = now.add(length);
      }
      final nextDeadline = Timestamp.fromDate(next);

      tx.update(roomRef, {'currentRound': n + 1, 'roundEndsAt': nextDeadline});
      if (round != null) {
        tx.update(roundRef, {
          'closedAt': FieldValue.serverTimestamp(),
          'closeReason': allDone ? 'allDone' : 'deadline',
        });
      }
      tx.set(
        _roundRef(roomId, n + 1),
        _newRound(n + 1, nextDeadline, room.memberUids),
      );
    });
  }
}
