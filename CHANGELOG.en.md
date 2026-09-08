# Changelog

## 0.5.0 — 2026-09-09

**New**
- **The notch works on any Mac.** The geometry comes from the screen, not the model: where there's no physical notch it draws a floating island sized to the display. Works on an iMac, on a Mac mini with an external monitor, and on a pre-2021 MacBook.
- **A real performance monitor, not three charts.** Per-core CPU with efficiency and performance cores in different colours, GPU, memory with pressure and swap, disk (read, write and free space), network and **temperature**. Plus the thing you actually want when your Mac drags: **which apps are eating the CPU and the memory**, by name.
- **Temperature**: chip average, hottest diode, SSD, battery and all 45 sensors one by one. The system's thermal state is always there; the degrees only if macOS lets us read them.
- **Alerts** when the CPU has been maxed out for a while, memory is critical, disk is running low, the Mac heats up or the battery gets low. Each fires once and won't repeat until things are back to normal.
- **10-band equaliser**, global or per app, with nine ready-made presets (more bass, voice and podcast, rock, night mode…).
- **Boost past 100 %** (up to 400 %) with a peak limiter, so it doesn't crackle when several apps add up.
- **Output priority**: plug in headphones and they take over on their own; unplug them and the previous one comes back.
- **Standalone mixer** on ⌃⌥⌘V: one shortcut, sliders for whatever is playing, done.
- **Menu bar hider**: click the arrow and the icons you don't use every day appear; click again and they tuck away.
- **App cleaner**: uninstalls an app with everything it leaves behind, and finds the leftovers of apps you already deleted. Everything goes to the Trash; nothing is deleted outright.
- **Command bar** on ⌥Space: type and run any OmniMac feature, or open any app. It matches letters in order, even scattered (“slmi” finds “Silence the microphone”). **Off by default**, because ⌥Space is Raycast's and Alfred's shortcut.
- **Paste as plain text** with ⌥⇧⌘V.
- **Strip tracking from links** as you copy them: out go utm_source, fbclid, Spotify's si. Only when what you copied is a whole link, and it never touches parameters it doesn't know.
- **Brightness below macOS's minimum** with ⌃⌥⌘− and ⌃⌥⌘+, for working at night.
- **.dmg installer**: when a download finishes, OmniMac asks whether to mount the image, copy the app to Applications, eject it and move the .dmg to the Trash. It never acts without asking.
- The notch's icons reorder by dragging, and the performance charts can go in the notch, in the menu bar or nowhere.
- A **What's New** window when it updates, which you can skip.

**Fixed**
- **The menus were stuttering.** The cause was the notch's global mouse monitor: while it exists, macOS wakes the app on every mouse move across the whole system. It's now removed while a menu is open.
- The menu bar icon is now the same sparkle as the app icon; they used to be two different drawings.
- The menu bar hider was swallowing OmniMac's own icons.
- The cleaner said “freed X MB” even when it had moved nothing. It now counts only what actually reached the Trash, and it tells you macOS won't let any app touch Containers folders: those have to go from Finder.
- With the charts in the menu bar it was measuring **everything** (GPU, disk, sensors and all 445 processes) just to draw one CPU line: 1.9 % CPU at idle. The icon now asks only for what it shows.
- Eighteen translations fixed, and the Settings sidebar is wider so it no longer overlaps long labels.

## 0.4.2 — 2026-09-06

- Settings › Home › Storage: shows how much space the app and its cache take up (downloaded artwork and leftovers from Sparkle updates), a "Clean now" button that tells you how much it freed, and an automatic clean once a day (on by default, can be turned off). The web cache is capped at 16 MB on disk.

## 0.4.1 — 2026-09-05

- Settings: changing the language restarts OmniMac and reopens Settings already in the new language; the pickers in each row are vertically centred.
- Settings: closing the window destroys its content, so the Performance and Sound pages really stop sampling (they used to keep measuring with the window hidden: 0.37% CPU).
- Notch: the click tap is invalidated when it collapses (each opening used to leak a Mach port and a run loop source), and the panel is reframed only once the collapse animation has finished.
- Music: AppleScript now runs on its own thread with a run loop (`ScriptThread`) instead of on GCD, which piled up run loops and sources with every poll.
- Power use measured again (`docs/PERFORMANCE.md`): 0.02% CPU idle, under one wake-up per second, no memory growth after opening and closing the notch.
- Code: header comments in every file, test tools in `scripts/dev` (`quickbuild.sh`, `wakeups.sh`, `measure.sh`…) and the English site generator in `docs/site/tools`.

## 0.4.0 — 2026-09-04

- **English and Spanish interface**: it follows the Mac's language and can be pinned in Settings › Home › General › Language (changing it restarts the app). Permission prompts are localised too.
- Notch: the AirPods card opens in a smaller, centred panel (440×172) and collapses sooner (3.2 s; 2.2 s once the battery arrives); the shadow no longer jumps during the animation.
- Install with Homebrew: `brew install --cask BySergiMM/tap/omnimac`.
- English screenshots for the site (`--snapshots … --lang en`).

## 0.3.1 — 2026-09-04

- Notch: connecting AirPods or Beats unfolds it with an animated iPhone-style card (model and battery of each piece) and it folds back on its own; there's an option to dismiss the macOS banner (experimental). No permissions needed.

## 0.3.0 — 2026-09-04

**New**
- Notch: Calendar, Sound (per-app volume), Timer/Pomodoro (configurable) and Performance tabs; every tab and every header button can be turned on or off.
- Notch: a quick peek when the song changes, "unfolding the notch" notices (optional), it hides for full-screen apps, the battery is clickable, and there's AirDrop and a drop tray with a file picker.
- Window shortcuts: thirds, top/bottom halves, almost maximise, bigger/smaller, restore, move to another screen, drag-to-edge snapping, size cycling and **layouts** (⌃⌥1…9 saves/applies, hold to free, ⌃⌥0 undoes).
- ⌘Tab: type to search, ⌘W/⌘M/⌘H/⌘Q, optional ⌥Tab.
- Clipboard: images and files, search, pinned items (⌥P), pause, optional history on disk.
- Keep awake: until a given time, more durations, remaining time in the menu bar, a notice when it ends, stop on low battery, triggers (charger, external display) and closed-lid mode (one password, also from the installer).
- Tools: copy text from the screen (OCR, ⇧⌘2), copy a colour (⇧⌘6), mute the microphone (⌃⌥⌘M), lock the keyboard (⌃⌥⌘L), hide desktop icons, prevent an accidental ⌘Q.
- Sound: output/input, volume, balance, mute, per-app volume, ⌃⌥⌘O to cycle outputs; kept in sync with the volume keys in real time.
- Performance: three graphs (CPU, memory, network) in Settings and in the notch.
- Automatic updates (Sparkle + GitHub Releases) and a `.pkg` installer.
- Universal binary (Apple silicon and Intel), macOS 14.2 or later.
- The notch panel adapts to each screen's notch width: the tabs never end up underneath it.
- A website with real screenshots generated by the app itself (`OmniMac --snapshots <folder>`).
- Settings in the style of System Settings.

**Fixes**
- The notch draws above the menu bar, matches the physical notch exactly and doesn't show when switching desktops; it opens when you reach the top edge; AirDrop works with a single drop target.

## 0.2.0
- First version, with Keep awake, window-level ⌘Tab, Notch, Window shortcuts and Clipboard.
