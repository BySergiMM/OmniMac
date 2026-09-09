# Cambios

## 0.5.0 — 2026-09-09

**Nuevo**
- **El notch funciona en cualquier Mac.** La geometría se saca de la pantalla y no del modelo: donde no hay notch físico dibuja una isla flotante dimensionada al ancho del monitor. Sirve en un iMac, en un Mac mini con pantalla externa y en un MacBook anterior a 2021.
- **Rendimiento de verdad, no tres gráficas.** CPU por núcleo con los de eficiencia y los de rendimiento en colores distintos, GPU, memoria con su presión y el intercambio, disco (lectura, escritura y espacio libre), red y **temperatura**. Y lo que de verdad se pregunta uno cuando el Mac va lento: **qué apps se están comiendo la CPU y la memoria**, por nombre.
- **Temperatura**: media del chip, el diodo más caliente, el SSD, la batería y todos los sensores del chip, uno a uno. El estado térmico del sistema va siempre; los grados, solo si macOS los deja leer.
- **Avisos** cuando la CPU lleva rato al máximo, la memoria está al límite, queda poco disco, el Mac se calienta o la batería baja. Cada uno sale una vez y no se repite hasta que la cosa vuelve a estar bien.
- **Ecualizador de 10 bandas**, general o por app, con nueve ajustes preparados (más graves, voz y pódcast, rock, modo noche…).
- **Amplificación por encima del 100 %** (hasta 400 %) con limitador de picos, para que no cruja al sumar varias apps.
- **Prioridad de salidas**: al conectar unos auriculares se ponen solos, y al desconectarlos vuelve la anterior.
- **Mezclador suelto** con ⌃⌥⌘V: un atajo, las barras de lo que suene y fuera.
- **Escondedor de la barra de menús**: pulsa la flecha y los iconos que no usas a diario aparecen; la vuelves a pulsar y se guardan.
- **Limpiador de apps**: desinstala una app con todo lo que deja detrás y encuentra los restos de las apps que ya borraste. Todo va a la papelera, nunca se borra del todo.
- **Buscador de comandos** con ⌥Espacio: escribe y ejecuta cualquier función de OmniMac o abre cualquier app. Busca por letras sueltas y en orden («slmi» encuentra «Silenciar el micrófono»). **Apagado de fábrica**, porque ⌥Espacio es el atajo de Raycast y de Alfred.
- **Pegar sin formato** con ⌥⇧⌘V.
- **Limpiar el rastreo de los enlaces** al copiarlos: fuera «utm_source», «fbclid», el «si» de Spotify. Solo si lo copiado es un enlace entero, y nunca toca parámetros que no conozca.
- **Brillo por debajo del mínimo de macOS** con ⌃⌥⌘− y ⌃⌥⌘+, para trabajar de noche.
- **Instalador de .dmg**: al terminar una descarga, OmniMac pregunta si monta el disco, copia la app a Aplicaciones, lo expulsa y manda el .dmg a la papelera. Nunca hace nada sin preguntar.
- Los iconos del notch se reordenan arrastrándolos, y las gráficas de rendimiento se pueden poner en el notch, en la barra de menús o en ningún sitio.
- Ventana de **Novedades** al actualizar, que puedes saltarte.
- **Todos los atajos se pueden cambiar**, uno a uno, desde Ajustes. Y si otra app ya tiene esa combinación, OmniMac **lo dice** en vez de quedarse callado: antes `RegisterEventHotKey` fallaba, no había ningún aviso y la función simplemente no hacía nada. Quien tuviera Rectangle o Magnet pulsaba ⌃⌥→ y no pasaba nada, sin explicación.

**Arreglado**
- **«Mantener despierto» ya no se apaga sin decir por qué.** La sesión se puede parar sola —por la batería, por el temporizador, porque la app se cierra o se actualiza—, y con la tapa cerrada eso duerme el Mac en el acto: abrías el portátil, salía la pantalla de bloqueo y no había forma de saber qué había pasado. La notificación no valía, porque se manda justo cuando el Mac se está durmiendo y puede no llegar a entregarse. Ahora el motivo se **guarda en disco** y te lo cuenta al volver, en Ajustes y con el café en naranja en el notch. Además avisa **diez puntos antes** del corte por batería, mientras el aviso todavía se puede ver, y la regla se mira también al arrancar la sesión (antes, si ya estabas por debajo del umbral, la sesión empezaba igual y se caía sola más tarde).
- **Los menús iban a tirones.** La causa era el monitor global de ratón del notch: mientras existe, macOS despierta la app en cada movimiento del ratón de todo el sistema. Ahora se quita mientras hay un menú abierto.
- El icono de la barra de menús es ahora el mismo destello que el de la app; antes eran dos dibujos distintos.
- El escondedor de la barra se tragaba los iconos de la propia OmniMac.
- El limpiador decía «liberados X MB» aunque no hubiera movido nada. Ahora solo cuenta lo que de verdad llegó a la papelera, y avisa de que macOS no deja que ninguna app toque las carpetas de Contenedores: esas hay que quitarlas desde el Finder.
- Con las gráficas en la barra de menús se medía **todo** (GPU, disco, sensores y los 445 procesos del sistema) para dibujar una línea de CPU: costaba un 1,9 % en reposo. Ahora el icono pide solo lo que enseña.
- Dieciocho traducciones corregidas, la barra lateral de Ajustes es más ancha y ya no solapa con los textos largos.

