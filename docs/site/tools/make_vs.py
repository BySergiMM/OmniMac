#!/usr/bin/env python3
"""Genera las páginas comparativas «OmniMac frente a X» (español e inglés), sitemap.xml y
robots.txt a partir de los datos de abajo. Ejecutar desde cualquier sitio:

    python3 docs/site/tools/make_vs.py

Salida: docs/site/vs/<app>/index.html y docs/site/en/vs/<app>/index.html.
Los datos de consumo son los de docs/PERFORMANCE.md (medición del 4 de septiembre de 2026,
cada app sola en el mismo Mac); las funciones salen de docs/COMPETENCIA.md y de la
documentación pública de cada app. Reglas: solo hechos comprobables, nada de adjetivos
sobre las otras apps, y siempre un apartado con lo que la otra app hace mejor.
"""
import os, datetime

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
BASE = "https://bysergimm.github.io/OmniMac/"
DATE = {"es": "9 de septiembre de 2026", "en": "9 September 2026"}
OMNI = {"rss": "83 MB", "real": "27–36 MB", "cpu": "0,017 %", "cpu_en": "0.017 %", "disk": "16 MB", "threads": "6", "version": "0.5.0"}

APPS = [
    dict(slug="amphetamine", name="Amphetamine", version="5.3.2", rss="100 MB", cpu="0,000 %", cpu_en="0.000 %", disk="7 MB", threads="5",
         module={"es": "Mantener despierto", "en": "Keep awake"},
         price={"es": "Gratis (Mac App Store), código cerrado", "en": "Free (Mac App Store), closed source"},
         does={"es": "Evita que el Mac entre en reposo con sesiones de duración fija, hasta una hora, o mientras pase algo (una descarga, una app abierta…).",
               "en": "Keeps the Mac awake with fixed-length sessions, until a given time, or while something happens (a download, an app running…)."},
         theirs={"es": ["Disparadores automáticos por Wi-Fi, IP, app en primer plano, USB, Bluetooth, horario y muchos más", "Sesión «mientras se descarga un archivo» y «mientras una app esté abierta»", "Drive Alive: mantiene despiertos los discos externos", "Estadísticas de sesiones, control por AppleScript e iconos de barra personalizables", "Modo tapa cerrada mediante la app auxiliar Amphetamine Enhancer"],
                 "en": ["Automatic triggers: Wi-Fi, IP, frontmost app, USB, Bluetooth, schedule and many more", "“While a file downloads” and “while an app is running” sessions", "Drive Alive keeps external drives awake", "Session statistics, AppleScript control and custom menu-bar icons", "Closed-lid mode through the companion app Amphetamine Enhancer"]},
         ours={"es": ["Sesiones sin límite, de 15 min a horas, o hasta una hora concreta, con el tiempo restante en la barra y aviso al terminar", "Modo tapa cerrada integrado (una sola autorización, sin app auxiliar) y parada automática al bajar la batería", "Disparadores sencillos: cargador y pantalla externa", "Un botón de café dentro del notch: se activa sin abrir ningún menú"],
               "en": ["Unlimited sessions, 15 min to hours, or until a given time, with the remaining time in the menu bar and a notice at the end", "Built-in closed-lid mode (one authorisation, no companion app) and automatic stop when the battery runs low", "Simple triggers: charger and external display", "A coffee button inside the notch: switch it on without opening a menu"]},
         pick={"es": ["Amphetamine si dependes de disparadores complejos (por red, por app, por horario) o de Drive Alive.", "OmniMac si quieres mantener el Mac despierto con dos clics y, de paso, sustituir otras cuatro utilidades."],
               "en": ["Amphetamine if you rely on complex triggers (network, app, schedule) or on Drive Alive.", "OmniMac if you want to keep the Mac awake in two clicks and replace four other utilities along the way."]}),
    dict(slug="alttab", name="AltTab", version="11.5.0", rss="212 MB", cpu="0,020 %", cpu_en="0.020 %", disk="11 MB", threads="9",
         module={"es": "⌘Tab por ventanas", "en": "⌘Tab by windows"},
         price={"es": "Gratis, código abierto (GPL-3.0)", "en": "Free, open source (GPL-3.0)"},
         does={"es": "Sustituye el ⌘Tab de macOS por un selector de ventanas con miniaturas, al estilo de Windows.", "en": "Replaces the macOS ⌘Tab with a window switcher with thumbnails, Windows-style."},
         theirs={"es": ["Varios órdenes (reciente, creación, alfabético, por Espacio) y etiquetas del número de Espacio", "Exclusiones por app y ajustes de apariencia muy detallados (tamaño, temas, títulos)", "Elección de en qué pantalla aparece el selector y selección con el ratón", "Iconos de estado para ventanas ocultas, minimizadas y a pantalla completa"],
                 "en": ["Several orderings (recent, creation, alphabetical, by Space) and Space number labels", "Per-app exclusions and very detailed appearance settings (size, themes, titles)", "Choice of which display shows the switcher, plus mouse selection", "Status icons for hidden, minimised and full-screen windows"]},
         ours={"es": ["⌘Tab por ventanas con miniaturas en vivo y ventanas de todos los Espacios", "Buscar escribiendo, y ⌘W, ⌘M, ⌘H y ⌘Q sobre la ventana elegida sin salir del selector", "⌥Tab opcional para conservar el ⌘Tab del sistema", "Atajos de ventanas y disposiciones en la misma app (mitades, tercios, ⌃⌥1…9 para guardar y aplicar)"],
               "en": ["⌘Tab by windows with live thumbnails and windows from every Space", "Search by typing, and ⌘W, ⌘M, ⌘H and ⌘Q on the selected window without leaving the switcher", "Optional ⌥Tab to keep the system ⌘Tab", "Window shortcuts and layouts in the same app (halves, thirds, ⌃⌥1…9 to save and apply)"]},
         pick={"es": ["AltTab si quieres afinar cada detalle del selector o excluir apps concretas.", "OmniMac si te basta un selector por ventanas rápido con búsqueda y quieres las ventanas, el portapapeles y el notch en la misma app."],
               "en": ["AltTab if you want to tune every detail of the switcher or exclude specific apps.", "OmniMac if a fast window switcher with search is enough and you want windows, clipboard and the notch in one app."]}),
    dict(slug="rectangle", name="Rectangle", version="1.100", rss="84 MB", cpu="0,040 %", cpu_en="0.040 %", disk="9 MB", threads="4",
         module={"es": "Atajos de ventanas", "en": "Window shortcuts"},
         price={"es": "Gratis y código abierto; Rectangle Pro de pago", "en": "Free and open source; Rectangle Pro is paid"},
         does={"es": "Mueve y redimensiona ventanas con atajos de teclado y arrastrándolas a los bordes.", "en": "Moves and resizes windows with keyboard shortcuts and by dragging them to the edges."},
         theirs={"es": ["Atajo personalizable para cada acción y muchas más acciones (sextos, mover a esquinas, centrar con tamaño…)", "Márgenes entre ventanas, modo «Todo» y apps ignoradas", "Rectangle Pro: anclar ventanas, disposiciones por app, atajos de ratón"],
                 "en": ["A customisable shortcut for every action and many more actions (sixths, corners, centre with size…)", "Gaps between windows, Todo mode and ignored apps", "Rectangle Pro: pinning, per-app layouts, mouse shortcuts"]},
         ours={"es": ["Mitades, tercios, mitades superior e inferior, casi maximizar, más grande o más pequeño, restaurar y otra pantalla", "Ajuste arrastrando a los bordes con huella previa", "Disposiciones: ⌃⌥1…9 guarda o aplica, mantener libera, ⌃⌥0 deshace", "Todo dentro de la misma app que el ⌘Tab por ventanas y el notch"],
               "en": ["Halves, thirds, top and bottom halves, almost maximise, bigger or smaller, restore and other display", "Drag-to-edge snapping with a preview footprint", "Layouts: ⌃⌥1…9 saves or applies, hold to release, ⌃⌥0 undoes", "All inside the same app as ⌘Tab by windows and the notch"]},
         pick={"es": ["Rectangle si necesitas cambiar cada atajo o las funciones de Rectangle Pro.", "OmniMac si los atajos por defecto y las disposiciones guardadas te cubren y prefieres una sola app residente."],
               "en": ["Rectangle if you need to change every shortcut or want Rectangle Pro's features.", "OmniMac if the default shortcuts and saved layouts cover you and you prefer a single resident app."]}),
    dict(slug="maccy", name="Maccy", version="2.7.1", rss="91 MB", cpu="0,020 %", cpu_en="0.020 %", disk="10 MB", threads="4",
         module={"es": "Portapapeles", "en": "Clipboard"},
         price={"es": "Gratis y código abierto (MIT); versión de pago en el Mac App Store", "en": "Free and open source (MIT); paid version on the Mac App Store"},
         does={"es": "Historial del portapapeles con búsqueda, pensado para usarse solo con el teclado.", "en": "Clipboard history with search, designed to be used from the keyboard."},
         theirs={"es": ["Tamaño del historial configurable hasta miles de entradas y búsqueda difusa", "Pegar sin formato con su propio atajo y apps ignoradas", "Interfaz enteramente manejable con el teclado y atajos personalizables"],
                 "en": ["History size configurable up to thousands of entries and fuzzy search", "Paste without formatting with its own shortcut, and ignored apps", "Fully keyboard-driven interface with customisable shortcuts"]},
         ours={"es": ["Texto, imágenes y archivos, con búsqueda y elementos anclados (⌥P)", "Pausa, y historial en disco opcional (por defecto no se guarda nada)", "Sondeo a 1 Hz con tolerancia: cero trabajo cuando no copias nada", "Comparte app con el notch, el ⌘Tab y las ventanas"],
               "en": ["Text, images and files, with search and pinned items (⌥P)", "Pause, and optional on-disk history (nothing is saved by default)", "1 Hz polling with tolerance: zero work when you copy nothing", "Shares the app with the notch, ⌘Tab and windows"]},
         pick={"es": ["Maccy si vives en el teclado y quieres un historial enorme con búsqueda difusa.", "OmniMac si te basta un historial reciente con imágenes y archivos y no quieres otra app más."],
               "en": ["Maccy if you live in the keyboard and want a huge history with fuzzy search.", "OmniMac if a recent history with images and files is enough and you don't want yet another app."]}),
    dict(slug="boringnotch", name="BoringNotch", version="2.7.3", rss="149 MB", cpu="0,340 %", cpu_en="0.340 %", disk="19 MB", threads="7",
         module={"es": "Notch dinámico", "en": "Dynamic notch"},
         price={"es": "Gratis y código abierto", "en": "Free and open source"},
         does={"es": "Convierte el notch en un panel con la música que suena, una bandeja de archivos y otras utilidades.", "en": "Turns the notch into a panel with the playing music, a file shelf and other utilities."},
         theirs={"es": ["«Ahora suena» universal: cualquier app de audio, no solo Spotify y Música", "HUD de volumen y brillo dentro del notch y visualizador de música", "Espejo de la cámara y más opciones de aspecto", "Comunidad grande y muchas más opciones de personalización"],
                 "en": ["Universal “now playing”: any audio app, not only Spotify and Music", "Volume and brightness HUD inside the notch, plus a music visualiser", "Camera mirror and more appearance options", "A large community and many more customisation options"]},
         ours={"es": ["Pestañas Música (Spotify y Música), Bandeja con zona AirDrop, Calendario, Sonido con volumen por app, Temporizador y Rendimiento", "Tarjeta al estilo iPhone al conectar AirPods o Beats, con la batería de cada pieza", "Vistazo rápido al cambiar de canción, se oculta a pantalla completa, funciona como isla en Macs sin notch", "Consumo medido en reposo: 0,017 % de CPU frente al 0,340 % de BoringNotch, y diez módulos más en la misma app"],
               "en": ["Music (Spotify and Music), Tray with an AirDrop zone, Calendar, Sound with per-app volume, Timer and Performance tabs", "iPhone-style card when AirPods or Beats connect, with the battery of each piece", "Sneak peek on track change, hides in full screen, works as an island on Macs without a notch", "Measured idle usage: 0.017 % CPU versus BoringNotch's 0.340 %, plus ten more modules in the same app"]},
         pick={"es": ["BoringNotch si escuchas música en apps que no son Spotify ni Música, o quieres el HUD y el visualizador.", "OmniMac si usas Spotify o Música, quieres AirDrop, calendario y volumen por app en el notch, y te importa el consumo."],
               "en": ["BoringNotch if you listen to music in apps other than Spotify or Music, or want the HUD and the visualiser.", "OmniMac if you use Spotify or Music, want AirDrop, calendar and per-app volume in the notch, and care about resource usage."]}),
    dict(slug="ice", name="Ice", version="0.11.12", rss="99 MB", cpu="0,040 %", cpu_en="0.040 %", disk="8 MB", threads="6",
         module={"es": "Barra de menús", "en": "Menu bar"},
         price={"es": "Gratis y código abierto (GPL-3.0)", "en": "Free and open source (GPL-3.0)"},
         does={"es": "Gestor de la barra de menús: esconde los iconos que no caben o no usas, y deja personalizar el aspecto de la barra.",
               "en": "A menu bar manager: hides the icons that don't fit or you don't use, and lets you restyle the bar itself."},
         theirs={"es": ["Personalizar el aspecto de la barra: fondo, sombra, bordes redondeados y formas", "Espaciado entre iconos configurable", "La «Ice Bar», una barra flotante propia donde se despliegan los iconos escondidos", "Sección «siempre oculta» además de la normal", "Buscador de iconos y ajustes distintos en apariencia clara u oscura"],
                 "en": ["Restyling the bar itself: background, shadow, rounded corners and shapes", "Configurable spacing between icons", "The “Ice Bar”, its own floating bar where hidden icons unfold", "An always-hidden section on top of the normal one", "Menu bar item search and different settings for light and dark appearance"]},
         ours={"es": ["Esconder iconos es un módulo más, no otra app residente", "Al arrancar recoloca los iconos antes de crearlos, para que el escondedor no se trague los de la propia app", "Comparte proceso con el notch, el ⌘Tab, el portapapeles y el sonido"],
               "en": ["Hiding icons is one more module, not another resident app", "On launch it re-places the icons before creating them, so the hider can't swallow its own", "Shares its process with the notch, ⌘Tab, the clipboard and sound"]},
         pick={"es": ["Ice si quieres control fino del aspecto de la barra, la sección siempre oculta o su barra flotante.", "OmniMac si solo quieres esconder lo que sobra y no sumar otra app residente."],
               "en": ["Ice if you want fine control over how the bar looks, the always-hidden section or its floating bar.", "OmniMac if you just want the clutter hidden and would rather not add another resident app."]}),
    dict(slug="finetune", name="FineTune", version="1.9.0", rss="116 MB", cpu="0,000 %", cpu_en="0.000 %", disk="11 MB", threads="6",
         module={"es": "Sonido", "en": "Sound"},
         price={"es": "Gratis (con donaciones)", "en": "Free (donation-supported)"},
         does={"es": "Control de audio por app: volumen individual, ecualizador con ajustes guardados, enrutado a dispositivos y perfiles de corrección para auriculares.",
               "en": "Per-app audio control: individual volume, an equaliser with saved presets, routing to devices and correction profiles for headphones."},
         theirs={"es": ["Perfiles de corrección AutoEQ por modelo de auricular, con catálogo descargable", "Compensación de sonoridad: refuerza los graves a volumen bajo", "Bloquear el dispositivo de entrada para que macOS no lo cambie solo", "Aviso al desconectarse un dispositivo y control de las teclas multimedia", "Guardar y renombrar tus propios ajustes del ecualizador"],
                 "en": ["AutoEQ correction profiles per headphone model, with a downloadable catalogue", "Loudness compensation: lifts the bass at low volume", "Locking the input device so macOS can't switch it on its own", "A notice when a device disconnects, and media-key control", "Saving and renaming your own equaliser presets"]},
         ours={"es": ["Ecualizador de 10 bandas con nueve ajustes preparados, general o por app", "Amplificación hasta el 400 % con limitador de picos", "El mezclador y el ecualizador también desde el notch, y suelto con ⌃⌥⌘V", "Prioridad de salidas: al conectar unos auriculares se ponen solos", "Y las otras diez funciones en el mismo proceso"],
               "en": ["A 10-band equaliser with nine ready-made presets, global or per app", "Boost up to 400 % with a peak limiter", "The mixer and the equaliser from the notch too, and standalone on ⌃⌥⌘V", "Output priority: plug in headphones and they take over on their own", "Plus the other ten features in the same process"]},
         pick={"es": ["FineTune si te importa la corrección por modelo de auricular y el detalle fino del audio.", "OmniMac si quieres volumen por app y un ecualizador decente sin sumar otra app residente."],
               "en": ["FineTune if headphone-model correction and fine audio detail matter to you.", "OmniMac if you want per-app volume and a decent equaliser without adding another resident app."]}),
    dict(slug="appcleaner", name="AppCleaner", version="3.6.8", rss="90 MB", cpu="0,000 %", cpu_en="0.000 %", disk="9 MB", threads="6",
         module={"es": "Limpiador de apps", "en": "App cleaner"},
         price={"es": "Gratis (no es código abierto)", "en": "Free (not open source)"},
         does={"es": "Desinstalador: arrastras una app y encuentra también los archivos que deja por el sistema para borrarlos con ella.",
               "en": "An uninstaller: drop an app on it and it also finds the files it leaves around the system, to remove them with it."},
         theirs={"es": ["SmartDelete: vigila la papelera y ofrece limpiar cuando arrastras una app a ella", "También desinstala widgets y plugins, no solo apps", "Lista aparte de apps del sistema, con protección para no tocarlas por error"],
                 "en": ["SmartDelete: watches the Trash and offers to clean up when you drag an app into it", "It also uninstalls widgets and plugins, not just apps", "A separate list of system apps, protected so you can't touch them by accident"]},
         ours={"es": ["Busca restos de apps que ya no están instaladas, no solo al desinstalar", "Descarta lo del sistema, los marcos compartidos y los contenedores de apps que sí tienes", "Avisa de lo que macOS no deja tocar (las carpetas de Contenedores) en vez de fallar en silencio", "No vive en segundo plano: es un módulo de una app que ya tienes abierta"],
               "en": ["It finds leftovers from apps that are no longer installed, not only while uninstalling", "It discards system files, shared frameworks and containers of apps you do have", "It warns about what macOS won't let it touch (Containers folders) instead of failing silently", "It doesn't live in the background: it is a module of an app you already have open"]},
         pick={"es": ["AppCleaner si quieres SmartDelete y limpiar también widgets y plugins.", "OmniMac si además quieres encontrar lo que dejaron las apps que ya borraste, sin instalar nada más."],
               "en": ["AppCleaner if you want SmartDelete and to clean widgets and plugins too.", "OmniMac if you also want to find what already-deleted apps left behind, without installing anything else."]}),
]

