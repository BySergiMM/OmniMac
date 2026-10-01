import Foundation

/// La regla de administrador que necesita el modo «tapa cerrada», los avisos con los
/// que se explica y las decisiones de cuándo se puede encender y usar.
///
/// Está aparte de `KeepAwakeFeature` para poder probarla sin tocar el sistema, y
/// porque aquí hay una sola fuente de verdad: de `allowedCommands` salen a la vez la
/// línea que se instala en sudoers y todos los textos que se le enseñan al usuario
/// (el aviso previo y el pie de Ajustes), así que lo que se explica no puede
/// distinguirse de lo que se instala.
///
/// Los textos reciben el idioma por parámetro (en la app, `Localization.isSpanish`,
/// que es lo que usa `L`) para poder probar los dos sin depender del Mac donde corra
/// la prueba. Es el mismo patrón que `UpdateCheckText`.
enum ClosedLidRule {
    static let path = "/etc/sudoers.d/omnimac-lid"

    /// Lo único que la regla deja ejecutar sin contraseña. sudoers compara estas
    /// órdenes con sus argumentos exactos: no vale ninguna otra variante de `pmset`.
    static let allowedCommands = [
        "/usr/bin/pmset -a disablesleep 1",
        "/usr/bin/pmset -a disablesleep 0",
    ]

    // MARK: - La regla

    private static let userNameCharacters: Set<Character> =
        Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-")

    /// El nombre va dentro de una línea de sudoers y de una orden de shell: solo se
    /// acepta lo que no puede colar nada más. Se mira carácter a carácter, y no con una
    /// expresión regular, para no depender de cómo trate el motor un salto de línea
    /// final: abriría una línea nueva en el archivo de sudoers.
    static func isValidUserName(_ name: String) -> Bool {
        !name.isEmpty && name.allSatisfy { userNameCharacters.contains($0) }
    }

    /// La línea de sudoers: «usuario ALL=(root) NOPASSWD: orden, orden».
    static func sudoersLine(for user: String) -> String {
        "\(user) ALL=(root) NOPASSWD: " + allowedCommands.joined(separator: ", ")
    }

    /// El archivo temporal lleva un punto a propósito: sudo ignora los archivos de
    /// `sudoers.d` con punto en el nombre, así que la regla no vale hasta que se
    /// valida y se renombra.
    static var temporaryPath: String { path + ".tmp" }

    /// La orden que se ejecuta como administrador: escribe la regla con permisos
    /// estrictos, la valida con `visudo`, la coloca y activa el ajuste.
    ///
    /// No contiene comillas dobles ni barras invertidas: va dentro de una cadena de
    /// AppleScript (`do shell script "…"`) y cualquiera de las dos habría que escaparla.
    static func installScript(user: String) -> String {
        let tmp = temporaryPath
        return "umask 077; echo '\(sudoersLine(for: user))' > \(tmp) && chmod 0440 \(tmp) && chown root:wheel \(tmp)"
            + " && /usr/sbin/visudo -c -f \(tmp) && mv \(tmp) \(path) && /usr/bin/pmset -a disablesleep 1"
    }

    // MARK: - Preferencias

    static let modeKey = "keepawake.closedLid"
    static let consentKey = "keepawake.closedLidConsent"

    /// ¿Arranca encendido el modo? Solo si estaba encendido **y** el usuario aceptó el
    /// aviso. Sin nada guardado, no: viene apagado.
    ///
    /// Un «encendido» guardado sin permiso es de las versiones en las que el modo
    /// nacía encendido, antes de que existiera el aviso. Se ignora: el usuario lo
    /// vuelve a encender y pasa por el aviso.
    static func startsOn(stored: Bool, consented: Bool) -> Bool {
        stored && consented
    }

    static func isOn(in defaults: UserDefaults) -> Bool {
        startsOn(stored: defaults.bool(forKey: modeKey), consented: defaults.bool(forKey: consentKey))
    }

    // MARK: - Decisiones

