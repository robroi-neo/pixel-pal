/**
 * DORMANT — not currently deployed. Cloud Functions (any generation)
 * require the Blaze plan, and this project stays on Spark for now (see
 * CLAUDE.md). The `createRoom`/`joinRoom`/`onUserCreated` logic below
 * currently lives client-side instead — see
 * app/lib/services/room_service.dart and app/lib/services/auth_service.dart
 * — with firestore.rules doing what validation rules reasonably can in
 * place of trusted server code.
 *
 * This file is kept, still lint-clean, as the straightforward upgrade
 * path: when the project moves to Blaze, deploy this, tighten
 * firestore.rules back to "client never writes rooms/**", and delete the
 * client-side transaction logic it replaces.
 */

const {setGlobalOptions} = require("firebase-functions");
const {onCall, HttpsError} = require("firebase-functions/v2/https");
const functionsV1 = require("firebase-functions/v1");
const {initializeApp} = require("firebase-admin/app");
const {getFirestore, FieldValue} = require("firebase-admin/firestore");

initializeApp();
const db = getFirestore();

// For cost control, cap concurrent containers per function.
setGlobalOptions({maxInstances: 10});

// Excludes easily-confused characters (0/O, 1/I) — matches the client's
// placeholder generator in create_room_screen.dart, which this replaces.
const INVITE_CODE_CHARS = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
const INVITE_CODE_LENGTH = 6;
const MAX_CODE_ATTEMPTS = 5;

// Design.md's create-room mockup: "Rooms hold 2 to 8 players."
const MAX_MEMBERS = 8;

const CANVAS_SIZES = [16, 32, 64];
const ROUND_LENGTH_HOURS = [12, 24, 48];

// How many members to keep denormalized on the room doc for the room
// list's avatar stack, so the client can render it without a second read
// per room. `memberCount` (not this array's length) is the source of
// truth for "+N" overflow.
const MEMBER_PREVIEW_LIMIT = 4;

/**
 * A random 6-character invite code from `INVITE_CODE_CHARS`.
 * @return {string}
 */
function generateInviteCode() {
  let code = "";
  for (let i = 0; i < INVITE_CODE_LENGTH; i++) {
    code += INVITE_CODE_CHARS.charAt(
        Math.floor(Math.random() * INVITE_CODE_CHARS.length),
    );
  }
  return code;
}

/**
 * "MR", "J" — up to two initials from a display name, uppercased. Falls
 * back to "?" so a room never renders a blank avatar.
 * @param {string} name
 * @return {string}
 */
function initialsFor(name) {
  const parts = String(name || "").trim().split(/\s+/).filter(Boolean);
  if (parts.length === 0) return "?";
  const initials = parts.slice(0, 2).map((part) => part[0].toUpperCase());
  return initials.join("");
}

/**
 * The caller's `users/{uid}.displayName`, or a safe fallback.
 * @param {string} uid
 * @return {Promise<string>}
 */
async function getDisplayName(uid) {
  const snap = await db.collection("users").doc(uid).get();
  const data = snap.data() || {};
  return data.displayName || "Player";
}

/**
 * Creates `users/{uid}` the moment a Firebase Auth account exists —
 * covers email/password registration and Google sign-in alike, so the
 * client never has to remember a separate "first sign-in" write.
 */
exports.onUserCreated = functionsV1.auth.user().onCreate(async (user) => {
  await db.collection("users").doc(user.uid).set({
    displayName: user.displayName || null,
    email: user.email || null,
    photoUrl: user.photoURL || null,
    createdAt: FieldValue.serverTimestamp(),
  });
});

/**
 * Creates a room, its owner membership, and a unique invite code in one
 * transaction. The client never writes rooms/** directly — see
 * Implementations.md "Standing rules".
 */