T = {
    "es": dict(lang="es", title="OmniMac frente a {name}: comparativa con datos", desc="{name} y OmniMac comparados con datos medidos: consumo en reposo, precio, lo que hace mejor cada uno y cuándo elegir cada app.",
               home="Inicio", other_lang="English", other_href="../../en/vs/{slug}/", eyebrow="Comparativa", h1="OmniMac frente a {name}", lead="{name} hace una cosa ({module}). OmniMac la hace y añade otros seis módulos en la misma app. Aquí van los datos, sin adjetivos: consumo medido en el mismo Mac, qué hace mejor cada uno y cuándo elegir uno u otro.",
               facts="Los datos", th=["", "{name} {version}", "OmniMac {oversion}"], rows=[("Qué hace", "{does}", "Siete módulos: mantener despierto, ⌘Tab por ventanas, notch dinámico, atajos de ventanas, portapapeles, utilidades (OCR, color, teclado, micrófono) y sonido"), ("Precio y código", "{price}", "Gratis, código abierto (MIT), sin cuentas ni telemetría"), ("Memoria en reposo (RSS)", "{rss}", "{orss} ({oreal} de memoria física real)"), ("CPU en reposo", "{cpu}", "{ocpu}"), ("Tamaño en disco", "{disk}", "{odisk}"), ("Hilos en reposo", "{threads}", "{othreads}"), ("Requisitos", "macOS (ver su web)", "macOS 14.2 o posterior, Apple silicon e Intel")],
               theirs="Lo que {name} hace y OmniMac no", ours="Lo que OmniMac añade", pick="Cuándo elegir cada una", method="Cómo se midió", methodtext="Cada app sola en el mismo MacBook con Apple silicon y macOS 26.5, el {date}, 50 s de reposo con el cursor lejos del notch tras 15 s de arranque. CPU = tiempo de CPU consumido dividido por el tiempo transcurrido (<code>ps -o cputime</code>); memoria = RSS (<code>ps -o rss</code>); la memoria física real de OmniMac (<code>footprint</code>) es de 27–36 MB en la medición de 0.5.0. Una sola tanda: son órdenes de magnitud, no décimas. Metodología completa y resultados en <a href=\"https://github.com/BySergiMM/OmniMac/blob/main/docs/PERFORMANCE.md\">docs/PERFORMANCE.md</a>; el inventario de funciones, en <a href=\"https://github.com/BySergiMM/OmniMac/blob/main/docs/COMPETENCIA.md\">docs/COMPETENCIA.md</a>.",
               cta="Prueba OmniMac", dl="Descargar OmniMac.pkg", gh="Ver el código en GitHub", ctanote="Gratis, sin cuentas. macOS 14.2 o posterior. Instala también con <code>brew install --cask BySergiMM/tap/omnimac</code>.",
               foot="{name} es una marca de sus autores; esta comparativa se basa en mediciones propias y en la documentación pública de cada app, y se corrige si nos avisan de un error: <a href=\"https://github.com/BySergiMM/OmniMac/issues\">issues</a>.", others="Otras comparativas:", back="← Todas las comparativas y la app"),
    "en": dict(lang="en", title="OmniMac vs {name}: a comparison with data", desc="{name} and OmniMac compared with measured data: idle usage, price, what each does better and when to pick each app.",
               home="Home", other_lang="Español", other_href="../../../vs/{slug}/", eyebrow="Comparison", h1="OmniMac vs {name}", lead="{name} does one thing ({module}). OmniMac does it and adds six more modules in the same app. Here are the facts, no adjectives: usage measured on the same Mac, what each does better and when to pick one or the other.",
               facts="The facts", th=["", "{name} {version}", "OmniMac {oversion}"], rows=[("What it does", "{does}", "Seven modules: keep awake, ⌘Tab by windows, dynamic notch, window shortcuts, clipboard, tools (OCR, colour, keyboard, microphone) and sound"), ("Price and code", "{price}", "Free, open source (MIT), no accounts, no telemetry"), ("Memory at idle (RSS)", "{rss}", "{orss} ({oreal} of real physical memory)"), ("CPU at idle", "{cpu}", "{ocpu}"), ("Size on disk", "{disk}", "{odisk}"), ("Threads at idle", "{threads}", "{othreads}"), ("Requirements", "macOS (see its site)", "macOS 14.2 or later, Apple silicon and Intel")],
               theirs="What {name} does that OmniMac doesn't", ours="What OmniMac adds", pick="When to pick each", method="How it was measured", methodtext="Each app on its own on the same Apple silicon MacBook running macOS 26.5, on {date}, 50 s at idle with the cursor away from the notch after 15 s of startup. CPU = CPU time consumed divided by elapsed time (<code>ps -o cputime</code>); memory = RSS (<code>ps -o rss</code>); OmniMac's real physical memory (<code>footprint</code>) is 27–36 MB in the 0.5.0 measurement. One run: think orders of magnitude, not decimals. Full methodology and results in <a href=\"https://github.com/BySergiMM/OmniMac/blob/main/docs/PERFORMANCE.md\">docs/PERFORMANCE.md</a> (Spanish); the feature inventory in <a href=\"https://github.com/BySergiMM/OmniMac/blob/main/docs/COMPETENCIA.md\">docs/COMPETENCIA.md</a>.",
               cta="Try OmniMac", dl="Download OmniMac.pkg", gh="See the code on GitHub", ctanote="Free, no accounts. macOS 14.2 or later. Also <code>brew install --cask BySergiMM/tap/omnimac</code>.",
               foot="{name} is a trademark of its authors; this comparison is based on our own measurements and on each app's public documentation, and is corrected if you report a mistake: <a href=\"https://github.com/BySergiMM/OmniMac/issues\">issues</a>.", others="Other comparisons:", back="← All comparisons and the app"),
}

