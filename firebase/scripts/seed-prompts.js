/**
 * Seeds the global `prompts` pool with 10 dummy words — enough to try the
 * prompt-pick screen (services/prompt_service.dart picks 3 at random from
 * whatever's in this collection). Implementations.md's real design calls
 * for 300-500 prompts, tiered/categorized, issued per room server-side —
 * this is just enough to see the UI work end to end, not that system.
 *
 * Setup (once): same as seed-rooms.js — a service account key, then
 * `cd firebase/scripts && npm install` (already done if you ran that
 * seeder before).
 *
 * Run:
 *   GOOGLE_APPLICATION_CREDENTIALS=/path/to/key.json node seed-prompts.js
 *
 * Remove what this seeds:
 *   GOOGLE_APPLICATION_CREDENTIALS=/path/to/key.json node seed-prompts.js --clear
 */

const admin = require("firebase-admin");

const SEED_TAG = "dev-seed";

// Multipliers match difficulty 1:1 for this dummy set, per the mockup
// (×1.0 / ×1.4 / ×1.8). The real system would vary multiplier within a
// difficulty tier too — not modeled here.
const MULTIPLIER_BY_DIFFICULTY = {
  easy: 1.0,
  medium: 1.4,
  hard: 1.8,
};

const WORDS = [
  ["apple", "easy"],
  ["umbrella", "easy"],
  ["cactus", "easy"],
  ["sandwich", "easy"],
  ["lighthouse", "medium"],
  ["bicycle", "medium"],
  ["telescope", "medium"],
  ["carnival", "hard"],
  ["orchestra", "hard"],
  ["avalanche", "hard"],
];

function parseArgs() {
  return Object.fromEntries(
      process.argv.slice(2).map((arg) => {
        const [key, value] = arg.replace(/^--/, "").split("=");
        return [key, value === undefined ? true : value];
      }),
  );
}

async function seed(db) {
  console.log(`Seeding ${WORDS.length} prompts...\n`);

  const batch = db.batch();
  for (const [word, difficulty] of WORDS) {
    const ref = db.collection("prompts").doc();
    batch.set(ref, {
      word,
      difficulty,
      multiplier: MULTIPLIER_BY_DIFFICULTY[difficulty],
      seedTag: SEED_TAG,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    console.log(`  ${word.padEnd(12)} ${difficulty.padEnd(8)} x${MULTIPLIER_BY_DIFFICULTY[difficulty]}`);
  }
  await batch.commit();

  console.log("\nDone.");
}

async function clear(db) {
  const snap = await db
      .collection("prompts")
      .where("seedTag", "==", SEED_TAG)
      .get();

  if (snap.empty) {
    console.log("Nothing to clear.");
    return;
  }

  console.log(`Removing ${snap.size} seeded prompt(s)...`);
  const batch = db.batch();
  for (const doc of snap.docs) batch.delete(doc.ref);
  await batch.commit();
  console.log("Done.");
}

async function main() {
  const args = parseArgs();
  admin.initializeApp();
  const db = admin.firestore();

  if (args.clear) {
    await clear(db);
  } else {
    await seed(db);
  }
}

main().catch((err) => {
  console.error(err);
  process.exitCode = 1;
});
