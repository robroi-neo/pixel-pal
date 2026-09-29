import 'package:cloud_firestore/cloud_firestore.dart';

/// One round, `rooms/{roomId}/rounds/{n}`. Rounds run back to back with
/// no end: while round n is the room's current round, members draw round
/// n's prompts and guess round n−1's drawings, and round n−1's results
/// land when round n ends (see `RoundService`).
class RoundInfo {
  const RoundInfo({
    required this.number,
    required this.deadline,
    required this.requiredUids,
    required this.doneUids,
    this.closedAt,
    this.closeReason,
  });

  final int number;
  final DateTime? deadline;

  /// Who the round waits for before it can close early — everyone in the
  /// room when it opened, minus anyone who's left since. Players who join
  /// mid-round start counting from the next one.
  final List<String> requiredUids;

  /// The [requiredUids] who are done: drawing submitted and every card
  /// from last round finished. Append-only.
  final List<String> doneUids;

  /// Set by whoever advanced the room past this round.
  final DateTime? closedAt;

  /// `'deadline'` or `'allDone'` (everyone finished early).
  final String? closeReason;

  bool get closedEarly => closeReason == 'allDone';

  factory RoundInfo.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const {};
    return RoundInfo(
      number: (data['number'] as num?)?.toInt() ?? int.tryParse(doc.id) ?? 0,
      deadline: (data['deadline'] as Timestamp?)?.toDate(),
      requiredUids: List<String>.from(
        data['requiredUids'] as List? ?? const [],
      ),
      doneUids: List<String>.from(data['doneUids'] as List? ?? const []),
      closedAt: (data['closedAt'] as Timestamp?)?.toDate(),
      closeReason: data['closeReason'] as String?,
    );
  }
}
