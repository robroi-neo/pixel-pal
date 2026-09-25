/**
 * Seeds a handful of realistic dummy rooms straight into the real
 * Firestore project (via the Admin SDK, which bypasses firestore.rules
 * entirely) — a quick way to check the create-room data shape end to end
 * and to have varied rooms to look at in the app without clicking through
 * the "New room" form by hand every time.
 *
 * Caveat: every seeded room's `memberUids` only ever contains the one
 * real UID you pass in (there's no second real account to add). The
 * "N players" numbers and avatar initials on each preset are cosmetic —
 * `memberCount`/`memberPreview` are set directly to look realistic in the
 * UI, not backed by real memberships. Good for checking the room
 * list/detail screens render correctly; not a test of joinRoom with
 * multiple accounts.
 *
 * Setup (once):
 *   1. Firebase Console -> Project settings -> Service accounts ->
 *      Generate new private key. Save the JSON somewhere OUTSIDE the repo
 *      (it's a real credential — do not commit it).
 *   2. cd firebase/scripts && npm install
 *
 * Run:
 *   GOOGLE_APPLICATION_CREDENTIALS=/path/to/key.json node seed-rooms.js --uid=<your-uid>
 *
 * Find your UID: Firebase Console -> Authentication -> Users, or log
 * `FirebaseAuth.instance.currentUser?.uid` from the running app.
 *
 * Remove what this seeds:
 *   GOOGLE_APPLICATION_CREDENTIALS=/path/to/key.json node seed-rooms.js --uid=<your-uid> --clear
 */

const admin = require("firebase-admin");

const SEED_TAG = "dev-seed"; // marks seeded rooms so --clear only touches these.
const INVITE_CODE_CHARS = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"; // no 0/O/1/I
const INVITE_CODE_LENGTH = 6;

const PRESETS = [
  {
    name: "Pixel pals",
    canvasSize: 32,
    roundLengthHours: 24,
    hoursFromNow: 18, // matches Design.md's "18h left" mockup exactly
    memberCount: 5,
    memberPreview: ["MR", "JS", "PF", "TK"],
  },
  {
    name: "Office doodles",
    canvasSize: 32,
    roundLengthHours: 12,
    hoursFromNow: 2,
    memberCount: 8, // deliberately full — exercises the "8 of 8" join state
    memberPreview: ["DN", "SH", "RK", "LY"],
  },
  {
    name: "Sunday sketch club",
    canvasSize: 64,
    roundLengthHours: 48,
    hoursFromNow: 40,
    memberCount: 2,
    memberPreview: ["AL"],
  },
  {
    name: "Late night lineart",
    canvasSize: 16,
    roundLengthHours: 12,
    hoursFromNow: -1, // already past — exercises the "locked" state
    memberCount: 1, // just the owner — exercises the empty-room state
    memberPreview: [],
  },
  {
    name: "Study break doodles",
    canvasSize: 32,
    roundLengthHours: 24,
    hoursFromNow: 6,
    memberCount: 3,
    memberPreview: ["EV", "QN"],
  },
];

function parseArgs() {
  const args = Object.fromEntries(
      process.argv.slice(2).map((arg) => {
        const [key, value] = arg.replace(/^--/, "").split("=");
        return [key, value === undefined ? true : value];
      }),
  );
  return args;
}

function randomCode() {
  let code = "";
  for (let i = 0; i < INVITE_CODE_LENGTH; i++) {
    code += INVITE_CODE_CHARS.charAt(
        Math.floor(Math.random() * INVITE_CODE_CHARS.length),
    );
  }
  return code;
}

async function uniqueCode(db) {
  for (let attempt = 0; attempt < 10; attempt++) {
    const code = randomCode();
    const snap = await db.collection("roomCodes").doc(code).get();
    if (!snap.exists) return code;
  }
  throw new Error("Could not find a free invite code after 10 attempts.");
}

async function seed(db, ownerUid) {
  const ownerSnap = await db.collection("users").doc(ownerUid).get();
  const ownerDisplayName =
    (ownerSnap.exists && ownerSnap.data().displayName) || "Player";

  console.log(`Seeding as ${ownerDisplayName} (${ownerUid})...\n`);

  for (const preset of PRESETS) {
    const code = await uniqueCode(db);
    const roomRef = db.collection("rooms").doc();

    await db.runTransaction(async (tx) => {
      tx.set(db.collection("roomCodes").doc(code), {
        roomId: roomRef.id,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      tx.set(roomRef, {
        name: preset.name,
        code,
        canvasSize: preset.canvasSize,
        roundLengthHours: preset.roundLengthHours,
        roundEndsAt: admin.firestore.Timestamp.fromDate(
            new Date(Date.now() + preset.hoursFromNow * 3600 * 1000),
        ),
        ownerUid,
        ownerDisplayName,
        memberCount: preset.memberCount,
        memberUids: [ownerUid],
        memberPreview: preset.memberPreview,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        seedTag: SEED_TAG,
      });
      tx.set(roomRef.collection("members").doc(ownerUid), {
        displayName: ownerDisplayName,
        role: "owner",
        status: "active",
        joinedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    });

    console.log(`  ${preset.name.padEnd(22)} code ${code}  room ${roomRef.id}`);
  }

  console.log("\nDone.");
}

async function clear(db, ownerUid) {
  const snap = await db
      .collection("rooms")
      .where("ownerUid", "==", ownerUid)
      .where("seedTag", "==", SEED_TAG)
      .get();

  if (snap.empty) {
    console.log("Nothing to clear.");
    return;
  }

  console.log(`Removing ${snap.size} seeded room(s)...`);
  for (const doc of snap.docs) {
    const {code} = doc.data();
    const batch = db.batch();
    batch.delete(doc.ref.collection("members").doc(ownerUid));
    batch.delete(doc.ref);
    if (code) batch.delete(db.collection("roomCodes").doc(code));
    await batch.commit();
    console.log(`  removed ${doc.data().name} (${code})`);
  }
  console.log("Done.");
}

async function main() {
  const args = parseArgs();
  if (!args.uid || args.uid === true) {
    console.error(
        "Usage: node seed-rooms.js --uid=<your-uid> [--clear]\n" +
        "Find your UID in Firebase Console -> Authentication -> Users.",
    );
    process.exitCode = 1;
    return;
  }

  admin.initializeApp();
  const db = admin.firestore();

  if (args.clear) {
    await clear(db, args.uid);
  } else {
    await seed(db, args.uid);
  }
}

main().catch((err) => {
  console.error(err);
  process.exitCode = 1;
});