    /// Qué hace el interruptor de Ajustes al pulsarlo.
    enum SwitchAction: Equatable {
        /// Apagar es siempre inmediato.
        case turnOff
        /// Encender, cuando el usuario ya aceptó el aviso en otra ocasión.
        case turnOn
        /// Encender por primera vez: antes, el aviso. Si dice que no, sigue apagado.
        case askFirst
    }

    static func switchAction(turningOn: Bool, consented: Bool) -> SwitchAction {
        guard turningOn else { return .turnOff }
        return consented ? .turnOn : .askFirst
    }

    /// Qué hay que hacer al empezar una sesión con el modo encendido.
    enum Activation: Equatable {
        /// La regla ya está: se usa, sin tocar nada del sistema.
        case useInstalledRule
        /// Falta la regla: se instala con el diálogo de contraseña de macOS.
        case installRuleWithAdminPrompt
        /// El usuario no ha dicho que sí: no se usa ni se instala nada.
        case refuse
    }

    /// Sin permiso no se hace nada de administrador, esté o no la regla. Es la red de
    /// seguridad detrás del interruptor: `startsOn` y `switchAction` ya impiden llegar
    /// aquí con el modo encendido y sin permiso.
    static func activation(ruleInstalled: Bool, consented: Bool) -> Activation {
        guard consented else { return .refuse }
        return ruleInstalled ? .useInstalledRule : .installRuleWithAdminPrompt
    }

    // MARK: - Los textos

    private static var commandList: String {
        allowedCommands.map { "    \($0)" }.joined(separator: "\n")
    }

    static func consentTitle(spanish: Bool) -> String {
        spanish ? "¿Activar el modo tapa cerrada?" : "Turn on closed-lid mode?"
    }

    /// El aviso previo. Es verdad esté o no ya instalada la regla: no promete una
    /// contraseña que, si la regla existe, no se va a pedir.
    static func consentMessage(user: String, spanish: Bool) -> String {
        if spanish {
            return """
            Para que el Mac no se duerma al cerrar la tapa, OmniMac tiene que cambiar el ajuste de energía «disablesleep», y macOS solo deja hacerlo a un administrador.

            Para no pedirte la contraseña cada vez, OmniMac usa una regla de administrador: el archivo \(path). Si todavía no existe, macOS te pedirá tu contraseña una sola vez, la primera vez que uses el modo, y se creará. La regla permite a tu usuario («\(user)») ejecutar como administrador, sin contraseña, exactamente estas dos órdenes y ninguna más:

            \(commandList)

            Mientras la regla exista, cualquier programa que se ejecute con tu usuario puede cambiar ese ajuste sin pedirte la contraseña. Si cancelas, no se instala nada y el modo sigue apagado. Para quitar la regla más adelante: sudo rm \(path)
            """
        }
        return """
        For your Mac to stay awake when you close the lid, OmniMac has to change the “disablesleep” power setting, and macOS only lets an administrator do that.

        So it doesn’t have to ask for your password every time, OmniMac uses an administrator rule: the file \(path). If it doesn’t exist yet, macOS will ask for your password once, the first time you use the mode, and it will be created. The rule lets your user (“\(user)”) run exactly these two commands as an administrator, without a password, and nothing else:

        \(commandList)

        While the rule exists, any program running as your user can change that setting without asking for your password. If you cancel, nothing is installed and the mode stays off. To remove the rule later: sudo rm \(path)
        """
    }

    /// El pie de la sección en Ajustes: lo mismo que el aviso, en pocas palabras.
    static func settingsFooter(spanish: Bool) -> String {
        let commands = allowedCommands.joined(separator: spanish ? " y " : " and ")
        if spanish {
            return "El modo tapa cerrada usa una regla de administrador (\(path)) que permite a tu usuario, sin contraseña, solo estas órdenes: \(commands). Para quitarla: sudo rm \(path)"
        }
        return "Closed-lid mode uses an administrator rule (\(path)) that lets your user run, without a password, only these commands: \(commands). To remove it: sudo rm \(path)"
    }
}
