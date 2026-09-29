import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../utils/pixel_codec.dart';
import 'prompt.dart';

/// A submitted drawing, as read from `rooms/{roomId}/drawings/{authorUid}`
/// — one per member per room (there's no round to scope it to yet;
/// Implementations.md Phase 3). Word/category/difficulty/multiplier and
/// the author's initials are all denormalized at submission time so
/// reading a drawing later (the guess screen) doesn't need extra lookups
/// into `prompts` or the author's `members` doc.
///
/// The word being readable here at all — by any room member, not just the
/// author (see firestore.rules) — is a real, known trade-off: guessing
/// needs to render someone else's drawing, and Spark has no trusted
/// server (a Cloud Function) to compare a guess against a hidden answer
/// without exposing it to *someone*. The app's own UI never displays this
/// field directly during guessing, but a technically curious player could
/// read it straight from Firestore. Implementations.md's real design
/// avoids this via `private/answer`, admin-SDK-only; that needs Blaze.
class DrawingSubmission {
  const DrawingSubmission({
    required this.authorUid,
    required this.authorDisplayName,
    required this.promptId,
    required this.word,
    required this.category,
    required this.difficulty,
    required this.multiplier,
    required this.canvasSize,
    required this.packedPixels,
  });

  final String authorUid;
  final String authorDisplayName;
  final String promptId;
  final String word;
  final String category;
  final PromptDifficulty difficulty;
  final double multiplier;
  final int canvasSize;
  final String packedPixels;

  List<Color> get pixels => PixelCodec.decode(packedPixels);

  factory DrawingSubmission.fromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? const {};
    return DrawingSubmission(
      authorUid: (data['authorUid'] as String?) ?? '',
      authorDisplayName: (data['authorDisplayName'] as String?) ?? 'Player',
      promptId: (data['promptId'] as String?) ?? '',
      word: (data['word'] as String?) ?? '',
      category: (data['category'] as String?) ?? '',
      difficulty: PromptDifficulty.fromString(
        (data['difficulty'] as String?) ?? 'easy',
      ),
      multiplier: (data['multiplier'] as num?)?.toDouble() ?? 1.0,
      canvasSize: (data['canvasSize'] as num?)?.toInt() ?? 32,
      packedPixels: (data['packedPixels'] as String?) ?? '',
    );
  }
}
