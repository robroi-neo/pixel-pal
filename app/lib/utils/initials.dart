/// "MR", "J", "?" — up to two initials from a display name, uppercased.
/// Mirrors `initialsFor` in firebase/functions/index.js (dormant on Spark,
/// kept for when the app moves that logic server-side on Blaze).
String initialsFor(String? name) {
  final parts = (name ?? '').trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
  if (parts.isEmpty) return '?';
  return parts.take(2).map((p) => p[0].toUpperCase()).join();
}

/// [name] if it's non-empty, else a safe fallback for display/storage
/// where a blank string wouldn't make sense (e.g. a room member's name).
String displayNameOr(String? name, {String fallback = 'Player'}) {
  final trimmed = (name ?? '').trim();
  return trimmed.isEmpty ? fallback : trimmed;
}
