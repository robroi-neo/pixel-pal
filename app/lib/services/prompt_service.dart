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

  // Session-lifetime cache, shared by every PromptService instance — the
  // pool only ever changes via the seeder script, never from inside a
  // running app, so one collection read per app run covers both
  // [pickRandom] and [getByIds]. Implementations.md's real design
  // (300-500 prompts) would need this to be smarter (paged/queried, not
  // held whole in memory) — revisit once the pool is actually that large.
  static List<Prompt>? _poolCache;

  Future<List<Prompt>> _pool() async {
    final cached = _poolCache;
    if (cached != null) return cached;
    // The pool is small for now (a handful of seeded docs), so fetching
    // it all and sampling/filtering client-side is simplest.
    final snapshot = await _firestore.collection('prompts').get();
    return _poolCache = snapshot.docs.map(Prompt.fromDoc).toList();
  }

  Future<List<Prompt>> pickRandom({int count = 3}) async {
    final shuffled = List<Prompt>.from(await _pool())..shuffle(Random());
    return shuffled.take(count).toList();
  }

  /// Re-fetches specific prompts by id, in the given order, silently
  /// dropping any that no longer exist (e.g. removed from the pool after
  /// being issued to someone). Served from the same cached pool as
  /// [pickRandom] rather than one read per id.
  Future<List<Prompt>> getByIds(List<String> ids) async {
    final byId = {for (final p in await _pool()) p.id: p};
    return ids.map((id) => byId[id]).whereType<Prompt>().toList();
  }
}
