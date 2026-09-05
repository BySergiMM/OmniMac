# Product Hunt — kit de lanzamiento de OmniMac

Todo lo que pide el formulario de Product Hunt, listo para pegar. Lo publicas tú con tu
cuenta (crea la cuenta con unos días de antelación y sigue a algunos *makers*: una cuenta
recién creada sin actividad lanza peor).

## Campos del formulario

| Campo | Valor |
|---|---|
| Name | OmniMac |
| Tagline (60 caracteres máx.) | Seven Mac utilities in one free, open-source menu-bar app |
| Links | Web: https://bysergimm.github.io/OmniMac/en/ · GitHub: https://github.com/BySergiMM/OmniMac |
| Description (260 caracteres máx.) | Keep-awake, ⌘Tab by windows, a dynamic notch with music, AirDrop and an AirPods card, window snapping, clipboard history, screen OCR and per-app volume. Native Swift, 25 MB at idle, MIT, no accounts. |
| Topics | Mac · Productivity · Open Source (añade Developer Tools si deja un cuarto) |
| Pricing | Free |
| Thumbnail (240×240) | `docs/site/img/icon-512.png` (Product Hunt lo reduce) |
| Gallery (1270×760) | `docs/producthunt/01-hero.png` … `05-light.png`, en ese orden (están a 2×, 2540×1520; se aceptan) |
| Video (opcional) | Enlace de YouTube al vídeo de `docs/VIDEO.md`; si no lo tienes aún, lanza sin vídeo, el GIF de la galería cumple |
| Makers | Tú (BySergiMM) |
| Built with | Swift · SwiftUI · AppKit · CoreAudio · Sparkle |
| Launch date | Martes, miércoles o jueves a las 00:01 PT (09:01 en España). Programa el lanzamiento el día anterior con «Schedule» |

## Primer comentario (del maker, se publica nada más lanzar)

> Hi Product Hunt! I'm Sergi, a developer from Spain.
>
> I kept installing the same five utilities on every Mac: Amphetamine to keep it awake, AltTab to switch by windows, Rectangle for window shortcuts, Maccy for the clipboard and a notch app for music. Five icons in the menu bar, five updaters, 636 MB of RAM between them. So I wrote one native app that does all of it and adds the things I was missing: per-app volume, screen OCR, a colour picker, a keyboard lock, a mic-mute key, and an iPhone-style card in the notch when my AirPods connect.
>
> What I care about most is that it stays out of the way: 0.017 % CPU, 19–27 MB of real memory and under one wake-up per second at idle. Every measurement and the method are in the repo (docs/PERFORMANCE.md), and I compared it with the apps it replaces using the same method on the same Mac.
>
> It's free and MIT-licensed, no accounts, no telemetry, universal binary, macOS 14.2+, interface in English and Spanish. Honest caveats: it isn't notarized by Apple yet (I don't have the developer account), so the first launch needs right-click › Open; and the per-app volume uses macOS process taps, which need the system-audio recording permission.
>
> I'd love to hear which module you'd use most and what's missing. I'm around all day to answer.

## Respuestas preparadas para los comentarios habituales

- **«¿Por qué no está en la App Store?»** Because half of the modules (window management, ⌘Tab, keep-awake with closed lid) need Accessibility and shell access that the sandbox does not allow. It's open source and installs with a signed .pkg or Homebrew.
- **«Gatekeeper dice que no se puede abrir»** Right-click the app › Open, once. Notarization will come with the Apple developer account; the code is public if you want to build it yourself (`./build.sh`).
- **«¿Usa APIs privadas?»** One: the trackpad haptic actuator (resolved at runtime with dlopen; if it's missing, the public API is used). Everything else is public: CoreAudio process taps, AppleScript for Spotify/Music, Accessibility, CGEvent taps for click forwarding in the notch.
- **«¿Cómo lo mediste?»** 60 s at idle with the cursor away from the notch, CPU from `ps -o cputime`, real memory from `footprint`, wake-ups from two `top` samples. Each competing app measured alone on the same Mac. Everything in docs/PERFORMANCE.md.
- **«¿Funciona sin notch?»** Yes, it shows as an island under the menu bar on Macs without one.
- **«¿Intel?»** Universal binary; macOS 14.2 or later.

## Checklist del día

1. Una semana antes: crea la página «Coming soon» en Product Hunt para acumular seguidores (avisa en X/Mastodon y en el README con la insignia que te dan).
2. El día anterior: sube galería, miniatura, textos; programa para las 00:01 PT.
3. A las 09:01 (España): publica el primer comentario, comparte el enlace en X/Mastodon/LinkedIn y en el Discord o Slack donde estés («I launched OmniMac today, feedback welcome»), sin pedir votos.
4. Durante el día: contesta cada comentario en menos de una hora; apunta las peticiones en `docs/PENDIENTE.md`.
5. Al día siguiente: agradece, publica el resultado en X y añade la insignia de Product Hunt al README y a la web si quedas entre los cinco primeros.
