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
    required this.memberPreview,
    required this.canvasSize,
    required this.roundLengthHours,
    required this.roundEndsAt,
  });

  final String id;
  final String name;
  final String code;
  final String ownerUid;
  final String ownerDisplayName;
  final int memberCount;
  final List<String> memberPreview;
  final int canvasSize;
  final int roundLengthHours;

  /// Stamped by [RoomService.startRound], not at room creation — a room
  /// sits in the lobby (null) until the owner explicitly starts round 1.
  /// Null for rooms created before this field existed.
  final DateTime? roundEndsAt;

  bool isOwnedBy(String uid) => ownerUid == uid;

  /// Whether the owner has started round 1 yet — the lobby
  /// ([RoomScreen])/hub ([RoundHomeScreen]) split hinges on this.
  bool get isRoundStarted => roundEndsAt != null;

  /// False (never locked) when [roundEndsAt] is unknown — an absent
  /// deadline isn't the same as a passed one.
  bool get isRoundLocked =>
      roundEndsAt != null && DateTime.now().isAfter(roundEndsAt!);

  factory RoomDetail.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data()!;
    return RoomDetail(
      id: doc.id,
      name: (data['name'] as String?) ?? 'Untitled room',
      code: (data['code'] as String?) ?? '',
      ownerUid: (data['ownerUid'] as String?) ?? '',
      ownerDisplayName: (data['ownerDisplayName'] as String?) ?? 'the host',
      memberCount: (data['memberCount'] as num?)?.toInt() ?? 1,
      memberPreview: List<String>.from(
        data['memberPreview'] as List? ?? const [],
      ),
      canvasSize: (data['canvasSize'] as num?)?.toInt() ?? 32,
      roundLengthHours: (data['roundLengthHours'] as num?)?.toInt() ?? 24,
      roundEndsAt: (data['roundEndsAt'] as Timestamp?)?.toDate(),
    );
  }
}