CSS = """:root{--bg:#fff;--bg2:#f5f5f7;--ink:#1d1d1f;--ink2:#6e6e73;--line:#d2d2d7;--accent:#5b5bd6;--max:880px}*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--ink);font-family:-apple-system,BlinkMacSystemFont,"SF Pro Text","SF Pro Display","Helvetica Neue",Helvetica,Arial,sans-serif;-webkit-font-smoothing:antialiased;line-height:1.5}a{color:var(--accent);text-decoration:none}a:hover{text-decoration:underline}.wrap{max-width:var(--max);margin:0 auto;padding:0 24px}nav{position:sticky;top:0;background:rgba(255,255,255,.85);backdrop-filter:blur(14px);border-bottom:1px solid var(--line);z-index:5}nav .wrap{display:flex;align-items:center;justify-content:space-between;height:52px}nav .brand{display:flex;align-items:center;gap:10px;font-weight:600;color:var(--ink)}nav .brand img{width:26px;height:26px;border-radius:7px}nav .links{display:flex;gap:18px;font-size:14px}header{padding:72px 0 40px}.eyebrow{font-size:13px;font-weight:600;letter-spacing:.08em;text-transform:uppercase;color:var(--accent)}h1{font-size:clamp(34px,5vw,54px);line-height:1.08;letter-spacing:-.02em;margin:10px 0 18px}h2{font-size:26px;letter-spacing:-.01em;margin:0 0 14px}.lead{font-size:20px;color:var(--ink2);max-width:720px}section{padding:36px 0}.alt{background:var(--bg2)}table{width:100%;border-collapse:collapse;font-size:15.5px;background:#fff;border-radius:14px;overflow:hidden;box-shadow:0 1px 0 var(--line),0 8px 30px rgba(0,0,0,.05)}th,td{text-align:left;padding:13px 16px;border-bottom:1px solid var(--line);vertical-align:top}th{background:var(--bg2);font-weight:600}td:first-child{color:var(--ink2);white-space:nowrap}td.me{font-weight:600}tr:last-child td{border-bottom:0}.tbl{overflow-x:auto}ul{padding-left:20px;margin:0}li{margin:8px 0}.two{display:grid;grid-template-columns:1fr 1fr;gap:28px}@media(max-width:700px){.two{grid-template-columns:1fr}td:first-child{white-space:normal}}.note{font-size:14px;color:var(--ink2)}.cta{background:#000;color:#fff;text-align:center;padding:64px 0;border-radius:24px;margin:28px 0}.cta h2{color:#fff;font-size:34px}.btn{display:inline-flex;align-items:center;gap:8px;padding:13px 24px;border-radius:999px;font-weight:600;font-size:16px;margin:8px 6px 0}.btn.primary{background:var(--accent);color:#fff}.btn.ghost{background:rgba(255,255,255,.1);color:#fff;border:1px solid rgba(255,255,255,.25)}.cta .note{color:#a1a1a6;margin-top:14px}code{background:var(--bg2);padding:1px 6px;border-radius:6px;font-size:.92em}.cta code{background:#2c2c2e;color:#fff}footer{padding:36px 0 56px;font-size:13.5px;color:var(--ink2)}footer p{margin:6px 0}"""

