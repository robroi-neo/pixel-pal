/// What a code resolves to before actually joining — the join sheet shows
/// this preview and lets the user confirm, rather than joining outright
/// the moment a code matches. Round tracking doesn't exist yet
/// (Implementations.md Phase 3), so [subtitle]-style copy elsewhere can't
/// reference a real round number — only what's actually tracked today.
class RoomPreview {
  const RoomPreview({
    required this.roomId,
    required this.name,
    required this.ownerDisplayName,
    required this.memberCount,
    required this.memberPreview,
    required this.canvasSize,
    required this.roundLengthHours,
  });

  final String roomId;
  final String name;
  final String ownerDisplayName;
  final int memberCount;
  final List<String> memberPreview;
  final int canvasSize;
  final int roundLengthHours;
}

/// What `RoomService.previewRoomByCode` found — a sealed result so the
/// join sheet's UI is a straightforward `switch`, one case per outcome
/// shown in the mockup (matched / full / already a member / not found).
sealed class RoomLookupResult {
  const RoomLookupResult();
}

class RoomLookupNotFound extends RoomLookupResult {
  const RoomLookupNotFound();
}

class RoomLookupJoinable extends RoomLookupResult {
  const RoomLookupJoinable(this.preview);
  final RoomPreview preview;
}

class RoomLookupFull extends RoomLookupResult {
  const RoomLookupFull(this.preview);
  final RoomPreview preview;
}

class RoomLookupAlreadyMember extends RoomLookupResult {
  const RoomLookupAlreadyMember(this.preview);
  final RoomPreview preview;
}
