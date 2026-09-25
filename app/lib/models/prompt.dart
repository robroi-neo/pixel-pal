import 'package:cloud_firestore/cloud_firestore.dart';

enum PromptDifficulty {
  easy('Easy'),
  medium('Medium'),
  hard('Hard');

  const PromptDifficulty(this.label);
  final String label;

  static PromptDifficulty fromString(String value) => switch (value) {
    'medium' => PromptDifficulty.medium,
    'hard' => PromptDifficulty.hard,
    _ => PromptDifficulty.easy,
  };
}

/// A word to draw, as read from the global `prompts` collection.
///
/// Implementations.md's real design has a 300–500 word bundle, tiered and
/// categorized, issued per room via an `issuePrompts` callable with a
/// no-reroll rule enforced server-side (Phase 3, the round engine — not
/// built yet). For now this just reads the shared pool directly and picks
/// randomly client-side — see `services/prompt_service.dart`.
class Prompt {
  const Prompt({
    required this.id,
    required this.word,
    required this.difficulty,
    required this.multiplier,
  });

  final String id;
  final String word;
  final PromptDifficulty difficulty;
  final double multiplier;

  factory Prompt.fromDoc(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    return Prompt(
      id: doc.id,
      word: (data['word'] as String?) ?? '',
      difficulty: PromptDifficulty.fromString(
        (data['difficulty'] as String?) ?? 'easy',
      ),
      multiplier: (data['multiplier'] as num?)?.toDouble() ?? 1.0,
    );
  }
}
