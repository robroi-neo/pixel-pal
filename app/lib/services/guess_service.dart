import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/guess_progress.dart';

/// Thrown by [GuessService] with copy that's already safe to show the
/// user — same pattern as the app's other `*ServiceException` types.
class GuessServiceException implements Exception {
  GuessServiceException(this.message);

  final String message;

  @override
  String toString() => message;
}

enum GuessOutcome { correct, incorrect, outOfAttempts }

/// Tracks a member's own attempts at guessing other members' drawings, in
/// `rooms/{roomId}/members/{myUid}/guesses/{authorUid}` — one doc per
/// (guesser, drawing) pair. There's no round to scope this to yet
/// (Implementations.md Phase 3), same limitation as `issuedPromptIds`.
///
/// Matching happens entirely client-side against the plaintext `word` on
/// the drawing doc — see the trade-off documented on [DrawingSubmission].
/// Design.md calls for "fuzzy submit"; this allows one character of
/// difference (a Levenshtein distance of 1) for words longer than 4
/// letters, exact match otherwise.
class GuessService {
  GuessService({FirebaseFirestore? firestore, FirebaseAuth? auth})
    : _firestore = firestore ?? FirebaseFirestore.instance,
      _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  CollectionReference<Map<String, dynamic>> _myGuesses(String roomId) {
    final uid = _auth.currentUser!.uid;
    return _firestore
        .collection('rooms')
        .doc(roomId)
        .collection('members')
        .doc(uid)
        .collection('guesses');
  }

  /// Every guesser's progress on every drawing — for the deadline reveal
  /// — as `{guesserUid: {authorUid: progress}}`. One live query per
  /// guesser (rooms cap at 8), combined into a single stream that first
  /// emits once every guesser has reported in. firestore.rules only allows
  /// reading other members' guesses once the round has locked.
  Stream<Map<String, Map<String, GuessProgress>>> watchAllGuesses({
    required String roomId,
    required List<String> guesserUids,
  }) {
    final subscriptions = <StreamSubscription<Object?>>[];
    final latest = <String, Map<String, GuessProgress>>{};
    late final StreamController<Map<String, Map<String, GuessProgress>>>
    controller;

    controller = StreamController(
      onListen: () {
        if (guesserUids.isEmpty) {
          controller.add(const {});
          return;
        }
        for (final uid in guesserUids) {
          final guesses = _firestore
              .collection('rooms')
              .doc(roomId)
              .collection('members')
              .doc(uid)
              .collection('guesses');
          subscriptions.add(
            guesses.snapshots().listen((snapshot) {
              latest[uid] = {
                for (final doc in snapshot.docs)
                  doc.id: GuessProgress.fromDoc(doc),
              };
              if (latest.length == guesserUids.length) {
                controller.add(Map.of(latest));
              }
            }, onError: controller.addError),
          );
        }
      },
      onCancel: () async {
        for (final subscription in subscriptions) {
          await subscription.cancel();
        }
      },
    );
    return controller.stream;
  }

  CollectionReference<Map<String, dynamic>> _myStars(String roomId) {
    final uid = _auth.currentUser!.uid;
    return _firestore
        .collection('rooms')
        .doc(roomId)
        .collection('members')
        .doc(uid)
        .collection('stars');
  }

  /// Author uids of the drawings I've starred. Stars are given at the
  /// reveal and never touch the score.
  Stream<Set<String>> watchMyStars(String roomId) {
    return _myStars(
      roomId,
    ).snapshots().map((snapshot) => {for (final doc in snapshot.docs) doc.id});
  }

  Future<void> setStarred({
    required String roomId,
    required String authorUid,
    required bool starred,
  }) async {
    final ref = _myStars(roomId).doc(authorUid);
    try {
      if (starred) {
        await ref.set({'createdAt': FieldValue.serverTimestamp()});
      } else {
        await ref.delete();
      }
    } on FirebaseException {
      throw GuessServiceException("Couldn't save your star — try again.");
    }
  }

  /// Live, keyed by the drawing's authorUid.
  Stream<Map<String, GuessProgress>> watchMyGuesses(String roomId) {
    return _myGuesses(roomId).snapshots().map(
      (snapshot) => {
        for (final doc in snapshot.docs) doc.id: GuessProgress.fromDoc(doc),
      },
    );
  }

  static bool fuzzyMatches(String guess, String answer) {
    final a = guess.trim().toLowerCase();
    final b = answer.trim().toLowerCase();
    if (a.isEmpty) return false;
    if (a == b) return true;
    final tolerance = b.length > 4 ? 1 : 0;
    return _levenshtein(a, b) <= tolerance;
  }

  static int _levenshtein(String s, String t) {
    if (s == t) return 0;
    if (s.isEmpty) return t.length;
    if (t.isEmpty) return s.length;

    var previousRow = List<int>.generate(t.length + 1, (i) => i);
    for (var i = 0; i < s.length; i++) {
      final currentRow = List<int>.filled(t.length + 1, 0);
      currentRow[0] = i + 1;
      for (var j = 0; j < t.length; j++) {
        final deletionCost = previousRow[j + 1] + 1;
        final insertionCost = currentRow[j] + 1;
        final substitutionCost = previousRow[j] + (s[i] == t[j] ? 0 : 1);
        currentRow[j + 1] = [
          deletionCost,
          insertionCost,
          substitutionCost,
        ].reduce((a, b) => a < b ? a : b);
      }
      previousRow = currentRow;
    }
    return previousRow[t.length];
  }

  /// [progress] is the caller's last-known state for this drawing (e.g.
  /// [GuessProgress.initial] if this is the first attempt) — used to
  /// decide `create` vs `update` and to compute the next attempt/reveal
  /// counts, since firestore.rules pins both to move by exactly the
  /// expected amount each write.
  Future<GuessOutcome> submitGuess({
    required String roomId,
    required String authorUid,
    required String answer,
    required String guessText,
    required GuessProgress progress,
  }) async {
    final correct = fuzzyMatches(guessText, answer);
    final nextAttempts = progress.attempts + 1;
    final nextRevealed = correct
        ? progress.revealedCount
        : (progress.revealedCount + 1).clamp(0, answer.length);

    final data = {
      'attempts': nextAttempts,
      'solved': correct,
      'revealedCount': nextRevealed,
      'updatedAt': FieldValue.serverTimestamp(),
    };

    try {
      final ref = _myGuesses(roomId).doc(authorUid);
      if (progress.attempts == 0) {
        await ref.set(data);
      } else {
        await ref.update(data);
      }
    } on FirebaseException {
      throw GuessServiceException("Couldn't submit your guess — try again.");
    }

    if (correct) return GuessOutcome.correct;
    if (nextAttempts >= GuessProgress.maxAttempts) {
      return GuessOutcome.outOfAttempts;
    }
    return GuessOutcome.incorrect;
  }
}
