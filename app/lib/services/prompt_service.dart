import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/prompt.dart';

/// Reads from the global `prompts` pool. No per-room "issued prompts" or
/// no-reroll enforcement yet (Implementations.md Phase 3) — every call
/// just picks a fresh random sample from whatever's seeded, client-side.
/// See seed-prompts.js for how the pool gets populated on Spark (no
/// Cloud Function to do this server-side either).
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
}