def fmt(s, app, lang):
    o = OMNI
    return s.format(name=app["name"], version=app["version"], slug=app["slug"], module=app["module"][lang], does=app["does"][lang], price=app["price"][lang],
                    rss=app["rss"], cpu=app["cpu" if lang == "es" else "cpu_en"], disk=app["disk"], threads=app["threads"],
                    oversion=o["version"], orss=o["rss"], oreal=o["real"], ocpu=o["cpu" if lang == "es" else "cpu_en"], odisk=o["disk"], othreads=o["threads"], date=DATE[lang])

def page(app, lang):
    t = T[lang]
    prefix = "../../" if lang == "es" else "../../../"          # hasta docs/site/
    home = prefix if lang == "es" else prefix + "en/"
    url = BASE + ("vs/" if lang == "es" else "en/vs/") + app["slug"] + "/"
    alt_es, alt_en = BASE + "vs/" + app["slug"] + "/", BASE + "en/vs/" + app["slug"] + "/"
    others = " · ".join(f'<a href="../{a["slug"]}/">{a["name"]}</a>' for a in APPS if a is not app)
    rows = "".join(f"<tr><td>{fmt(r[0], app, lang)}</td><td>{fmt(r[1], app, lang)}</td><td class=\"me\">{fmt(r[2], app, lang)}</td></tr>" for r in t["rows"])
    li = lambda items: "".join(f"<li>{x}</li>" for x in items)
    ld = {"@context": "https://schema.org", "@type": "Article", "headline": fmt(t["h1"], app, lang), "inLanguage": lang, "datePublished": "2026-09-05", "dateModified": datetime.date.today().isoformat(),
          "author": {"@type": "Person", "name": "Sergi (BySergiMM)", "url": "https://github.com/BySergiMM"}, "about": {"@type": "SoftwareApplication", "name": "OmniMac", "operatingSystem": "macOS 14.2+", "applicationCategory": "UtilitiesApplication", "offers": {"@type": "Offer", "price": "0", "priceCurrency": "EUR"}, "url": BASE}}
    import json
    return f"""<!doctype html>
<html lang="{lang}">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{fmt(t["title"], app, lang)}</title>
<meta name="description" content="{fmt(t["desc"], app, lang)}">
<link rel="canonical" href="{url}">
<link rel="alternate" hreflang="es" href="{alt_es}">
<link rel="alternate" hreflang="en" href="{alt_en}">
<link rel="alternate" hreflang="x-default" href="{alt_en}">
<meta property="og:title" content="{fmt(t["title"], app, lang)}">
<meta property="og:description" content="{fmt(t["desc"], app, lang)}">
<meta property="og:image" content="{BASE}img/social-preview.png">
<meta property="og:type" content="article">
<meta name="twitter:card" content="summary_large_image">
<link rel="icon" href="{prefix}img/icon.png">
<script type="application/ld+json">{json.dumps(ld, ensure_ascii=False)}</script>
<style>{CSS}</style>
</head>
<body>
<nav><div class="wrap"><a class="brand" href="{home}"><img src="{prefix}img/icon.png" alt="">OmniMac</a><div class="links"><a href="{home}">{t["home"]}</a><a href="{fmt(t["other_href"], app, lang)}">{t["other_lang"]}</a><a href="https://github.com/BySergiMM/OmniMac">GitHub</a></div></div></nav>
<header><div class="wrap"><div class="eyebrow">{t["eyebrow"]}</div><h1>{fmt(t["h1"], app, lang)}</h1><p class="lead">{fmt(t["lead"], app, lang)}</p></div></header>
<section class="alt"><div class="wrap"><h2>{t["facts"]}</h2><div class="tbl"><table><thead><tr><th>{fmt(t["th"][0], app, lang)}</th><th>{fmt(t["th"][1], app, lang)}</th><th>{fmt(t["th"][2], app, lang)}</th></tr></thead><tbody>{rows}</tbody></table></div></div></section>
<section><div class="wrap two"><div><h2>{fmt(t["theirs"], app, lang)}</h2><ul>{li(app["theirs"][lang])}</ul></div><div><h2>{t["ours"]}</h2><ul>{li(app["ours"][lang])}</ul></div></div></section>
<section class="alt"><div class="wrap"><h2>{t["pick"]}</h2><ul>{li(app["pick"][lang])}</ul></div></section>
<section><div class="wrap"><h2>{t["method"]}</h2><p class="note">{fmt(t["methodtext"], app, lang)}</p></div></section>
<div class="wrap"><div class="cta"><h2>{t["cta"]}</h2><a class="btn primary" href="https://github.com/BySergiMM/OmniMac/releases/latest/download/OmniMac.pkg">{t["dl"]}</a><a class="btn ghost" href="https://github.com/BySergiMM/OmniMac">{t["gh"]}</a><p class="note">{t["ctanote"]}</p></div></div>
<footer><div class="wrap"><p>{t["others"]} {others} · <a href="{home}#comparativa">{t["back"]}</a></p><p>{fmt(t["foot"], app, lang)}</p></div></footer>
</body>
</html>
"""

def main():
    urls = [BASE, BASE + "en/"]
    for app in APPS:
        for lang in ("es", "en"):
            folder = os.path.join(ROOT, "vs" if lang == "es" else "en/vs", app["slug"])
            os.makedirs(folder, exist_ok=True)
            with open(os.path.join(folder, "index.html"), "w", encoding="utf-8") as f:
                f.write(page(app, lang))
            urls.append(BASE + ("vs/" if lang == "es" else "en/vs/") + app["slug"] + "/")
    today = datetime.date.today().isoformat()
    with open(os.path.join(ROOT, "sitemap.xml"), "w", encoding="utf-8") as f:
        f.write('<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n' + "".join(f"  <url><loc>{u}</loc><lastmod>{today}</lastmod></url>\n" for u in urls) + "</urlset>\n")
    with open(os.path.join(ROOT, "robots.txt"), "w", encoding="utf-8") as f:
        f.write(f"User-agent: *\nAllow: /\nSitemap: {BASE}sitemap.xml\n")
    print(f"{len(APPS) * 2} páginas comparativas, sitemap.xml ({len(urls)} URL) y robots.txt")

if __name__ == "__main__":
    main()
