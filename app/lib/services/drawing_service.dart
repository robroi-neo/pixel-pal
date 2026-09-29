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

/// Submits to `rooms/{roomId}/rounds/{n}/drawings/{uid}` — one drawing
/// per member per round. firestore.rules makes this genuinely
/// submit-once (a resubmit is an update, always refused) and only while
/// round n is current and before its deadline.
class DrawingService {
  DrawingService({FirebaseFirestore? firestore, FirebaseAuth? auth})
    : _firestore = firestore ?? FirebaseFirestore.instance,
      _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  CollectionReference<Map<String, dynamic>> _drawings(
    String roomId,
    int round,
  ) => _firestore
      .collection('rooms')
      .doc(roomId)
      .collection('rounds')
      .doc('$round')
      .collection('drawings');

  /// Live — so the editor can notice a drawing already exists (e.g. the
  /// screen was reopened after submitting) without a manual refresh.
  Stream<bool> watchHasSubmitted(String roomId, int round) {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return Stream.value(false);
    return _drawings(
      roomId,
      round,
    ).doc(uid).snapshots().map((doc) => doc.exists);
  }

  /// Every drawing from [round] *except* the caller's own — the cards to
  /// guess. Readable once that round is over (see firestore.rules). Small
  /// rooms (max 8), so filtering client-side is simplest.
  Stream<List<DrawingSubmission>> watchOthersDrawings(
    String roomId,
    int round,
  ) {
    final uid = _auth.currentUser?.uid;
    return _drawings(roomId, round).snapshots().map(
      (snapshot) => snapshot.docs
          .where((doc) => doc.id != uid)
          .map(DrawingSubmission.fromDoc)
          .toList(),
    );
  }

  /// Every drawing from [round], the caller's own included — for the
  /// reveal.
  Stream<List<DrawingSubmission>> watchDrawings(String roomId, int round) {
    return _drawings(roomId, round).snapshots().map(
      (snapshot) => snapshot.docs.map(DrawingSubmission.fromDoc).toList(),
    );
  }

  Future<void> submitDrawing({
    required String roomId,
    required int round,
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
      await _drawings(roomId, round).doc(user.uid).set({
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
          "Couldn't submit — this round may have ended, or you've "
          'already submitted.',
        );
      }
      throw DrawingServiceException(
        "Couldn't submit your drawing — try again.",
      );
    }
  }
}
