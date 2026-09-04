# Cambios

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
