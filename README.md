# Pixel Guess

**An unhurried pixel-art drawing and guessing game for a small group of friends.**

Everyone gets two small jobs a round: draw one prompt on a tiny pixel canvas, and guess what everyone else drew last round. Play whenever you're free. When the round's deadline passes, or everyone's done early, the results land and the next round begins. Rounds roll on, one after another, with no end.

Built with Flutter and Firebase on the free **Spark** plan, with no Cloud Functions.

<!--
  HERO GIF — a short loop of one round: hub → draw → guess → reveal.
  Replace the line below with:
  <p align="center"><img src="docs/media/hero.gif" alt="Pixel Guess gameplay" width="320"></p>
-->
<p align="center"><em>[ Hero GIF goes here ]</em></p>

---

## Screenshots

<!--
  Drop images into docs/media/ and replace each placeholder cell with, e.g.:
  <img src="docs/media/hub.png" alt="Round hub" width="240">
-->

| Room list | Round hub | Prompt pick |
|:---:|:---:|:---:|
| _[ screenshot ]_ | _[ screenshot ]_ | _[ screenshot ]_ |
| **Pixel editor** | **Guess card** | **Result card** |
| _[ screenshot ]_ | _[ screenshot ]_ | _[ screenshot ]_ |
| **Reveal** | **Your round score** | **Leaderboard** |
| _[ screenshot ]_ | _[ screenshot ]_ | _[ screenshot ]_ |

### In motion

<!-- Replace each placeholder with <img src="docs/media/<name>.gif" alt="..." width="240"> -->

| Round start | Swiping guess cards | Card flip & reveal |
|:---:|:---:|:---:|
| _[ GIF ]_ | _[ GIF ]_ | _[ GIF ]_ |

---

## How it plays

Each round has two halves that run at the same time:

| While round **N** is open | |
|---|---|
| ✏️ **Draw** | Pick one of 3 prompts and draw it on a 16×16 or 32×32 canvas. |
| 🔍 **Guess** | Guess the drawings from round **N − 1**, one card at a time. |

- **Round 1 is draw-only.** There's nothing to guess yet.
- **Guessing.** You see the category and word length. You get 5 tries, and every miss flips in one more letter. Who drew it stays hidden until you finish the card.
- **The reveal.** When round N ends, round N − 1's results open for everyone at once: who solved each drawing and on which try, your round score, and the table. You can give a star to drawings you loved; stars never affect the score.
- **Deadlines.** Rounds last 12h or 24h. If everyone finishes early, the round closes early and the next one starts straight away with its full length.

### Scoring

- **Guessing half:** 100 / 80 / 60 / 40 / 20 points for solving on try 1–5, times the drawing's difficulty (easy ×1.0, medium ×1.4, hard ×1.8). This is averaged across every drawing you could guess, so small and large rooms compare fairly.
- **Drawing half:** the share of players who solved your drawing × 100 × your prompt's difficulty.
- **Round score** = guessing half + drawing half. The leaderboard ranks your **average** round score. Skipped rounds count as 0.

The full maths, with a worked example, is also in the app: **⋯ → How to play**.

---

## Features

- **Rooms:** create a room (2–8 players), or join with a 6-character invite code.
- **Continuous rounds:** rounds advance by themselves, with early close when everyone's done.
- **Pixel editor:** pencil, fill and eraser tools, undo, a fixed 16-colour palette, and a gallery-size preview.
- **Swipeable guess cards:** letter hints, attempt dots, and cards that flip over to show the result.
- **Results reveal:** played as a sequence, ending with your round score and rank change.
- **Leaderboard:** season averages or a single round, a podium, and a "most starred" card.
- **Profiles:** a display name plus a 16×16 pixel-art avatar you draw yourself.
- **Sign-in:** email/password or Google.
- **Help:** a short "How to play" walkthrough in every room.

---

## Tech stack

| | |
|---|---|
| App | Flutter (Dart ≥ 3.12), `go_router`, `google_fonts` |
| Auth | Firebase Authentication (email/password, Google) |
| Data | Cloud Firestore |
| Backend logic | Firestore Security Rules; no server code |

### Why no backend?

The project stays on Firebase's free **Spark** plan, which has no Cloud Functions. So the app does the work a server normally would, and `firestore.rules` checks every write:

- **Round engine.** There's no scheduler. The first player's app to find a round over moves the room on, in a single transaction the rules validate field by field.
- **Scoring.** Each round is scored once by whichever app gets there first, then stored, so the leaderboard reads one or two documents instead of every round.
- **Trade-offs**, accepted knowingly and documented in the code:
  - A player who reads Firestore directly could see a drawing's word.
  - Scores are computed client-side.
  - "Done" for early close is client-asserted.

---

## Project structure

```
asynch-pixel/
├── app/                      Flutter app
│   └── lib/
│       ├── models/           Firestore document models (rooms, rounds, drawings, scores…)
│       ├── services/         Firestore/Auth access — rooms, rounds, drawings, guesses, scores
│       ├── screens/          auth · rooms · round · guess · leaderboard · profile · help
│       ├── widgets/          Shared UI (pixel editor/canvas, sheets, chips, snackbars…)
│       ├── theme/            Design tokens: colours, palette, spacing, type
│       ├── router/           go_router routes and the auth gate
│       └── utils/            Pixel codec, seeded ordering, helpers
├── firebase/
│   ├── firestore.rules       All the game's server-side enforcement
│   └── scripts/              Dev seeding scripts (prompt pool)
├── Design.md                 Visual direction and design principles
└── Implementations.md        Implementation plan
```

---

## Getting started

### Prerequisites

- [Flutter](https://docs.flutter.dev/get-started/install) (stable channel, Dart ≥ 3.12)
- [Firebase CLI](https://firebase.google.com/docs/cli) and a Firebase project (Spark is enough)
- Node.js, for the seed script

### 1. Connect your Firebase project

The repo ships with the original project's client config. To use your own:

```bash
dart pub global activate flutterfire_cli
cd app
flutterfire configure        # regenerates lib/firebase_options.dart and platform configs
```

In the Firebase console, enable the **Email/Password** and **Google** sign-in providers.

### 2. Deploy the security rules

```bash
cd firebase
firebase use <your-project-id>
firebase deploy --only firestore:rules
```

### 3. Seed the prompt pool

Download a service-account key from **Project settings → Service accounts**. Keep it out of git; the repo's `.gitignore` already covers `*-firebase-adminsdk-*.json`.

```bash
cd firebase/scripts
npm install
GOOGLE_APPLICATION_CREDENTIALS=/path/to/key.json npm run seed-prompts
```

### 4. Run the app

```bash
cd app
flutter pub get
flutter run
```

---

## Design

The visual direction is in [`Design.md`](Design.md): yellow and ink throughout, thick borders, and hard offset shadows. A few principles carry through the app:

- The pixel art is the only pixelated thing on screen.
- Deadlines are never red.
- A shadow means "this needs you".
