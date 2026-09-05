# Vídeo de OmniMac (30 segundos) — guion y cómo grabarlo

OmniMac entra por los ojos: el notch que se abre, la tarjeta de AirPods, la carátula
que aparece. Un clip de 20–30 s vale más que cualquier texto en Reddit, X, TikTok,
Reels o Shorts. Este guion está pensado para grabarlo en una tarde con lo que ya
tienes: el Mac, unos AirPods y Spotify.

## Antes de grabar (10 minutos)

- Fondo de pantalla oscuro y liso (Ajustes del Sistema › Fondo de pantalla › Colores › Negro o «Sonoma Horizon» oscuro). El notch negro luce más sobre fondo oscuro.
- Escritorio limpio: sin iconos (OmniMac › Utilidades › Ocultar iconos del escritorio) y sin ventanas abiertas salvo las que salgan en escena.
- Barra de menús sin apps de terceros a la vista (o solo OmniMac). Quita el Wi-Fi si aparece lleno de texto.
- Spotify abierto con una canción con carátula bonita, **volumen al 5 %** (el vídeo va sin sonido del sistema; le pones música libre después).
- AirPods con la funda cerrada al lado del Mac, conectados antes a este Mac.
- Modo No molestar activado para que no entre ninguna notificación.
- Grabación: ⌘⇧5 › «Grabar una parte de la pantalla», selecciona una franja de 1440×540 px centrada en el notch (o la pantalla entera y luego recortas). Sin micrófono. Cursor visible (se ve mejor qué pasa).

## Guion (versión horizontal 16:9, 28 s)

| Tiempo | Qué pasa en pantalla | Texto sobreimpreso (ES / EN) |
|---|---|---|
| 0–3 s | Pantalla quieta, notch cerrado. El cursor sube al notch. | «Tu Mac puede hacer esto» / *Your Mac can do this* |
| 3–8 s | El notch se abre: pestaña Música con carátula y progreso. Pausa y reanuda con el botón. | «Música en el notch» / *Music in the notch* |
| 8–12 s | Pestaña Bandeja: arrastras un archivo del Finder al notch y lo sueltas en la zona AirDrop. | «AirDrop arrastrando» / *AirDrop by dragging* |
| 12–16 s | Pestaña Sonido: bajas el volumen solo de Spotify con su deslizador. | «Volumen por app» / *Per-app volume* |
| 16–21 s | Cierras el notch. Abres la funda de los AirPods: aparece la tarjeta con la batería de cada auricular y se cierra sola. | «Como en el iPhone» / *iPhone-style* |
| 21–25 s | ⌘Tab: el selector por ventanas, escribes dos letras para filtrar. Luego ⌃⌥→ y la ventana se pega a la mitad derecha. | «⌘Tab por ventanas · atajos de ventanas» / *⌘Tab by windows · window snapping* |
| 25–28 s | Corte a negro con el icono. | «OmniMac. Gratis y de código abierto. bysergimm.github.io/OmniMac» |

Cada escena dura lo que tarda el gesto real: no aceleres el vídeo, el ritmo natural
del notch abriéndose es parte del encanto. Si una escena sale mal, repite solo esa; se
monta luego en iMovie o en QuickTime (⌘T para dividir, arrastrar para ordenar).

## Versión vertical 9:16 (TikTok, Reels, Shorts), 15–20 s

Usa solo las escenas 1, 2, 5 y 7. Graba la franja superior de la pantalla y en el
montaje amplía al 200 % centrando el notch: en vertical el notch ocupa todo el ancho y
se lee perfectamente. Primer segundo con el texto «tu Mac puede hacer esto y no lo sabías»
(es el gancho; sin él la gente pasa). Termina con «enlace en la bio» y pon la web en la
bio del perfil.

## Título, descripción y etiquetas

