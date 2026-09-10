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

## Medición 0.4.1 (5 de septiembre de 2026)

Misma metodología (60 s de reposo con el cursor lejos del notch, `ps -o cputime`, `footprint`),
más dos cosas nuevas: despertares por segundo (diferencia de `IDLEW` entre dos muestras de `top`)
y recuento de objetos con `heap` antes y después de abrir y cerrar el notch 10 veces con Spotify.

| Escenario | CPU media | RSS | Memoria física real | Despertares | Hilos |
|---|---|---|---|---|---|
| **Reposo** (notch plegado, 60 s) | **0,017 %** | 64 MB | **19 MB** | **0,7/s** | 6 |
| Plegado con Spotify en pausa (30 s) | 0,000 % | 64 MB | 19 MB | 1,0/s | 6 |
| Tras abrir y cerrar el notch 10 veces | — | — | 27 MB | 0,7/s | 6 |
| **Expandido + música** (pestaña Música, Spotify sonando, 30 s) | 2,1 % | — | 25 MB | — | 8 |

- La memoria física real baja de 50 a 19 MB frente a 0.3.0 porque ahora la ventana de Ajustes
  destruye su vista al cerrarse (antes quedaba oculta con sus gráficos vivos) y porque esta medida
  es de un arranque limpio sin haber abierto Ajustes; con el notch usado sube a 25–27 MB y ahí se queda.
- Los objetos que antes crecían con cada apertura ya no crecen: `NSMachPort` y `CFRunLoopSource`
  (el tap de clics del notch no se invalidaba) y `CFRunLoop`/`CFRunLoopMode`/colas de run loop
  (los AppleScript en GCD dejaban un run loop por hilo de trabajo; ahora corren en `ScriptThread`).
- Ajustes: al cerrar la ventana con la página Rendimiento o Sonido a la vista seguían muestreando
  (0,37 % de CPU con la ventana oculta). Ahora la vista se destruye al cerrar y se crea al abrir.

**Dos trampas de medición que nos engañaron** (documentadas para no repetirlas):

1. Consultar la app por Accesibilidad (para leer la altura del notch) le cuesta a *ella* unos 3 ms
   por consulta: un sondeo cada 10 s inflaba el reposo a 0,047 %. `scripts/dev/notch.swift height`
   lee ahora el marco con `CGWindowList`, que no despierta a la app.
2. Las columnas `IDLEW` y `CSW` de `top -l N` son contadores acumulados desde que arrancó el
   proceso (el «+» solo indica que han crecido). Tomar el valor bruto como tasa «descubrió» una
   fuga de 35 despertares por segundo por cada apertura del notch que no existía: `proc_pidinfo`
   daba 4 cambios de contexto por segundo y 0 ms de CPU. `scripts/dev/wakeups.sh` resta dos muestras.

## Medición 0.4.2 (8 de septiembre de 2026)

Misma metodología (`scripts/dev/measure.sh`: calentar abriendo y cerrando el notch una vez,
60 s de reposo comprobando cada 5 s que sigue plegado, `ps -o cputime` para la CPU y
`footprint` para la memoria real). Arranque limpio, sin abrir Ajustes.

| Escenario | CPU media | RSS | Memoria física real | Hilos | Disco |
|---|---|---|---|---|---|
| **Reposo** (notch plegado, 60 s) | **0,017 %** | 80 MB | **35 MB** | 6 | 14 MB |
| Con la ventana de Novedades abierta antes | 0,017 % | 110 MB | 37 MB | 6 | |

- La CPU en reposo no se mueve (0,017 % por cuarta versión seguida): lo añadido desde 0.4.1
  —limpiador de apps, ecualizador, ventana de Novedades— **no tiene nada corriendo en reposo**.
- La memoria real sube de 19 a 35 MB y el disco de 12 a 14 MB. El disco son los dos
  registros de cambios en Recursos y el código nuevo; la memoria, los marcos que ahora se
  enlazan y las vistas nuevas ya recorridas.
- El ecualizador y el volumen por app solo montan el motor de audio **si hay algo guardado
  que aplicar y alguna app sonando**; en reposo, con todo a 100 %, no hay tap ni temporizador.

