import AppKit
import Combine
import IOKit.pwr_mgt
import UserNotifications

/// Evita que el Mac entre en reposo, como Amphetamine/Caffeine.
final class KeepAwakeFeature: BaseFeature {
    @Published private(set) var isActive = false
    @Published private(set) var deadline: Date?

    typealias EndReason = KeepAwakeEndReason

    /// Cómo acabó la última sesión que no paró el usuario.
    ///
    /// Se guarda en disco a propósito: cuando la sesión se corta con la tapa cerrada
    /// el Mac se duerme en el acto, la notificación puede no llegar a entregarse
    /// nunca, y al abrir el portátil no quedaba forma de saber qué había pasado.
    @Published private(set) var lastEnding: KeepAwakeEnding?
    /// Ya se ha avisado de que queda poco para el corte por batería en esta sesión.
    private var warnedLowBattery = false

    /// Tiempo restante junto al icono de la barra de menús (sesiones con temporizador).
    @Published var showRemainingInMenuBar: Bool {
        didSet { UserDefaults.standard.set(showRemainingInMenuBar, forKey: "keepawake.menuBarTime") }
    }
    /// Notificación al terminar el temporizador o al pararse por batería.
    @Published var notifyOnEnd: Bool {
        didSet { UserDefaults.standard.set(notifyOnEnd, forKey: "keepawake.notify") }
    }
    /// Sin cargador, terminar la sesión si la batería baja del umbral.
    @Published var stopOnLowBattery: Bool {
        didSet { UserDefaults.standard.set(stopOnLowBattery, forKey: "keepawake.stopLowBattery") }
    }
    @Published var lowBatteryThreshold: Int {
        didSet { UserDefaults.standard.set(lowBatteryThreshold, forKey: "keepawake.lowBatteryThreshold") }
    }
    private let battery = BatteryMonitor()
    private var batteryCancellable: AnyCancellable?

    /// Disparadores: mantener despierto automáticamente mientras…
    @Published var awakeWhilePluggedIn: Bool {
        didSet {
            UserDefaults.standard.set(awakeWhilePluggedIn, forKey: "keepawake.trigger.charger")
            evaluateTriggers()
        }
    }
    @Published var awakeWithExternalDisplay: Bool {
        didSet {
            UserDefaults.standard.set(awakeWithExternalDisplay, forKey: "keepawake.trigger.display")
            evaluateTriggers()
        }
    }
    /// La sesión actual la inició un disparador (se cierra sola cuando deja de cumplirse).
    private var triggerSession = false
    /// Tras apagar a mano una sesión de disparador, no la volvemos a encender hasta
    /// que la condición deje de cumplirse y vuelva a cumplirse.
    private var triggerArmed = true
    private var screenObserver: Any?

    /// true → la pantalla se mantiene encendida; false → la pantalla puede apagarse,
    /// pero el Mac no entra en reposo.
    @Published var keepDisplayOn: Bool {
        didSet {
            UserDefaults.standard.set(keepDisplayOn, forKey: "keepawake.displayOn")
            // Si se cambia con la sesión en marcha, se nota al momento en vez de
            // esperar a la siguiente: solo va y viene la fianza de pantalla.
            guard isActive else { return }
            applyDisplayAssertion()
        }
    }

    /// Modo tapa cerrada: mientras la sesión está activa, el Mac tampoco se duerme
    /// al cerrar la tapa (la música sigue sonando). Los `IOPMAssertion` solo evitan
    /// el reposo por inactividad; el de tapa requiere `pmset disablesleep`, que es
    /// de administrador. Ver `LidSleepControl`: la contraseña se pide UNA sola vez.
    @Published var closedLidMode: Bool {
        didSet {
            UserDefaults.standard.set(closedLidMode, forKey: "keepawake.closedLid")
            guard isActive else { return }
            if closedLidMode { enableClosedLid() } else { disableClosedLid() }
        }
    }
    /// true mientras `disablesleep` está puesto por nosotros.
    @Published private(set) var closedLidActive = false
    /// Último problema legible al activar el modo tapa cerrada (cancelación, etc.).
    @Published private(set) var closedLidError: String?

    /// Fianza de sistema: el Mac no se duerme. Siempre se pide.
    private var assertionID: IOPMAssertionID = 0
    /// Fianza de pantalla: además, el monitor no se apaga. Solo si se ha pedido.
    private var displayAssertionID: IOPMAssertionID = 0
    private var timer: Timer?

