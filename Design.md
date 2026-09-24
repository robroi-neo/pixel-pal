# Pixel Guess — Design

Companion to `plan.md`. Mechanics live there; this is visual direction only.

> **Status: direction resolved.** Direction B is committed. Eight screens have been prototyped end to end (sign in → room list → round home → prompt pick → editor → guess → reveal → leaderboard). This document now describes what the prototype settled, what it exposed, and what is still open.

---

## 1. Direction

**Committed: Direction B — the loud reference.**

Yellow and black throughout, thick borders, hard offset shadows, chunky display type. The app looks like a game, not a productivity tool.

Direction A (quiet chrome, loud moments) stays rejected. Its mockup read as a banking app: clean, safe, no personality. Two of the five mood board references are deliberately loud, and Direction A talked that half out of existence. The reasoning is kept in §9 so it isn't re-litigated from scratch.

The three risks recorded against Direction B were real, and two of them are now answered:

| Risk | Status |
|---|---|
| Heavy chrome competes with the pixel art | **Solved** — see the three-layer rule in §4 |
| Saturated backgrounds shift perceived pixel colour | **Solved** — the art never borders yellow |
| Hard to keep coherent across ~12 screens | **Partly** — eight screens hold. The editor is the strain point (§7) |

---

## 2. Tokens

Fixed values. These are the app's palette, not a theme — see §4 on what does and does not respond to mode.

### Surfaces

| Token | Value | Use |
|---|---|---|
| `ink` | `#17171A` | Every border, all body text, filled buttons, avatars |
| `yellow` | `#FFC93C` | Screen background, everywhere |
| `cream` | `#FFF6DC` | Band behind artwork; secondary/settled card fill |
| `white` | `#FFFFFF` | Card fill |
| `canvas` | `#E9E7E0` | **Locked.** Empty pixel, in every mode, forever |
| `grey` | `#8A8A94` | Inactive and vacation avatars only |
| `error` | `#8A2B2B` | Inline form validation text only — never a deadline, never a score |

`error` is the single near-red value in the system. It appears when a field is empty on submit and nowhere else. Deadlines and failures do not use it (§4).

### Structure

- Border: `3px solid ink` on cards, buttons, tiles, tools, swatches. `2px` on chips and small pills.
- Shadow: `4px 4px 0 ink`. Hard offset, never blurred. **Shadow means "this needs you"** — see §4.
- Radius: cards `14px`, buttons and tools `10–11px`, tiles and swatches `5px`, chips `999px`, phone screen `22px`.

### Type

| Role | Face | Weights |
|---|---|---|
| Display | Space Grotesk | 700, tracking `-0.02em` |
| UI | Plus Jakarta Sans | 400 / 500 / 600 |
| Score numerals only | Silkscreen | 400 |

Scale in use: screen title 25–30, card title 16–19, body 13–14, secondary 12, chip 11, caption 10.

All three available via `google_fonts`.

---

## 3. Components

| Component | Spec |
|---|---|
| **Chip** | `2px` ink border, `999px` radius, 11px/600. White fill = neutral. Ink fill with yellow text = attention (deadline under 12h, difficulty, active state) |
| **Card** | White fill, `3px` ink border, `14px` radius. Shadow only when the card is the thing to act on |
| **Letter tile** | 33×40, white fill, `3px` border, `5px` radius, Space Grotesk 700 at 19px. Solved state inverts to ink fill |
| **Attempt marker** | 11px dot, `2px` ink border. Filled = spent, hollow = remaining |
| **Primary button** | Full width, ink fill, yellow text, Space Grotesk 700 at 16px. One per screen |
| **Secondary action** | Underlined text link, 13px/600. Not a button — keeps the single-primary rule honest |
| **Avatar** | 22–31px circle, ink fill, yellow initials. Grey fill when inactive or on vacation |
| **Canvas frame** | Cream band → white card (`3px` border) → locked `canvas` fill → pixel grid. Never fewer than these layers |