## Medición 0.5.0 (9 de septiembre de 2026)

Misma metodología (`scripts/dev/measure.sh`: calentar abriendo y cerrando el notch una
vez, 60 s de reposo comprobando cada 5 s que sigue plegado, `ps -o cputime` para la CPU
y `footprint` para la memoria real). Esta versión añade doce módulos, así que se mide
también el caso peor de cada uno.

| Escenario | CPU media | RSS | Memoria real | Hilos |
|---|---|---|---|---|
| **Reposo** (notch plegado, 60 s, tres muestras) | **0,017–0,033 %** | 82–83 MB | **27–36 MB** | 6–7 |
| Notch abierto con música (30 s) | 0,93 % | 84 MB | 29 MB | 9 |
| **Motor de audio activo** (volumen por app y audio sonando, 40 s) | **0,55 %** | 133 MB | **72 MB** | 8 |
| Página de Rendimiento abierta (60 s) | 1,57 % | — | — | — |
| Despertares en reposo | **1,0/s**, igual tras tres ciclos de abrir y cerrar el notch | | | |

En disco: **16 MB**.

**La medida está cuantizada.** `measure.sh` cuenta el tiempo de CPU en centésimas de
segundo sobre una ventana de 60 s, así que el escalón mínimo es 0,017 %. Un «0,033 %»
son dos escalones, no una medida fina: por eso el reposo se da como intervalo y con
tres muestras.

**Lo que cuesta cada cosa, medido una por una** (50 repeticiones, media):

| Lectura | Coste |
|---|---|
| `coreTicks` (CPU por núcleo) | 0,01 ms |
| `memory` (presión y swap) | 0,00 ms |
| `battery` | 0,03 ms |
| `thermalState` | 0,00 ms |
| `diskSpace` **rápido** | 0,09 ms |
| `diskSpace` **«disponible para lo importante»** | **4,96 ms** |

Ese último dato cambió el diseño de los avisos. Con la lectura precisa, el vigilante de
alertas metía picos de 0,083 % en el reposo —cinco escalones— porque macOS calcula el
espacio purgable cada vez. Para un aviso de «queda poco disco» sobra con el hueco a
secas, y con eso las alertas encendidas quedan **indistinguibles** de tenerlas apagadas:

| | Tres muestras |
|---|---|
| Alertas apagadas | 0,017 · 0,033 · 0,017 % |
| Alertas encendidas (antes) | 0,083 · 0,017 · 0,033 % |
| Alertas encendidas (ahora) | 0,017 · 0,033 · 0,017 · 0,033 % |

**Dos cosas que se pagan y conviene saber:**

- **El motor de audio duplica la memoria real** (de ~30 a 72 MB) mientras está
  montado. Solo se monta si hay algo guardado que aplicar **y** alguna app sonando; en
  cuanto deja de haberlo, se desmonta. Con todo a 100 % no existe.
- **La página de Rendimiento cuesta 1,57 %** mientras se mira. Eran 5,67 % hasta que se
  agruparon las notificaciones de SwiftUI: doce propiedades `@Published` cambiaban por
  muestra y cada una recalculaba el diseño de la página entera. Ahora se avisa una vez.

## Espacio en disco (6 de septiembre de 2026)

| Qué | Cuánto | Notas |
|---|---|---|
| La app instalada | **12 MB** | 8 MB de binario universal (Apple silicon + Intel), 3 MB de Sparkle, 1 MB de recursos |
| Preferencias y disposiciones | < 10 KB | `~/Library/Preferences` y `~/Library/Application Support/OmniMac` |
| Historial del portapapeles en disco | 0 por defecto | Solo si se activa la opción en Ajustes › Portapapeles |
| Caché (`~/Library/Caches/com.seergiii.omnimac`) | **antes: 20 MB** · ahora ≤ 16 MB y limpiada a diario | 10 MB de restos del instalador de Sparkle y ~10 MB de carátulas de Spotify (146 imágenes) que la caché web guardaba sin tope útil |

