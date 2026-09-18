# Changelog

## 0.5.3 — 2026-09-18

**Fixed**
- **macOS 27**: on a notched laptop, hiding the menu bar icons made them reappear on the other side of the notch, next to the app's menus, instead of tucking away. The expander grew to 45% of the screen, but the area to the right of the notch is narrower than that, so it crossed over and dragged the icons with it. It now measures how much room there is up to the notch's edge and stops there: the icons slip under the notch and vanish.

## 0.5.2 — 2026-09-17

**New**
- **Clipboard: the apps whose copies are never saved.** Settings › Clipboard now has a list of apps whose copies never make it into the history, with an app picker, plus a switch for the well-known password managers (1Password, Bitwarden, KeePassXC, Enpass, Dashlane, LastPass, Strongbox, Keychain Access and Passwords), on by default. It's a switch rather than a copy of identifiers, so a manager you install tomorrow is covered without going back to Settings; below it you see the ones you actually have installed, instead of promising a list of apps you don't. Anything an app marks as confidential is never saved, list or no list.

**Fixed**
- Clipboard: opening the history from the menu bar icon or the command bar left OmniMac in front, so it ate the ⌘V itself: the item was copied but never pasted anywhere. It now goes back to the app you were in.
- Clipboard: copying two things in a row lost the first one, because the clipboard was only checked once per second. While you are copying it is checked four times a second, settling down again after four seconds; at rest it is checked exactly as before and idle cost doesn't change.
- Clipboard: in the panel, a motionless mouse stole the selection from the keyboard whenever the list scrolled. The mouse now only wins if you actually move it.
- Clipboard: you couldn't search for anything starting with a digit, because the number pasted that item outright. Digits now search, and picking by number is ⌘1–⌘9, which also works while searching.
- Clipboard: the panel stayed floating above everything when you clicked another app, and not even Esc closed it there. It now closes when it loses focus.
- Clipboard: text longer than 20,000 characters was trimmed silently; the row now says so. And Settings no longer claims that nothing touches the disk with "save to disk" off: pinned items are always saved.
- What's new: in a version that only fixed things, "What's new…" did nothing at all — the tour skips fixes on purpose and was left without a single screen. Asked for by hand it now shows the fixes too, and if there were nothing to show, it says so.
- Menu bar: the icons jumped around. When a status icon is removed, macOS forgets where you had left it, so rebuilding them lost the position of the line and the arrow. They are now saved and put back, their order is kept at launch, and "Put the icons back" no longer moves the line, which is the boundary you set: moving it revealed everything you had hidden.
- **macOS 27**: the menu bar hider hid nothing and its divider vanished. The menu bar is now a single window and macOS discards any icon that reaches half the screen's width instead of clamping it as before; the expander was 10,000 points wide. On macOS 27 it is now 45 % of the narrowest screen, recalculated when displays change, and not drawn while collapsed.
- **macOS 27**: picking an item in the clipboard history didn't paste, and after closing the panel with Esc what you typed never reached your app. When the panel closed, AppKit made the notch panel the key window and the keyboard stayed with OmniMac. The notch can now only be the key window while it shows something, and the paste's ⌘V waits until no window of ours has focus and until you release ⌥, ⇧ and ⌃ (with ⌥⇧⌘V it went out with the keys still held).
- **macOS 27**: the AirPods card showed no battery. macOS 27 writes the level with a non-breaking space before the "%" ("100 %"), which was left stuck to the number so it couldn't be parsed. It now reads the digits only. Added the product id of the newest AirPods Pro too.
- **Keyboard lock**: brightness, volume and media keys still worked. They arrive as a different event type (regular keys don't), and the system handles them before a session-level tap sees them. The tap now sits at the lowest level (HID) and catches them too, and re-enables itself if macOS disables it under load.
- Updates: Sparkle 2.10.0, which fixes applying delta updates on macOS 27.

## 0.5.1 — 2026-09-11

**Fixed**
- Performance: some app names showed up with garbled letters, like “m√°quina” instead of “máquina”. macOS hands the name over already broken; OmniMac now repairs it before showing it and leaves correctly written names alone. Same in the volume mixer, ⌘Tab by windows, the ⌘Q warning and the app cleaner.
- Notch: clicking the battery opened System Settings on General. It now opens Battery.

## 0.5.0 — 2026-09-09

**New**
- **The notch works on any Mac.** The geometry comes from the screen, not the model: where there's no physical notch it draws a floating island sized to the display. Works on an iMac, on a Mac mini with an external monitor, and on a pre-2021 MacBook.
- **A real performance monitor, not three charts.** Per-core CPU with efficiency and performance cores in different colours, GPU, memory with pressure and swap, disk (read, write and free space), network and **temperature**. Plus the thing you actually want when your Mac drags: **which apps are eating the CPU and the memory**, by name.
- **Temperature**: chip average, hottest diode, SSD, battery and every sensor on the chip, one by one. The system's thermal state is always there; the degrees only if macOS lets us read them.
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
- **Every shortcut can be changed**, one by one, in Settings. And when another app already owns a combination, OmniMac **says so** instead of staying quiet: `RegisterEventHotKey` used to fail with no warning at all, and the feature simply did nothing. Anyone with Rectangle or Magnet pressed ⌃⌥→ and nothing happened, with no explanation.

**Fixed**
- **Keep awake no longer switches itself off without telling you.** A session can stop on its own — low battery, the timer, the app quitting or updating — and with the lid closed that puts the Mac to sleep right then: you opened the laptop, found the lock screen, and had no way to know why. The notification didn't help, because it's sent exactly as the Mac is going to sleep and may never be delivered. The reason is now **saved to disk** and told to you when you come back, in Settings and with an orange coffee cup in the notch. It also warns **ten points before** the battery cut-off, while the warning can still be seen, and the rule is checked when the session starts (before, if you were already below the threshold, the session began anyway and died later on its own).
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
