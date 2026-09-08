# OmniMac

App de barra de menús para macOS (Swift + SwiftUI, SwiftPM, macOS 14.2+).
Siete módulos en una sola app: mantener despierto, ⌘Tab por ventanas, notch dinámico,
atajos y disposiciones de ventanas, portapapeles, utilidades y sonido.

## Al publicar una versión: lee `docs/RELEASE.md`

**Antes de tocar nada de una release, abre `docs/RELEASE.md` y sigue la lista.**
La app es solo la mitad del trabajo: hay que volver a medir el consumo, actualizar la
web en los dos idiomas, los dos README del proyecto, el README del perfil de GitHub
(repositorio aparte `BySergiMM/BySergiMM`), el cask de Homebrew y la comparativa con
las apps a las que sustituye. Si se publica el binario y no se toca lo demás, la web
anuncia funciones que no existen y las cifras dejan de ser ciertas.

## Cómo se trabaja aquí

- **No hagas commits salvo que Sergi lo pida.** «Trabajar en local» incluye no
  confirmar en git: deja los cambios sin confirmar y avisa cuando algo esté listo.
- **No publiques nunca** (push, release, web, redes) sin un sí explícito.
- Si una instrucción admite dos lecturas, pregunta antes de elegir una.
- Código y comentarios **en español**, explicando el porqué y no el qué. Los textos
  visibles van siempre en `L("español", "English")`.
- Lo que se pueda probar sin abrir ventanas, se prueba: la lógica va aparte de la
  vista para que tenga pruebas.

## Comandos

```bash
swift build                      # compilar
swift test                       # las pruebas (deben quedar en verde)
scripts/dev/quickbuild.sh        # recompila solo arm64 en segundos, misma firma
./build.sh run                   # compilación completa y ejecutar
./build.sh pkg                   # instalador
scripts/release.sh X.Y.Z --publish   # publicar (ver docs/RELEASE.md antes)
```

## Herramientas de prueba (`scripts/dev`)

`measure.sh` (consumo en reposo), `wakeups.sh` (despertares, restando dos muestras),
`notch.swift` (alto del panel: 32 plegado, 232 abierto), `mouse.swift`, `keys.swift`,
`drag.swift`, `settings.swift` (recorrer Ajustes por accesibilidad), `video.swift`.

## Trampas conocidas

- Las columnas IDLEW y CSW de `top -l` son **contadores acumulados**, no tasas.
- Los menús de la app se ponen a tirones si el notch tiene puesto su monitor global de
  ratón: mientras existe, macOS despierta la app en cada movimiento del ratón. Se quita
  mientras hay un menú abierto (ver `NotchFeature.setHiddenForMenu`).
- macOS reescribe por su cuenta las posiciones de los iconos de la barra; el escondedor
  llegó a tragarse los de OmniMac. Se recolocan al arrancar, **antes** de crearlos.
- Un `grep` de una línea no encuentra las llamadas `L(...)` partidas en varias.
