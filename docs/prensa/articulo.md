# OmniMac: siete utilidades del Mac en una sola app gratis y de código abierto

*Artículo listo para publicar en un blog (Medium, dev.to, Substack) o para ofrecer a un medio como pieza de invitado. Unas 700 palabras. Imágenes: `docs/site/img/notch-media.png`, `notch-headphones.png`, `menu.png` y el GIF `docs/site/img/demo.gif`.*

Si usas un Mac con cierta intensidad, seguramente tienes instaladas las mismas cuatro o cinco utilidades que todo el mundo: una para que el Mac no se duerma mientras descargas algo, otra para cambiar de ventana con ⌘Tab como en Windows, otra para colocar las ventanas con atajos, otra para el historial del portapapeles y, desde que los portátiles tienen notch, alguna que lo convierta en algo útil. Cinco iconos en la barra de menús, cinco procesos residentes y, sumadas, más de 600 MB de memoria.

OmniMac nace de esa pequeña frustración. Es una sola app de barra de menús, nativa (Swift y SwiftUI), gratuita y de código abierto (licencia MIT), que hace todo eso y algunas cosas más, y que se mantiene fuera del camino: en reposo consume el 0,017 % de la CPU, entre 19 y 27 MB de memoria física real y despierta al procesador menos de una vez por segundo.

## Qué hace

- **Mantener despierto**: sesiones sin límite, con duración o hasta una hora concreta, con el tiempo restante junto al icono. Tiene un modo de tapa cerrada que funciona con una sola autorización y se detiene solo si la batería baja demasiado.
- **⌘Tab por ventanas**: el selector muestra ventanas, no apps, con miniaturas en vivo. Se puede buscar escribiendo y cerrar, minimizar u ocultar la ventana elegida sin salir del selector.
- **Notch dinámico**: al pasar el ratón, el notch se despliega con la música que suena en Spotify o Música (carátula, progreso y controles), una bandeja para arrastrar archivos con una zona de AirDrop, los eventos de hoy, el volumen de cada app, un temporizador con Pomodoro y tres gráficos de rendimiento. Al conectar unos AirPods o unos Beats aparece una tarjeta al estilo del iPhone con la batería de cada auricular y de la funda. En los Macs sin notch se muestra como una isla.
- **Atajos de ventanas**: mitades, tercios, casi maximizar, mover a otra pantalla, ajustar arrastrando a los bordes y disposiciones guardadas con ⌃⌥1…9.
- **Portapapeles**: historial con texto, imágenes y archivos, búsqueda y elementos anclados. Por defecto no guarda nada en disco.
- **Utilidades**: copiar el texto de cualquier zona de la pantalla (OCR), copiar un color, bloquear el teclado para limpiarlo, silenciar el micrófono con un atajo y evitar el ⌘Q accidental.
- **Sonido**: salida, entrada, balance y volumen por app, sincronizado con las teclas de volumen.

Cada módulo se puede desactivar, y lo que está apagado no consume nada. Sigue el idioma del Mac (español e inglés) y se actualiza sola.

## Por qué el consumo importa

Es fácil decir que una app es ligera; lo difícil es demostrarlo. El repositorio de OmniMac incluye la metodología y los resultados: cada app medida sola en el mismo Mac, 60 segundos de reposo, tiempo de CPU consumido dividido por tiempo transcurrido y memoria física real medida con la herramienta `footprint` de macOS. Las cinco apps a las que sustituye suman 636 MB de memoria residente; OmniMac usa 119 MB de RSS, de los que solo 19 a 27 MB son memoria física real. También documenta con honestidad las dos trampas de medición en las que el autor cayó por el camino, para que quien repita las medidas no tropiece en lo mismo.

## Lo que todavía no hace

La comparativa de la web es de las que dicen también lo que la otra app hace mejor: Amphetamine tiene disparadores automáticos mucho más completos, AltTab permite afinar cada detalle del selector, Rectangle deja cambiar todos los atajos, Maccy guarda miles de entradas con búsqueda difusa y BoringNotch muestra la música de cualquier app, no solo de Spotify y Música. OmniMac no pretende sustituir todas esas funciones, sino cubrir lo que la mayoría usa a diario con una sola app.

Tampoco está notarizada por Apple todavía (el autor no tiene cuenta de desarrollador), así que la primera vez hay que abrirla con clic derecho › Abrir. El código es público, y quien quiera puede compilarla con un solo script.

## Dónde conseguirla

OmniMac es gratuita, sin cuentas ni telemetría, para macOS 14.2 o posterior en Apple silicon e Intel. Se descarga desde [bysergimm.github.io/OmniMac](https://bysergimm.github.io/OmniMac/) o con Homebrew (`brew install --cask BySergiMM/tap/omnimac`), y el código está en [github.com/BySergiMM/OmniMac](https://github.com/BySergiMM/OmniMac).
