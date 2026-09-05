# Vídeos de OmniMac: qué hay y cómo se regeneran

Los vídeos se grabaron de la app real y se montaron sin herramientas externas; todo lo necesario para repetirlo está en `scripts/dev`.

## Vídeos disponibles

- `omnimac-16x9-{es,en}.mp4` (45 s) y `omnimac-vertical-{es,en}.mp4` (35 s): el tráiler corto.
- `omnimac-tour-16x9-{es,en}.mp4` (107 s) y `omnimac-tour-vertical-{es,en}.mp4` (79 s): el recorrido
  completo: música, vistazo rápido, arrastrar archivos a la bandeja, pestañas, temporizador,
  rendimiento, AirPods, café y menú, ⌘Tab, atajos de ventanas, ajuste por arrastre, portapapeles,
  utilidades (bloqueo del teclado) y Ajustes. Las especificaciones están en `scripts/dev/video/tour-*.json`.

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
3. `swift scripts/dev/video.swift scripts/dev/video/16x9-es.json` monta el vídeo (AVFoundation):
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
