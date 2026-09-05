# OmniMac — Marca, lanzamiento y monetización

## Identidad

- **Nombre**: OmniMac
- **Tagline**: «Todo lo que le falta a tu Mac» · EN: *"Everything your Mac is missing"*
- **Personalidad**: cercana y clara, cero jerga. Promesa: *una app, cero fricción*.
- **Color**: violeta `#6C4DFF` + lila `#A98BFF` sobre tinta `#1A0F47`.
- **Icono**: chispa blanca + notch sobre degradado violeta (generado con `scripts/make-icon.swift`).
- **Voz**: segunda persona, frases cortas. Español nativo + versión EN para el lanzamiento global.

## Posicionamiento

> **5 utilidades que instalarías por separado, en una sola app nativa, gratis y de código abierto.**

Diferenciadores frente a Amphetamine + BoringNotch + AltTab + Rectangle + Maccy:

1. **Todo-en-uno modular** — un solo icono en la barra, cada función con su interruptor.
2. **Privacidad radical** — sin cuentas, sin telemetría, portapapeles solo en memoria.
3. **Nativa y ligera** — Swift/SwiftUI, sin Electron, arranca en milisegundos.

## Canales de lanzamiento (herramienta gratuita)

| Canal | Jugada |
|---|---|
| **GitHub** | README en inglés con GIFs de cada módulo, topics (`macos`, `menubar`, `notch`), releases con `.dmg`. Es la base de todo lo demás. |
| **Product Hunt** | Martes–jueves. Hero: GIF del notch expandiéndose con música + AirDrop. |
| **Hacker News** | «Show HN: OmniMac – one free menu bar app replacing 5 Mac utilities». |
| **Reddit** | r/macapps, r/MacOS, r/apple. Mostrar, no vender: vídeo corto + responder todo. |
| **TikTok / Shorts / Reels** | El notch es muy visual: «tu Mac puede hacer esto y no lo sabías». 15–30 s por módulo. |
| **X / Mastodon** | Build in public: progreso, clips, encuestas de próximos módulos. |
| **Homebrew** | `brew install --cask omnimac` en cuanto haya release estable. |
| **Listas** | awesome-mac, AlternativeTo, MacMenuBar.com, ToolFinder. |
| **Prensa Mac** | 9to5Mac tips, MacStories, y en español Applesfera / Hipertextual. |
| **Landing** | GitHub Pages: demo GIF arriba, botón de descarga, comparativa «5 apps → 1». |

**Calendario sugerido**

1. Semanas 1–2: pulir, cuenta Apple Developer (99 €/año) para firmar y **notarizar** el `.dmg` (sin esto Gatekeeper asusta a la mayoría), landing y GIFs.
2. Semana 3: soft launch en GitHub + Reddit, iterar con el feedback.
3. Semana 4: Product Hunt + Show HN el mismo día.

**Métricas**: estrellas GitHub, descargas por release, y (solo si el usuario acepta, nunca por defecto) usuarios activos.

## Monetización (la base siempre gratis)

Escalera, de menor a mayor esfuerzo:

1. **Donaciones desde el día 1** — GitHub Sponsors + Buy Me a Coffee + «tip jar» discreto en Ajustes.
2. **OmniMac Pro** (pago único, 9–15 €) — freemium honesto: lo que hoy existe será gratis siempre; Pro añade extras de poder:
   - Temas y tamaños del notch
   - Atajos personalizables
   - Portapapeles persistente con búsqueda e imágenes
   - Miniaturas en vivo en ⌘Tab
   - Sincronización de ajustes vía iCloud
   - Módulos premium futuros (ocultar iconos de la barra, No molestar por app…)
3. **Setapp** — cuando haya tracción, ingresos recurrentes por uso sin gestionar pagos.
4. **Licencia para equipos** — despliegue MDM y ajustes gestionados para empresas.
5. **Nunca**: anuncios, venta de datos, ni suscripción para funciones básicas.

