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
2. **Logic lives outside the view**, so it can be tested. `swift test` runs 151 tests
   and they should stay green.

Code and comments are written in **Spanish**, explaining *why* rather than *what*.
Anything a user reads goes through `L("español", "English")` — both languages, always.
If Spanish is a barrier, open the PR anyway and write the English half; the Spanish
comments can be sorted out in review.

```bash
./build.sh run     # build and launch
swift test         # the tests
```

## What I won't merge

- Private APIs where a public one exists. (Temperature is the one exception, and it's
  loaded at runtime so it degrades instead of crashing.)
- Telemetry, analytics, crash reporters, accounts.
- Anything that makes the app phone home for something other than update checks.
