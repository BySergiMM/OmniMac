# OmniMac — Estudio de consumo y optimización

Mediciones en Apple Silicon, macOS 26.5. CPU media obtenida por diferencia de
tiempo de CPU (`ps -o cputime`) durante la ventana indicada; RSS con `ps -o rss`.
Script reproducible en `scripts/` del historial de desarrollo.

## Resultados (antes → después)

| Escenario | CPU media | RAM (RSS) | Hilos |
|---|---|---|---|
| **Reposo** (notch plegado) — antes | 0,12 % | 64 MB | 4 |
| **Reposo** (notch plegado) — **después** | **0,02 %** | **48 MB** | **3** |
| **Expandido + música** — antes¹ | 9,4 % | 72 MB | 7 |
| **Expandido + música** — **después** | **2,1 %** | 72 MB | 7 |

Reposo largo (3 min) tras optimizar: **0,02 % CPU, 48 MB, 3 hilos** — estable, sin fugas.
Despertares de CPU en reposo (*idle wakeups*): ~75/s, impacto de batería insignificante.

¹ La animación del ecualizador (SwiftUI `repeatForever`) más la barra de progreso
animada 1,5 s eran el grueso del coste; el perfilado (`sample`) lo situó en
renderizado de SwiftUI (`SwiftUICore`, `CA::Transaction::commit`).

## Medición 0.3.0 (4 de septiembre de 2026)

Repetida con la misma metodología tras añadir Sonido, Utilidades, Rendimiento, calendario,
temporizador, disposiciones y Sparkle (7 módulos frente a 5):

| Escenario | CPU media | RSS | Memoria física real (footprint) | Hilos | Disco |
|---|---|---|---|---|---|
| **Reposo** (notch plegado, 60 s) | **0,017 %** | 119 MB | **50 MB** | 6 | 7 MB |
| Plegado con Spotify en pausa (30 s) | 0,033 % | 119 MB | 50 MB | 6 | |
| **Expandido + música** (pestaña Música, Spotify sonando, 30 s) | 2,9 % | 119 MB | 50 MB | 6 | |

- La CPU en reposo es la misma que en 0.2.0 (0,017 %): los módulos nuevos no tienen temporizadores
  en reposo (CoreAudio, batería y música avisan por notificación; los gráficos solo muestrean con la
  pestaña abierta).
- El RSS sube de 72 a 119 MB, pero la **memoria física real** (lo que enseña Monitor de Actividad,
  `footprint`) se queda en **50 MB**: la diferencia son páginas *limpias y compartidas* de frameworks
  del sistema que ahora enlazamos (Vision para el OCR, CoreAudio, EventKit, Sparkle) y que macOS
  descarta o comparte con otras apps sin coste.
- Los 7 MB de disco son 5 MB de Sparkle (actualizaciones) + 2 MB de app.

## Corto plazo (mientras la usas)

- La interacción es fluida.
- El único pico de CPU (2,1 %) ocurre **solo** los segundos que tienes el notch
  abierto con música sonando. Al plegarlo, todo el trabajo se detiene.

## Largo plazo (todo el día en segundo plano)

- **0,02 % de CPU y ~48 MB** en reposo: es el 99 % del tiempo de vida de la app.
- Sin procesos hijo, sin fugas de memoria (RSS plano), y los temporizadores se
  paran cuando no se usan. Impacto de batería insignificante.

## Comparativa con las apps en las que se inspira

Misma metodología para todas: **cada app medida en aislamiento** (solo ella + el sistema),
50 s de reposo con el cursor lejos del notch, tras 15 s de arranque. CPU = tiempo de CPU
consumido / tiempo transcurrido; RAM = RSS (BoringNotch incluye su proceso ayudante XPC).
OmniMac medida tras abrir y cerrar el notch una vez (estado "caliente", el habitual).

