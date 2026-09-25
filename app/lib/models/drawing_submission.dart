import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../utils/pixel_codec.dart';
import 'prompt.dart';

/// A submitted drawing, as read from `rooms/{roomId}/drawings/{authorUid}`
/// — one per member per room (there's no round to scope it to yet;
/// Implementations.md Phase 3). Word/difficulty/multiplier are
/// denormalized from the [Prompt] at submission time so reading a
/// drawing later (e.g. an eventual guess/reveal screen) doesn't need a
/// second lookup into `prompts`.
class DrawingSubmission {
  const DrawingSubmission({
    required this.authorUid,
    required this.promptId,
    required this.word,
    required this.difficulty,
    required this.multiplier,
    required this.canvasSize,
    required this.packedPixels,
  });

  final String authorUid;
  final String promptId;
  final String word;
  final PromptDifficulty difficulty;
  final double multiplier;
  final int canvasSize;
  final String packedPixels;

  List<Color> get pixels => PixelCodec.decode(packedPixels);

  factory DrawingSubmission.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const {};
    return DrawingSubmission(
      authorUid: (data['authorUid'] as String?) ?? '',
      promptId: (data['promptId'] as String?) ?? '',
      word: (data['word'] as String?) ?? '',
      difficulty: PromptDifficulty.fromString(
        (data['difficulty'] as String?) ?? 'easy',
      ),
      multiplier: (data['multiplier'] as num?)?.toDouble() ?? 1.0,
      canvasSize: (data['canvasSize'] as num?)?.toInt() ?? 32,
      packedPixels: (data['packedPixels'] as String?) ?? '',
    );
  }
}