    init() {
        if UserDefaults.standard.object(forKey: "keepawake.displayOn") == nil {
            keepDisplayOn = true
        } else {
            keepDisplayOn = UserDefaults.standard.bool(forKey: "keepawake.displayOn")
        }
        if UserDefaults.standard.object(forKey: "keepawake.closedLid") == nil {
            closedLidMode = true
        } else {
            closedLidMode = UserDefaults.standard.bool(forKey: "keepawake.closedLid")
        }
        let defaults = UserDefaults.standard
        showRemainingInMenuBar = defaults.object(forKey: "keepawake.menuBarTime") == nil ? true : defaults.bool(forKey: "keepawake.menuBarTime")
        notifyOnEnd = defaults.object(forKey: "keepawake.notify") == nil ? true : defaults.bool(forKey: "keepawake.notify")
        stopOnLowBattery = defaults.object(forKey: "keepawake.stopLowBattery") == nil ? true : defaults.bool(forKey: "keepawake.stopLowBattery")
        let threshold = defaults.integer(forKey: "keepawake.lowBatteryThreshold")
        lowBatteryThreshold = threshold == 0 ? 20 : threshold
        awakeWhilePluggedIn = defaults.bool(forKey: "keepawake.trigger.charger")
        awakeWithExternalDisplay = defaults.bool(forKey: "keepawake.trigger.display")
        super.init(id: "keepawake",
                   name: L("Mantener despierto", "Keep awake"),
                   symbol: "cup.and.saucer.fill",
                   blurb: L("Evita que tu Mac se duerma, como Amphetamine. Sin límite o con temporizador.", "Keeps your Mac awake, like Amphetamine. Indefinitely or with a timer."),
                   defaultEnabled: true)

        // Si la app murió de golpe con la tapa "bloqueada", al arrancar lo deshacemos.
        // Solo actúa si la regla ya existe: nunca muestra ningún diálogo.
        DispatchQueue.global(qos: .utility).async {
            if LidSleepControl.isAuthorized { LidSleepControl.set(false) }
        }

        loadEnding()

        batteryCancellable = battery.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.checkBattery(state)
                self?.evaluateTriggers()
            }
        screenObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                                                object: nil, queue: .main) { [weak self] _ in
            self?.evaluateTriggers()
        }
    }

    // MARK: - Disparadores

    private func evaluateTriggers() {
        guard isEnabled else { return }
        let plugged = awakeWhilePluggedIn && battery.state.hasBattery && battery.state.isPluggedIn
        let external = awakeWithExternalDisplay && NSScreen.screens.count > 1
        let wanted = plugged || external
        if !wanted { triggerArmed = true }
        if wanted, !isActive, triggerArmed {
            activate(seconds: nil)
            triggerSession = true
        } else if !wanted, isActive, triggerSession {
            deactivate(reason: .trigger)
        }
    }

    override func stop() {
        deactivate(reason: .moduleOff)
    }

    /// Activa la sesión. `minutes == nil` → sin límite de tiempo.
    func activate(minutes: Int?) {
        activate(seconds: minutes.map { TimeInterval($0 * 60) })
    }

    /// Activa la sesión hasta una hora concreta.
    func activate(until date: Date) {
        let seconds = date.timeIntervalSinceNow
        guard seconds > 30 else { return }
        activate(seconds: seconds)
    }

    func activate(seconds: TimeInterval?) {
        deactivate()
        warnedLowBattery = false
        clearEnding()

        // La fianza de sistema va siempre. Antes, con «mantener la pantalla
        // encendida» se pedía **solo** la de pantalla, y eso deja de valer en cuanto
        // la pantalla se apaga: al cerrar la tapa no quedaba nada sujetando al Mac.
        var id: IOPMAssertionID = 0
        let result = IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
                                                 IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                                 "OmniMac: mantener despierto" as CFString,
                                                 &id)
        guard result == kIOReturnSuccess else { return }
        assertionID = id

        // Y encima, si se quiere, la de pantalla.
        applyDisplayAssertion()
        isActive = true

        if let seconds {
            deadline = Date().addingTimeInterval(seconds)
            timer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { [weak self] _ in
                self?.deactivate(reason: .timer)
            }
            requestNotificationsIfNeeded()
        } else {
            deadline = nil
        }

        if closedLidMode { enableClosedLid() }

        // La regla de batería solo corría cuando **cambiaba** el nivel. Si al empezar
        // ya estabas por debajo del umbral, la sesión arrancaba igual y se caía sola
        // más tarde, cuando la batería diera su siguiente salto. Ahora se mira ya.
        checkBattery(battery.state)
    }

    /// Pone o quita la fianza de pantalla según la preferencia actual.
    private func applyDisplayAssertion() {
        if keepDisplayOn, displayAssertionID == 0 {
            var displayID: IOPMAssertionID = 0
            if IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
                                           IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                           "OmniMac: pantalla encendida" as CFString,
                                           &displayID) == kIOReturnSuccess {
                displayAssertionID = displayID
            }
        } else if !keepDisplayOn, displayAssertionID != 0 {
            IOPMAssertionRelease(displayAssertionID)
            displayAssertionID = 0
        }
    }

    func toggle() {
        if isActive { deactivate() } else { activate(minutes: nil) }
    }

    func deactivate(reason: EndReason = .manual) {
        timer?.invalidate()
        timer = nil
        if triggerSession, reason == .manual, isActive {
            // Apagada a mano: no reactivar hasta que la condición cambie.
            let plugged = awakeWhilePluggedIn && battery.state.isPluggedIn
            let external = awakeWithExternalDisplay && NSScreen.screens.count > 1
            if plugged || external { triggerArmed = false }
        }
        triggerSession = false
        let wasActive = isActive
        if isActive {
            IOPMAssertionRelease(assertionID)
            assertionID = 0
            if displayAssertionID != 0 {
                IOPMAssertionRelease(displayAssertionID)
                displayAssertionID = 0
            }
        }
        isActive = false
        deadline = nil
        disableClosedLid()
        if wasActive, reason != .manual {
            // Primero se apunta y luego se notifica: con la tapa cerrada el Mac se
            // duerme en cuanto se suelta la fianza, y la notificación puede quedarse
            // por el camino. Lo guardado sí sobrevive.
            record(KeepAwakeEnding(reason: reason,
                                   batteryLevel: reason == .lowBattery ? battery.state.level : nil,
                                   at: Date()))
            notify(reason)
        }
    }

    // MARK: - Batería y avisos

    private func checkBattery(_ state: BatteryState) {
        guard isActive else { return }
        switch KeepAwakeBatteryRule.decide(level: state.level,
                                           hasBattery: state.hasBattery,
                                           isPluggedIn: state.isPluggedIn,
                                           enabled: stopOnLowBattery,
                                           threshold: lowBatteryThreshold,
                                           alreadyWarned: warnedLowBattery) {
        case .nothing:
            break
        case .warn(let level):
            // Se avisa **antes** del corte, mientras el aviso todavía se puede ver:
            // después puede ser tarde, porque con la tapa cerrada parar la sesión
            // duerme el Mac en el acto.
            warnedLowBattery = true
            warnLowBattery(level: level)
        case .stop:
            deactivate(reason: .lowBattery)
        }
    }

    // MARK: - El último final

    private func record(_ ending: KeepAwakeEnding) {
        lastEnding = ending
        if let data = try? JSONEncoder().encode(ending) {
            UserDefaults.standard.set(data, forKey: KeepAwakeEnding.key)
        }
    }

    /// El usuario ya lo ha leído (o ha empezado otra sesión).
    func clearEnding() {
        guard lastEnding != nil else { return }
        lastEnding = nil
        UserDefaults.standard.removeObject(forKey: KeepAwakeEnding.key)
    }

    private func loadEnding() {
        guard let data = UserDefaults.standard.data(forKey: KeepAwakeEnding.key) else { return }
        lastEnding = try? JSONDecoder().decode(KeepAwakeEnding.self, from: data)
    }

    private func warnLowBattery(level: Int) {
        Toast.show(L("Batería al \(level) %: mantener despierto se parará al \(lowBatteryThreshold) %",
                     "Battery at \(level)%: keep awake will stop at \(lowBatteryThreshold)%"),
                   symbol: "battery.25")
        guard notifyOnEnd, Bundle.main.bundleIdentifier != nil else { return }
        let content = UNMutableNotificationContent()
        content.title = L("Mantener despierto", "Keep awake")
        content.body = L("Batería al \(level) %. La sesión se parará al \(lowBatteryThreshold) %, y si tienes la tapa cerrada el Mac se dormirá. Conecta el cargador para seguir.",
                         "Battery at \(level)%. The session will stop at \(lowBatteryThreshold)%, and if your lid is closed your Mac will go to sleep. Connect the charger to keep going.")
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }

    private func requestNotificationsIfNeeded() {
        guard notifyOnEnd, Bundle.main.bundleIdentifier != nil else { return }
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .notDetermined else { return }
            center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
        }
    }

    private func notify(_ reason: EndReason) {
        guard notifyOnEnd, Bundle.main.bundleIdentifier != nil else { return }
        let content = UNMutableNotificationContent()
        content.title = L("Mantener despierto", "Keep awake")
        switch reason {
        case .timer:
            content.body = L("La sesión ha terminado: tu Mac volverá a dormirse con normalidad.", "The session has ended: your Mac will sleep normally again.")
        case .lowBattery:
            content.body = L("Sesión detenida: batería al \(battery.state.level) %. Si tenías la tapa cerrada, tu Mac se ha dormido. Conecta el cargador para seguir.",
                             "Session stopped: battery at \(battery.state.level)%. If your lid was closed, your Mac has gone to sleep. Connect the charger to continue.")
        case .appQuit, .moduleOff, .trigger:
            // Estos no se notifican: o los ha provocado el propio usuario, o la app
            // se está muriendo y la notificación no llegaría. Quedan apuntados en
            // `lastEnding`, que es lo que sí se lee al volver.
            return
        case .manual:
            return
        }
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    /// Texto tipo "43min" con el tiempo restante, o nil si no hay temporizador.
    var remainingDescription: String? {
        guard isActive, let deadline else { return nil }
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute]
        formatter.unitsStyle = .abbreviated
        return formatter.string(from: max(60, deadline.timeIntervalSinceNow))
    }

    // MARK: - Tapa cerrada

    private func enableClosedLid() {
        closedLidError = nil
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var error: String?
            if LidSleepControl.isAuthorized {
                if !LidSleepControl.set(true) { error = L("No se pudo cambiar el ajuste de energía.", "Couldn't change the power setting.") }
            } else {
                // Primera vez: diálogo de contraseña del sistema (una sola vez).
                error = LidSleepControl.authorizeAndEnable()
            }
            DispatchQueue.main.async {
                guard let self else { return }
                let ok = error == nil
                if ok, !(self.isActive && self.closedLidMode) {
                    // La sesión terminó (o se desmarcó la opción) mientras se autorizaba.
                    LidSleepControl.set(false)
                    return
                }
                self.closedLidActive = ok
                self.closedLidError = error
            }
        }
    }

    /// Síncrono a propósito: también se llama al salir de la app y debe terminar
    /// antes de que el proceso muera. Cuesta unas decenas de milisegundos.
    private func disableClosedLid() {
        guard closedLidActive else { return }
        closedLidActive = false
        if !LidSleepControl.set(false) {
            closedLidError = L("No se pudo restaurar el ajuste de energía. En Terminal: sudo pmset -a disablesleep 0", "Couldn't restore the power setting. In Terminal: sudo pmset -a disablesleep 0")
        }
    }
}

