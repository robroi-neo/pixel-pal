import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../utils/pixel_codec.dart';

/// `profiles/{uid}` — the public half of a user: what other players see.
/// The one source of truth for a player's name and icon, read wherever a
/// uid is at hand, so a rename or a new icon shows up everywhere at once
/// — including on drawings made before it. (`users/{uid}` stays private:
/// it holds the email.)
class UserProfile {
  const UserProfile({required this.uid, required this.displayName, this.icon});

  static const iconSize = 16;
  static const minNameLength = 3;
  static const maxNameLength = 16;

  final String uid;
  final String displayName;

  /// 16×16, row-major. Null means "show my initial".
  final List<Color>? icon;

  factory UserProfile.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const {};
    return UserProfile(
      uid: doc.id,
      displayName: (data['displayName'] as String?) ?? '',
      icon: _decodeIcon(data['iconPixels']),
    );
  }

  /// Anything that isn't a well-formed 16×16 icon falls back to the
  /// initial rather than crashing a screen that happens to show it —
  /// rules bound the field's size, not its contents.
  static List<Color>? _decodeIcon(Object? raw) {
    if (raw is! String) return null;
    try {
      final pixels = PixelCodec.decode(raw);
      return pixels.length == iconSize * iconSize ? pixels : null;
    } catch (_) {
      return null;
    }
  }
}
