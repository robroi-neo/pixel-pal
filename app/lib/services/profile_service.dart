import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/user_profile.dart';
import '../utils/initials.dart';
import '../utils/pixel_codec.dart';

/// Thrown by [ProfileService] with copy that's already safe to show the
/// user — same pattern as the app's other `*ServiceException` types.
class ProfileServiceException implements Exception {
  ProfileServiceException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Reads and writes `profiles/{uid}`. Written by the client itself (Spark
/// — no Cloud Function), and firestore.rules only lets you write your own.
class ProfileService {
  ProfileService({FirebaseFirestore? firestore, FirebaseAuth? auth})
    : _firestore = firestore ?? FirebaseFirestore.instance,
      _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  DocumentReference<Map<String, dynamic>> _ref(String uid) =>
      _firestore.collection('profiles').doc(uid);

  /// Null while the profile doc doesn't exist yet (a player who hasn't
  /// opened the app since profiles shipped) — callers fall back to the
  /// name copied onto the room/drawing.
  Stream<UserProfile?> watch(String uid) => _ref(
    uid,
  ).snapshots().map((doc) => doc.exists ? UserProfile.fromDoc(doc) : null);

  /// Creates the signed-in user's profile from their account name if it
  /// doesn't exist yet, and returns it either way. Safe to call on every
  /// app open.
  Future<UserProfile> ensureOwnProfile() async {
    final user = _auth.currentUser;
    if (user == null) {
      throw ProfileServiceException('Sign in to see your profile.');
    }
    try {
      final ref = _ref(user.uid);
      final existing = await ref.get();
      if (existing.exists) return UserProfile.fromDoc(existing);

      var name = displayNameOr(user.displayName);
      if (name.length > UserProfile.maxNameLength) {
        name = name.substring(0, UserProfile.maxNameLength).trim();
      }
      await ref.set({
        'displayName': name,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      return UserProfile(uid: user.uid, displayName: name);
    } on FirebaseException {
      throw ProfileServiceException("Couldn't load your profile — try again.");
    }
  }

  /// Also updates the account's own display name, so the copies written
  /// into new rooms/drawings from now on start from the new name too (and
  /// `users/{uid}` picks it up on the next sign-in).
  Future<void> saveDisplayName(String name) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw ProfileServiceException('Sign in to change your name.');
    }
    final trimmed = name.trim();
    try {
      await _ref(user.uid).update({
        'displayName': trimmed,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } on FirebaseException {
      throw ProfileServiceException("Couldn't save your name — try again.");
    }
    try {
      await user.updateDisplayName(trimmed);
    } on FirebaseAuthException {
      // Non-fatal: the profile — what everyone actually sees — is saved.
    }
  }

  Future<void> saveIcon(List<Color> pixels) =>
      _updateIcon(PixelCodec.encode(pixels));

  /// "Go back to my initial".
  Future<void> clearIcon() => _updateIcon(FieldValue.delete());

  Future<void> _updateIcon(Object value) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw ProfileServiceException('Sign in to change your icon.');
    }
    try {
      await _ref(user.uid).update({
        'iconPixels': value,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } on FirebaseException {
      throw ProfileServiceException("Couldn't save your icon — try again.");
    }
  }
}