/// Controla el ajuste de energía `disablesleep` (el único que evita el reposo al
/// cerrar la tapa). Requiere administrador. Para pedir la contraseña UNA sola vez,
/// la primera activación instala una regla en `/etc/sudoers.d/omnimac-lid` que
/// permite a este usuario ejecutar sin contraseña exactamente dos comandos:
///
///     /usr/bin/pmset -a disablesleep 1
///     /usr/bin/pmset -a disablesleep 0
///
/// Nada más. Se deshace con `sudo rm /etc/sudoers.d/omnimac-lid`.
enum LidSleepControl {
    static let rulePath = "/etc/sudoers.d/omnimac-lid"

    /// ¿Ya está instalada la regla? `sudo -n` nunca pide contraseña: si no puede, falla.
    static var isAuthorized: Bool {
        run("/usr/bin/sudo", ["-n", "-l", "/usr/bin/pmset", "-a", "disablesleep", "1"]).status == 0
    }

    /// Cambia el ajuste en silencio (solo funciona con la regla instalada).
    @discardableResult
    static func set(_ on: Bool) -> Bool {
        run("/usr/bin/sudo", ["-n", "/usr/bin/pmset", "-a", "disablesleep", on ? "1" : "0"]).status == 0
    }

    /// Primera vez: instala la regla (validada con `visudo`) y activa el ajuste, todo
    /// en una sola orden como root. macOS muestra su propio diálogo de contraseña;
    /// la app nunca la ve. Devuelve un mensaje de error legible, o nil si fue bien.
    static func authorizeAndEnable() -> String? {
        let user = NSUserName()
        guard user.range(of: "^[A-Za-z0-9._-]+$", options: .regularExpression) != nil else {
            return L("El nombre de usuario contiene caracteres no válidos para sudoers.", "The user name contains characters that are not valid for sudoers.")
        }
        let rule = "\(user) ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep 1, /usr/bin/pmset -a disablesleep 0"
        let tmp = rulePath + ".tmp"
        let shell = "umask 077; echo '\(rule)' > \(tmp) && chmod 0440 \(tmp) && chown root:wheel \(tmp)"
            + " && /usr/sbin/visudo -c -f \(tmp) && mv \(tmp) \(rulePath) && /usr/bin/pmset -a disablesleep 1"
        let source = "do shell script \"\(shell)\" with administrator privileges"

        guard let script = NSAppleScript(source: source) else { return L("No se pudo preparar la autorización.", "Couldn't prepare the authorization.") }
        var error: NSDictionary?
        script.executeAndReturnError(&error)
        guard let error else { return nil }
        if (error[NSAppleScript.errorNumber] as? Int) == -128 { return L("Autorización cancelada.", "Authorization cancelled.") }
        return (error[NSAppleScript.errorMessage] as? String) ?? L("No se pudo autorizar.", "Couldn't authorize.")
    }

    private static func run(_ path: String, _ args: [String]) -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do { try process.run() } catch { return (-1, error.localizedDescription) }
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return (process.terminationStatus, String(decoding: data, as: UTF8.self))
    }
}
