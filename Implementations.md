# Pixel Guess — Implementation Plan

Companion to `plan.md` (mechanics, architecture) and `design.md` (visual direction).
Flutter + Firebase, solo developer.

Estimates are padded well beyond first instinct. Every number here is roughly 1.5–2× the naive one, because the naive one has never once been right.

> **Total: 29–43 weeks.** Call it 7–10 months full-time, or 14–18 months at nights and weekends.

---

## What the prototype does and does not give you

The HTML prototype is a specification, not a head start. Nothing in it ports.

| Transfers | Doesn't |
|---|---|
| Token values, spacing, type scale | Any line of code |
| Screen flow and state transitions | The editor — Flutter needs `CustomPainter`, not DOM nodes |
| Copy, button labels, empty-state wording | Layout — flex/grid assumptions don't map to Flutter |
| The fuzzy-match rules, proven against real input | Matching runs server-side in the real app, not on device |
| Scoring formulas, checked against real play | Scoring lives in a Cloud Function reading `config/scoring` |

Treat it as the thing you check your build against, and keep it open while you work.

---

## Phase order and why

The two long poles are the **editor** (client) and the **round engine** (server). They're independent, so if you stall on one you can move to the other — but both must land before anything can be played end to end.

```
0 skeleton ─┬─> 1 auth/rooms ─┬─> 2 editor ──┐
            │                 └─> 3 engine ──┼─> 4 guess/reveal ─> 5 board ─> 6 push ─> 7 polish
            └─ design system ────────────────┘
```

Phase 7 is not a buffer. It is the phase where playtesting changes the numbers in `config/scoring`, and it is the most commonly under-budgeted phase in projects like this.

---

## Phase 0 — Skeleton and design system
**2–3 weeks**

The whole app is built from about eight components. Build them once, properly, before building any screen.

- Flutter project, dev/prod flavors, two Firebase projects, Blaze on both
- `google_fonts` wired for Space Grotesk, Plus Jakarta Sans, Silkscreen
- `ThemeData` carrying the tokens from `design.md` §2
- Components: chip, card (raised/flat), primary button, text link, letter tile, attempt marker, avatar, and the canvas frame
- The canvas frame is the important one: it enforces the three-layer rule structurally so no screen can accidentally put artwork on yellow
- Golden tests on each component, light mode only for now

**Done when:** sign in and room list render natively from static data and are indistinguishable from the prototype at a glance.

**Risk:** skipping this and styling screens ad hoc. Twelve screens of inline styling is how the direction drifts.

---

## Phase 1 — Auth, rooms, join codes
**3–5 weeks**

- Google auth and email registration, `users/{uid}` write on first sign-in
- `createRoom` and `joinRoom` callables — the client never writes `rooms/**`
- `roomCodes/{CODE}` top-level lookup, collision handling on generation
- Security rules for `users`, `roomCodes`, `rooms`, `rooms/**/members`
- Screens: sign in, room list, create room, join by code, room settings
- Room settings needs canvas size, round length, and member removal — none of it is in the prototype

**Done when:** two accounts on two physical devices are members of the same room, and the rules deny a direct client write to every path.

**Risk:** email verification and account recovery are quietly a week on their own. They're in the estimate; don't spend them elsewhere.

---

## Phase 2 — Pixel editor
**5–8 weeks**

The longest client phase, and the one the prototype most under-represents.

- Packed-nibble codec and base64 encode/decode, with `canvasSize` stored on the drawing document
- `CustomPainter` canvas with pointer handling that survives fast drags
- Pencil, flood fill, eraser, undo/redo with a bounded history
- **Real pinch zoom and pan.** The prototype's zoom button is a stand-in; a 32×32 pixel is roughly 8 logical px on a phone, so this is not optional and gesture conflicts with drawing are the hard part
- Fixed 16-colour palette on cream, inset-tick selection indicator (`design.md` §4)
- Live preview at gallery size
- Local drafts in Hive or `sqflite` — no autosave to Firestore, ever
- `submitDrawing()` callable, called exactly once

**Done when:** you can draw, force-quit, reopen, and find the draft intact; and a round-trip through the codec is byte-identical at all three canvas sizes.

**Risk:** gesture arbitration between draw and pinch. Budget a week for it alone and test on a small phone, not a simulator.

---

## Phase 3 — Round engine and Cloud Functions
**5–7 weeks**

The longest server phase and where the hidden complexity actually lives.

- Full Firestore model per `plan.md` §4.1
- Prompt bundle: **300–500 minimum**, categorised and tiered, with per-room seeded shuffle and a Firestore override collection
- Callables: `issuePrompts`, `submitDrawing`, `submitGuess`
- `private/answer` locked to `if false`, written and read by Admin SDK only
- Security rules for every nested path — rules do not cascade, and a missing `match` block is the classic leak
- Cloud Scheduler sweep every 15 minutes: collection-group query on `(status, deadline)`, then one batch write per room
- Scoring in the function, reading `config/scoring` — never hardcoded in Flutter
- Composite indexes created early, not when a query first fails in production

