# Project Instructions
- Make Minimal changes unless stated otherwise.
- Ensure that any firebase modifications or any backend features can be done with only SPARK plan. I can accept tradeoffs. 
- DO NOT USE CLOUDBUILD.GOOGLEAPIS.COM

## UI Changes

Always look up [Design.md](Design.md) first before making any UI changes. It contains the design reference/spec that UI work should follow.

## Visual verification of UI changes

When you need to visually confirm a UI/styling change (e.g. theme colors,
layout), do NOT try multiple approaches. Go straight to this flow:

1. Run `flutter run -d web-server --web-port=8765` in the background.
2. Poll `curl -sf http://localhost:8765` until it responds (don't wait on
   log markers like "Flutter run key commands" — they're unreliable).
3. Screenshot via the browser tool once the server is up.

Do NOT:
- Try `chromium-cli` — it is not installed on this machine.
- Launch `-d windows` desktop builds to verify UI — this has repeatedly
  crashed/hung and is not worth the retry cost.
- Run `flutter build web` as a separate pre-check before `flutter run` —
  it's redundant since `run` builds anyway.

If you only need to confirm the code compiles (not verify appearance),
`flutter build web` alone is sufficient — skip the server/screenshot flow
entirely.

## Theme

The app's design tokens live under [app/lib/theme/](app/lib/theme/), sourced from Design.md §2–3. Screens and widgets should read colors and text styles from `Theme.of(context)` — never hardcode a hex value in a screen or widget.

- **[app_colors.dart](app/lib/theme/app_colors.dart)** — fixed Design.md tokens: `ink`, `cream`, `white`, `canvas`, `grey`, `error`. These never change. `yellowDefault` is the seed value for the accent color only (see below).
- **[app_accent.dart](app/lib/theme/app_accent.dart)** — `AppAccent.notifier` is a `ValueNotifier<Color>` holding the app's one user-changeable color: Design.md's "yellow" role. Set `AppAccent.notifier.value = someColor` from anywhere (e.g. a future settings screen) and the whole app re-themes immediately — no other plumbing needed.
- **[app_theme.dart](app/lib/theme/app_theme.dart)** — `AppTheme.build(Color accent)` assembles `ThemeData` from the fixed tokens plus the given accent. Wired up in [main.dart](app/lib/main.dart) via a `ValueListenableBuilder<Color>` listening to `AppAccent.notifier`, so it rebuilds whenever the accent changes.
- **[app_tokens.dart](app/lib/theme/app_tokens.dart)** — a `ThemeExtension` for the handful of roles that don't map onto Flutter's `ColorScheme`: the error banner surface, the "attention" chip (ink fill + accent text), the Silkscreen score-numeral style, and the hard `4px 4px 0 ink` offset shadow. Read via `Theme.of(context).extension<AppTokens>()!`.
- **[app_dimens.dart](app/lib/theme/app_dimens.dart)** — spacing, border widths (`AppBorders.thick` = 3px, `.thin` = 2px), and radii (`AppRadius.card` = 14, `.control` = 10, `.tile` = 5, `.chip` = 999) per Design.md §2 "Structure".

Fonts come from `google_fonts` (Space Grotesk for display/titles, Plus Jakarta Sans for UI text, Silkscreen for score numerals only — never elsewhere, per Design.md §4 "The UI must not be pixelated").

Dark mode is deferred (Design.md §6); `canvas` must never respond to it when it lands.
