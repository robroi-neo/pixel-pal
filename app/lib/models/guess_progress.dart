import 'package:cloud_firestore/cloud_firestore.dart';

/// My attempts at guessing one specific other member's drawing, as read
/// from `rooms/{roomId}/members/{myUid}/guesses/{authorUid}`. Design.md
/// §3 "Attempt marker" / §5 "Guess": tiles show word length from attempt
/// 1, one more letter reveals per wrong guess, up to [maxAttempts].
class GuessProgress {
  const GuessProgress({
    required this.attempts,
    required this.solved,
    required this.revealedCount,
  });

  final int attempts;
  final bool solved;
  final int revealedCount;

  /// Matches the 5 attempt-marker dots in the mockup, and
  /// firestore.rules' own cap on the `guesses` subcollection.
  static const maxAttempts = 5;

  static const initial = GuessProgress(
    attempts: 0,
    solved: false,
    revealedCount: 0,
  );

  bool get isOutOfAttempts => !solved && attempts >= maxAttempts;

  /// Solved or given up — either way, no longer part of "N drawings left".
  bool get isDone => solved || isOutOfAttempts;

  factory GuessProgress.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    if (data == null) return initial;
    return GuessProgress(
      attempts: (data['attempts'] as num?)?.toInt() ?? 0,
      solved: data['solved'] as bool? ?? false,
      revealedCount: (data['revealedCount'] as num?)?.toInt() ?? 0,
    );
  }
}
