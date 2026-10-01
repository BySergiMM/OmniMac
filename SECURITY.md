# Security

OmniMac runs on your Mac and makes two kinds of network request: to GitHub, to check for
updates (you can turn the check off in Settings), and, while Spotify is playing, to the
address Spotify reports for the cover art of the current track. No accounts, no analytics,
no telemetry.

## Permissions it asks for

Each is requested only when a feature needs it. The one you can meet at launch is
Accessibility, which OmniMac asks for when it starts with ⌘Tab by windows or window
snapping switched on:

| Permission | Used for |
|---|---|
| Accessibility | Moving windows, ⌘Tab, pasting from the clipboard history |
| Screen Recording | ⌘Tab thumbnails, OCR, the colour picker |
| Calendar | The notch's calendar tab only |
| Audio capture | Per-app volume and the equaliser only |
| Administrator password | Closed-lid mode only, and only if you turn it on (see below) |

## Things worth knowing

- The app is **not notarized** (that needs a paid Apple developer account), so macOS
  warns on first launch. If you'd rather not trust the binary, the source is here and
  `./build.sh` builds it.
- **Closed-lid mode is off by default.** If you turn it on, OmniMac first shows what it
  will do and asks you; if you continue, macOS asks for your password once and OmniMac
  installs `/etc/sudoers.d/omnimac-lid`, a rule that lets your user run
  `pmset -a disablesleep 1` and `pmset -a disablesleep 0` without a password. While it
  exists, any program running as your user can change that setting. The `.pkg` installer
  does not install it, and turning the mode off or trashing the app does not remove it:
  run `sudo rm /etc/sudoers.d/omnimac-lid` or `scripts/uninstall.sh`. More in the
  [README](README.md#permissions).
- Clipboard history lives in memory unless you turn on "save to disk", and that file is
  **not encrypted**. Don't turn it on if you paste secrets.
- The app cleaner moves things to the Trash. It never deletes outright.

## Reporting something

Open a [security advisory](https://github.com/BySergiMM/OmniMac/security/advisories/new)
or email the address on my GitHub profile. I'll reply as fast as one person reasonably
can.
