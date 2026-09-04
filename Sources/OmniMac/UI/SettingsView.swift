import AppKit
import SwiftUI
import ServiceManagement

// MARK: - Páginas

enum SettingsPage: String, CaseIterable, Identifiable {
    case home
    case keepAwake
    case switcher
    case notch
    case snapping
    case clipboard
    case tools
    case sound
    case performance

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: "Inicio"
        case .keepAwake: "Mantener despierto"
        case .switcher: "⌘Tab por ventanas"
        case .notch: "Notch dinámico"
        case .snapping: "Atajos de ventanas"
        case .clipboard: "Portapapeles"
        case .tools: "Utilidades"
        case .sound: "Sonido"
        case .performance: "Rendimiento"
        }
    }

    var symbol: String {
        switch self {
        case .home: "sparkles"
        case .keepAwake: "cup.and.saucer.fill"
        case .switcher: "rectangle.on.rectangle"
        case .notch: "sparkles.rectangle.stack"
        case .snapping: "rectangle.split.2x1"
        case .clipboard: "doc.on.clipboard"
        case .tools: "wrench.and.screwdriver.fill"
        case .sound: "speaker.wave.3.fill"
        case .performance: "gauge.with.dots.needle.33percent"
        }
    }

    /// Color del icono en la barra lateral, como en Ajustes del Sistema.
    var color: Color {
        switch self {
        case .home: Brand.accent
        case .keepAwake: .orange
        case .switcher: .blue
        case .notch: Color(white: 0.2)
        case .snapping: .teal
        case .clipboard: .yellow
        case .tools: .gray
        case .sound: .pink
        case .performance: .green
        }
    }
}

struct SettingsView: View {
    @ObservedObject var manager: FeatureManager
    @ObservedObject private var permissions = PermissionsMonitor.shared
    @State private var page: SettingsPage? = .home

    private var axGranted: Bool { permissions.accessibilityGranted }

    var body: some View {
        NavigationSplitView {
            List(SettingsPage.allCases, selection: $page) { item in
                SidebarRow(page: item)
                    .tag(item)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 200, ideal: 215, max: 250)
            .modifier(SolidToolbar())
        } detail: {
            detailView
                .formStyle(.grouped)
                .navigationTitle((page ?? .home).title)
                .modifier(SolidToolbar())
        }
        .frame(minWidth: 860, minHeight: 600)
        .tint(Brand.accent)
    }

    @ViewBuilder
    private var detailView: some View {
        switch page ?? .home {
        case .home: HomePage(manager: manager, axGranted: axGranted)
        case .keepAwake: KeepAwakePage(feature: manager.keepAwake)
        case .switcher: SwitcherPage(feature: manager.switcher, axGranted: axGranted, screenGranted: permissions.screenRecordingGranted)
        case .notch: NotchPage(feature: manager.notch, timer: NotchTimer.shared)
        case .snapping: SnappingPage(feature: manager.snapping, axGranted: axGranted)
        case .clipboard: ClipboardPage(feature: manager.clipboard, axGranted: axGranted)
        case .tools: ToolsPage(feature: manager.tools, screenGranted: permissions.screenRecordingGranted, axGranted: axGranted)
        case .sound: SoundPage(feature: manager.sound)
        case .performance: PerformancePage()
        }
    }
}

/// Barra de título opaca (fondo de ventana, no cristal): el contenido no se ve a
/// través de ella al desplazarse.
struct SolidToolbar: ViewModifier {
    func body(content: Content) -> some View {
        let base = content
            .toolbarBackground(Color(nsColor: .windowBackgroundColor), for: .windowToolbar)
            .toolbarBackground(.visible, for: .windowToolbar)
        // El efecto de borde solo existe en el SDK de macOS 26 (Xcode 26 / Swift 6.2+); con SDKs
        // anteriores (por ejemplo en CI) se compila sin él.
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            base.scrollEdgeEffectStyle(.hard, for: .top)
        } else {
            base
        }
        #else
        base
        #endif
    }
}

struct SidebarRow: View {
    let page: SettingsPage

    var body: some View {
        HStack(spacing: 9) {
            SettingsIcon(symbol: page.symbol, color: page.color, size: 24)
            Text(page.title)
        }
        .padding(.vertical, 1)
    }
}