La regla que protege la marca: **lo gratuito nunca empeora**. Pro añade, no recorta.

## Ko-fi (ko-fi.com/seergiii) y GitHub Sponsors (github.com/sponsors/BySergiMM)

**Titular (una línea):** Hago OmniMac, la app gratuita que le da a tu Mac todo lo que le falta.

**Bio corta (campo «Sobre mí»):**

> Hago **OmniMac**, una app gratuita y de código abierto que le da a tu Mac lo que le falta: un notch dinámico con tu música, ⌘Tab por ventanas, atajos para colocar ventanas, historial del portapapeles y un «mantener despierto» que aguanta con la tapa cerrada. Todo en una sola app ligera (72 MB, 0,03 % de CPU), sin anuncios, sin cuentas y sin telemetría.
>
> La desarrollo en mi tiempo libre. Si te ahorra tiempo cada día, un café me ayuda a seguir puliéndola y a pagar la firma de Apple para que se instale sin avisos. ☕️

**Versión en inglés (Ko-fi es internacional):**

> I build **OmniMac**, a free, open-source app that gives your Mac everything it's missing: a dynamic notch with your music, ⌘Tab by windows, window-snapping shortcuts, clipboard history and a keep-awake that survives closing the lid. One tiny app (72 MB, 0.03 % CPU), no ads, no accounts, no tracking.
>
> I make it in my spare time. If it saves you time every day, a coffee keeps me polishing it and pays for Apple's signing so it installs without warnings. ☕️

**Niveles sugeridos:**

| Nivel | Precio | Qué recibe |
|---|---|---|
| Un café | 3 € | Gracias en el README |
| Café y tostada | 5 € | Tu nombre en «Agradecimientos» de la app |
| Mecenas | 10 €/mes | Prioridad en peticiones de funciones y acceso a betas |

**Objetivo público sugerido:** «99 €/año: certificado de desarrollador de Apple para firmar y notarizar OmniMac».

## Posts e imágenes para Ko-fi

En `docs/kofi/`: `posts.md` (cuatro posts en español e inglés y el texto del perfil), `cover.png` y `avatar.png` para el perfil, `post-*.png` como portadas de cada post y `galeria-*.png` para la pestaña Galería. Todo generado a partir de capturas reales de la app.

## Promoción en GitHub y fuera (4 de septiembre de 2026; cifras actualizadas a 0.4.1 el 5)

Hecho:
- Temas del repositorio, Discussions, botón Sponsor (`.github/FUNDING.yml`), imagen social (`docs/site/img/social-preview.png`).
- Tap de Homebrew: https://github.com/BySergiMM/homebrew-tap → `brew install --cask BySergiMM/tap/omnimac` (release.sh lo actualiza al publicar).
- Pull requests a las listas: https://github.com/jaywcjlove/awesome-mac/pull/2765 · https://github.com/iCHAIT/awesome-macOS/pull/1072 · https://github.com/serhii-londar/open-source-mac-os-apps/pull/1331
- Material preparado el 5 de septiembre de 2026 (0.4.1):
  - GIF del notch para el README y Reddit: `docs/site/img/demo.gif` (ES) y `docs/site/img/en/demo.gif` (EN); se regeneran con `scripts/dev/hero-gif.swift` a partir de la animación de la web.
  - Guion del vídeo de 30 s y versión vertical: `docs/VIDEO.md`.
  - Kit de Product Hunt (textos, galería 1270×760, primer comentario, respuestas): `docs/producthunt/`.
  - Fichas para AlternativeTo, MacUpdate y MacMenuBar: `docs/DIRECTORIOS.md`.
  - Páginas comparativas «OmniMac frente a X» en español e inglés, con sitemap y datos estructurados: `docs/site/vs/` y `docs/site/en/vs/` (generador `docs/site/tools/make_vs.py`).
  - Artículo para blog y correos para Applesfera, Hipertextual, 9to5Mac y MacStories: `docs/prensa/`.
  - Recordatorios programados en la app de Claude: Reddit el martes 8 de septiembre a las 15:00 y Show HN el miércoles 9 a las 15:00, con los textos listos (no publican nada solos).

