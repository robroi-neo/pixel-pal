import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/prompt.dart';

/// Reads from the global `prompts` pool. See seed-prompts.js for how the
/// pool gets populated on Spark (no Cloud Function to do this
/// server-side). Which 3 a given member is actually offered, and keeping
/// that stable across visits, is `RoomService.getIssuedPromptIds` /
/// `setIssuedPromptIds`'s job, not this service's — this just knows how
/// to pick and how to re-fetch by id.
class PromptService {
  PromptService({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  Future<List<Prompt>> pickRandom({int count = 3}) async {
    // The pool is small for now (a handful of seeded docs), so fetching
    // it all and sampling client-side is simplest. Implementations.md's
    // real design (300-500 prompts) would need a smarter query — revisit
    // once the pool is actually that large.
    final snapshot = await _firestore.collection('prompts').get();
    final prompts = snapshot.docs.map(Prompt.fromDoc).toList()..shuffle(Random());
    return prompts.take(count).toList();
  }

  /// Re-fetches specific prompts by id, in the given order, silently
  /// dropping any that no longer exist (e.g. removed from the pool after
  /// being issued to someone).
  Future<List<Prompt>> getByIds(List<String> ids) async {
    final docs = await Future.wait(
      ids.map((id) => _firestore.collection('prompts').doc(id).get()),
    );
    return docs.where((doc) => doc.exists).map(Prompt.fromDoc).toList();
  }
}
