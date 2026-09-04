# OmniMac — Radiografía de la competencia

Inventario de **todas** las funciones de las cinco apps en las que se inspira OmniMac, contrastado con lo que OmniMac ya hace, para decidir qué añadir. Hecho el 3 de septiembre de 2026.

Fuentes: README o web oficial de cada app, la descripción del App Store (Amphetamine) y **los textos de los paneles de ajustes extraídos de cada bundle** (`Localizable.strings`), que listan hasta la última opción. Las apps se instalaron solo para medir consumo y se han eliminado después.

## Cobertura

| App | Versión | Módulo de OmniMac | Ya | Parcial | Falta |
|---|---|---|---|---|---|
| **Amphetamine** | 5.3.2 | Mantener despierto | 4 | 3 | 16 |
| **AltTab** | 11.5.0 | ⌘Tab por ventanas | 3 | 5 | 17 |
| **Rectangle** | 1.100 | Atajos de ventanas | 4 | 1 | 18 |
| **Maccy** | 2.7.1 | Historial del portapapeles | 1 | 3 | 13 |
| **BoringNotch** | 2.7.3 | Notch dinámico | 7 | 7 | 18 |
| **Total** | | | **19** | **19** | **82** |

«Falta» incluye funciones que **no conviene** copiar (marcadas como *Descartar*): OmniMac gana por ser simple, no por tener más casillas.

## Qué añadir (por orden de valor)

| # | Módulo | Función | Valor | Esfuerzo | Viene de |
|---|---|---|---|---|---|
| 1 | Notch | «Ahora suena» universal: cualquier app de audio, no solo Spotify y Música | alto | alto | BoringNotch |
| 2 | Notch | HUD de volumen y brillo dentro del notch | alto | medio | BoringNotch |
| 3 | Notch | Ocultarse en apps a pantalla completa | alto | bajo | BoringNotch |
| 4 | Notch | Sneak peek al cambiar de canción y volumen en el reproductor | medio | bajo | BoringNotch |
| 5 | Notch | Pestaña de calendario con el siguiente evento | medio | medio | BoringNotch |
| 6 | ⌘Tab | Buscar escribiendo y acciones sobre la ventana elegida (⌘W, ⌘M, ⌘Q) | alto | bajo | AltTab Pro |
| 7 | ⌘Tab | Selección con el ratón, tamaño automático y excepciones por app | medio | bajo | AltTab |
| 8 | Ventanas | Ajustar arrastrando a bordes y esquinas, con huella | alto | medio | Rectangle |
| 9 | Ventanas | Tercios, mitades superior/inferior, casi maximizar, más grande/pequeño, restaurar, otra pantalla | alto | bajo | Rectangle |
| 10 | Ventanas | Atajos personalizables | medio | medio | Rectangle / AltTab |
| 11 | Portapapeles | Imágenes y archivos, búsqueda, anclados e historial persistente opcional | alto | medio | Maccy |
| 12 | Portapapeles | Pausar o ignorar la siguiente copia, pegar sin formato, atajo personalizable | medio | bajo | Maccy |
| 13 | Café | Hasta una hora concreta, más duraciones, tiempo restante en la barra y aviso al terminar | medio | bajo | Amphetamine |
| 14 | Café | Parar si la batería baja del X % y disparadores sencillos (cargador, pantalla externa, app) | medio | medio | Amphetamine |
| 15 | General | Actualizaciones automáticas y exportar/importar ajustes | medio | medio | todas |

## Amphetamine 5.3.2 → Mantener despierto

Fuente: descripción del App Store + 722 textos de la app.

