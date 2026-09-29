import 'guess_progress.dart';

/// The guessing-flow scoring, shown only at the deadline reveal:
///
/// - Per drawing: 100 / 80 / 60 / 40 / 20 by the attempt you solved it
///   on, times the drawing's difficulty multiplier. A miss is 0.
/// - Guessing half: the mean of those across the drawings you could guess.
/// - Drawing half: solvers ÷ eligible guessers × 100 × your multiplier.
/// - Round total: the two halves added.
///
/// Computed client-side from the guess docs — there's no server on Spark
/// to do it, and nothing here is stored.
class RoundScore {
  RoundScore._();

  static const attemptPoints = [100, 80, 60, 40, 20];

  static int guessPoints(GuessProgress? progress, double multiplier) {
    if (progress == null || !progress.solved) return 0;
    final attempt = progress.attempts.clamp(1, attemptPoints.length);
    return (attemptPoints[attempt - 1] * multiplier).round();
  }

  static int guessingHalf(List<int> points) {
    if (points.isEmpty) return 0;
    return (points.reduce((a, b) => a + b) / points.length).round();
  }

  static int drawingHalf({
    required int solvers,
    required int eligible,
    required double multiplier,
  }) {
    if (eligible == 0) return 0;
    return (solvers / eligible * 100 * multiplier).round();
  }
}