/// Icono cuadrado de color, como los de Ajustes del Sistema.
struct SettingsIcon: View {
    let symbol: String
    let color: Color
    var size: CGFloat = 24

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
            .fill(LinearGradient(colors: [color.opacity(0.95), color.opacity(0.75)], startPoint: .top, endPoint: .bottom))
            .frame(width: size, height: size)
            .overlay(
                Image(systemName: symbol)
                    .font(.system(size: size * 0.52, weight: .semibold))
                    .foregroundStyle(.white)
            )
            .shadow(color: .black.opacity(0.12), radius: 0.5, y: 0.5)
    }
}

// MARK: - Piezas comunes (estilo formulario nativo)

/// Cabecera de módulo: icono, nombre, descripción e interruptor general.
struct ModuleHeader: View {
    @ObservedObject var feature: BaseFeature
    let page: SettingsPage

    var body: some View {
        Section {
            HStack(alignment: .center, spacing: 14) {
                SettingsIcon(symbol: page.symbol, color: page.color, size: 44)
                VStack(alignment: .leading, spacing: 3) {
                    Text(feature.displayName)
                        .font(.title3.weight(.semibold))
                    Text(feature.blurb)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Toggle("", isOn: $feature.isEnabled)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .controlSize(.large)
            }
            .padding(.vertical, 4)
        }
    }
}

/// Interruptor con título y explicación corta debajo.
struct SettingToggle: View {
    let title: String
    var subtitle: String? = nil
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            SettingLabel(title: title, subtitle: subtitle)
        }
        .toggleStyle(.switch)
    }
}

/// Etiqueta a la izquierda + cualquier control a la derecha.
struct SettingRow<Control: View>: View {
    let title: String
    var subtitle: String? = nil
    @ViewBuilder var control: Control

    var body: some View {
        LabeledContent {
            control
        } label: {
            SettingLabel(title: title, subtitle: subtitle)
        }
    }
}

struct SettingLabel: View {
    let title: String
    var subtitle: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
            if let subtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// Atajo (tecla) + qué hace.
struct ShortcutRow: View {
    let keys: String
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            Text(keys)
                .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(.quaternary))
                .frame(minWidth: 110, alignment: .leading)
            Text(text)
                .foregroundStyle(.secondary)
        }
    }
}

