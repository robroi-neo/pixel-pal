# Voice expense tracker — style guide

Status: v1, based on the "Calm & trustworthy" direction
Companion docs: `plan.md` (architecture), `schedule.md` (timeline)

## Principles

- **Calm over alarming.** This app touches money every day — it should never feel like it's scolding the user. Reserve strong color for real signals (errors, over-budget), not routine spending.
- **Clarity over decoration.** Flat surfaces, low saturation, generous whitespace. The transcript and the numbers are the content — the UI should stay quiet around them.
- **Voice-first, not voice-only.** The record button is the most important control on screen. Everything else supports it.

## Color

Primary is teal. Blue is a secondary accent for links/info only. Gray carries structure. Warm colors (amber, red) are reserved for real semantic states, not everyday transactions.

### Primary — teal

| Token | Hex | Usage |
|---|---|---|
| `teal/50` | `#E1F5EE` | Icon chip backgrounds, subtle fills |
| `teal/100` | `#9FE1CB` | Hover/pressed fills |
| `teal/200` | `#5DCAA5` | Secondary accents, chart fills |
| `teal/400` | `#1D9E75` | Active states, selected tab |
| `teal/600` | `#0F6E56` | Primary buttons, mic button, links |
| `teal/800` | `#085041` | Text on teal/50–100 fills |
| `teal/900` | `#04342C` | Text on teal/200+ fills |

### Secondary — blue (info/links only)

| Token | Hex |
|---|---|
| `blue/50` | `#E6F1FB` |
| `blue/600` | `#185FA5` |
| `blue/800` | `#0C447C` |

### Neutral — gray (structure)

| Token | Hex | Usage |
|---|---|---|
| `gray/50` | `#F1EFE8` | App background |
| `gray/100` | `#D3D1C7` | Card borders, dividers |
| `gray/200` | `#B4B2A9` | Disabled fills |
| `gray/400` | `#888780` | Placeholder text, muted icons |
| `gray/600` | `#5F5E5A` | Secondary text |
| `gray/900` | `#2C2C2A` | Primary text |
| `white` | `#FFFFFF` | Cards, surfaces |

### Semantic (use sparingly)

| State | Hex | Usage |
|---|---|---|
| Income / positive | `teal/600` `#0F6E56` | Income amounts only |
| Expense / negative | `gray/900` `#2C2C2A` | **Not red.** Regular spending stays neutral — see rationale below |
| Warning | `amber/600` `#854F0B` on `amber/50` `#FAEEDA` | Over-budget, approaching limit |
| Error | `red/600` `#A32D2D` on `red/50` `#FCEBEB` | Failed save, malformed LLM output, network error |

**Rationale for not using red on expenses:** if every grocery run and jeepney fare renders in red, the whole feed reads as a wall of alarms and the color loses meaning by Day 2. Keep expenses neutral; save red for things that actually need attention (a failed sync, a budget breach). Income gets teal as positive reinforcement.

## Typography

Recommended: **Inter** (via `google_fonts` package), falls back to platform default (San Francisco / Roboto) if unavailable offline.

| Style | Size | Weight | Usage |
|---|---|---|---|
| Display | 28sp | 500 | Balance figure on home screen |
| Title | 20sp | 500 | Screen titles |
| Heading | 16sp | 500 | Section headers ("Recent", "This month") |
| Body | 14sp | 400 | Transaction labels, form values |
| Caption | 12sp | 400 | Timestamps, hints, subtext |
| Amount (list) | 15sp | 500 | Transaction row amounts |

Two weights only — 400 regular, 500 medium. No bold (700); it reads heavy against the flat surfaces.

Sentence case everywhere — buttons, headers, labels. Never Title Case or ALL CAPS.

## Spacing & shape

| Token | Value | Usage |
|---|---|---|
| `space/xs` | 4dp | Icon-to-label gap |
| `space/sm` | 8dp | Within a row |
| `space/md` | 12dp | Between rows |
| `space/lg` | 16dp | Card padding, screen margins |
| `space/xl` | 24dp | Between sections |
| `radius/control` | 8dp | Buttons, inputs, chips |
| `radius/card` | 12dp | Cards, sheets |
| Touch target | min 44x44dp | All tappable elements, especially the mic button |

## Components

**Mic / record button** — 56dp circle, `teal/600` fill, white icon, centered on the home screen and full-focus on the record screen. Only element allowed a filled (non-outline) treatment — everything else stays flat/outlined to keep the mic visually dominant.

**Transaction row** — 32dp icon chip (`teal/50` bg, `teal/800` icon) + label + muted subtext (merchant/date) + amount right-aligned. No card wrapper per row; rows separate with a 0.5dp `gray/100` hairline, not shadows.

**Buttons** — primary: `teal/600` fill, white text, `radius/control`. Secondary: transparent bg, `gray/100` border, `gray/900` text. Avoid more than one primary button per screen.

**Cards** — white surface, 0.5dp `gray/100` border, `radius/card`, `space/lg` padding. No drop shadows.

**Inputs** — 40dp height, `gray/100` border at rest, `teal/400` border on focus, `radius/control`.

**Category chips** — pill shape, `teal/50` bg, `teal/800` text, icon optional at 14sp.

## Iconography

Outline-style icons only (matches the flat aesthetic) — e.g. a Material Icons *outlined* set or `flutter_tabler_icons` for Flutter. 20dp standard, 24dp max for decorative use. Icons inherit `gray/600` by default; `teal/600` when indicating an active/selected state.

## Motion

Minimal and functional only: 150–200ms ease-out for screen transitions, mic button pulse (subtle scale, not color-flashing) while listening. No bouncy/overshoot easing — keep it calm.

## Accessibility

- Text contrast: body text meets WCAG AA against its surface (verify `gray/600` on white — currently ~4.6:1, passes at 14sp+).
- Never convey income/expense by color alone — the `+`/`-` sign carries the meaning too.
- Support system font scaling up to at least 130% without clipping the balance figure.
- Mic button never shrinks below the 44x44dp minimum touch target regardless of screen size.

## Voice & tone (copy)

- Sentence case, no exclamation marks, no "successfully" (the confirmation *is* the success — e.g. "Saved", not "Transaction saved successfully!").
- Errors say what happened and what to do next, plainly: "Couldn't save — check your connection and try again," not "Error: request failed."
- Empty states invite rather than apologize: "Record your first expense" over "No transactions yet."

## Dark mode

Not in MVP scope per `plan.md`, but if added later: invert the neutral ramp (`gray/900` background, `gray/50` text), keep `teal/400` (lighter, more saturated) as the dark-mode primary instead of `teal/600` for sufficient contrast, and keep expense text on `gray/100` rather than pure white.

## Flutter mapping (reference)

```dart
ColorScheme.light(
  primary: Color(0xFF0F6E56),      // teal/600
  onPrimary: Colors.white,
  surface: Colors.white,
  onSurface: Color(0xFF2C2C2A),    // gray/900
  background: Color(0xFFF1EFE8),   // gray/50
  error: Color(0xFFA32D2D),        // red/600
)
```
