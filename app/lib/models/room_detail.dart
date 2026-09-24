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
  });

  final String id;
  final String name;
  final String code;
  final String ownerUid;
  final int memberCount;
  final List<String> memberPreview;
  final int canvasSize;
  final int roundLengthHours;

  bool isOwnedBy(String uid) => ownerUid == uid;

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
    );
  }
}