### Reddit · r/macapps (inglés)

**Título:** I built OmniMac: seven Mac utilities (keep-awake, ⌘Tab by windows, dynamic notch, window snapping, clipboard, OCR, per-app volume) in one free, open-source menu-bar app

**Texto:** I got tired of running Amphetamine, AltTab, Rectangle, Maccy and a notch app side by side, so I wrote one native Swift app that does all of it and stays out of the way: 0.017 % CPU, 19–27 MB of real memory and under one wake-up per second at idle (measurements and methodology in the repo). It also does per-app volume, screen OCR, a colour picker and an iPhone-style card when your AirPods connect. Free, MIT, universal binary, macOS 14.2+, interface in English and Spanish. Website: https://bysergimm.github.io/OmniMac/en/ · Code: https://github.com/BySergiMM/OmniMac

### Hacker News · Show HN (la app ya está en inglés desde 0.4.0)

**Título:** Show HN: OmniMac – seven Mac utilities in one 25 MB open-source menu-bar app

**Texto:** OmniMac replaces the five utilities I kept installing on every Mac (keep-awake, ⌘Tab by windows, a notch companion, window snapping, a clipboard manager) with a single native Swift/SwiftUI app, and adds per-app volume, screen OCR, a colour picker and an AirPods card in the notch. I measured it against the apps it replaces with the same method: 636 MB for the five together vs 119 MB RSS / 19–27 MB real memory for OmniMac, at 0.017 % CPU idle and under one wake-up per second. MIT, no accounts, no telemetry, universal binary, macOS 14.2+. https://bysergimm.github.io/OmniMac/en/

### MacUpdate / AlternativeTo (requieren cuenta)

Nombre: OmniMac · Categoría: Utilidades / Menú · Precio: gratis · Licencia: MIT · Web: https://bysergimm.github.io/OmniMac/ · Descarga: https://github.com/BySergiMM/OmniMac/releases/latest/download/OmniMac.pkg · Descripción corta: la del post de Reddit. Alternativa a: Amphetamine, AltTab, Rectangle, Maccy, BoringNotch.


## LinkedIn (ideas de posts · nada se publica sin que Sergi lo diga)

Reglas que funcionan en LinkedIn: la primera línea decide si alguien pulsa «ver más», así que
es un gancho, no un título; vídeo subido directamente (no un enlace de YouTube), mejor el
vertical o el 16:9 con subtítulos; el enlace externo va en el primer comentario, no en el
cuerpo (LinkedIn recorta el alcance de los posts con enlaces); 3–5 hashtags al final; publicar
de martes a jueves entre las 8 y las 10; contestar todos los comentarios la primera hora;
terminar con una pregunta. Un post cada 4–7 días, no todos el mismo día.

### 1 · Lanzamiento (con el vídeo vertical o el tráiler 16:9)

> Tenía cinco apps en la barra de menús del Mac. Ahora tengo una. La he hecho yo.
>
> Amphetamine para que no se durmiera, AltTab para cambiar de ventana, Rectangle para
> colocarlas, Maccy para el portapapeles y otra para el notch. Cinco iconos, cinco
> actualizadores, 636 MB de memoria entre todas.
>
> OmniMac hace todo eso en una sola app nativa (Swift), y añade lo que echaba de menos:
> volumen por app, OCR de la pantalla, un selector de color y una tarjeta como la del iPhone
> cuando conecto los AirPods.
>
> En reposo: 0,017 % de CPU y 25 MB de memoria. Medido, no prometido: la metodología está en el
> repositorio.
>
> Gratis, de código abierto (MIT), en español e inglés. Enlace en el primer comentario.
>
> ¿Qué utilidad no te quitarías nunca del Mac?
>
> #macOS #Swift #OpenSource #Productividad #IndieDev