/// Aviso de permiso que falta, con botón para concederlo.
struct PermissionRow: View {
    enum Kind { case accessibility, screenRecording }
    let kind: Kind

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: kind == .accessibility ? "exclamationmark.shield.fill" : "rectangle.dashed.badge.record")
                .font(.system(size: 22))
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 5) {
                Text(kind == .accessibility ? "Falta el permiso de Accesibilidad" : "Falta el permiso de Grabación de pantalla")
                    .font(.headline)
                Text(kind == .accessibility
                     ? "Necesario para el selector ⌘Tab, mover ventanas y pegar automáticamente. macOS te pedirá marcar OmniMac en la lista."
                     : "Necesario para las miniaturas en vivo, copiar texto y colores de la pantalla.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Conceder permiso…") {
                    if kind == .accessibility {
                        Permissions.requestAccessibility()
                        Permissions.openAccessibilitySettings()
                    } else {
                        _ = Permissions.requestScreenRecording()
                        Permissions.openScreenRecordingSettings()
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Inicio

struct HomePage: View {
    @ObservedObject var manager: FeatureManager
    let axGranted: Bool
    @ObservedObject private var updater = UpdaterController.shared
    @State private var loginEnabled = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    var body: some View {
        Form {
            Section {
                HStack(spacing: 14) {
                    SettingsIcon(symbol: "sparkles", color: Brand.accent, size: 52)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(Brand.name)
                            .font(.title.bold())
                        Text(Brand.tagline)
                            .foregroundStyle(.secondary)
                        Text("Versión \(Brand.version) · gratis y de código abierto")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(.vertical, 4)
            }

            if !axGranted {
                Section { PermissionRow(kind: .accessibility) }
            }

            Section {
                ForEach(manager.all) { feature in
                    ModuleRow(feature: feature)
                }
            } header: {
                Text("Módulos")
            } footer: {
                Text("Cada módulo se activa o desactiva aquí; sus opciones están en su página de la barra lateral.")
            }

            Section("General") {
                SettingToggle(title: "Abrir OmniMac al iniciar sesión",
                              subtitle: loginError ?? "Así los módulos están siempre disponibles.",
                              isOn: Binding(get: { loginEnabled }, set: setLogin))
                SettingToggle(title: "Buscar actualizaciones automáticamente",
                              subtitle: "Una vez al día. \(updater.lastCheckText).",
                              isOn: $updater.automaticChecks)
                SettingRow(title: "Actualizaciones", subtitle: "Comprueba ahora si hay una versión nueva.") {
                    Button("Buscar ahora") { updater.checkForUpdates() }
                        .disabled(!updater.canCheck)
                }
            }

            Section {
                HStack(spacing: 14) {
                    Text("☕️").font(.system(size: 28))
                    VStack(alignment: .leading, spacing: 3) {
                        Text("¿Te está ayudando OmniMac?")
                            .font(.headline)
                        Text("Es gratis, sin anuncios ni cuentas. Si quieres apoyar el desarrollo, invítame a un café.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    VStack(spacing: 6) {
                        Button {
                            NSWorkspace.shared.open(Brand.coffeeURL)
                        } label: {
                            Label("Invítame a un café", systemImage: "cup.and.saucer.fill")
                        }
                        .buttonStyle(.borderedProminent)
                        Button("GitHub Sponsors") { NSWorkspace.shared.open(Brand.sponsorsURL) }
                            .controlSize(.small)
                    }
                }
                .padding(.vertical, 4)
            } header: {
                Text("Apoyar el proyecto")
            }
        }
    }

    private func setLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginEnabled = enabled
            loginError = nil
        } catch {
            loginEnabled = SMAppService.mainApp.status == .enabled
            loginError = "No se pudo cambiar: \(error.localizedDescription)"
        }
    }
}

struct ModuleRow: View {
    @ObservedObject var feature: BaseFeature

    private var page: SettingsPage? {
        switch feature.featureID {
        case "keepawake": .keepAwake
        case "switcher": .switcher
        case "notch": .notch
        case "snapping": .snapping
        case "clipboard": .clipboard
        case "tools": .tools
        case "sound": .sound
        default: nil
        }
    }

    var body: some View {
        Toggle(isOn: $feature.isEnabled) {
            HStack(spacing: 10) {
                SettingsIcon(symbol: feature.symbol, color: page?.color ?? .gray, size: 26)
                VStack(alignment: .leading, spacing: 2) {
                    Text(feature.displayName)
                    Text(feature.blurb)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .toggleStyle(.switch)
    }
}

// MARK: - Mantener despierto

struct KeepAwakePage: View {
    @ObservedObject var feature: KeepAwakeFeature
    @State private var untilTime = Date().addingTimeInterval(3600)

    private var untilDate: Date {
        var date = untilTime
        if date <= Date() { date = Calendar.current.date(byAdding: .day, value: 1, to: date) ?? date }
        return date
    }

    var body: some View {
        Form {
            ModuleHeader(feature: feature, page: .keepAwake)

            if feature.isEnabled {
                Section("Sesión") {
                    if feature.isActive {
                        HStack(spacing: 10) {
                            Image(systemName: "bolt.fill").foregroundStyle(.yellow)
                            Text(feature.remainingDescription.map { "Activo · queda \($0)" } ?? "Activo · sin límite")
                            Spacer()
                            Button("Desactivar") { feature.deactivate() }
                        }
                    } else {
                        SettingRow(title: "Empezar", subtitle: "Sin límite o con temporizador.") {
                            HStack(spacing: 6) {
                                Button("Sin límite") { feature.activate(minutes: nil) }
                                    .buttonStyle(.borderedProminent)
                                Button("15 min") { feature.activate(minutes: 15) }
                                Button("30 min") { feature.activate(minutes: 30) }
                                Button("1 h") { feature.activate(minutes: 60) }
                                Button("2 h") { feature.activate(minutes: 120) }
                                Button("4 h") { feature.activate(minutes: 240) }
                                Button("8 h") { feature.activate(minutes: 480) }
                            }
                            .controlSize(.small)
                        }
                        SettingRow(title: "Hasta una hora concreta") {
                            HStack(spacing: 8) {
                                DatePicker("", selection: $untilTime, displayedComponents: .hourAndMinute)
                                    .labelsHidden()
                                Button("Activar") { feature.activate(until: untilDate) }
                            }
                        }
                    }
                }

                Section {
                    SettingToggle(title: "Mantener también la pantalla encendida",
                                  subtitle: "Si lo desactivas, la pantalla podrá apagarse pero el Mac seguirá despierto.",
                                  isOn: $feature.keepDisplayOn)
                    SettingToggle(title: "Seguir despierto con la tapa cerrada",
                                  subtitle: "Cierra el MacBook y la música sigue. La primera vez macOS pide tu contraseña de administrador; después no vuelve a pedirla.",
                                  isOn: $feature.closedLidMode)
                    if feature.closedLidMode, feature.isActive, feature.closedLidActive {
                        Label("Activo: el Mac no se dormirá al cerrar la tapa. No lo guardes en una bolsa con el café puesto.", systemImage: "laptopcomputer")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if feature.closedLidMode, let error = feature.closedLidError {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                    SettingToggle(title: "Tiempo restante en la barra de menús",
                                  subtitle: "Junto al icono, cuando la sesión tiene temporizador.",
                                  isOn: $feature.showRemainingInMenuBar)
                    SettingToggle(title: "Avisar cuando termine la sesión",
                                  subtitle: "Una notificación al acabar el temporizador o al pararse por batería.",
                                  isOn: $feature.notifyOnEnd)
                    SettingRow(title: "Parar si la batería baja del…",
                               subtitle: "Sin cargador conectado, la sesión termina para no agotar la batería.") {
                        HStack(spacing: 8) {
                            Picker("", selection: $feature.lowBatteryThreshold) {
                                Text("10 %").tag(10)
                                Text("20 %").tag(20)
                                Text("30 %").tag(30)
                            }
                            .labelsHidden()
                            .frame(width: 80)
                            .disabled(!feature.stopOnLowBattery)
                            Toggle("", isOn: $feature.stopOnLowBattery)
                                .toggleStyle(.switch)
                                .labelsHidden()
                        }
                    }
                } header: {
                    Text("Opciones")
                } footer: {
                    Text("El modo tapa cerrada instala una regla que solo permite a OmniMac cambiar el ajuste de energía «disablesleep». Para quitarla: sudo rm /etc/sudoers.d/omnimac-lid")
                }

                Section {
                    SettingToggle(title: "Mientras esté conectado al cargador",
                                  subtitle: "Se activa solo al enchufarlo y se apaga al desenchufarlo.",
                                  isOn: $feature.awakeWhilePluggedIn)
                    SettingToggle(title: "Mientras haya una pantalla externa",
                                  subtitle: "Ideal si trabajas con monitor: nunca se duerme a mitad de algo.",
                                  isOn: $feature.awakeWithExternalDisplay)
                } header: {
                    Text("Activar automáticamente")
                } footer: {
                    Text("También puedes activarlo desde el icono de la barra de menús o desde el notch.")
                }
            }
        }
    }
}

// MARK: - Selector de ventanas

struct SwitcherPage: View {
    @ObservedObject var feature: WindowSwitcherFeature
    let axGranted: Bool
    let screenGranted: Bool

    var body: some View {
        Form {
            ModuleHeader(feature: feature, page: .switcher)
            if !axGranted { Section { PermissionRow(kind: .accessibility) } }

            if feature.isEnabled {
                Section("Opciones") {
                    SettingToggle(title: "Miniaturas en vivo",
                                  subtitle: "Una vista previa real de cada ventana, como AltTab. Necesita Grabación de pantalla.",
                                  isOn: $feature.showThumbnails)
                    if feature.showThumbnails && !screenGranted { PermissionRow(kind: .screenRecording) }
                    SettingToggle(title: "También con ⌥Tab",
                                  subtitle: "Abre el selector con ⌥Tab además de ⌘Tab (se confirma al soltar ⌥).",
                                  isOn: $feature.useOptionTab)
                    SettingToggle(title: "Incluir ventanas minimizadas",
                                  subtitle: "Aparecen al final con una insignia naranja y se restauran al elegirlas.",
                                  isOn: $feature.includeMinimized)
                }

                Section {
                    ShortcutRow(keys: "⌘ Tab", text: "abre el selector y avanza")
                    ShortcutRow(keys: "⌘⇧ Tab", text: "retrocede")
                    ShortcutRow(keys: "⌘ + flechas", text: "moverse por la cuadrícula")
                    ShortcutRow(keys: "Escribir", text: "busca por título de ventana o app")
                    ShortcutRow(keys: "⌘ W / ⌘ M", text: "cierra / minimiza la ventana elegida")
                    ShortcutRow(keys: "⌘ H / ⌘ Q", text: "oculta / cierra la app de la ventana elegida")
                    ShortcutRow(keys: "Soltar ⌘", text: "cambia a la ventana elegida")
                    ShortcutRow(keys: "Esc", text: "cancela")
                } header: {
                    Text("Cómo se usa")
                } footer: {
                    Text("Mientras este módulo está activo, el selector nativo de macOS queda sustituido.")
                }
            }
        }
    }
}

// MARK: - Notch

struct NotchPage: View {
    @ObservedObject var feature: NotchFeature
    @ObservedObject var timer: NotchTimer
    @State private var player: MusicPlayer? = MusicPlayer.preferred
    @AppStorage(NotchHaptics.key) private var haptic = 1
    @AppStorage(NotchSettings.hoverDelayKey) private var hoverDelay = 0.3
    @AppStorage(Toast.styleKey) private var toastStyle = 0
    @State private var presetsText = NotchTimer.shared.presetsText

    var body: some View {
        Form {
            ModuleHeader(feature: feature, page: .notch)

            if feature.isEnabled {
                Section("Apertura") {
                    SettingRow(title: "Retardo antes de abrir",
                               subtitle: "Cuánto hay que estar con el ratón encima (la animación añade ~0,1 s).") {
                        HStack(spacing: 10) {
                            Slider(value: $hoverDelay, in: 0.1...1.0, step: 0.1)
                                .frame(width: 140)
                            Text(String(format: "%.1f s", hoverDelay))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                                .frame(width: 36, alignment: .trailing)
                        }
                    }
                    SettingToggle(title: "Vibración al abrir",
                                  subtitle: "Un toque en el trackpad cuando se expande.",
                                  isOn: Binding(get: { haptic != 0 }, set: { haptic = $0 ? 1 : 0 }))
                    if haptic != 0 {
                        SettingRow(title: "Intensidad") {
                            Picker("", selection: $haptic) {
                                Text("Mínima").tag(1)
                                Text("Suave").tag(2)
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 150)
                            .labelsHidden()
                        }
                    }
                }

                Section {
                    ForEach(NotchTab.allCases, id: \.self) { tab in
                        SettingToggle(title: tab.title, subtitle: tab.settingsHint,
                                      isOn: Binding(
                                        get: { feature.enabledTabs.contains(tab) },
                                        set: { on in
                                            var tabs = feature.enabledTabs
                                            if on { tabs.insert(tab) } else { tabs.remove(tab) }
                                            feature.enabledTabs = tabs
                                        }))
                    }
                } header: {
                    Text("Pestañas")
                } footer: {
                    Text("Apaga lo que no uses: su icono desaparece del notch al momento.")
                }

                Section("Botones de la cabecera") {
                    SettingToggle(title: "Mantener despierto (café)", subtitle: "Activa o apaga el café con un clic.", isOn: $feature.showCoffeeButton)
                    SettingToggle(title: "Ajustes de OmniMac (engranaje)", subtitle: "Abre esta ventana.", isOn: $feature.showSettingsButton)
                    SettingToggle(title: "Batería", subtitle: "Porcentaje y estado; clic para ir a Ajustes del Sistema › Batería.", isOn: $feature.showBattery)
                }

                Section("Música") {
                    SettingRow(title: "App de música",
                               subtitle: "La que el notch controla y puede abrir para reproducir aunque esté cerrada.") {
                        Picker("", selection: Binding(
                            get: { player?.rawValue ?? "" },
                            set: { raw in
                                player = MusicPlayer(rawValue: raw)
                                MusicPlayer.preferred = player
                            }
                        )) {
                            Text("Sin asignar").tag("")
                            ForEach(MusicPlayer.installed) { candidate in
                                Text(candidate.displayName).tag(candidate.rawValue)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 150)
                    }
                    SettingToggle(title: "Vistazo rápido al cambiar de canción",
                                  subtitle: "Título y artista bajo el notch durante unos segundos.",
                                  isOn: $feature.sneakPeek)
                }

                Section {
                    SettingRow(title: "Dónde aparecen los avisos",
                               subtitle: "«Texto copiado», «Micrófono silenciado», el temporizador…") {
                        Picker("", selection: $toastStyle) {
                            ForEach(ToastStyle.allCases, id: \.rawValue) { style in
                                Text(style.title).tag(style.rawValue)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 190)
                    }
                    SettingRow(title: "Probar") {
                        Button("Enseñar un aviso") { Toast.show("Así se ven los avisos", symbol: "hand.wave.fill", duration: 2.5) }
                    }
                } header: {
                    Text("Avisos")
                } footer: {
                    Text("Con el notch abierto u oculto (pantalla completa), el aviso sale abajo.")
                }

                Section {
                    SettingRow(title: "Trabajo") { minutesStepper($timer.workMinutes, range: 5...120) }
                    SettingRow(title: "Descanso") { minutesStepper($timer.restMinutes, range: 1...60) }
                    SettingRow(title: "Descanso largo") { minutesStepper($timer.longRestMinutes, range: 5...90) }
                    SettingRow(title: "Descanso largo cada", subtitle: "Pomodoros seguidos antes del descanso largo (0 = nunca).") {
                        Stepper(value: $timer.longRestEvery, in: 0...10) {
                            Text(timer.longRestEvery == 0 ? "nunca" : "\(timer.longRestEvery) pomodoros")
                                .monospacedDigit()
                                .frame(width: 96, alignment: .trailing)
                        }
                    }
                    SettingRow(title: "Tiempos rápidos", subtitle: "Los botones del notch, en minutos y separados por comas (hasta 6).") {
                        TextField("5, 10, 25, 45, 60", text: $presetsText)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 170)
                            .onSubmit {
                                timer.presetsText = presetsText
                                presetsText = timer.presetsText
                            }
                    }
                } header: {
                    Text("Temporizador y Pomodoro")
                } footer: {
                    Text("Pulsa Intro en los tiempos rápidos para guardarlos.")
                }

                Section {
                    SettingToggle(title: "Animación al conectar AirPods o Beats",
                                  subtitle: "El notch se despliega un momento con el modelo y la batería de cada pieza, como en el iPhone, y se pliega solo.",
                                  isOn: $feature.headphonesCard)
                    SettingToggle(title: "Ocultar el aviso de macOS",
                                  subtitle: "Cierra el aviso de «conectados» de Control Center en cuanto aparece. Necesita Accesibilidad; experimental.",
                                  isOn: $feature.hideSystemBanner)
                    .disabled(!feature.headphonesCard)
                    SettingRow(title: "Vista previa", subtitle: "Enseña la tarjeta con unos AirPods Pro de ejemplo.") {
                        Button("Probar") { feature.previewHeadphones() }
                    }
                } header: {
                    Text("Auriculares")
                } footer: {
                    Text("Sin permisos extra: la app se entera por CoreAudio en cuanto aparecen los auriculares y lee la batería con la información del sistema. Funciona con AirPods (todos), AirPods Max y Beats.")
                }

                Section("Otros") {
                    SettingToggle(title: "Ocultar en apps a pantalla completa",
                                  subtitle: "Vídeo, juegos, presentaciones… el notch no estorba.",
                                  isOn: $feature.hideInFullscreen)
                    SettingToggle(title: "Mostrar también sin notch",
                                  subtitle: "En pantallas sin notch aparece una pequeña isla negra arriba, en el centro.",
                                  isOn: $feature.showWithoutNotch)
                }
            }
        }
    }

    private func minutesStepper(_ value: Binding<Int>, range: ClosedRange<Int>) -> some View {
        Stepper(value: value, in: range) {
            Text("\(value.wrappedValue) min")
                .monospacedDigit()
                .frame(width: 60, alignment: .trailing)
        }
    }
}

// MARK: - Atajos de ventanas

struct SnappingPage: View {
    @ObservedObject var feature: SnappingFeature
    let axGranted: Bool
    @ObservedObject private var store = WindowLayoutStore.shared
    @State private var newName = ""

    var body: some View {
        Form {
            ModuleHeader(feature: feature, page: .snapping)
            if !axGranted { Section { PermissionRow(kind: .accessibility) } }

            if feature.isEnabled {
                Section("Opciones") {
                    SettingToggle(title: "Ajustar arrastrando a los bordes",
                                  subtitle: "Arrastra una ventana a un lado (mitad), a una esquina (cuarto) o arriba (maximizar); una huella te enseña dónde quedará.",
                                  isOn: $feature.snapByDragging)
                    SettingToggle(title: "Ciclar tamaños al repetir",
                                  subtitle: "Repetir un atajo de mitad en la misma ventana pasa de ½ a ⅔ y a ⅓.",
                                  isOn: $feature.cycleSizes)
                }

                Section {
                    HStack(spacing: 8) {
                        TextField("Nombre, p. ej. «Trabajo» o «Monitor»", text: $newName)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit(saveLayout)
                        Button("Guardar la disposición actual", action: saveLayout)
                            .buttonStyle(.borderedProminent)
                            .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    ForEach(store.layouts) { layout in
                        HStack(spacing: 10) {
                            Picker("", selection: Binding(
                                get: { layout.hotKey ?? 0 },
                                set: { store.setHotKey($0 == 0 ? nil : $0, for: layout) }
                            )) {
                                Text("Sin atajo").tag(0)
                                ForEach(1...9, id: \.self) { number in Text("⌃⌥ \(number)").tag(number) }
                            }
                            .labelsHidden()
                            .frame(width: 100)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(layout.name).fontWeight(.semibold)
                                Text("\(layout.windows.count) ventanas de \(layout.appCount) apps · \(layout.screenCount == 1 ? "1 pantalla" : "\(layout.screenCount) pantallas")")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Aplicar") { store.apply(layout) }
                            Button("Actualizar") { store.refresh(layout) }
                                .help("Vuelve a guardar dónde están las ventanas ahora")
                            Button("Eliminar", role: .destructive) { store.delete(layout) }
                        }
                        .controlSize(.small)
                    }
                    SettingToggle(title: "Aplicar sola al cambiar de pantallas",
                                  subtitle: "Al conectar o quitar un monitor, coloca las ventanas según la última disposición guardada con ese número de pantallas.",
                                  isOn: $store.autoApply)
                } header: {
                    Text("Disposiciones")
                } footer: {
                    Text("Sin abrir Ajustes: ⌃⌥ + número guarda la disposición actual si ese número está libre, o la aplica si ya tiene una; mantén pulsado el atajo para liberar el número. ⌃⌥0 deshace la última aplicada.")
                }

                Section {
                    ForEach(SnappingFeature.shortcutHelp, id: \.shortcut) { item in
                        ShortcutRow(keys: item.shortcut, text: item.action)
                    }
                } header: {
                    Text("Atajos")
                } footer: {
                    Text("«Restaurar» devuelve la ventana a como estaba antes del primer ajuste.")
                }
            }
        }
    }

    private func saveLayout() {
        guard store.saveCurrent(named: newName) != nil else { return }
        newName = ""
    }
}

// MARK: - Portapapeles

struct ClipboardPage: View {
    @ObservedObject var feature: ClipboardFeature
    let axGranted: Bool

    var body: some View {
        Form {
            ModuleHeader(feature: feature, page: .clipboard)
            if !axGranted { Section { PermissionRow(kind: .accessibility) } }

            if feature.isEnabled {
                Section {
                    SettingRow(title: "Elementos guardados", subtitle: "Cuántas copias recordar como máximo.") {
                        Picker("", selection: $feature.maxItems) {
                            Text("20").tag(20)
                            Text("40").tag(40)
                            Text("100").tag(100)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 160)
                        .labelsHidden()
                    }
                    SettingToggle(title: "Guardar el historial en disco",
                                  subtitle: "Se conserva al cerrar la app (en tu carpeta de Application Support, sin cifrar). Apagado, solo vive en memoria.",
                                  isOn: $feature.persist)
                    SettingToggle(title: "Pausar el historial",
                                  subtitle: "Mientras esté en pausa no se guarda nada de lo que copies.",
                                  isOn: $feature.paused)
                    SettingRow(title: "\(feature.items.count) elementos en el historial") {
                        Button("Vaciar historial", role: .destructive) { feature.clear() }
                            .controlSize(.small)
                    }
                } header: {
                    Text("Opciones")
                } footer: {
                    Text("Guarda texto, imágenes y archivos. Se ignoran los gestores de contraseñas y las copias marcadas como confidenciales.")
                }

                Section("Cómo se usa") {
                    ShortcutRow(keys: "⇧⌘ V", text: "abre el historial")
                    ShortcutRow(keys: "Escribir", text: "busca en lo copiado")
                    ShortcutRow(keys: "↑ ↓ o 1–9", text: "elige un elemento")
                    ShortcutRow(keys: "↩", text: "lo pega donde estabas escribiendo")
                    ShortcutRow(keys: "⌥ P", text: "ancla el elemento (siempre arriba y se conserva)")
                    ShortcutRow(keys: "⌥ ⌫", text: "borra el elemento elegido")
                }
            }
        }
    }
}

// MARK: - Utilidades

struct ToolsPage: View {
    @ObservedObject var feature: ToolsFeature
    let screenGranted: Bool
    let axGranted: Bool

    var body: some View {
        Form {
            ModuleHeader(feature: feature, page: .tools)

            if feature.isEnabled {
                if !screenGranted { Section { PermissionRow(kind: .screenRecording) } }

                Section("Herramientas") {
                    SettingRow(title: "Copiar texto de la pantalla",
                               subtitle: "⇧⌘2: selecciona cualquier zona (una imagen, un vídeo, una app que no deja copiar) y el texto va al portapapeles.") {
                        Button("Probar") { feature.captureText() }
                    }
                    SettingRow(title: "Copiar un color de la pantalla",
                               subtitle: "⇧⌘6: haz clic en cualquier punto y su color va al portapapeles en hexadecimal (#3A7BD5).") {
                        Button("Probar") { feature.pickColor() }
                    }
                    SettingRow(title: "Silenciar el micrófono",
                               subtitle: "⌃⌥⌘M en cualquier app (videollamadas). Cambia el micrófono por defecto del sistema.") {
                        Button(feature.microphoneMuted ? "Activar" : "Silenciar") { feature.toggleMicrophone() }
                    }
                    SettingRow(title: "Bloquear el teclado para limpiarlo",
                               subtitle: "⌃⌥⌘L: 30 segundos sin que ninguna tecla haga nada; un clic lo desbloquea. Necesita Accesibilidad.") {
                        Button("Bloquear 30 s") { feature.lockKeyboard() }
                            .disabled(!axGranted)
                    }
                    SettingToggle(title: "Evitar cerrar apps por accidente",
                                  subtitle: "⌘Q solo cierra la app si lo mantienes pulsado medio segundo; un toque rápido no hace nada. Necesita Accesibilidad.",
                                  isOn: $feature.quitGuardEnabled)
                        .disabled(!axGranted)
                    SettingToggle(title: "Ocultar los iconos del escritorio",
                                  subtitle: "Para presentaciones y capturas limpias. Finder se reinicia un instante al cambiarlo.",
                                  isOn: Binding(get: { feature.desktopIconsHidden }, set: { _ in feature.toggleDesktopIcons() }))
                }

                Section("Atajos") {
                    ForEach(ToolsFeature.shortcutHelp, id: \.shortcut) { item in
                        ShortcutRow(keys: item.shortcut, text: item.action)
                    }
                }
            }
        }
    }
}