- **Título (YouTube / X)**: «OmniMac: 7 utilidades de Mac en una sola app gratis» · EN: *OmniMac: 7 Mac utilities in one free app*.
- **Descripción**: «Mantener despierto, ⌘Tab por ventanas, notch dinámico, atajos de ventanas, portapapeles, OCR y volumen por app. Nativa, 25 MB de memoria y 0,02 % de CPU en reposo. Gratis y de código abierto (MIT). Descarga: https://bysergimm.github.io/OmniMac/ · Código: https://github.com/BySergiMM/OmniMac».
- **Etiquetas**: #mac #macos #macbook #notch #dynamicisland #productivity #opensource #swift #macapps #trucosmac.
- **Música**: solo pistas libres de derechos (la biblioteca de audio de YouTube o de la propia app de TikTok/Instagram); nunca la canción que suene en Spotify durante la grabación.

## Dónde publicarlo y en qué orden

1. GIF corto (escenas 1–2 o la tarjeta de AirPods) en el post de Reddit y en el README (`docs/site/img/demo.gif` se genera solo con `scripts/dev/hero-gif.swift` a partir de la animación de la web; el vídeo real es mejor si lo grabas).
2. Vídeo horizontal en X/Mastodon y en el Show HN como respuesta a quien pida verlo.
3. Vertical en TikTok, Reels y Shorts el mismo día, con el mismo texto. Sube el archivo directamente (no un enlace) para que cada red lo muestre a su gente.
4. Repite cada semana con un módulo distinto (una escena por vídeo: «volumen por app en 10 s», «AirDrop desde el notch»…). La constancia importa más que el primer vídeo.

## Vídeos disponibles

- `omnimac-16x9-{es,en}.mp4` (45 s) y `omnimac-vertical-{es,en}.mp4` (35 s): el tráiler corto.
- `omnimac-tour-16x9-{es,en}.mp4` (107 s) y `omnimac-tour-vertical-{es,en}.mp4` (79 s): el recorrido
  completo: música, vistazo rápido, arrastrar archivos a la bandeja, pestañas, temporizador,
  rendimiento, AirPods, café y menú, ⌘Tab, atajos de ventanas, ajuste por arrastre, portapapeles,
  utilidades (bloqueo del teclado) y Ajustes. Las especificaciones están en `scripts/dev/video-tour-*.json`.

## Cómo se hizo el vídeo (5 de septiembre de 2026) y cómo regenerarlo

Los vídeos de `docs/video/` (no van en git por peso) se grabaron de la app real y se
montaron sin ninguna herramienta externa:

1. `swift scripts/dev/backdrop.swift &` pone un fondo degradado oscuro por debajo de las ventanas.
2. Cada escena se graba con `screencapture -v -V <segundos> -R 0,0,1512,330 clip.mov` (franja del notch)
   o a pantalla completa, mientras `scripts/dev/mouse.swift`, `notch.swift`, `settings.swift` y
   `keys.swift` (⌘Tab con búsqueda, ⌃⌥→/←/↩, secuencias con `seq`), `drag.swift` (arrastres por
   varios puntos: archivo → bandeja, ventana → borde) y `axdump.swift` (qué hay en pantalla por
   Accesibilidad, para localizar botones e iconos) manejan la app. La tarjeta de AirPods sale del
   botón «Probar» de Ajustes › Notch, cerrando la ventana de Ajustes justo después.
3. `swift scripts/dev/video.swift scripts/dev/video-16x9-es.json` monta el vídeo (AVFoundation):
   fondo, recorte y escala de cada clip, títulos, tarjeta de entrada y de cierre. Hay cuatro
   especificaciones: `16x9` y `vertical`, en `es` y `en`; en ellas `CLIPS/` es la carpeta de clips.
4. `swift scripts/dev/frame.swift vídeo.mp4 <segundos> salida.png` saca un fotograma para revisar.

Cosas que se activan solo para grabar y se devuelven a su estado: el vistazo rápido (Ajustes ›
Notch), el café (si estaba encendido se apaga antes y la escena lo enciende), el temporizador
(se cierra al terminar) y el portapapeles (se copian diez elementos de ejemplo para que el panel
no enseñe nada personal y al final se restaura el contenido original).

Antes de grabar: Spotify sonando al 5 %, Modo No molestar, todas las apps ocultas (el
selector ⌘Tab enseña también las ventanas de las apps ocultas, así que en esa escena se
escribe «fin» para filtrar solo el Finder y el clip empieza ya filtrado), y una carpeta neutra
`/Users/Shared/Demo` con archivos de ejemplo para no enseñar nada personal.