## 0.4.2 — 2026-09-06

- Ajustes › Inicio › Almacenamiento: muestra lo que ocupa la app y la caché (carátulas descargadas y restos de actualizaciones de Sparkle), un botón «Limpiar ahora» que avisa de cuánto ha liberado, y limpieza automática una vez al día (activada por defecto, se puede apagar). La caché web queda acotada a 16 MB en disco.

## 0.4.1 — 2026-09-05

- Ajustes: al cambiar el idioma, OmniMac se reinicia y vuelve a abrir Ajustes ya en el idioma nuevo; los selectores de las filas quedan centrados en vertical.
- Ajustes: al cerrar la ventana se destruye su contenido, así las páginas Rendimiento y Sonido dejan de muestrear de verdad (antes seguían midiendo con la ventana oculta: 0,37 % de CPU).
- Notch: el tap de clics se invalida al plegar (antes cada apertura dejaba un puerto Mach y una fuente del run loop huérfanos) y el reencuadre del panel espera a que termine la animación de plegado.
- Música: los AppleScript corren en un hilo propio con run loop (`ScriptThread`) en vez de en GCD, que iba acumulando run loops y fuentes por cada sondeo.
- Rendimiento medido de nuevo (`docs/PERFORMANCE.md`): reposo 0,02 % de CPU, menos de un despertar por segundo, sin crecimiento de memoria tras abrir y cerrar el notch.
- Código: comentarios de cabecera en todos los archivos, herramientas de prueba en `scripts/dev` (`quickbuild.sh`, `wakeups.sh`, `measure.sh`…) y generador de la web inglesa en `docs/site/tools`.

## 0.4.0 — 2026-09-04

- **Interfaz en inglés y español**: sigue el idioma del Mac y se puede fijar en Ajustes › Inicio › General › Idioma (cambiarlo reinicia la app). Textos de permisos localizados.
- Notch: la tarjeta de AirPods se abre en un panel más recogido y centrado (440×172) y se pliega antes (3,2 s; 2,2 s tras la batería); sombra estable durante la animación.
- Instalación con Homebrew: `brew install --cask BySergiMM/tap/omnimac`.
- Capturas de la web en inglés (`--snapshots … --lang en`).

## 0.3.1 — 2026-09-04

- Notch: al conectar AirPods o Beats se despliega con una tarjeta animada al estilo iPhone (modelo y batería de cada pieza) y se pliega solo; opción para cerrar el aviso de macOS (experimental). Sin pedir permisos.

## 0.3.0 — 2026-09-04

**Nuevo**
- Notch: pestañas Calendario, Sonido (volumen por app), Temporizador/Pomodoro (tiempos configurables) y Rendimiento; cada pestaña y cada botón de la cabecera se puede activar o desactivar.
- Notch: vistazo rápido al cambiar de canción, avisos «desplegando el notch» (opcional), se oculta con apps a pantalla completa, batería clicable, AirDrop y bandeja con selector de archivos.
- Atajos de ventanas: tercios, mitades superior/inferior, casi maximizar, más grande/pequeño, restaurar, otra pantalla, ajuste arrastrando a los bordes, ciclar tamaños y **disposiciones** (⌃⌥1…9 guarda/aplica, mantener libera, ⌃⌥0 deshace).
- ⌘Tab: búsqueda escribiendo, ⌘W/⌘M/⌘H/⌘Q, ⌥Tab opcional.
- Portapapeles: imágenes y archivos, búsqueda, anclados (⌥P), pausa, historial en disco opcional.
- Mantener despierto: hasta una hora concreta, más duraciones, tiempo restante en la barra, aviso al terminar, parada por batería, disparadores (cargador, pantalla externa) y modo tapa cerrada (una sola contraseña, también desde el instalador).
- Utilidades: copiar texto de la pantalla (OCR, ⇧⌘2), copiar un color (⇧⌘6), silenciar micrófono (⌃⌥⌘M), bloquear teclado (⌃⌥⌘L), ocultar iconos del escritorio, evitar ⌘Q accidental.
- Sonido: salida/entrada, volumen, balance, silencio, volumen por app, ⌃⌥⌘O para ciclar salida; sincronizado en tiempo real con las teclas de volumen.
- Rendimiento: tres gráficos (CPU, memoria, red) en Ajustes y en el notch.
- Actualizaciones automáticas (Sparkle + GitHub Releases) e instalador `.pkg`.
- Binario universal (Apple silicon e Intel), macOS 14.2 o posterior.
- El panel del notch se adapta al ancho del notch de cada pantalla: las pestañas nunca quedan debajo.
- Web de presentación con capturas reales generadas por la propia app (`OmniMac --snapshots <carpeta>`).
- Ajustes al estilo Ajustes del Sistema.

**Arreglos**
- El notch va por encima de la barra de menús, mide exactamente lo que el notch físico y no se ve al cambiar de escritorio; abre al llegar al borde superior; AirDrop funciona con un destino único de arrastre.

## 0.2.0
- Primera versión con Mantener despierto, ⌘Tab por ventanas, Notch, Atajos de ventanas y Portapapeles.