**Done when:** a round opens, closes, scores, reveals, and opens the next one with nobody watching; and emulator tests reproduce the worked examples in `plan.md` §3.6 exactly.

**Risk:** the batch write at reveal touches drawings, guesses, members, and the round doc for every room simultaneously. Test it with eight players and seven drawings before trusting it.

---

## Phase 4 — Guess and reveal flow
**4–6 weeks**

- Guess screen: category, letter tiles, attempt markers, drawer and difficulty
- Hint state comes from the server response, never computed on device
- Sequenced reveal, one drawing at a time, then your two halves, then the board
- Stars given at reveal
- The states the prototype doesn't have: loading, offline, a guess submitted while the round closes underneath you, a drawing that failed to load

**Done when:** three people play a full round end to end on real devices and the reveal matches what the function computed.

**Risk:** latency on `submitGuess`. Every guess is a round trip, and a slow one on the fifth attempt feels broken. Decide the optimistic-UI behaviour here, not in polish.

---

## Phase 5 — Leaderboard, drop-out, vacation
**3–4 weeks**

- Member aggregates maintained in the reveal batch
- Rank on mean round score, with `roundsCounted` visible so late joiners understand the ranking
- Missed round scores zero and still counts; three consecutive misses flags `inactive`
- Vacation mode removes rounds from the denominator entirely
- Owner can remove a member
- Stars as a separate column, never in the score

**Done when:** a member who skips three rounds, then takes a vacation, then returns, has a defensible number.

**Risk:** aggregate drift. Write a repair function now rather than discovering a wrong total in month six.

---

## Phase 6 — Notifications
**3–4 weeks**

An async game without push is a dead app, so this is not optional and not polish.

- FCM token storage and refresh, multi-device
- **APNs certificates and Apple's provisioning.** This always takes longer than expected; that's why the estimate is what it is
- Three types: round closing soon, your drawing was guessed, results are in
- Deep links into the right room and round
- Quiet hours, and a per-room mute
- Copy matters — it's the only surface outside the app that has to sound like the app

**Done when:** a scheduled round transition produces a push on a physical iPhone and a physical Android device, and tapping it lands on the reveal.

---

## Phase 7 — Polish, playtesting, submission
**7–10 weeks**

- Round 1 onboarding: a new room has no Round N-1, so round 1 is draw-only and needs its own screen
- Empty and error states across the app — with no mascot, these are pure typography and none are designed yet
- Accessibility: tap targets, contrast on yellow, screen reader labels, reduced motion on the reveal sequence
- Dark mode: ship or defer. The canvas is locked either way, so the cost is chrome only
- **Two weeks of real play with real friends**, then retune the decay curve in `config/scoring`. If scores bunch, steepen to 100/70/45/25/10 and leave the multipliers alone — they're load-bearing for the anti-cheat balance
- Report/flag flow for word-writing
- Store listing, screenshots, privacy labels, review cycles

**Done when:** a room of five has played fourteen consecutive rounds without intervention and nobody has asked you what a number means.

---

## Schedule summary

| Phase | Weeks |
|---|---|
| 0 · Skeleton and design system | 2–3 |
| 1 · Auth, rooms, join codes | 3–5 |
| 2 · Pixel editor | 5–8 |
| 3 · Round engine and functions | 5–7 |
| 4 · Guess and reveal | 4–6 |
| 5 · Leaderboard and drop-out | 3–4 |
| 6 · Notifications | 3–4 |
| 7 · Polish, playtest, submission | 7–10 |
| **Total** | **29–43** |

---

## If it slips

Cut in this order. Everything here is already outside v1 in `plan.md` §7 or can be moved there without breaking the loop.

1. Dark mode — defer entirely
2. Stars — the reveal works without them, the gallery isn't in v1 anyway
3. 64×64 canvas — ship 16 and 32 only, which also removes the worst zoom cases
4. Room settings beyond canvas size and round length
5. Vacation mode — `inactive` flagging alone is survivable for one release

Do not cut push notifications, drop-out handling, or the two weeks of playtesting. The first two make the app dead on arrival, and the third is what makes the scoring defensible.

---

## Standing rules

- Tuning constants live in `config/scoring`, never in the app. Retuning must not wait on an App Store review.
- All game writes go through Cloud Functions. The client never writes `rooms/**`.
- Every nested Firestore path gets its own `match` block.
- Drafts stay on the device.
- The canvas background never changes value, in any phase, for any reason.