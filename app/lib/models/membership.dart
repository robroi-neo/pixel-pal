import 'package:cloud_firestore/cloud_firestore.dart';

/// What the signed-in player has already seen in a room, from their own
/// `rooms/{roomId}/members/{uid}` doc. Drives the one-time moments: the
/// round-start takeover on the hub, and the "NEW" on a results banner.
class Membership {
  const Membership({required this.seenRound, required this.seenResultsRound});

  /// The last round whose start the player has been shown. 0 = none yet.
  final int seenRound;

  /// The last round whose results the player has opened. 0 = none yet.
  final int seenResultsRound;

  static const none = Membership(seenRound: 0, seenResultsRound: 0);

  factory Membership.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const {};
    return Membership(
      seenRound: (data['seenRound'] as num?)?.toInt() ?? 0,
      seenResultsRound: (data['seenResultsRound'] as num?)?.toInt() ?? 0,
    );
  }
}
