import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/drawing_submission.dart';
import '../models/prompt.dart';
import '../utils/initials.dart';
import '../utils/pixel_codec.dart';

/// Thrown by [DrawingService] with copy that's already safe to show the
/// user — same pattern as [AuthException]/[RoomServiceException].
class DrawingServiceException implements Exception {
  DrawingServiceException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Submits to `rooms/{roomId}/drawings/{uid}` — one drawing per member
/// per room (Implementations.md's real per-round scoping doesn't exist
/// yet — Phase 3). firestore.rules makes this genuinely submit-once: a
/// resubmit is a Firestore `update` (the doc already exists), and the
/// rules refuse all updates outright, matching Implementations.md's
/// "submitDrawing() callable, called exactly once" even without a
/// callable to enforce it.
class DrawingService {
  DrawingService({FirebaseFirestore? firestore, FirebaseAuth? auth})
    : _firestore = firestore ?? FirebaseFirestore.instance,
      _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  DocumentReference<Map<String, dynamic>> _ref(String roomId, String uid) =>
      _firestore
          .collection('rooms')
          .doc(roomId)
          .collection('drawings')
          .doc(uid);

  /// Live — so the editor can notice a drawing already exists (e.g. the
  /// screen was reopened after submitting) without a manual refresh.
  Stream<bool> watchHasSubmitted(String roomId) {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return Stream.value(false);
    return _ref(roomId, uid).snapshots().map((doc) => doc.exists);
  }

  /// Every drawing submitted in this room *except* the caller's own — the
  /// pool the guess screen picks from. Small rooms (max 8 members), so
  /// reading the whole subcollection and filtering client-side is simpler
  /// than trying to query around "not mine" in Firestore.
  Stream<List<DrawingSubmission>> watchOthersDrawings(String roomId) {
    final uid = _auth.currentUser?.uid;
    return _firestore
        .collection('rooms')
        .doc(roomId)
        .collection('drawings')
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .where((doc) => doc.id != uid)
              .map(DrawingSubmission.fromDoc)
              .toList(),
        );
  }

  /// How many drawings exist in this room, including the caller's own —
  /// for naming the cost of deleting it. A server-side count aggregate,
  /// so it doesn't download the drawings themselves.
  Future<int> countDrawings(String roomId) async {
    final snapshot = await _firestore
        .collection('rooms')
        .doc(roomId)
        .collection('drawings')
        .count()
        .get();
    return snapshot.count ?? 0;
  }

  Future<void> submitDrawing({
    required String roomId,
    required Prompt prompt,
    required int canvasSize,
    required List<Color> pixels,
  }) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw DrawingServiceException('Sign in to submit a drawing.');
    }
    if (PixelCodec.isEmpty(pixels)) {
      throw DrawingServiceException('Draw something before submitting.');
    }

    try {
      await _ref(roomId, user.uid).set({
        'authorUid': user.uid,
        'authorDisplayName': displayNameOr(user.displayName),
        'promptId': prompt.id,
        'word': prompt.word,
        'category': prompt.category,
        'difficulty': prompt.difficulty.name,
        'multiplier': prompt.multiplier,
        'canvasSize': canvasSize,
        'packedPixels': PixelCodec.encode(pixels),
        'submittedAt': FieldValue.serverTimestamp(),
      });
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') {
        throw DrawingServiceException(
          "Couldn't submit — you may have already submitted, or you're "
          "not a member of this room.",
        );
      }
      throw DrawingServiceException(
        "Couldn't submit your drawing — try again.",
      );
    }
  }
}
