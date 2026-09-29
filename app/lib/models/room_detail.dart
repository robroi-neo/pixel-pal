import 'package:cloud_firestore/cloud_firestore.dart';

/// The full `rooms/{roomId}` document — everything [RoomSummary] leaves
/// out because the room list doesn't need it (the invite code, raw
/// member count, ownership). Used by the per-room screen.
class RoomDetail {
  const RoomDetail({
    required this.id,
    required this.name,
    required this.code,
    required this.ownerUid,
    required this.ownerDisplayName,
    required this.memberCount,
    required this.memberUids,
    required this.memberPreview,
    required this.canvasSize,
    required this.roundLengthHours,
    required this.roundEndsAt,
    this.currentRound,
  });

  final String id;
  final String name;
  final String code;
  final String ownerUid;
  final String ownerDisplayName;
  final int memberCount;

  /// In join order, owner first.
  final List<String> memberUids;

  /// Initials copied at join time — only a fallback now; avatars render
  /// from each player's live profile via [memberUids].
  final List<String> memberPreview;
  final int canvasSize;
  final int roundLengthHours;

  /// The current round's deadline. Stamped when the owner starts round 1
  /// (a room sits in the lobby, null, until then), and moved on each time
  /// the room advances to its next round.
  final DateTime? roundEndsAt;

  /// 1, 2, 3, … with no end. Null in the lobby — and for rooms started
  /// before rounds existed (see [isLegacyRound]).
  final int? currentRound;

  bool isOwnedBy(String uid) => ownerUid == uid;

  /// Whether the owner has started round 1 yet — the lobby
  /// ([RoomScreen])/hub ([RoundHomeScreen]) split hinges on this.
  bool get isRoundStarted => roundEndsAt != null;

  /// Started before the round engine existed: a deadline but no round
  /// number, and its data in the old per-room layout. Can't advance.
  bool get isLegacyRound => roundEndsAt != null && currentRound == null;

  /// The current round's deadline has passed and the next round hasn't
  /// opened yet — a moment, until someone's app advances the room (see
  /// `RoundService.checkIn`). False when [roundEndsAt] is unknown.
  bool get isRoundLocked =>
      roundEndsAt != null && DateTime.now().isAfter(roundEndsAt!);

  /// The round whose drawings are up for guessing now — last round's.
  /// Null in round 1, which is draw-only.
  int? get guessRound {
    final n = currentRound;
    return n != null && n > 1 ? n - 1 : null;
  }

  /// Round [round]'s drawings can be guessed right now.
  bool isGuessingOpen(int round) => currentRound == round + 1 && !isRoundLocked;

  /// Round [round]'s guesses are revealed: the round it was guessed in
  /// has ended.
  bool isRevealed(int round) =>
      currentRound != null && currentRound! >= round + 2;

  /// The newest round with results out, or null before round 3.
  int? get latestResultsRound {
    final n = currentRound;
    return n != null && n > 2 ? n - 2 : null;
  }

  factory RoomDetail.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data()!;
    return RoomDetail(
      id: doc.id,
      name: (data['name'] as String?) ?? 'Untitled room',
      code: (data['code'] as String?) ?? '',
      ownerUid: (data['ownerUid'] as String?) ?? '',
      ownerDisplayName: (data['ownerDisplayName'] as String?) ?? 'the host',
      memberCount: (data['memberCount'] as num?)?.toInt() ?? 1,
      memberUids: List<String>.from(data['memberUids'] as List? ?? const []),
      memberPreview: List<String>.from(
        data['memberPreview'] as List? ?? const [],
      ),
      canvasSize: (data['canvasSize'] as num?)?.toInt() ?? 32,
      roundLengthHours: (data['roundLengthHours'] as num?)?.toInt() ?? 24,
      roundEndsAt: (data['roundEndsAt'] as Timestamp?)?.toDate(),
      currentRound: (data['currentRound'] as num?)?.toInt(),
    );
  }
}