---

## 4. Principles

These are constraints from the medium and the product promise, not style preferences. The first six carry over unchanged; the last three came out of prototyping.

### The UI must not be pixelated

The pixel art is the only pixelated thing on screen. No 8-bit fonts, no retro borders. Thick black borders and hard offset shadows carry the game feeling without a single pixel letterform.

One exception: **score numerals only** use Silkscreen. Ranks, points, multipliers. Nothing else — not timers, not counts, not labels.

### The canvas ignores the app theme

The card holding a drawing can be soft and rounded. The canvas inside it is hard-edged, square, and sits on `canvas` (`#E9E7E0`), which does not respond to light/dark mode, ever. A drawing made against a light background and viewed against a dark one falls apart.

The reveal screen proves the rule: chrome flips to near-black, the canvas does not move at all.

### The art never borders yellow — three layers minimum

New, and the answer to the "chrome competes with the art" risk. The artwork is fenced off from the saturated chrome rather than the chrome being quietened:

```
yellow screen → cream band → white card (3px ink border) → locked canvas → pixels
```

No tinted or gradient background ever sits directly behind artwork. Corollary: **no artwork on a room card or list row without the full frame.** If there isn't room for the frame, don't show the art.

### Deadlines are never red

Neutral above 12h, attention below 12h, never red at any point. The attention state is a chip inversion — ink fill, yellow text — not a colour shift. Red says panic; the promise is that nobody has to hurry.

### No score preview before submitting

No "solve now for 60 points". Attempt markers communicate remaining value without turning every guess into arithmetic.

### Difficulty is public

Shown on the drawing while guessing and again at reveal, where it explains the drawer's score. It changes how charitably guessers read an ambiguous image, and makes the reveal legible instead of mysterious.

### Progress replaces the timer

`4 of 7 drawings left this round`, `3 of 7 done`. Segmented bars, not countdowns.

### Shadow is a call to action, not decoration

New. In a system where everything already has a heavy border, the offset shadow is the only remaining emphasis axis. Reserve it: the card that needs you gets the shadow, settled cards go flat. On the room list this stacks with chip fill and card tint, so the one room needing attention is obvious with no badge count and no red.

### The palette may not sit on raw yellow

New, from the editor. A fixed 16-colour palette has to contain a yellow, and it sits a few shades from the app background. Colour-selection UI goes on cream, and the selection indicator is an ink inset tick — not a yellow ring, which is ambiguous on the yellow swatch.

---

## 5. Screen inventory

| Screen | Status | Notes |
|---|---|---|
| Sign in | **Prototyped** | Pixel-art mark, wordmark, Google primary / email secondary |
| Room list | **Prototyped** | Card stack, three room states |
| Round home (hub) | **Prototyped** | Single primary action |
| Prompt pick | **Prototyped** | Three cards, selection state, no-reroll stated on screen |
| Draw / editor | **Prototyped, interactive** | Pencil, fill, eraser, undo, zoom + pan, 16 swatches, thumbnail |
| Guess | **Prototyped, interactive** | Letter tiles, attempt markers, fuzzy submit |
| Reveal | **Prototyped, sequenced** | Four stages, star given here |
| Leaderboard | **Prototyped** | Mean round score, stars as separate column |
| Create / join room | Not designed | |
| Room settings | Not designed | Canvas size, round length, member management |
| Round 1 onboarding | Not designed | A new room has no Round N-1, so round 1 is draw-only |
| Gallery / log | Deferred to post-v1 | |

### Screen notes

**Sign in.** The only pixel art outside a canvas frame is the app mark, which is a logo, not user artwork. Tagline carries the premise: unhurried, low-stakes.

**Room list.** Three states, each encoded three ways (chip / shadow / tint): needs you, all in and waiting, paused. No member scores — this is a to-do list, not a scoreboard. Rooms already dealt with stay visible but flatten.

