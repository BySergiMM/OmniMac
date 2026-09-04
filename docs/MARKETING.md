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

