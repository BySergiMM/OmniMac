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
    case menuBar
    case cleaner

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: L("Inicio", "Home")
        case .keepAwake: L("Mantener despierto", "Keep awake")
        case .switcher: L("⌘Tab por ventanas", "⌘Tab by windows")
        case .notch: L("Notch dinámico", "Dynamic notch")
        case .snapping: L("Atajos de ventanas", "Window shortcuts")
        case .clipboard: L("Portapapeles", "Clipboard")
        case .tools: L("Utilidades", "Tools")
        case .sound: L("Sonido", "Sound")
        case .performance: L("Rendimiento", "Performance")
        case .menuBar: L("Barra de menús", "Menu bar")
        case .cleaner: L("Limpiador de apps", "App cleaner")
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
        case .menuBar: "menubar.arrow.up.rectangle"
        case .cleaner: "trash"
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
        case .menuBar: .indigo
        case .cleaner: .red
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
            .navigationSplitViewColumnWidth(min: 235, ideal: 255, max: 320)
            // Sin el botón de plegar la barra lateral: en una ventana de Ajustes no
            // sirve de nada (la de macOS tampoco lo tiene) y empujaba el título de la
            // página hasta encima del divisor, que quedaba feísimo con nombres largos
            // como «Window shortcuts».
            .toolbar(removing: .sidebarToggle)
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
        case .menuBar: MenuBarPage(feature: manager.menuBar)
        case .cleaner: AppCleanerPage()
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
/// Una pestaña del notch en Ajustes: agarradero, icono, nombre e interruptor.
///
/// Se reordena de dos maneras, porque el arrastre no siempre es evidente: soltando
/// una fila encima de otra, o con el botón derecho › Subir / Bajar. (`.onMove`, que
/// sería lo natural, no reordena dentro de un formulario en macOS.)
struct TabOrderRow: View {
    let tab: NotchTab
    @ObservedObject var feature: NotchFeature
    @State private var dragging = false
    @State private var dragOffset: CGFloat = 0

    /// Alto de una fila con su separación: lo que hay que arrastrar para adelantar a
    /// la siguiente.
    private static let rowHeight: CGFloat = 56