| Función | OmniMac | Qué hacer | Nota |
|---|---|---|---|
| Sesión sin límite | ✅ Ya |  |  |
| Sesión con duración fija (de 1 min a 24 h) | 🟡 Parcial | **Añadir** | Tenemos 15/30/60/120 min: añadir más tramos y «otra duración» |
| Sesión hasta una hora concreta («hasta las 18:30») | ❌ Falta | **Añadir** | Muy usado; es un temporizador con otra entrada |
| Sesión mientras se descarga un archivo | ❌ Falta | Descartar | Nicho |
| Sesión mientras una app esté abierta (o en primer plano) | ❌ Falta | Más adelante | Disparador sencillo con NSWorkspace |
| Permitir o impedir que la pantalla se apague | ✅ Ya |  |  |
| Permitir el salvapantallas tras N minutos | 🟡 Parcial | Más adelante | Nuestra aserción de pantalla también lo bloquea; falta la opción |
| Modo pantalla cerrada (seguir despierto con la tapa cerrada) | ✅ Ya |  | Nuestro «modo tapa cerrada», sin pedir contraseña tras instalar |
| Mover el cursor automáticamente (simular actividad) | ❌ Falta | Descartar | Truco para apps de presencia; fuera del alcance |
| Bloquear la pantalla tras N minutos de inactividad | ❌ Falta | Descartar | macOS ya lo hace |
| Terminar la sesión si la batería baja del X % o sin cargador | ❌ Falta | **Añadir** | Protege la batería; ya tenemos el monitor IOKit |
| Terminar la sesión al forzar reposo o cambiar de usuario | ❌ Falta | Más adelante |  |
| Recordatorios periódicos y aviso al terminar la sesión | ❌ Falta | **Añadir** | Una notificación al acabar el temporizador |
| Tiempo restante visible en la barra de menús | ❌ Falta | **Añadir** | Barato y útil |
| Disparadores automáticos: pantalla externa, espejo, USB, Bluetooth, app, batería, cargador, IP, Wi-Fi, VPN, DNS, audio, volumen montado, CPU, inactividad, horario | ❌ Falta | Más adelante | Solo los dos o tres comunes (cargador, pantalla externa, app); el resto complica |
| Drive Alive (mantener discos externos despiertos) | ❌ Falta | Descartar |  |
| Atajos de teclado globales para iniciar y terminar | ❌ Falta | Más adelante |  |
| Iconos de barra de menús a elegir e imágenes propias | ❌ Falta | Descartar | Estética; nuestro icono es de marca |
| Estadísticas de sesiones | ❌ Falta | Descartar |  |
| Control por AppleScript | ❌ Falta | Descartar |  |
| Iniciar sesión al arrancar o al despertar el Mac | ❌ Falta | Más adelante |  |
| Abrir al iniciar sesión | ✅ Ya |  |  |
| Amphetamine Enhancer / Power Protect (app auxiliar) | 🟡 Parcial |  | Nuestra regla mínima en sudoers cumple ese papel sin app extra |

## AltTab 11.5.0 → ⌘Tab por ventanas

Fuente: web oficial + 322 textos de ajustes.

| Función | OmniMac | Qué hacer | Nota |
|---|---|---|---|
| Cambiar entre ventanas (no apps) con miniaturas en vivo | ✅ Ya |  |  |
| Ventanas minimizadas, ocultas y a pantalla completa con icono de estado | 🟡 Parcial | Más adelante | Minimizadas con insignia; ocultas y pantalla completa sin distinguir |
| Ventanas de todos los Espacios con etiqueta del número de Space | 🟡 Parcial | Más adelante | Las incluimos; falta la etiqueta |
| Varias pantallas: dónde aparece el selector (activa / con el ratón / con la barra) | ❌ Falta | Más adelante |  |
| Orden: reciente, por creación, alfabético, por Space | ❌ Falta | Más adelante | Solo reciente |
| Agrupar por app o por pestañas (una ventana por pestaña) | ❌ Falta | Descartar | Complejo y raro |
| Filtros: solo app activa / otras apps / pantalla activa / Spaces visibles | ❌ Falta | Más adelante |  |
| Mostrar apps sin ventana abierta | ❌ Falta | Descartar |  |
| Excepciones por app (ocultar, ignorar atajo, en pantalla completa) | ❌ Falta | **Añadir** | Lista de apps excluidas |
| Filtrar por título de ventana | ❌ Falta | Descartar |  |
| Hasta 9 atajos personalizables (Pro) | ❌ Falta | **Añadir** | Con uno o dos basta: ⌘Tab y ⌥Tab |
| Foco al soltar la tecla o al pulsar | ✅ Ya |  | Suelta ⌘ para cambiar |
| Navegar con flechas, teclas vim o con el ratón | 🟡 Parcial | **Añadir** | Flechas sí; falta seleccionar con el ratón y clic |
| Acciones con el selector abierto: cerrar, minimizar, pantalla completa, ocultar app, salir | ❌ Falta | **Añadir** | ⌘W, ⌘M, ⌘H, ⌘Q sobre la ventana seleccionada |
| Gestos de trackpad (3 o 4 dedos) | ❌ Falta | Descartar |  |
| El cursor sigue al foco | ❌ Falta | Descartar |  |
| Vibración háptica al cambiar | ❌ Falta | Más adelante | Ya tenemos el actuador del notch |
| Tres estilos: miniaturas, iconos de app, títulos (Pro) | 🟡 Parcial |  | Miniaturas; sin permiso, icono + título |
| Tamaño pequeño/mediano/grande y tamaño automático (Pro) | ❌ Falta | **Añadir** | Que las miniaturas crezcan con pocas ventanas |
| Buscar ventanas escribiendo (Pro) | ❌ Falta | **Añadir** | La función Pro más pedida |
| Tema claro/oscuro, animaciones y retardo de aparición | 🟡 Parcial | Más adelante |  |
| Vista previa grande de la ventana seleccionada | ❌ Falta | Más adelante |  |
| Capturar en segundo plano (evita el indicador morado) | ✅ Ya |  | Capturamos solo al abrir: sin indicador permanente |
| Ocultar círculos de estado, etiquetas de Space, truncado de títulos | ❌ Falta | Descartar |  |
| Importar/exportar ajustes, idioma, actualizaciones, informes de fallos | ❌ Falta | Más adelante | Actualizaciones automáticas para toda la app |

