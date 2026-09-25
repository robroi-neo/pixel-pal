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
  final int memberCount;
  final List<String> memberPreview;
  final int canvasSize;
  final int roundLengthHours;

  /// Computed client-side at creation (no Cloud Function to stamp it
  /// authoritatively — Spark, see CLAUDE.md), and there's no round engine
  /// to advance it (Implementations.md Phase 3), so this is really "round
  /// 1 ends at" rather than a rolling per-round deadline. Null for rooms
  /// created before this field existed.
  final DateTime? roundEndsAt;

  bool isOwnedBy(String uid) => ownerUid == uid;

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
