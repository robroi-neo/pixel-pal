import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/room_detail.dart';
import '../models/room_lookup.dart';
import '../models/room_summary.dart';
import '../utils/initials.dart';

/// Thrown by [RoomService] with copy that's already safe to show the user
/// — same pattern as [AuthException] in services/auth_service.dart.
class RoomServiceException implements Exception {
  RoomServiceException(this.message);

  final String message;

  @override
  String toString() => message;
}

class CreatedRoom {
  const CreatedRoom({required this.roomId, required this.code});

  final String roomId;
  final String code;
}

class JoinedRoom {
  const JoinedRoom({required this.roomId, required this.roomName});

  final String roomId;
  final String roomName;
}

// Excludes easily-confused characters (0/O, 1/I).
const _inviteCodeChars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
const _inviteCodeLength = 6;
const _maxCodeAttempts = 5;

// Design.md's create-room mockup: "Rooms hold 2 to 8 players."
const _maxMembers = 8;

String _generateInviteCode(Random random) {
  return List.generate(
    _inviteCodeLength,
    (_) => _inviteCodeChars[random.nextInt(_inviteCodeChars.length)],
  ).join();
}

/// Creates and joins rooms directly against Firestore from the client.
///
/// Implementations.md's "Standing rules" call for this to go through
/// `createRoom`/`joinRoom` Cloud Functions callables instead — but Cloud
/// Functions (any generation) require the Blaze plan, and this project
/// stays on Spark (see CLAUDE.md). `firestore.rules` carries as much of
/// the validation a trusted server would have done as rules reasonably
/// can (ownership, field shape, one-member-at-a-time joins, the 8-player
/// cap) — see the comments there for what that can't fully cover (mainly:
/// a client could squat an invite code pointing at an unrelated room,
/// since rules can't cheaply cross-validate two documents written in the
/// same client transaction against each other).
class RoomService {
  RoomService({FirebaseFirestore? firestore, FirebaseAuth? auth})
    : _firestore = firestore ?? FirebaseFirestore.instance,
      _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  /// Rooms the given user is a member of, newest first. `memberUids` is
  /// denormalized onto each room doc specifically so this query — and the
  /// security rule that scopes it — can stay a single cheap read.
  Stream<List<RoomSummary>> watchMyRooms(String uid) {
    return _firestore
        .collection('rooms')
        .where('memberUids', arrayContains: uid)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => RoomSummary.fromDoc(doc, currentUid: uid))
              .toList(),
        );
  }

  /// A single room, live — for the per-room screen. Emits `null` if the
  /// room doesn't exist (or was deleted out from under the viewer).
  Stream<RoomDetail?> watchRoom(String roomId) {
    return _firestore
        .collection('rooms')
        .doc(roomId)
        .snapshots()
        .map((snapshot) => snapshot.exists ? RoomDetail.fromDoc(snapshot) : null);
  }

  Future<CreatedRoom> createRoom({
    required String name,
    required int canvasSize,
    required int roundLengthHours,
  }) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw RoomServiceException('Sign in to create a room.');
    }

    final displayName = displayNameOr(user.displayName);
    final roomRef = _firestore.collection('rooms').doc();
    final random = Random();

    for (var attempt = 0; attempt < _maxCodeAttempts; attempt++) {
      final code = _generateInviteCode(random);
      final codeRef = _firestore.collection('roomCodes').doc(code);

      try {
        await _firestore.runTransaction((tx) async {
          final codeSnap = await tx.get(codeRef);
          if (codeSnap.exists) {
            // Not a Firestore write conflict, so the SDK won't retry this
            // transaction on its own — caught below to try a new code.
            throw StateError('CODE_TAKEN');
          }

          tx.set(codeRef, {
            'roomId': roomRef.id,
            'createdAt': FieldValue.serverTimestamp(),
          });
          tx.set(roomRef, {
            'name': name,
            'code': code,
            'canvasSize': canvasSize,
            'roundLengthHours': roundLengthHours,
            // Computed from the client's own clock, not a Cloud Function
            // (Spark — see CLAUDE.md), so it's only as accurate as the
            // creator's device clock. There's no round engine to advance
            // this later (Implementations.md Phase 3), so it's really
            // "round 1 ends at" rather than a rolling deadline.
            'roundEndsAt': Timestamp.fromDate(
              DateTime.now().add(Duration(hours: roundLengthHours)),
            ),
            'ownerUid': user.uid,
            'ownerDisplayName': displayName,
            'memberCount': 1,
            'memberUids': [user.uid],
            'memberPreview': [initialsFor(displayName)],
            'createdAt': FieldValue.serverTimestamp(),
          });
          tx.set(roomRef.collection('members').doc(user.uid), {
            'displayName': displayName,
            'role': 'owner',
            'status': 'active',
            'joinedAt': FieldValue.serverTimestamp(),
          });
        });

        return CreatedRoom(roomId: roomRef.id, code: code);
      } on StateError catch (e) {
        if (e.message == 'CODE_TAKEN' && attempt < _maxCodeAttempts - 1) {
          continue;
        }
        throw RoomServiceException("Couldn't create the room — try again.");
      } on FirebaseException {
        throw RoomServiceException("Couldn't create the room — try again.");
      }
    }

    throw RoomServiceException("Couldn't create the room — try again.");
  }

  /// Read-only — resolves a code to a room and reports whether joining is
  /// actually possible, without joining yet. [joinRoom] re-checks
  /// everything fresh in its own transaction when the user confirms, so a
  /// stale preview (e.g. the room filled up in between) can't cause a bad
  /// write — it just fails there and the caller re-previews.
  Future<RoomLookupResult> previewRoomByCode(String rawCode) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw RoomServiceException('Sign in to join a room.');
    }

    final code = rawCode.trim().toUpperCase();
    if (code.length != _inviteCodeLength) {
      throw RoomServiceException('Enter the full 6-character code.');
    }

    try {
      final codeSnap = await _firestore.collection('roomCodes').doc(code).get();
      if (!codeSnap.exists) {
        return const RoomLookupNotFound();
      }

      final roomId = codeSnap.data()!['roomId'] as String;
      final roomSnap = await _firestore.collection('rooms').doc(roomId).get();
      if (!roomSnap.exists) {
        return const RoomLookupNotFound();
      }

      final data = roomSnap.data()!;
      final memberUids = List<String>.from(data['memberUids'] as List? ?? const []);
      final preview = RoomPreview(
        roomId: roomId,
        name: (data['name'] as String?) ?? 'Untitled room',
        ownerDisplayName: (data['ownerDisplayName'] as String?) ?? 'someone',
        memberCount: (data['memberCount'] as num?)?.toInt() ?? 1,
        memberPreview: List<String>.from(
          data['memberPreview'] as List? ?? const [],
        ),
        canvasSize: (data['canvasSize'] as num?)?.toInt() ?? 32,
        roundLengthHours: (data['roundLengthHours'] as num?)?.toInt() ?? 24,
      );

      if (memberUids.contains(user.uid)) {
        return RoomLookupAlreadyMember(preview);
      }
      if (memberUids.length >= _maxMembers) {
        return RoomLookupFull(preview);
      }
      return RoomLookupJoinable(preview);
    } on FirebaseException {
      throw RoomServiceException("Couldn't look up that code — try again.");
    }
  }

  Future<JoinedRoom> joinRoom(String rawCode) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw RoomServiceException('Sign in to join a room.');
    }

    final code = rawCode.trim().toUpperCase();
    if (code.length != _inviteCodeLength) {
      throw RoomServiceException('Enter the full 6-character code.');
    }

    final displayName = displayNameOr(user.displayName);
    final codeRef = _firestore.collection('roomCodes').doc(code);

    try {
      return await _firestore.runTransaction((tx) async {
        final codeSnap = await tx.get(codeRef);
        if (!codeSnap.exists) {
          throw RoomServiceException("That code doesn't match a room.");
        }

        final roomId = codeSnap.data()!['roomId'] as String;
        final roomRef = _firestore.collection('rooms').doc(roomId);
        final roomSnap = await tx.get(roomRef);
        if (!roomSnap.exists) {
          throw RoomServiceException('That room no longer exists.');
        }

        final room = roomSnap.data()!;
        final memberUids = List<String>.from(room['memberUids'] as List? ?? const []);

        if (memberUids.contains(user.uid)) {
          return JoinedRoom(roomId: roomId, roomName: room['name'] as String);
        }
        if (memberUids.length >= _maxMembers) {
          throw RoomServiceException('This room is full.');
        }

        tx.set(roomRef.collection('members').doc(user.uid), {
          'displayName': displayName,
          'role': 'member',
          'status': 'active',
          'joinedAt': FieldValue.serverTimestamp(),
        });

        final preview = List<String>.from(room['memberPreview'] as List? ?? const []);
        tx.update(roomRef, {
          'memberCount': FieldValue.increment(1),
          'memberUids': FieldValue.arrayUnion([user.uid]),
          if (preview.length < 4)
            'memberPreview': FieldValue.arrayUnion([initialsFor(displayName)]),
        });

        return JoinedRoom(roomId: roomId, roomName: room['name'] as String);
      });
    } on RoomServiceException {
      rethrow;
    } on FirebaseException {
      throw RoomServiceException("Couldn't join that room — try again.");
    }
  }

  /// Live version of [getIssuedPromptIds] — for a screen that should
  /// update the moment prompts are issued (e.g. round home's drawing
  /// status chip flipping right after prompt pick, without needing a
  /// manual refresh).
  Stream<List<String>?> watchIssuedPromptIds(String roomId, String uid) {
    return _firestore
        .collection('rooms')
        .doc(roomId)
        .collection('members')
        .doc(uid)
        .snapshots()
        .map((snapshot) {
          final ids = snapshot.data()?['issuedPromptIds'];
          return ids == null ? null : List<String>.from(ids as List);
        });
  }

  /// The prompt IDs already issued to this member for their current
  /// drawing, if any — null if [setIssuedPromptIds] hasn't been called
  /// yet. There's no real round engine to scope this per-round yet
  /// (Implementations.md Phase 3), so it's one persistent set per member.
  Future<List<String>?> getIssuedPromptIds(String roomId, String uid) async {
    final snapshot = await _firestore
        .collection('rooms')
        .doc(roomId)
        .collection('members')
        .doc(uid)
        .get();
    final ids = snapshot.data()?['issuedPromptIds'];
    return ids == null ? null : List<String>.from(ids as List);
  }

  /// Persists [promptIds] as this member's issued prompts. Succeeds only
  /// once — firestore.rules refuses the write once `issuedPromptIds`
  /// already exists on the doc, which is what actually enforces "no
  /// swapping once you start" rather than just claiming it on screen. A
  /// second call (e.g. a race) is swallowed rather than surfaced as an
  /// error — the caller should re-read via [getIssuedPromptIds] instead.
  Future<void> setIssuedPromptIds(
    String roomId,
    String uid,
    List<String> promptIds,
  ) async {
    try {
      await _firestore
          .collection('rooms')
          .doc(roomId)
          .collection('members')
          .doc(uid)
          .update({'issuedPromptIds': promptIds});
    } on FirebaseException catch (e) {
      if (e.code != 'permission-denied') rethrow;
    }
  }
}