exports.createRoom = onCall(async (request) => {
  const uid = request.auth && request.auth.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "Sign in to create a room.");
  }

  const data = request.data || {};
  const name = String(data.name || "").trim();
  const canvasSize = Number(data.canvasSize);
  const roundLengthHours = Number(data.roundLengthHours);

  if (!name) {
    throw new HttpsError("invalid-argument", "Room name is required.");
  }
  if (!CANVAS_SIZES.includes(canvasSize)) {
    throw new HttpsError("invalid-argument", "Invalid canvas size.");
  }
  if (!ROUND_LENGTH_HOURS.includes(roundLengthHours)) {
    throw new HttpsError("invalid-argument", "Invalid round length.");
  }

  const displayName = await getDisplayName(uid);
  const roomRef = db.collection("rooms").doc();

  for (let attempt = 0; attempt < MAX_CODE_ATTEMPTS; attempt++) {
    const code = generateInviteCode();
    const codeRef = db.collection("roomCodes").doc(code);

    try {
      // eslint-disable-next-line no-await-in-loop
      await db.runTransaction(async (tx) => {
        const codeSnap = await tx.get(codeRef);
        if (codeSnap.exists) {
          // Not a Firestore write conflict, so the transaction isn't
          // retried by the SDK — caught below to retry with a new code.
          throw new Error("CODE_TAKEN");
        }

        tx.set(codeRef, {
          roomId: roomRef.id,
          createdAt: FieldValue.serverTimestamp(),
        });
        tx.set(roomRef, {
          name,
          code,
          canvasSize,
          roundLengthHours,
          ownerUid: uid,
          memberCount: 1,
          memberUids: [uid],
          memberPreview: [initialsFor(displayName)],
          createdAt: FieldValue.serverTimestamp(),
        });
        tx.set(roomRef.collection("members").doc(uid), {
          displayName,
          role: "owner",
          status: "active",
          joinedAt: FieldValue.serverTimestamp(),
        });
      });

      return {roomId: roomRef.id, code};
    } catch (err) {
      const collided = err instanceof Error && err.message === "CODE_TAKEN";
      if (collided && attempt < MAX_CODE_ATTEMPTS - 1) {
        continue;
      }
      throw new HttpsError("internal", "Could not create the room. Try again.");
    }
  }

  // Unreachable — the loop above always returns or throws — but keeps the
  // function's return type honest without an explicit `return` after it.
  throw new HttpsError("internal", "Could not create the room. Try again.");
});

/**
 * Joins an existing room by its invite code.
 */
exports.joinRoom = onCall(async (request) => {
  const uid = request.auth && request.auth.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "Sign in to join a room.");
  }

  const code = String((request.data && request.data.code) || "")
      .trim()
      .toUpperCase();
  if (code.length !== INVITE_CODE_LENGTH) {
    throw new HttpsError("invalid-argument", "Enter the full code.");
  }

  const displayName = await getDisplayName(uid);
  const codeRef = db.collection("roomCodes").doc(code);

  return db.runTransaction(async (tx) => {
    const codeSnap = await tx.get(codeRef);
    if (!codeSnap.exists) {
      throw new HttpsError("not-found", "That code doesn't match a room.");
    }

    const roomId = codeSnap.data().roomId;
    const roomRef = db.collection("rooms").doc(roomId);
    const roomSnap = await tx.get(roomRef);
    if (!roomSnap.exists) {
      throw new HttpsError("not-found", "That room no longer exists.");
    }

    const room = roomSnap.data();
    const memberUids = room.memberUids || [];

    if (memberUids.includes(uid)) {
      return {roomId, roomName: room.name};
    }
    if (memberUids.length >= MAX_MEMBERS) {
      throw new HttpsError("failed-precondition", "This room is full.");
    }

    tx.set(roomRef.collection("members").doc(uid), {
      displayName,
      role: "member",
      status: "active",
      joinedAt: FieldValue.serverTimestamp(),
    });

    const update = {
      memberCount: FieldValue.increment(1),
      memberUids: FieldValue.arrayUnion(uid),
    };
    const preview = room.memberPreview || [];
    if (preview.length < MEMBER_PREVIEW_LIMIT) {
      update.memberPreview = FieldValue.arrayUnion(initialsFor(displayName));
    }
    tx.update(roomRef, update);

    return {roomId, roomName: room.name};
  });
});
