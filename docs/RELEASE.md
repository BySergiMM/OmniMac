# Publicar una versión de OmniMac

Lista completa de lo que hay que tocar. **La app es solo la mitad del trabajo**: si se
publica el binario y no se toca lo demás, la web anuncia funciones que no existen, los
README enseñan cifras viejas y la comparativa con las otras ocho apps deja de ser cierta.

Marca cada punto al hacerlo. El orden importa: las medidas van antes de escribir los
textos, porque los textos citan las medidas.

---

## 1. Antes de empezar

- [ ] `swift test` en verde.
- [ ] Probado en el Mac de verdad, no solo compilado: `scripts/dev/quickbuild.sh` y
      abrir la app.
- [ ] `CHANGELOG.md` con la entrada de la versión, en el formato de siempre
      (`## 0.4.3 — 2026-09-10` y viñetas `- Zona: qué cambia`).
      **No es opcional**: es lo que lee la ventana de Novedades que se abre tras
      actualizar, y de ahí salen sus pantallas.
- [ ] `CHANGELOG.en.md` con la misma entrada traducida. Si falta, quien tenga la app
      en inglés verá las novedades en español.
- [ ] Nada personal en el código (nombres, rutas con tu usuario, capturas de tu Mac).
- [ ] Todo lo que entra en la versión está **confirmado en `main`** y `git status` sale
      limpio. El script se niega a seguir si no: lo que se compila tiene que ser lo que
      queda en la etiqueta.

## 2. Medir otra vez (antes de escribir nada)

Las cifras de consumo son el argumento principal de OmniMac. Si se publican funciones
nuevas sin volver a medir, la comparativa deja de ser real.

- [ ] Reposo: `scripts/dev/measure.sh` (60 s, con el notch plegado).
- [ ] Despertares: `scripts/dev/wakeups.sh` — **resta dos muestras**; las columnas
      IDLEW y CSW de `top -l` son contadores acumulados, no tasas.
- [ ] Memoria física real con `footprint`, no el RSS.
- [ ] Con el notch abierto y música sonando, que es el caso peor.
- [ ] Si se ha tocado audio (ecualizador, volumen por app), medir también con el
      mezclador activo: ahí es donde puede dispararse.
- [ ] Actualizar `docs/PERFORMANCE.md` con la fecha, la versión y el método.
- [ ] Si las cifras cambian, actualizarlas **en todos los sitios donde se citan**:
      `README.md`, `README.es.md`, `docs/site/index.html`, `docs/site/en/index.html`
      y las páginas de `docs/site/vs`.

Y cada varios meses, o cuando alguna de ellas saque versión mayor:

- [ ] Volver a medir **las ocho apps a las que sustituye** (Amphetamine, AltTab,
      Rectangle, Maccy, BoringNotch, Ice, FineTune y AppCleaner), cada una sola y con
      el mismo método, y las siete residentes juntas. Instalarlas solo para medir y
      desinstalarlas después. **Pedir permiso a Sergi antes de descargar nada.**
      Dos trampas ya vistas: Ice no arranca sin permiso de Accesibilidad (concederlo
      es cosa suya, pide contraseña) y su ventana de bienvenida infla la CPU a 3,5 %;
      AppCleaner no vive en segundo plano, así que va fuera del total.
- [ ] Actualizar `docs/COMPETENCIA.md` con sus versiones y funciones nuevas.
- [ ] Si entra una app nueva a la comparativa, crear su página en `docs/site/vs/<slug>/`
      y `docs/site/en/vs/<slug>/`, añadir el enlace en el pie de **todas** las demás
      (el pie en inglés usa otra ruta de vuelta) y meter las dos URLs en `sitemap.xml`.

## 3. Publicar la app

- [ ] `scripts/release.sh X.Y.Z` primero, como ensayo: compila, empaqueta, firma y deja todo
      en `dist/release`, y **no toca git** (la subida de versión se deshace al terminar).
- [ ] `scripts/release.sh X.Y.Z --publish`. Se niega si el árbol no está limpio, si no
      estás en `main` al día con `origin/main`, si la etiqueta `vX.Y.Z` ya existe (aquí o
      en GitHub) o si falta la entrada de `CHANGELOG.md` / `CHANGELOG.en.md`. Si pasa
      todo, hace esto, en este orden:
      1. sube la versión y el número de build en `Resources/Info.plist`, compila y genera
         el `.zip`, el `.pkg` y el appcast;
      2. confirma esa subida en un commit, `X.Y.Z (build N)`;
      3. crea la etiqueta **anotada** `vX.Y.Z` sobre ese commit;
      4. sube commit y etiqueta (`git push --follow-tags origin main`);
      5. crea la release con `gh release create --verify-tag` (si tu `gh` no conoce esa
         opción, actualízalo: sin ella `gh` crearía la etiqueta él, sobre otro commit);
      6. actualiza el cask de Homebrew.

      Por qué ese orden: antes la etiqueta la creaba `gh` sobre la punta de `main` cuando
      aún no existía el commit de la subida de versión, y las etiquetas v0.5.2 a v0.5.4
      apuntan al commit anterior (la de v0.5.4 trae un `Info.plist` que dice 0.5.3). Esas
      etiquetas no se tocan: reetiquetar una release publicada rompe a quien ya la tiene.