Desde 0.4.2 la caché web está acotada (16 MB en disco, 4 MB en memoria) y Ajustes › Inicio ›
Almacenamiento enseña los tamaños, limpia a mano («Limpiar ahora» dice cuánto ha liberado) y
limpia sola una vez al día con un único temporizador de un solo disparo y una hora de
tolerancia: coste en reposo, cero. Nada de lo que se borra es necesario: las carátulas se
vuelven a descargar (100–300 KB cada una) y Sparkle recrea su carpeta cuando hay una
actualización; si hay una en marcha, esa carpeta no se toca.

## Corto plazo (mientras la usas)

- La interacción es fluida.
- El único pico de CPU (2,1 %) ocurre **solo** los segundos que tienes el notch
  abierto con música sonando. Al plegarlo, todo el trabajo se detiene.

## Largo plazo (todo el día en segundo plano)

- **0,02 % de CPU y ~48 MB** en reposo: es el 99 % del tiempo de vida de la app.
- Sin procesos hijo, sin fugas de memoria (RSS plano), y los temporizadores se
  paran cuando no se usan. Impacto de batería insignificante.

## Medición 0.5.1 (11 de septiembre de 2026)

Misma metodología (`scripts/dev/measure.sh`). Varios arranques limpios, con Spotify sonando y
con Spotify en pausa, para descartar que la música cambie algo con el notch plegado.

| Escenario | CPU media | RSS | Memoria real | Hilos |
|---|---|---|---|---|
| **Reposo** (notch plegado, 60 s, seis muestras en tres arranques) | **0,017–0,033 %** | 84–86 MB | **33–37 MB** | 6–9 |
| Notch abierto con música (30 s, dos muestras) | 2,3 % | 86 MB | 29 MB | 8 |
| Página de Rendimiento abierta (60 s, dos muestras) | 2,6 % | 124–125 MB | 59 MB | 7 |
| Despertares en reposo | **0,3/s**; 0,7/s tras tres ciclos de abrir y cerrar el notch | | | |

En disco: **16 MB**, igual que en 0.5.0.

- **La memoria sube respecto a 0.5.0** (real: de 27–36 a 33–37 MB; RSS: de 82–83 a 84–86 MB).
  No sale de lo nuevo, porque los dos arreglos de esta versión no corren en reposo, ni de la
  música, porque con Spotify en pausa sale lo mismo. Se publica la cifra de ahora.
- **Notch abierto con música: 2,3 %, no 0,93 %.** La 0.5.0 dio 0,93 % en una sola muestra; ahora
  dos muestras limpias dan 2,30 y 2,27 %, en la línea de la 0.4.1 (2,1 %). El código del notch no
  ha cambiado desde entonces: con una sola muestra de referencia, lo prudente es quedarse con esta.
  (La segunda muestra se tomó después de abrir Ajustes, con la memoria ya más alta: 126 MB de RSS
  y 54 MB reales. La CPU, la misma.)
- **Lo que cuesta arreglar los nombres.** `SystemText.repaired` pasa por el nombre de cada proceso
  en cada muestra de la lista, unos 445 nombres cada 4 s y solo con la página de Rendimiento a la
  vista. Tal como se escribió costaba 2 µs por nombre: 0,9 ms por muestra, un 0,02 % de CPU. Con la
  salida rápida para los nombres ASCII (casi todos lo son, y el error nunca está en ellos) son
  0,015 ms por muestra, 61 veces menos, con exactamente el mismo resultado.
- **Página de Rendimiento abierta: 2,6 %** (0.5.0: 1,57 %, en una sola muestra). Con la salida
  rápida da lo mismo que sin ella (2,62 y 2,57 %), así que no es el arreglo de los nombres; el
  resto de la página no ha cambiado desde 0.5.0. Solo cuesta mientras la página está a la vista.
- **Al cerrar Ajustes la CPU vuelve al reposo (0,017 %), pero la memoria no baja del todo**: con la
  página de Rendimiento abierta la memoria real llega a 59 MB, y al cerrar la ventana se queda en
  54. Queda por ver si la retiene OmniMac o son cachés del sistema.
- **Una medida descartada.** La primera de la página de Rendimiento abrió Ajustes con
  `open -b com.seergiii.omnimac`, y lo que se midió ya era otro proceso: LaunchServices tiene
  registrada además una copia vieja que ya no existe. Se repitió abriendo la app por su ruta.

