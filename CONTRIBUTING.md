# Contributing to OmniMac

Thanks for looking. This is a one-person project, so here's how it actually works.

## Reporting a bug

Open an issue with:

- **What you did, what you expected, what happened.** In that order.
- **Your Mac and macOS version** (Apple menu → About This Mac).
- **Which module.** OmniMac is eleven modules in one app; knowing whether it's the
  notch or the clipboard saves a round trip.

If it's a performance problem, `Settings › Performance` shows which apps are using the
CPU — a screenshot of that helps more than a description.

## Suggesting a feature

Say what you'd do with it, not just what it should be. OmniMac deliberately doesn't do
everything: a feature that adds a background timer, needs a new permission, or makes
Settings harder to read has to earn it. Being told *why* you want something makes that
call much easier.

## Pull requests

Welcome, with two house rules:

1. **Nothing runs when nothing is visible.** Timers stop, monitors are removed, panels
   free their resources. `scripts/dev/measure.sh` measures idle cost — if a change
   moves that number, say so in the PR.
2. **Logic lives outside the view**, so it can be tested. `swift test` runs the whole
   suite and it should stay green.

Code and comments are written in **Spanish**, explaining *why* rather than *what*.
Anything a user reads goes through `L("español", "English")` — both languages, always.
If Spanish is a barrier, open the PR anyway and write the English half; the Spanish
comments can be sorted out in review.

```bash
./build.sh run     # build and launch
swift test         # the tests
```

## What I won't merge

- Private APIs where a public one exists. OmniMac uses four today, and they don't all
  fail the same way:
  - `_AXUIElementGetWindow` (Accessibility → window ID) for ⌘Tab by windows and window
    snapping. It is linked directly, not looked up at run time, so if a macOS update
    removed it the app would crash instead of degrading. If a call returns an error,
    that window is left out of the ⌘Tab list, and snapping can't restore its size or
    cycle ½ → ⅔ → ⅓.
  - `responsibility_get_pid_responsible_for_pid` for per-app volume, to group a helper
    process under the app that owns it. Also linked directly, with the same consequence if
    it disappears. If a call returns an error, the process is listed on its own instead
    of under its app.
  - IOKit's `IOHIDEventSystemClient…` functions, for the temperature sensors. Loaded at
    run time with `dlopen`/`dlsym`: if a symbol is missing, the temperature readout
    simply doesn't appear.
  - MultitouchSupport's `MT…` functions, for the trackpad haptic when the notch opens.
    Loaded at run time: if a symbol is missing it falls back to the public
    `NSHapticFeedbackManager`.
- Telemetry, analytics, crash reporters, accounts.
- Anything that makes the app phone home for something other than update checks (and
  the Spotify cover art the notch shows).