- [ ] Si el script se queda a medias después del commit (se lo dice), no repitas el
      comando: mira `git log -1`, `git ls-remote --tags origin vX.Y.Z` y
      `gh release view vX.Y.Z`, y termina a mano lo que falte.
- [ ] Comprobar que la release trae `OmniMac.pkg`, el `.zip` y `appcast.xml`, y que la
      etiqueta es anotada y lleva la versión nueva: `git cat-file -t vX.Y.Z` dice `tag`
      y `git show vX.Y.Z:Resources/Info.plist` tiene `X.Y.Z`.
- [ ] Que Sparkle ve la actualización: menú › «Buscar actualizaciones…».
- [ ] Descargar el `.pkg` desde el enlace de la web y abrirlo, como haría alguien nuevo.
- [ ] **Homebrew**: el script ya actualiza el cask de `BySergiMM/homebrew-tap` (cambia
      con `sed` las líneas `version` y `sha256` de `Casks/omnimac.rb`). Comprueba que lo
      hizo; si algún día esas dos líneas cambian de forma, cambia también el `sed`.

## 4. La web (`docs/site`)

- [ ] Funciones nuevas en `index.html` y en `en/index.html`. Las dos, siempre.
- [ ] Capturas nuevas si la interfaz ha cambiado:
      `OmniMac --snapshots docs/site/img` y `--snapshots … --lang en`.
- [ ] Vídeo, si la novedad se entiende mejor viéndola (`docs/site/video`).
- [ ] Páginas de comparación (`docs/site/vs`): `python3 docs/site/tools/make_vs.py`.
- [ ] `sitemap.xml` con las páginas nuevas y la fecha.
- [ ] Que las etiquetas Open Graph de las dos versiones digan lo suyo: la raíz está en
      inglés y `/es/` en español. La tarjeta por defecto (`img/social-preview.png`, la que
      sube GitHub y la que captura cualquiera al compartir) es la inglesa; `/es/` usa
      `img/es/social-preview.png`.
- [ ] **Tarjeta social**, que lleva el número de módulos y las cifras de consumo
      escritos dentro de la imagen y por eso caduca sin que se note:

      swift scripts/dev/social.swift en docs/site/img/social-preview.png
      swift scripts/dev/social.swift es docs/site/img/es/social-preview.png

      Los textos están arriba del guion: número de módulos, CPU en reposo, memoria y
      disco. Súbela también a GitHub › Settings › General › **Social preview** — eso
      no tiene API, se hace a mano.

## 5. Los README

- [ ] `README.md` y `README.es.md`: módulos nuevos en la tabla, cifras de consumo,
      vídeo y capturas.
- [ ] **README de tu perfil de GitHub** (repositorio `BySergiMM/BySergiMM`): es un
      repositorio aparte, no está en este proyecto. Actualizar ahí la descripción de
      OmniMac y las cifras si las cita.
- [ ] **Descripción del repositorio en GitHub** (`gh api -X PATCH repos/BySergiMM/OmniMac
      -f description=…`): también lleva el número de módulos y la CPU en reposo.

## 5 bis. LinkedIn

Fuera del repositorio, y por eso se olvida. Todo esto cita el número de módulos o el
consumo, así que caduca en cada versión:

- [ ] **Perfil › Acerca de**: número de módulos y memoria.
- [ ] **Perfil › Proyectos › OmniMac**: la descripción larga, con las cifras.
- [ ] **Perfil › Destacado**: el resumen corto de OmniMac.
- [ ] Las tres existen en **español y en inglés** (versión secundaria del perfil).

## 6. Limpieza (lo que le llega a quien no es tú)

- [ ] Que el repositorio público no tenga nada que a un usuario no le sirva: notas
      personales, material de promoción, capturas de pruebas, borradores.
      Eso vive en el repositorio privado `BySergiMM/omnimac-marketing`.
- [ ] `.gitignore` al día (`dist/`, `.build/`, capturas temporales).
- [ ] Sin restos de depuración: `NSLog`, `print`, TODO/FIXME olvidados.
      Los avisos de lentitud que sí deben quedarse están documentados en el código.
- [ ] Traducciones: que ningún texto visible se haya quedado sin `L(...)`.
      Un `grep` de una línea no ve las llamadas partidas en varias, así que revisar
      también `Text(`, `Button(`, `NSMenuItem(title:`, `.help(`, `toolTip`.

## 7. Después de publicar

- [ ] Abrir la app actualizada y comprobar que **la ventana de Novedades** sale una vez
      y enseña lo de esta versión.
- [ ] Mirar que la web se ha desplegado (GitHub Pages tarda un par de minutos).
- [ ] Si la versión trae algo que enseñar, avisar donde toque (Ko-fi, LinkedIn, y la
      lista de sitios de `omnimac-marketing/DIRECTORIOS.md`).
