import 'dart:math';

/// FNV-1a, 32-bit. Dart's own `String.hashCode` isn't guaranteed to be the
/// same across runs or platforms, and these orders have to survive
/// reopening the app.
int stableHash(String input) {
  var hash = 0x811c9dc5;
  for (final unit in input.codeUnits) {
    hash ^= unit;
    hash = (hash * 0x01000193) & 0xffffffff;
  }
  return hash;
}

/// The guessing flow's card order: "seeded shuffle per player. Never by
/// author, uid or submit time". Each item's place depends only on
/// [seed] and its own id, so a drawing that arrives later slots in
/// without reshuffling the others.
List<T> seededOrder<T>(
  Iterable<T> items, {
  required String seed,
  required String Function(T item) idOf,
}) {
  int rank(T item) => stableHash('$seed:${idOf(item)}');
  return items.toList()..sort((a, b) {
    final byRank = rank(a).compareTo(rank(b));
    return byRank != 0 ? byRank : idOf(a).compareTo(idOf(b));
  });
}

/// Which letter each wrong guess flips in, as indices into [word]: first
/// letter, last letter, then the middle in an order fixed per word, so
/// the same tiles come back after reopening. Spaces are never hidden and
/// never part of the order.
List<int> letterHintOrder(String word) {
  final letters = [
    for (var i = 0; i < word.length; i++)
      if (word[i] != ' ') i,
  ];
  if (letters.length <= 2) return letters;
  final middle = letters.sublist(1, letters.length - 1)
    ..shuffle(Random(stableHash(word.toLowerCase())));
  return [letters.first, letters.last, ...middle];
}