**Round home.** One primary button; the other route is a text link. Two task cards (drawing, guessing) with the unstarted one carrying the shadow. Current rank sits at the bottom as a quiet line, not a card.

**Prompt pick.** Difficulty multipliers in Silkscreen. The no-swap rule is stated on screen — the server rejects unoffered prompt IDs, and silent rejection would read as a bug.

**Guess.** Drawer avatar and difficulty above the art; category chip, attempt markers and letter tiles below. Tiles show word length from attempt 1 and reveal one letter per wrong guess. Solved state inverts the tiles and locks the input.

**Reveal.** Sequenced, not tabulated, in four stages: the word → who solved it and on which attempt → your two score halves and total → the leaderboard shift. Chrome goes near-black for the payoff. Stars are given here. Ends on the next round's deadline, which is the habit hook.

**Editor.** Prompt and difficulty in the header so the drawer never loses the brief. Tool row, 16-swatch palette, thumbnail preview at gallery size. Zoom swaps the 32×32 canvas for a 16×16 window with four pan controls — at 32×32 a pixel is roughly 8 logical px on a phone, which is below a usable tap target, so zoom is not optional. Submit validates that the canvas isn't empty.

**Leaderboard.** Ranked on mean round score, with the round count stated so late joiners understand the ranking. Stars are a separate column and never touch the score. Vacation and inactive states are tinted and grey-avatared, not hidden.

---

## 6. Dark mode

Deferred past v1, and cheaper than it looks: the canvas is locked either way, and the reveal screen already demonstrates dark chrome with the art untouched. The work is inverting yellow/ink across the other seven screens, not re-solving any principle.

Revisit after the palette question in §7 is settled, since the swatch grid is the one surface where an inverted background changes the answer.

---

## 7. What prototyping exposed

**The editor is roughly 70% chrome by area.** Every other screen has a large quiet region — the art, the word, the score — that gives the loud treatment something to frame. The editor has no such region, so borders and shadows stack up. It holds, but it is the screen that breaks first if the treatment is pushed harder. Any future increase in weight gets tested here before anywhere else.

**The palette clash is the concrete form of the chrome risk.** It showed up in tool chrome, not in the drawing. Fix recorded as a principle in §4; the swatch grid still needs a proper pass.

**Avatars were cut from the guess screen entirely.** The open question offered greyed avatars as a middle path, but on a saturated background any avatar row reads as a scoreboard, which is exactly the "everyone else already did this" pressure the question was trying to avoid. Nothing is shown. Revisit only if playtesters report the round feeling lonely.

**No mascot.** The borders and display type already carry the voice; a character on top tips it from confident into busy. This is the decision most likely to be reversed — it is hard to retrofit, so if it is coming back it should come back before v1 polish, not after.

---

## 8. Open decisions

- [ ] Swatch grid treatment — cream surround and inset tick are specified, not yet mocked
- [ ] One drawing per screen, or a scrollable feed? Prototype assumes one-at-a-time with auto-advance
- [ ] Create/join, settings, and round-1 onboarding screens
- [ ] Empty and error states across the app — nothing is designed, and with no mascot they are pure typography
- [ ] Push notification copy and tone — the one surface outside the app that has to sound like it
- [ ] Whether the room list should show a drawing thumbnail at all, given the three-layer frame rule

## 9. Rejected, recorded

**Direction A — quiet chrome, loud moments.** Everyday UI in minimal white, with yellow-black reserved for the reveal, leaderboard and badges. Rationale at the time: loud material means more if rationed, and quiet chrome supports the unhurried premise. Rejected because the mockup read as a banking app, and because rationing the loud half is effectively deleting it.

**Image 1's lavender wash.** Tinted backgrounds behind artwork shift perceived pixel colour. Rejected outright; now generalised into the three-layer rule.

**Red deadline states.** Never considered seriously, recorded so nobody adds one under pressure at polish time.