    private var index: Int? { feature.tabOrder.firstIndex(of: tab) }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.tertiary)
                .help(L("Arrastra para cambiar el orden", "Drag to reorder"))
            Image(systemName: tab.symbol)
                .frame(width: 20)
                .foregroundStyle(.secondary)
            SettingToggle(title: tab.title, subtitle: tab.settingsHint,
                          isOn: Binding(
                            get: { feature.enabledTabs.contains(tab) },
                            set: { on in
                                var tabs = feature.enabledTabs
                                if on { tabs.insert(tab) } else { tabs.remove(tab) }
                                feature.enabledTabs = tabs
                            }))
        }
        .contentShape(Rectangle())
        .padding(.vertical, 2)
        .background(dragging ? Color.accentColor.opacity(0.12) : .clear)
        .offset(y: dragOffset)
        .zIndex(dragging ? 1 : 0)
        // Arrastre con el gesto de toda la vida en vez de `draggable`/`dropDestination`:
        // dentro de un formulario aquellos no llegaban a activarse nunca. Y en
        // `simultaneousGesture`, que si no el interruptor de la fila se lo queda.
        .simultaneousGesture(
            DragGesture(minimumDistance: 6)
                .onChanged { value in
                    dragging = true
                    dragOffset = value.translation.height
                }
                .onEnded { value in
                    let shift = Int((value.translation.height / Self.rowHeight).rounded())
                    var order = feature.tabOrder
                    if let from = order.firstIndex(of: tab), shift != 0 {
                        let to = min(max(from + shift, 0), order.count - 1)
                        order.remove(at: from)
                        order.insert(tab, at: to)
                        feature.tabOrder = order
                    }
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.85)) {
                        dragging = false
                        dragOffset = 0
                    }
                }
        )
        .contextMenu {
            Button(L("Subir", "Move up")) { shift(-1) }
                .disabled(index == 0)
            Button(L("Bajar", "Move down")) { shift(1) }
                .disabled(index == feature.tabOrder.count - 1)
        }
    }

    /// Una posición arriba o abajo, desde el menú del botón derecho.
    private func shift(_ delta: Int) {
        guard let from = index else { return }
        let to = from + delta
        guard feature.tabOrder.indices.contains(to) else { return }
        var order = feature.tabOrder
        order.swapAt(from, to)
        feature.tabOrder = order
    }
}

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
/// Fila de Ajustes: título (y subtítulo opcional) a la izquierda y el control a la
/// derecha, centrado en vertical aunque el texto ocupe dos líneas. (`LabeledContent`
/// alineaba el control con la primera línea y los selectores quedaban altos.)
struct SettingRow<Control: View>: View {
    let title: String
    var subtitle: String? = nil
    @ViewBuilder var control: Control

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            SettingLabel(title: title, subtitle: subtitle)
            Spacer(minLength: 16)
            control
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
                Text(kind == .accessibility ? L("Falta el permiso de Accesibilidad", "Accessibility permission missing") : L("Falta el permiso de Grabación de pantalla", "Screen Recording permission missing"))
                    .font(.headline)
                Text(kind == .accessibility
                     ? L("Necesario para el selector ⌘Tab, mover ventanas y pegar automáticamente. macOS te pedirá marcar OmniMac en la lista.", "Needed for the ⌘Tab switcher, moving windows and auto-paste. macOS will ask you to tick OmniMac in the list.")
                     : L("Necesario para las miniaturas en vivo, copiar texto y colores de la pantalla.", "Needed for live thumbnails and for copying text and colours from the screen."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button(L("Conceder permiso…", "Grant permission…")) {
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
    @ObservedObject private var cache = CacheCleaner.shared
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
                        Text(L("Versión \(Brand.version) · gratis y de código abierto", "Version \(Brand.version) · free and open source"))
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
                Text(L("Módulos", "Modules"))
            } footer: {
                Text(L("Cada módulo se activa o desactiva aquí; sus opciones están en su página de la barra lateral.", "Each module switches on or off here; its options live on its own page in the sidebar."))
            }

            Section("General") {
                SettingRow(title: L("Idioma", "Language"), subtitle: L("Por defecto, el del Mac. Cambiarlo reinicia OmniMac.", "Follows the Mac's language by default. Changing it relaunches OmniMac.")) {
                    Picker("", selection: Binding(get: { Localization.preference }, set: { Localization.setPreference($0) })) {
                        ForEach(AppLanguage.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .labelsHidden()
                    .frame(width: 210)
                }
                SettingToggle(title: L("Abrir OmniMac al iniciar sesión", "Open OmniMac at login"),
                              subtitle: loginError ?? L("Así los módulos están siempre disponibles.", "So the modules are always available."),
                              isOn: Binding(get: { loginEnabled }, set: setLogin))
                SettingToggle(title: L("Buscar actualizaciones automáticamente", "Check for updates automatically"),
                              subtitle: L("Una vez al día. \(updater.lastCheckText).", "Once a day. \(updater.lastCheckText)."),
                              isOn: $updater.automaticChecks)
                SettingRow(title: L("Actualizaciones", "Updates"), subtitle: L("Comprueba ahora si hay una versión nueva.", "Check now for a new version.")) {
                    Button(L("Buscar ahora", "Check now")) { updater.checkForUpdates() }
                        .disabled(!updater.canCheck)
                }
            }

            Section {
                SettingRow(title: L("Espacio en disco", "Disk space"),
                           subtitle: L("La app ocupa \(CacheCleaner.format(cache.appSize)). \(cache.statusText)", "The app takes up \(CacheCleaner.format(cache.appSize)). \(cache.statusText)")) {
                    Button(L("Limpiar ahora", "Clean now")) { cache.cleanNow() }
                        .disabled(cache.cacheSize == 0)
                }
                SettingToggle(title: L("Limpiar la caché automáticamente", "Clean the cache automatically"),
                              subtitle: L("Una vez al día, sin que lo notes. Todo se regenera solo cuando hace falta.", "Once a day, without you noticing. Everything regenerates when needed."),
                              isOn: $cache.automatic)
            } header: {
                Text(L("Almacenamiento", "Storage"))
            }
            .onAppear { cache.refresh() }

            Section {
                HStack(spacing: 14) {
                    Text("☕️").font(.system(size: 28))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(L("¿Te está ayudando OmniMac?", "Is OmniMac helping you?"))
                            .font(.headline)
                        Text(L("Es gratis, sin anuncios ni cuentas. Si quieres apoyar el desarrollo, invítame a un café.", "It's free, with no ads or accounts. If you want to support development, buy me a coffee."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    VStack(spacing: 6) {
                        Button {
                            NSWorkspace.shared.open(Brand.coffeeURL)
                        } label: {
                            Label(L("Invítame a un café", "Buy me a coffee"), systemImage: "cup.and.saucer.fill")
                        }
                        .buttonStyle(.borderedProminent)
                        Button("GitHub Sponsors") { NSWorkspace.shared.open(Brand.sponsorsURL) }
                            .controlSize(.small)
                    }
                }
                .padding(.vertical, 4)
            } header: {
                Text(L("Apoyar el proyecto", "Support the project"))
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
            loginError = L("No se pudo cambiar: \(error.localizedDescription)", "Couldn't change it: \(error.localizedDescription)")
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
                Section(L("Sesión", "Session")) {
                    if feature.isActive {
                        HStack(spacing: 10) {
                            Image(systemName: "bolt.fill").foregroundStyle(.yellow)
                            Text(feature.remainingDescription.map { L("Activo · queda \($0)", "Active · \($0) left") } ?? L("Activo · sin límite", "Active · no limit"))
                            Spacer()
                            Button(L("Desactivar", "Turn off")) { feature.deactivate() }
                        }
                    } else {
                        SettingRow(title: L("Empezar", "Start"), subtitle: L("Sin límite o con temporizador.", "Indefinitely or with a timer.")) {
                            HStack(spacing: 6) {
                                Button(L("Sin límite", "No limit")) { feature.activate(minutes: nil) }
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
                        SettingRow(title: L("Hasta una hora concreta", "Until a specific time")) {
                            HStack(spacing: 8) {
                                DatePicker("", selection: $untilTime, displayedComponents: .hourAndMinute)
                                    .labelsHidden()
                                Button(L("Activar", "Turn on")) { feature.activate(until: untilDate) }
                            }
                        }
                    }
                }

                Section {
                    SettingToggle(title: L("Mantener también la pantalla encendida", "Keep the display on too"),
                                  subtitle: L("Si lo desactivas, la pantalla podrá apagarse pero el Mac seguirá despierto.", "If you turn this off, the display may sleep but the Mac stays awake."),
                                  isOn: $feature.keepDisplayOn)
                    SettingToggle(title: L("Seguir despierto con la tapa cerrada", "Stay awake with the lid closed"),
                                  subtitle: L("Cierra el MacBook y la música sigue. La primera vez macOS pide tu contraseña de administrador; después no vuelve a pedirla.", "Close the MacBook and the music keeps playing. The first time macOS asks for your administrator password; it never asks again."),
                                  isOn: $feature.closedLidMode)
                    if feature.closedLidMode, feature.isActive, feature.closedLidActive {
                        Label(L("Activo: el Mac no se dormirá al cerrar la tapa. No lo guardes en una bolsa con el café puesto.", "Active: the Mac won't sleep when you close the lid. Don't put it in a bag with keep-awake on."), systemImage: "laptopcomputer")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if feature.closedLidMode, let error = feature.closedLidError {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                    SettingToggle(title: L("Tiempo restante en la barra de menús", "Time left in the menu bar"),
                                  subtitle: L("Junto al icono, cuando la sesión tiene temporizador.", "Next to the icon, when the session has a timer."),
                                  isOn: $feature.showRemainingInMenuBar)
                    SettingToggle(title: L("Avisar cuando termine la sesión", "Notify when the session ends"),
                                  subtitle: L("Una notificación al acabar el temporizador o al pararse por batería.", "A notification when the timer ends or the session stops because of the battery."),
                                  isOn: $feature.notifyOnEnd)
                    SettingRow(title: L("Parar si la batería baja del…", "Stop if the battery drops below…"),
                               subtitle: L("Sin cargador conectado, la sesión termina para no agotar la batería.", "Without the charger connected, the session ends so the battery isn't drained.")) {
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
                    Text(L("Opciones", "Options"))
                } footer: {
                    Text(L("El modo tapa cerrada instala una regla que solo permite a OmniMac cambiar el ajuste de energía «disablesleep». Para quitarla: sudo rm /etc/sudoers.d/omnimac-lid", "Closed-lid mode installs a rule that only lets OmniMac change the “disablesleep” power setting. To remove it: sudo rm /etc/sudoers.d/omnimac-lid"))
                }

                Section {
                    SettingToggle(title: L("Mientras esté conectado al cargador", "While the charger is connected"),
                                  subtitle: L("Se activa solo al enchufarlo y se apaga al desenchufarlo.", "Turns on when you plug it in and off when you unplug it."),
                                  isOn: $feature.awakeWhilePluggedIn)
                    SettingToggle(title: L("Mientras haya una pantalla externa", "While an external display is connected"),
                                  subtitle: L("Ideal si trabajas con monitor: nunca se duerme a mitad de algo.", "Ideal with a monitor: it never sleeps halfway through something."),
                                  isOn: $feature.awakeWithExternalDisplay)
                } header: {
                    Text(L("Activar automáticamente", "Turn on automatically"))
                } footer: {
                    Text(L("También puedes activarlo desde el icono de la barra de menús o desde el notch.", "You can also turn it on from the menu-bar icon or from the notch."))
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
                Section(L("Opciones", "Options")) {
                    SettingToggle(title: L("Miniaturas en vivo", "Live thumbnails"),
                                  subtitle: L("Una vista previa real de cada ventana, como AltTab. Necesita Grabación de pantalla.", "A real preview of every window, like AltTab. Needs Screen Recording."),
                                  isOn: $feature.showThumbnails)
                    if feature.showThumbnails && !screenGranted { PermissionRow(kind: .screenRecording) }
                    SettingToggle(title: L("También con ⌥Tab", "Also with ⌥Tab"),
                                  subtitle: L("Abre el selector con ⌥Tab además de ⌘Tab (se confirma al soltar ⌥).", "Opens the switcher with ⌥Tab as well as ⌘Tab (confirmed when you release ⌥)."),
                                  isOn: $feature.useOptionTab)
                    SettingToggle(title: L("Incluir ventanas minimizadas", "Include minimized windows"),
                                  subtitle: L("Aparecen al final con una insignia naranja y se restauran al elegirlas.", "They appear last with an orange badge and are restored when chosen."),
                                  isOn: $feature.includeMinimized)
                }

                Section {
                    ShortcutRow(keys: "⌘ Tab", text: L("abre el selector y avanza", "opens the switcher and moves forward"))
                    ShortcutRow(keys: "⌘⇧ Tab", text: L("retrocede", "moves backwards"))
                    ShortcutRow(keys: L("⌘ + flechas", "⌘ + arrows"), text: L("moverse por la cuadrícula", "move around the grid"))
                    ShortcutRow(keys: L("Escribir", "Type"), text: L("busca por título de ventana o app", "searches by window or app title"))
                    ShortcutRow(keys: "⌘ W / ⌘ M", text: L("cierra / minimiza la ventana elegida", "closes / minimizes the selected window"))
                    ShortcutRow(keys: "⌘ H / ⌘ Q", text: L("oculta / cierra la app de la ventana elegida", "hides / quits the selected window's app"))
                    ShortcutRow(keys: L("Soltar ⌘", "Release ⌘"), text: L("cambia a la ventana elegida", "switches to the selected window"))
                    ShortcutRow(keys: "Esc", text: L("cancela", "cancels"))
                } header: {
                    Text(L("Cómo se usa", "How to use it"))
                } footer: {
                    Text(L("Mientras este módulo está activo, el selector nativo de macOS queda sustituido.", "While this module is on, the native macOS switcher is replaced."))
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
                Section(L("Apertura", "Opening")) {
                    SettingRow(title: L("Retardo antes de abrir", "Delay before opening"),
                               subtitle: L("Cuánto hay que estar con el ratón encima (la animación añade ~0,1 s).", "How long the mouse must hover (the animation adds ~0.1 s).")) {
                        HStack(spacing: 10) {
                            Slider(value: $hoverDelay, in: 0.1...1.0, step: 0.1)
                                .frame(width: 140)
                            Text(String(format: "%.1f s", hoverDelay))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                                .frame(width: 36, alignment: .trailing)
                        }
                    }
                    SettingToggle(title: L("Vibración al abrir", "Haptic on open"),
                                  subtitle: L("Un toque en el trackpad cuando se expande.", "A tap on the trackpad when it expands."),
                                  isOn: Binding(get: { haptic != 0 }, set: { haptic = $0 ? 1 : 0 }))
                    if haptic != 0 {
                        SettingRow(title: L("Intensidad", "Intensity")) {
                            Picker("", selection: $haptic) {
                                Text(L("Mínima", "Minimal")).tag(1)
                                Text(L("Suave", "Soft")).tag(2)
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 150)
                            .labelsHidden()
                        }
                    }
                }

                Section {
                    ForEach(feature.tabOrder, id: \.self) { tab in
                        TabOrderRow(tab: tab, feature: feature)
                    }
                    // Rendimiento no está en la lista: va siempre a la derecha (el
                    // quinto icono de la izquierda caería debajo del notch físico) y
                    // se enciende desde su propia página, donde se elige si sale en el
                    // notch, en la barra de menús o en ningún sitio.
                    SettingRow(title: NotchTab.performance.title,
                               subtitle: L("Se configura en Ajustes › Rendimiento: en el notch, en la barra de menús o en ningún sitio.",
                                           "Set in Settings › Performance: in the notch, in the menu bar or nowhere.")) {
                        Image(systemName: feature.enabledTabs.contains(.performance) ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(feature.enabledTabs.contains(.performance) ? Color.accentColor : .secondary)
                    }
                } header: {
                    Text(L("Pestañas", "Tabs"))
                } footer: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L("Arrastra los iconos para cambiar su orden en el notch.",
                               "Drag the icons to change their order in the notch."))
                        Text(L("Apaga lo que no uses: su icono desaparece del notch al momento. Rendimiento va siempre a la derecha.",
                               "Switch off what you don't use: its icon disappears from the notch at once. Performance always sits on the right."))
                    }
                }

                Section(L("Botones de la cabecera", "Header buttons")) {
                    SettingToggle(title: L("Mantener despierto (café)", "Keep awake (coffee)"), subtitle: L("Activa o apaga el café con un clic.", "Turns keep-awake on or off with one click."), isOn: $feature.showCoffeeButton)
                    SettingToggle(title: L("Ajustes de OmniMac (engranaje)", "OmniMac settings (gear)"), subtitle: L("Abre esta ventana.", "Opens this window."), isOn: $feature.showSettingsButton)
                    SettingToggle(title: L("Batería", "Battery"), subtitle: L("Porcentaje y estado; clic para ir a Ajustes del Sistema › Batería.", "Percentage and state; click to open System Settings › Battery."), isOn: $feature.showBattery)
                }

                Section(L("Música", "Music")) {
                    SettingRow(title: L("App de música", "Music app"),
                               subtitle: L("La que el notch controla y puede abrir para reproducir aunque esté cerrada.", "The one the notch controls and can launch to play even if it's closed.")) {
                        Picker("", selection: Binding(
                            get: { player?.rawValue ?? "" },
                            set: { raw in
                                player = MusicPlayer(rawValue: raw)
                                MusicPlayer.preferred = player
                            }
                        )) {
                            Text(L("Sin asignar", "Not set")).tag("")
                            ForEach(MusicPlayer.installed) { candidate in
                                Text(candidate.displayName).tag(candidate.rawValue)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 150)
                    }
                    SettingToggle(title: L("Vistazo rápido al cambiar de canción", "Sneak peek on track change"),
                                  subtitle: L("Título y artista bajo el notch durante unos segundos.", "Title and artist under the notch for a few seconds."),
                                  isOn: $feature.sneakPeek)
                }

                Section {
                    SettingRow(title: L("Dónde aparecen los avisos", "Where notices appear"),
                               subtitle: L("«Texto copiado», «Micrófono silenciado», el temporizador…", "“Text copied”, “Microphone muted”, the timer…")) {
                        Picker("", selection: $toastStyle) {
                            ForEach(ToastStyle.allCases, id: \.rawValue) { style in
                                Text(style.title).tag(style.rawValue)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 190)
                    }
                    SettingRow(title: L("Probar", "Try it")) {
                        Button(L("Enseñar un aviso", "Show a notice")) { Toast.show(L("Así se ven los avisos", "This is what notices look like"), symbol: "hand.wave.fill", duration: 2.5) }
                    }
                } header: {
                    Text(L("Avisos", "Notices"))
                } footer: {
                    Text(L("Con el notch abierto u oculto (pantalla completa), el aviso sale abajo.", "With the notch open or hidden (full screen), the notice appears at the bottom."))
                }

                Section {
                    SettingRow(title: L("Trabajo", "Work")) { minutesStepper($timer.workMinutes, range: 5...120) }
                    SettingRow(title: L("Descanso", "Break")) { minutesStepper($timer.restMinutes, range: 1...60) }
                    SettingRow(title: L("Descanso largo", "Long break")) { minutesStepper($timer.longRestMinutes, range: 5...90) }
                    SettingRow(title: L("Descanso largo cada", "Long break every"), subtitle: L("Pomodoros seguidos antes del descanso largo (0 = nunca).", "Pomodoros in a row before a long break (0 = never).")) {
                        Stepper(value: $timer.longRestEvery, in: 0...10) {
                            Text(timer.longRestEvery == 0 ? L("nunca", "never") : "\(timer.longRestEvery) pomodoros")
                                .monospacedDigit()
                                .frame(width: 96, alignment: .trailing)
                        }
                    }
                    SettingRow(title: L("Tiempos rápidos", "Quick times"), subtitle: L("Los botones del notch, en minutos y separados por comas (hasta 6).", "The notch buttons, in minutes, separated by commas (up to 6).")) {
                        TextField("5, 10, 25, 45, 60", text: $presetsText)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 170)
                            .onSubmit {
                                timer.presetsText = presetsText
                                presetsText = timer.presetsText
                            }
                    }
                } header: {
                    Text(L("Temporizador y Pomodoro", "Timer and Pomodoro"))
                } footer: {
                    Text(L("Pulsa Intro en los tiempos rápidos para guardarlos.", "Press Return in the quick times to save them."))
                }

                Section {
                    SettingToggle(title: L("Animación al conectar AirPods o Beats", "Animation when AirPods or Beats connect"),
                                  subtitle: L("El notch se despliega un momento con el modelo y la batería de cada pieza, como en el iPhone, y se pliega solo.", "The notch expands for a moment with the model and each piece's battery, like on iPhone, and folds away by itself."),
                                  isOn: $feature.headphonesCard)
                    SettingToggle(title: L("Ocultar el aviso de macOS", "Hide the macOS banner"),
                                  subtitle: L("Cierra el aviso de «conectados» de Control Center en cuanto aparece. Necesita Accesibilidad; experimental.", "Closes Control Center's “connected” banner as soon as it appears. Needs Accessibility; experimental."),
                                  isOn: $feature.hideSystemBanner)
                    .disabled(!feature.headphonesCard)
                    SettingRow(title: L("Vista previa", "Preview"), subtitle: L("Enseña la tarjeta con unos AirPods Pro de ejemplo.", "Shows the card with sample AirPods Pro.")) {
                        Button(L("Probar", "Try it")) { feature.previewHeadphones() }
                    }
                } header: {
                    Text(L("Auriculares", "Headphones"))
                } footer: {
                    Text(L("Sin permisos extra: la app se entera por CoreAudio en cuanto aparecen los auriculares y lee la batería con la información del sistema. Funciona con AirPods (todos), AirPods Max y Beats.", "No extra permissions: the app hears about the headphones through CoreAudio as soon as they appear and reads the battery from System Information. Works with all AirPods, AirPods Max and Beats."))
                }

                Section(L("Otros", "Other")) {
                    SettingToggle(title: L("Ocultar en apps a pantalla completa", "Hide in full-screen apps"),
                                  subtitle: L("Vídeo, juegos, presentaciones… el notch no estorba.", "Video, games, presentations… the notch stays out of the way."),
                                  isOn: $feature.hideInFullscreen)
                    SettingToggle(title: L("Mostrar también sin notch", "Show on Macs without a notch too"),
                                  subtitle: L("En pantallas sin notch aparece una pequeña isla negra arriba, en el centro.", "On displays without a notch, a small black island appears at the top centre."),
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
                Section(L("Opciones", "Options")) {
                    SettingToggle(title: L("Ajustar arrastrando a los bordes", "Snap by dragging to the edges"),
                                  subtitle: L("Arrastra una ventana a un lado (mitad), a una esquina (cuarto) o arriba (maximizar); una huella te enseña dónde quedará.", "Drag a window to a side (half), a corner (quarter) or the top (maximize); a footprint shows where it will land."),
                                  isOn: $feature.snapByDragging)
                    SettingToggle(title: L("Ciclar tamaños al repetir", "Cycle sizes on repeat"),
                                  subtitle: L("Repetir un atajo de mitad en la misma ventana pasa de ½ a ⅔ y a ⅓.", "Repeating a half shortcut on the same window goes from ½ to ⅔ to ⅓."),
                                  isOn: $feature.cycleSizes)
                }

                Section {
                    HStack(spacing: 8) {
                        TextField(L("Nombre, p. ej. «Trabajo» o «Monitor»", "Name, e.g. “Work” or “Monitor”"), text: $newName)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit(saveLayout)
                        Button(L("Guardar la disposición actual", "Save the current layout"), action: saveLayout)
                            .buttonStyle(.borderedProminent)
                            .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    ForEach(store.layouts) { layout in
                        HStack(spacing: 10) {
                            Picker("", selection: Binding(
                                get: { layout.hotKey ?? 0 },
                                set: { store.setHotKey($0 == 0 ? nil : $0, for: layout) }
                            )) {
                                Text(L("Sin atajo", "No shortcut")).tag(0)
                                ForEach(1...9, id: \.self) { number in Text("⌃⌥ \(number)").tag(number) }
                            }
                            .labelsHidden()
                            .frame(width: 100)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(layout.name).fontWeight(.semibold)
                                Text(L("\(layout.windows.count) ventanas de \(layout.appCount) apps · \(layout.screenCount == 1 ? "1 pantalla" : "\(layout.screenCount) pantallas")", "\(layout.windows.count) windows from \(layout.appCount) apps · \(layout.screenCount == 1 ? "1 display" : "\(layout.screenCount) displays")"))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button(L("Aplicar", "Apply")) { store.apply(layout) }
                            Button(L("Actualizar", "Update")) { store.refresh(layout) }
                                .help(L("Vuelve a guardar dónde están las ventanas ahora", "Saves again where the windows are now"))
                            Button(L("Eliminar", "Delete"), role: .destructive) { store.delete(layout) }
                        }
                        .controlSize(.small)
                    }
                    SettingToggle(title: L("Aplicar sola al cambiar de pantallas", "Apply automatically when displays change"),
                                  subtitle: L("Al conectar o quitar un monitor, coloca las ventanas según la última disposición guardada con ese número de pantallas.", "When you connect or remove a monitor, windows are placed following the last layout saved with that number of displays."),
                                  isOn: $store.autoApply)
                } header: {
                    Text(L("Disposiciones", "Layouts"))
                } footer: {
                    Text(L("Sin abrir Ajustes: ⌃⌥ + número guarda la disposición actual si ese número está libre, o la aplica si ya tiene una; mantén pulsado el atajo para liberar el número. ⌃⌥0 deshace la última aplicada.", "Without opening Settings: ⌃⌥ + number saves the current layout if that number is free, or applies it if it already has one; hold the shortcut to free the number. ⌃⌥0 undoes the last one applied."))
                }

                Section {
                    ForEach(SnappingFeature.shortcutHelp, id: \.shortcut) { item in
                        ShortcutRow(keys: item.shortcut, text: item.action)
                    }
                } header: {
                    Text(L("Atajos", "Shortcuts"))
                } footer: {
                    Text(L("«Restaurar» devuelve la ventana a como estaba antes del primer ajuste.", "“Restore” returns the window to how it was before the first snap."))
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
                    SettingRow(title: L("Elementos guardados", "Items kept"), subtitle: L("Cuántas copias recordar como máximo.", "How many copies to remember at most.")) {
                        Picker("", selection: $feature.maxItems) {
                            Text("20").tag(20)
                            Text("40").tag(40)
                            Text("100").tag(100)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 160)
                        .labelsHidden()
                    }
                    SettingToggle(title: L("Guardar el historial en disco", "Save the history to disk"),
                                  subtitle: L("Se conserva al cerrar la app (en tu carpeta de Application Support, sin cifrar). Apagado, solo vive en memoria.", "Kept when the app quits (in your Application Support folder, unencrypted). Off, it lives only in memory."),
                                  isOn: $feature.persist)
                    SettingToggle(title: L("Pausar el historial", "Pause the history"),
                                  subtitle: L("Mientras esté en pausa no se guarda nada de lo que copies.", "While paused, nothing you copy is saved."),
                                  isOn: $feature.paused)
                    SettingRow(title: L("\(feature.items.count) elementos en el historial", "\(feature.items.count) items in the history")) {
                        Button(L("Vaciar historial", "Clear history"), role: .destructive) { feature.clear() }
                            .controlSize(.small)
                    }
                } header: {
                    Text(L("Opciones", "Options"))
                } footer: {
                    Text(L("Guarda texto, imágenes y archivos. Se ignoran los gestores de contraseñas y las copias marcadas como confidenciales.", "Saves text, images and files. Password managers and copies marked confidential are ignored."))
                }

                Section(L("Cómo se usa", "How to use it")) {
                    ShortcutRow(keys: "⇧⌘ V", text: L("abre el historial", "opens the history"))
                    ShortcutRow(keys: L("Escribir", "Type"), text: L("busca en lo copiado", "searches what you copied"))
                    ShortcutRow(keys: L("↑ ↓ o 1–9", "↑ ↓ or 1–9"), text: L("elige un elemento", "selects an item"))
                    ShortcutRow(keys: "↩", text: L("lo pega donde estabas escribiendo", "pastes it where you were typing"))
                    ShortcutRow(keys: "⌥ P", text: L("ancla el elemento (siempre arriba y se conserva)", "pins the item (always on top and kept)"))
                    ShortcutRow(keys: "⌥ ⌫", text: L("borra el elemento elegido", "deletes the selected item"))
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

                Section(L("Herramientas", "What's included")) {
                    SettingRow(title: L("Copiar texto de la pantalla", "Copy text from the screen"),
                               subtitle: L("⇧⌘2: selecciona cualquier zona (una imagen, un vídeo, una app que no deja copiar) y el texto va al portapapeles.", "⇧⌘2: select any area (an image, a video, an app that won't let you copy) and the text goes to the clipboard.")) {
                        Button(L("Probar", "Try it")) { feature.captureText() }
                    }
                    SettingRow(title: L("Copiar un color de la pantalla", "Copy a colour from the screen"),
                               subtitle: L("⇧⌘6: haz clic en cualquier punto y su color va al portapapeles en hexadecimal (#3A7BD5).", "⇧⌘6: click any point and its colour goes to the clipboard as hex (#3A7BD5).")) {
                        Button(L("Probar", "Try it")) { feature.pickColor() }
                    }
                    SettingRow(title: L("Silenciar el micrófono", "Mute the microphone"),
                               subtitle: L("⌃⌥⌘M en cualquier app (videollamadas). Cambia el micrófono por defecto del sistema.", "⌃⌥⌘M in any app (video calls). Changes the system's default microphone.")) {
                        Button(feature.microphoneMuted ? L("Activar", "Turn on") : L("Silenciar", "Mute")) { feature.toggleMicrophone() }
                    }
                    SettingRow(title: L("Bloquear el teclado para limpiarlo", "Lock the keyboard to clean it"),
                               subtitle: L("⌃⌥⌘L: 30 segundos sin que ninguna tecla haga nada; un clic lo desbloquea. Necesita Accesibilidad.", "⌃⌥⌘L: 30 seconds during which no key does anything; a click unlocks it. Needs Accessibility.")) {
                        Button(L("Bloquear 30 s", "Lock for 30 s")) { feature.lockKeyboard() }
                            .disabled(!axGranted)
                    }
                    SettingToggle(title: L("Evitar cerrar apps por accidente", "Prevent quitting apps by accident"),
                                  subtitle: L("⌘Q solo cierra la app si lo mantienes pulsado medio segundo; un toque rápido no hace nada. Necesita Accesibilidad.", "⌘Q only quits the app if you hold it for half a second; a quick tap does nothing. Needs Accessibility."),
                                  isOn: $feature.quitGuardEnabled)
                        .disabled(!axGranted)
                    SettingToggle(title: L("Ocultar los iconos del escritorio", "Hide desktop icons"),
                                  subtitle: L("Para presentaciones y capturas limpias. Finder se reinicia un instante al cambiarlo.", "For presentations and clean screenshots. Finder restarts for an instant when you change it."),
                                  isOn: Binding(get: { feature.desktopIconsHidden }, set: { _ in feature.toggleDesktopIcons() }))
                }

                Section(L("Atajos", "Shortcuts")) {
                    ForEach(ToolsFeature.shortcutHelp, id: \.shortcut) { item in
                        ShortcutRow(keys: item.shortcut, text: item.action)
                    }
                }
            }
        }
    }
}