### 2 · La fuga que no existía (aprendizaje técnico)

> Perdí una tarde entera persiguiendo una fuga de memoria que no existía.
>
> Medía los «despertares» de mi app con `top` y cada vez que abría el notch subían 35 por
> segundo. Tres horas de heap dumps, lldb y teorías sobre run loops.
>
> La causa: la columna IDLEW de `top -l` es un contador acumulado desde que arranca el proceso,
> no una tasa. Estaba dividiendo un total por tres segundos.
>
> Lo que sí encontré por el camino y arreglé: un puerto Mach que se filtraba en cada apertura y
> un run loop por hilo que dejaba AppleScript en GCD.
>
> Moraleja: antes de optimizar, comprueba que la métrica mide lo que crees que mide. Lo dejé
> documentado en el repo para que nadie repita el tropiezo.
>
> ¿Cuál ha sido tu «fuga» fantasma?
>
> #Swift #macOS #Performance #Debugging

### 3 · Comparativa con datos (imagen: gráfico de barras de la web)

> 636 MB frente a 25 MB. Mismo Mac, mismo método, cada app medida sola.
>
> Comparé OmniMac con las cinco utilidades a las que sustituye. No es magia: es no hacer nada
> cuando no se usa. Nada sondea en reposo, cada módulo apagado no consume, y el trabajo por
> fotograma va a CoreAnimation, no al hilo principal.
>
> La comparativa completa, con lo que cada app hace mejor que la mía, está en la web. Porque
> AltTab, Rectangle, Maccy y Amphetamine son muy buenas en lo suyo; yo solo quería una sola app.
>
> #macOS #Swift #OpenSource

### 4 · Este vídeo lo grabó un script (detrás de las cámaras; adjuntar el vídeo)

> Este vídeo de mi app no lo grabé yo. Lo grabó un script.
>
> Quería un vídeo de demostración limpio y no tenía ganas de repetir 14 escenas a mano. Así
> que la propia tubería de pruebas mueve el ratón, pulsa los atajos, arrastra archivos al
> notch y graba cada escena con `screencapture`. El montaje (fondo, recortes, títulos) lo hace
> un script de AVFoundation sin ninguna dependencia.
>
> Lo mejor: cuando cambie la interfaz, el vídeo se regenera solo.
>
> ¿Automatizáis las demos de vuestros productos?
>
> #Automation #Swift #macOS #IndieDev

### 5 · Por qué no está en la App Store (transparencia)

> Me preguntan por qué OmniMac no está en la App Store.
>
> Porque la mitad de lo que hace (colocar ventanas de otras apps, ⌘Tab por ventanas, mantener
> el Mac despierto con la tapa cerrada) necesita permisos que el sandbox no permite. Así que
> es código abierto, se instala con un .pkg o con Homebrew, y todo lo que hace está a la vista.
>
> Lo que aún no tiene: la notarización de Apple (99 €/año que todavía no he pagado). La primera
> vez hay que abrirla con clic derecho › Abrir. Si el proyecto crece, será lo primero.
>
> Si la pruebas y te falta algo, dímelo: el backlog público está en GitHub.
>
> #OpenSource #macOS #Swift

### 6 · Carrusel (PDF con las cinco imágenes de `docs/producthunt/`)

LinkedIn muestra los PDF como carrusel: portada «Todo lo que le falta a tu Mac», una página por
bloque (notch, AirPods, módulos, consumo) y una última con la web. Texto corto: «7 utilidades en
una app. Desliza.» Es el formato con más alcance orgánico ahora mismo.

### Versión en inglés

Los mismos posts en inglés valen para X y para el público internacional de LinkedIn; el
tráiler `omnimac-16x9-en.mp4` y la web en inglés ya están listos.
