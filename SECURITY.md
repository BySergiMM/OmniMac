# Security

OmniMac runs on your Mac and talks to exactly one server: GitHub, to check for updates.
No accounts, no analytics, no telemetry. You can turn the update check off in Settings.

## Permissions it asks for

Each is requested only when a feature needs it, never at launch:

| Permission | Used for |
|---|---|
| Accessibility | Moving windows, ⌘Tab, pasting from the clipboard history |
| Screen Recording | ⌘Tab thumbnails, OCR, the colour picker |
| Calendar | The notch's calendar tab only |
| Audio capture | Per-app volume and the equaliser only |

## Things worth knowing

- The app is **not notarized** (that needs a paid Apple developer account), so macOS
  warns on first launch. The build is reproducible from source if you'd rather compile
  it yourself.
- Clipboard history lives in memory unless you turn on "save to disk", and that file is
  **not encrypted**. Don't turn it on if you paste secrets.
- The app cleaner moves things to the Trash. It never deletes outright.

## Reporting something

Open a [security advisory](https://github.com/BySergiMM/OmniMac/security/advisories/new)
or email the address on my GitHub profile. I'll reply as fast as one person reasonably
can.