| App | Sustituye a (módulo de OmniMac) | CPU reposo | RAM | Hilos | Disco | Versión |
|---|---|---|---|---|---|---|
| **OmniMac** | — (las 5 en una) | 0,017 % | 119 MB (50 MB reales) | 6 | 7 MB | 0.3.0 |
| **Amphetamine** | Mantener despierto | 0,000 % | 100 MB | 5 | 7 MB | 5.3.2 |
| **AltTab** | ⌘Tab por ventanas | 0,020 % | 212 MB | 9 | 11 MB | 11.5.0 |
| **Rectangle** | Atajos de ventanas | 0,040 % | 84 MB | 4 | 9 MB | 1.100 |
| **Maccy** | Portapapeles | 0,020 % | 91 MB | 4 | 10 MB | 2.7.1 |
| **BoringNotch** | Notch dinámico | 0,340 % | 149 MB (142+7 ayudante) | 7 | 19 MB | 2.7.3 |
| **Las 5 juntas** | — | 0,420 % | **636 MB** | — | 56 MB | — |

**OmniMac reemplaza a las cinco usando 119 MB de RSS (50 MB de memoria física real): un 81 % menos que tenerlas todas abiertas** (636 MB), y menos RSS que AltTab o BoringNotch por separado.

Matices honestos:

- AltTab captura miniaturas de las ventanas en segundo plano: por eso su RAM crece con el uso (en sesiones largas llegó a >300 MB).
- BoringNotch y OmniMac son apps de notch: **no se pueden medir a la vez**, se disparan mutuamente (por eso el aislamiento).
- Un solo Mac (Apple Silicon, macOS 26.5), una sola tanda: son órdenes de magnitud, no décimas.
- Amphetamine y las demás hacen bien lo suyo; el punto es que OmniMac hace las cinco cosas con una sola app residente.

## Optimizaciones aplicadas

1. **Hover del notch: de sondeo a eventos.** Antes un `Timer` a 10 Hz leía la
   posición del ratón *siempre*, incluso con el Mac en reposo. Ahora se usa un
   `NSTrackingArea .activeAlways` + monitores de `mouseMoved`: **cero trabajo con
   el ratón quieto**. (El mayor ahorro en reposo: 0,12 % → 0,03 %.)

2. **AppleScript en proceso.** Cada consulta de música lanzaba un proceso
   `osascript` (fork+exec, ~50 ms de CPU). Ahora se usa `NSAppleScript` en una
   cola en serie (~1 ms) y los scripts del *poll* se **compilan una vez y se
   cachean**. Menos CPU y sin procesos hijo.

3. **Ecualizador con CoreAnimation.** La animación SwiftUI `repeatForever`
   redibujaba en el hilo principal cada fotograma (~9 % de CPU). Reescrito con
   capas `CABasicAnimation`, que corren en el compositor/GPU. (9,4 % → 6,25 %.)

4. **Barra de progreso sin bucle continuo.** La animación lineal de 1,5 s
   mantenía el `CADisplayLink` activo el ~75 % del tiempo. Bajada a una
   transición de 0,35 s que se apaga entre *polls*. (6,25 % → 2,1 %.)

5. **Portapapeles a 1 Hz** (antes 2 Hz) con tolerancia, y sondeo inmediato al
   abrir el panel para no perder nada.

6. **Monitor de permisos acotado.** El temporizador que vigila el permiso de
   Accesibilidad vivía para siempre en la vista de Ajustes; ahora solo corre
   **mientras la ventana de Ajustes está abierta**.

7. **Tolerancia en todos los temporizadores.** Permite a macOS agrupar los
   despertares (*timer coalescing*) → menos consumo de batería.

## Principios de diseño para mantenerla óptima

- **Nada sondea en reposo.** Lo que no está en pantalla no consume: los
  temporizadores de música y el vigilante del notch solo viven mientras está
  expandido.
- **El trabajo por fotograma va a CoreAnimation**, no al hilo principal.
- **Sin procesos externos** en caminos calientes.
- Cada módulo desactivado en Ajustes **libera sus recursos** (`stop()`).
