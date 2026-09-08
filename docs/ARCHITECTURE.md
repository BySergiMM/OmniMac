# OmniMac — Arquitectura

> Notas para quien quiera tocar el código. Lo que un usuario necesita saber está en el
> [README](../README.md).

```
Sources/OmniMac/
├── main.swift                  Punto de entrada (NSApplication)
├── App/                        Ciclo de vida de la app
│   ├── AppDelegate.swift       Arranque, onboarding, actualizaciones
│   ├── Feature.swift           BaseFeature: módulo activable y persistente
│   ├── FeatureManager.swift    Registro de módulos
│   ├── StatusItemController    Menú de la barra de menús
│   ├── SettingsWindowController   Ventana de Ajustes
│   ├── UpdaterController       Sparkle (actualizaciones automáticas)
│   └── Snapshots.swift         `--snapshots`: capturas reales para la web (y `--lang en`)
├── Support/                    Ayudas compartidas por todos los módulos
│   ├── AX.swift                API de Accesibilidad (leer/colocar ventanas)
│   ├── HotKeyCenter.swift      Atajos globales (Carbon), con pulsar y soltar
│   ├── Permissions.swift       Accesibilidad y grabación de pantalla
│   ├── Notifier.swift          Notificaciones locales
│   ├── Toast.swift             Avisos breves (pastilla abajo o en el notch)
│   ├── FilePicker.swift        Diálogo del Finder para elegir archivos
│   ├── Localization.swift      Idioma: L("es", "en"), el del Mac o el fijado en Ajustes
│   ├── SystemBannerDismisser   Cierra el aviso de AirPods de Control Center (experimental)
│   └── HostingViews.swift      NSHostingView que acepta el primer clic
├── UI/                         Ajustes (SwiftUI): SettingsView, SoundView,
│                               PerformanceView, Brand (colores y textos)
└── Features/                   Un directorio por módulo
    ├── KeepAwake/              IOPMAssertion, modo tapa cerrada, disparadores
    ├── WindowSwitcher/         Event tap ⌘Tab + enumeración AX + panel SwiftUI
    ├── Notch/                  NotchFeature (panel y geometría), NotchView
    │   ├── Tabs/               MediaTab, TrayTab, CalendarTab, SoundTab, PerformanceTab
    │   ├── NotchTimer          Temporizador y Pomodoro
    │   ├── MediaBridge         Spotify / Música (AppleScript + notificaciones)
    │   ├── AirDropPresenter    AirDrop y archivos arrastrados
    │   └── BatteryMonitor, CalendarBridge, NotchHaptics, NotchControls
    ├── Windows/                SnappingFeature (21 atajos), SnapDrag (arrastrar a bordes),
    │                           WindowLayouts (disposiciones ⌃⌥1…9)
    ├── Clipboard/              Historial + panel de pegado
    ├── Tools/                  OCR (Vision), color, micrófono, bloqueo de teclado,
    │                           iconos del escritorio, guardia de ⌘Q
    ├── Sound/                  AudioSystem (CoreAudio), SoundFeature, AppVolumeMixer
    └── Performance/            Muestras de CPU, memoria y red (Mach/getifaddrs)
Tests/OmniMacTests/             Pruebas de la lógica pura (swift test; necesita Xcode)
docs/site/                      Web de presentación (index.html + img/ con capturas reales)
```

Reglas de la casa:

- **Un módulo = una subclase de `BaseFeature`** con `start()`/`stop()`, registrada en
  `FeatureManager` y con su página en `SettingsView`. Persistencia, menú y tarjeta de
  inicio son automáticos. Un módulo apagado **desaparece** del menú y del notch.
- **Nada trabaja en reposo**: sin temporizadores mientras el notch está plegado; batería,
  audio, música y pantallas avisan por notificación. Los gráficos solo muestrean con la
  pestaña abierta. Por eso el consumo en reposo es de 0,017 % de CPU (`docs/PERFORMANCE.md`).
- **Sin código repetido entre módulos**: lo común vive en `Support/` (`AX.setFrame`,
  `Notifier.post`, `Toast.show`, `FilePicker.choose`, `HotKeyCenter.register`).
- **Idioma**: cada texto de la interfaz se escribe una vez en cada idioma, `L("Guardar", "Save")`
  (`Support/Localization.swift`). Sin archivos `.strings`: el texto español queda a la vista en el
  código y es fácil de editar. Los textos de permisos van en `Resources/{es,en}.lproj/InfoPlist.strings`.
- Los cambios de cada versión van en `CHANGELOG.md`. Licencia MIT.
- Espacio: la app ocupa 12 MB; la caché (carátulas y restos de actualizaciones) está acotada a 16 MB y se limpia sola a diario, o a mano desde Ajustes › Inicio › Almacenamiento.