## Comparativa con las apps a las que sustituye (8 de septiembre de 2026)

Misma metodología para todas: **cada app medida en aislamiento** (solo ella y el sistema),
50 s de reposo tras 15 s de arranque, sin ninguna ventana suya abierta. CPU = tiempo de CPU
consumido / tiempo transcurrido; RAM = RSS, sumando procesos ayudantes si los tiene.
OmniMac se mide en caliente (tras abrir y cerrar el notch una vez), que es su estado normal; su
fila es la de la 0.5.1, medida el 11 de septiembre.

Ice, FineTune y AppCleaner se descargaron el 8 de septiembre de 2026, se midieron y se
borraron. Las otras cinco conservan la medición del 3 de septiembre, mismo Mac y mismo método.

| App | Sustituye a (módulo de OmniMac) | CPU reposo | RSS | Hilos | Disco | Versión |
|---|---|---|---|---|---|---|
| **OmniMac** | — (las ocho en una) | **0,017–0,033 %** | **86 MB** | 6 | 16 MB | 0.5.1 |
| **Amphetamine** | Mantener despierto | 0,000 % | 100 MB | 5 | 7 MB | 5.3.2 |
| **AltTab** | ⌘Tab por ventanas | 0,020 % | 212 MB | 9 | 11 MB | 11.5.0 |
| **Rectangle** | Atajos de ventanas | 0,040 % | 84 MB | 4 | 9 MB | 1.100 |
| **Maccy** | Portapapeles | 0,020 % | 91 MB | 4 | 10 MB | 2.7.1 |
| **BoringNotch** | Notch dinámico | 0,340 % | 149 MB | 7 | 19 MB | 2.7.3 |
| **Ice** | Barra de menús | 0,040 % | 99 MB | 6 | 8 MB | 0.11.12 |
| **FineTune** | Sonido (volumen por app y ecualizador) | 0,000 % | 116 MB | 6 | 11 MB | 1.9.0 |
| **Las 7 residentes juntas** | — | **0,460 %** | **851 MB** | — | 75 MB | — |
| *AppCleaner* | *Limpiador de apps* | *0,000 %* | *90 MB* | *6* | *9 MB* | *3.6.8* |

**OmniMac hace el trabajo de las siete que viven en la barra de menús con 86 MB en vez de
851: un 90 % menos de memoria y entre un 93 y un 96 % menos de CPU** (0,017–0,033 % frente a
0,460 %). En disco, 16 MB frente a 84 MB entre las ocho.

Matices honestos, para que las cifras signifiquen algo:

- **AppCleaner va aparte a propósito.** No vive en segundo plano: se abre, se usa y se cierra.
  Sumar sus 90 MB al total sería hacer trampa, así que está fuera del total y en cursiva.
- **Ice no arranca sin permiso de Accesibilidad.** Medida al primer intento, con su ventana de
  bienvenida delante, daba 3,52 %; eso es la ventana, no la app. Con los permisos concedidos y
  sin ventanas se queda en 0,040 %.
- **La memoria real (`footprint`) solo la tenemos de las cuatro medidas este mes**: OmniMac
  33–37 MB (0.5.1), FineTune 49 MB, Ice 37 MB, AppCleaner 33 MB. Para las otras cuatro solo hay RSS, así
  que la comparativa se hace **RSS contra RSS**, que es lo comparable.
- AltTab captura miniaturas de las ventanas en segundo plano: su RAM crece con el uso (en
  sesiones largas pasó de 300 MB).
- BoringNotch y OmniMac son apps de notch: **no se pueden medir a la vez**, se disparan
  mutuamente. De ahí el aislamiento.
- FineTune marca 0,000 % en reposo porque sin audio sonando no hay nada que procesar. OmniMac
  hace lo mismo: sin nada guardado que aplicar no monta ni el tap ni el temporizador.
- Un solo Mac (Apple silicon, macOS 26.5), una sola tanda: son órdenes de magnitud, no décimas.
- Las ocho hacen bien lo suyo. El punto no es que sean malas, es que OmniMac hace las ocho
  cosas con un solo proceso residente.

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