## Rectangle 1.100 → Atajos de ventanas

Fuente: README + 240 textos de menús y ajustes.

| Función | OmniMac | Qué hacer | Nota |
|---|---|---|---|
| Mitades izquierda y derecha | ✅ Ya |  |  |
| Mitades superior e inferior y mitad central | ❌ Falta | **Añadir** | Mismo mecanismo que las que ya hay |
| Cuartos en las esquinas | ✅ Ya |  |  |
| Tercios (primero, central, último) y dos tercios | ❌ Falta | **Añadir** | Muy usado en pantallas anchas |
| Sextos | ❌ Falta | Más adelante |  |
| Columnas de cuartos y tres cuartos | ❌ Falta | Más adelante |  |
| Maximizar | ✅ Ya |  |  |
| Casi maximizar y maximizar solo la altura | ❌ Falta | **Añadir** | «Casi maximizar» deja aire alrededor |
| Centrar (y centrar prominente) | ✅ Ya |  |  |
| Más grande / más pequeño | ❌ Falta | **Añadir** |  |
| Restaurar el tamaño anterior | ❌ Falta | **Añadir** | Deshacer el último ajuste |
| Pantalla siguiente / anterior | ❌ Falta | **Añadir** | Para quien usa monitor externo |
| Mover al borde sin redimensionar | ❌ Falta | Más adelante |  |
| Ajustar arrastrando a bordes y esquinas (con huella previa) | ❌ Falta | **Añadir** | La función estrella de Rectangle; necesita seguir el arrastre y una vista de huella |
| Doble clic en la barra de título para maximizar o restaurar | ❌ Falta | Más adelante |  |
| Ciclar tamaños al repetir el atajo (½ → ⅔ → ⅓) o saltar de pantalla | ❌ Falta | Más adelante |  |
| Espacios entre ventanas y márgenes | ❌ Falta | Más adelante |  |
| Modo «Todo» (una app fija a un lado) | ❌ Falta | Descartar |  |
| Ignorar apps | ❌ Falta | Más adelante |  |
| Atajos personalizables y presets (Rectangle / Spectacle) | ❌ Falta | **Añadir** | Grabador de atajos en Ajustes |
| Automatización por URL (rectangle://) | ❌ Falta | Descartar |  |
| Importar/exportar configuración JSON | ❌ Falta | Descartar |  |
| Ocultar icono de barra, abrir al iniciar sesión, actualizaciones | 🟡 Parcial | Más adelante |  |

## Maccy 2.7.1 → Historial del portapapeles

Fuente: README + textos de los 7 paneles de ajustes.

| Función | OmniMac | Qué hacer | Nota |
|---|---|---|---|
| Historial de texto | ✅ Ya |  |  |
| Imágenes y archivos en el historial | ❌ Falta | **Añadir** | Lo que más se echa en falta |
| Historial persistente en disco (200 por defecto) | ❌ Falta | **Añadir** | Opcional y con aviso: hoy vive en memoria por privacidad |
| Buscar escribiendo (exacta, aproximada, mixta, regex) | ❌ Falta | **Añadir** | Búsqueda simple al escribir |
| Anclar elementos (⌥P) con atajo, título y contenido editables | ❌ Falta | **Añadir** | Fragmentos fijos: direcciones, firmas… |
| Pegar automáticamente / solo copiar / pegar sin formato | 🟡 Parcial | **Añadir** | Pegamos; falta «sin formato» |
| Borrar un elemento, borrar todo, borrar al salir | 🟡 Parcial |  |  |
| Ignorar la próxima copia o pausar temporalmente | ❌ Falta | **Añadir** | Un clic con ⌥ en el icono |
| Ignorar apps concretas y tipos de portapapeles (gestores de contraseñas) | 🟡 Parcial | Más adelante | Ignoramos gestores; falta lista de apps |
| Vista previa (⌃Espacio) con retardo | ❌ Falta | Más adelante |  |
| Ventana en el cursor, centro o última posición | ❌ Falta | Descartar |  |
| Última copia junto al icono, iconos de apps, símbolos especiales, muestras de color hex | ❌ Falta | Más adelante | Iconos de app y color hex son detalles bonitos |
| Atajo global personalizable | ❌ Falta | **Añadir** |  |
| Orden: más nuevos o más antiguos primero | ❌ Falta | Descartar |  |
| Sonidos y notificaciones | ❌ Falta | Descartar |  |
| Integración con Atajos (App Intents) | ❌ Falta | Descartar |  |
| Vaciar también el portapapeles del sistema | ❌ Falta | Descartar |  |

## BoringNotch 2.7.3 → Notch dinámico

Fuente: README + 235 textos de ajustes (en español).

| Función | OmniMac | Qué hacer | Nota |
|---|---|---|---|
| Música: carátula, título, artista y controles | ✅ Ya |  |  |
| Barra de progreso arrastrable | ✅ Ya |  |  |
| Fuente «Ahora suena» universal (cualquier app: navegador, YouTube Music…) | ❌ Falta | **Añadir** | Hoy solo Spotify y Música por AppleScript; requiere MediaRemote (privado) como hace BoringNotch |
| Volumen desde el notch | ❌ Falta | **Añadir** |  |
| Visualizador y espectrograma de colores, animaciones Lottie | ❌ Falta | Descartar | Lo quitamos a propósito: costaba 9 % de CPU |
| Difuminado y resplandor tras la carátula | ✅ Ya |  | Resplandor al reproducir, gris en pausa |
| Letras bajo el artista | ❌ Falta | Más adelante |  |
| Sneak peek: título y artista bajo el notch al cambiar de canción | ❌ Falta | **Añadir** | Pequeño y muy vistoso |
| Cambiar de canción con gestos horizontales | ❌ Falta | Más adelante |  |
| Tiempo de inactividad multimedia | 🟡 Parcial |  |  |
| Calendario: eventos de hoy y siguiente evento | ❌ Falta | **Añadir** | EventKit; una pestaña más |
| Recordatorios (marcar como completado) | ❌ Falta | Más adelante |  |
| Bandeja: soltar, arrastrar fuera, copiar al arrastrar, quitar tras arrastrar, abrir si hay elementos | 🟡 Parcial |  | Soltar y arrastrar sí; faltan las opciones |
| AirDrop / Quick Share (elegir servicio) | ✅ Ya |  | Zona AirDrop |
| Batería: indicador, %, avisos de cargador, tiempo hasta carga completa, capacidad, bajo consumo | 🟡 Parcial | Más adelante | % e indicador; un aviso al conectar el cargador sería fácil |
| Espejo con la cámara (círculo o cuadrado) | ❌ Falta | Más adelante | Gimmick popular, AVFoundation |
| Sustituir el HUD del sistema (volumen, brillo, teclado) | ❌ Falta | **Añadir** | Función distintiva; escuchar teclas multimedia y dibujar en el notch |
| Mostrar el HUD dentro del notch abierto | ❌ Falta | Más adelante |  |
| Gestos de dos dedos para abrir y cerrar, sensibilidad | ❌ Falta | Más adelante |  |
| Abrir al pasar el cursor con retardo y zona ampliada | ✅ Ya |  | 0,5 s |
| Vibración háptica | ✅ Ya |  | Con intensidad a elegir |
| Comportamiento con la tecla ⌥ | ❌ Falta | Descartar |  |
| Recordar última pestaña, mostrar siempre pestañas, icono de ajustes en el notch | 🟡 Parcial |  |  |
| Notch en la pantalla de bloqueo, ocultar en grabación de pantalla | ❌ Falta | Descartar |  |
| Todas las pantallas, pantalla preferida, cambio automático | ❌ Falta | Más adelante |  |
| Tamaño del notch: igualar barra o notch real, altura personalizada, pantallas sin notch | 🟡 Parcial |  | Isla en pantallas sin notch |
| Radio de esquinas, sombra, color de acento, estilo de la barra de progreso | 🟡 Parcial |  | Sombra y esquinas fijas, a propósito |
| Comportamiento en pantalla completa (ocultar para todas / solo app multimedia / nunca) | ❌ Falta | **Añadir** | Importante: no estorbar en vídeo o juegos |
| Cara animada cuando está inactivo | ❌ Falta | Descartar |  |
| Estado del micrófono (silenciado / activo) | ❌ Falta | Descartar |  |
| Extensiones (gestor de portapapeles de pago) | ✅ Ya |  | Nuestro portapapeles es gratis |
| Icono en la barra, abrir al iniciar sesión, actualizaciones | 🟡 Parcial | Más adelante |  |

## Criterio

- **Añadir**: lo usa mucha gente y encaja en una app simple.
- **Más adelante**: útil pero secundario; solo si no complica los Ajustes.
- **Descartar**: nicho, estético o contrario a la filosofía (por ejemplo, el visualizador de BoringNotch costaba un 9 % de CPU).

