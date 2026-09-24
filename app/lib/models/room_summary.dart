import 'package:cloud_firestore/cloud_firestore.dart';

/// Design.md §5 "Room list": three states, each encoded three ways (chip /
/// shadow / tint) — needs you, all in and waiting, paused.
///
/// Round tracking (deadlines, "needs you") doesn't exist server-side yet
/// (Implementations.md Phase 3, the round engine) — until then every real
/// room reads as [waiting]. See [RoomSummary.fromDoc].
enum RoomStatus { needsYou, waiting, paused }

/// A room list row, as read from `rooms/{roomId}`. The client only ever
/// reads this collection — creation and membership changes go through the
/// `createRoom`/`joinRoom` Cloud Functions callables (see
/// `services/room_service.dart`).
class RoomSummary {
  const RoomSummary({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.status,
    required this.isOwner,
    this.timeLabel,
    this.members = const [],
    this.overflowCount,
    this.footer,
  });

  final String id;
  final String title;
  final String subtitle;
  final RoomStatus status;

  /// Whether the current user is `ownerUid` on this room — surfaced as a
  /// mark on the room card, and gates whether tapping it opens the room
  /// screen (only built for the owner's view so far).
  final bool isOwner;

  /// e.g. "18h left" — null until the round engine exists to produce one.
  final String? timeLabel;

  /// Pre-computed initials, denormalized onto the room doc by the
  /// `createRoom`/`joinRoom` callables (`memberPreview`) so the room list
  /// doesn't need a second read per room.
  final List<String> members;

  /// `memberCount` minus how many are already in [members].
  final int? overflowCount;

  /// e.g. "draw · 4 to guess" — null until the round engine exists.
  final String? footer;

  factory RoomSummary.fromDoc(
    QueryDocumentSnapshot<Map<String, dynamic>> doc, {
    required String currentUid,
  }) {
    final data = doc.data();
    final memberCount = (data['memberCount'] as num?)?.toInt() ?? 1;
    final preview = List<String>.from(data['memberPreview'] as List? ?? const []);
    final overflow = memberCount - preview.length;

    return RoomSummary(
      id: doc.id,
      title: (data['name'] as String?) ?? 'Untitled room',
      subtitle:
          'Round 1 · $memberCount player${memberCount == 1 ? '' : 's'}',
      status: RoomStatus.waiting,
      isOwner: data['ownerUid'] == currentUid,
      members: preview,
      overflowCount: overflow > 0 ? overflow : null,
    );
  }
}
