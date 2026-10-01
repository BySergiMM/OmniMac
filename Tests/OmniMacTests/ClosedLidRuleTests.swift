import XCTest
@testable import OmniMac

/// El modo «tapa cerrada»: la regla de administrador, el aviso previo y cuándo se
/// puede encender y usar. Nada de esto toca el sistema: son decisiones y textos.
final class ClosedLidRuleTests: XCTestCase {

    // MARK: - La regla

    func testTheRuleAllowsExactlyTwoPmsetCommands() {
        XCTAssertEqual(ClosedLidRule.allowedCommands, [
            "/usr/bin/pmset -a disablesleep 1",
            "/usr/bin/pmset -a disablesleep 0",
        ])
    }

    func testTheSudoersLineGrantsOnlyThoseCommandsToThatUser() {
        let line = ClosedLidRule.sudoersLine(for: "sergi")
        XCTAssertEqual(line, "sergi ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep 1, /usr/bin/pmset -a disablesleep 0")
        // Ni a todo el grupo admin ni a cualquier destino: era el plan B del instalador antiguo.
        XCTAssertFalse(line.contains("%admin"))
        XCTAssertFalse(line.contains("ALL=(ALL)"))
        XCTAssertFalse(line.contains("\n"))
    }

    func testUserNamesThatCannotSmuggleAnythingIntoSudoers() {
        for name in ["sergi", "maria.lopez", "a_b-c", "User1"] {
            XCTAssertTrue(ClosedLidRule.isValidUserName(name), name)
        }
        let hostile = [
            "", " ", "a b", "sergi ", "%admin", "a/b", "a'b", "a;b", "$(id)", "a\"b", "a\\b", "é",
            // Un salto de línea final abriría una línea nueva en el archivo de sudoers.
            "sergi\n",
            "sergi\nroot ALL=(ALL) NOPASSWD: ALL",
        ]
        for name in hostile {
            XCTAssertFalse(ClosedLidRule.isValidUserName(name), name)
        }
    }

    func testTheInstallScriptValidatesBeforeItInstalls() {
        let tmp = ClosedLidRule.temporaryPath
        let script = ClosedLidRule.installScript(user: "sergi")
        XCTAssertTrue(script.contains("echo '\(ClosedLidRule.sudoersLine(for: "sergi"))' > \(tmp)"), script)
        // La validación y el cambio de sitio van encadenados con «&&»: si `visudo`
        // rechaza el archivo, no se instala nada.
        XCTAssertTrue(script.contains("/usr/sbin/visudo -c -f \(tmp) && mv \(tmp) \(ClosedLidRule.path)"), script)
    }

    func testTheInstallScriptWritesWithStrictPermissions() {
        let tmp = ClosedLidRule.temporaryPath
        let script = ClosedLidRule.installScript(user: "sergi")
        XCTAssertTrue(script.hasPrefix("umask 077;"), script)
        XCTAssertTrue(script.contains("chmod 0440 \(tmp)"), script)
        XCTAssertTrue(script.contains("chown root:wheel \(tmp)"), script)
    }

    func testTheInstallScriptEndsByTurningTheSettingOn() {
        XCTAssertTrue(ClosedLidRule.installScript(user: "sergi").hasSuffix("&& /usr/bin/pmset -a disablesleep 1"))
    }

    func testTheInstallScriptFitsInsideAnAppleScriptString() {
        // Va dentro de `do shell script "…"`: una comilla doble o una barra invertida
        // habría que escaparlas, y un fallo ahí rompería la orden con la contraseña ya pedida.
        let script = ClosedLidRule.installScript(user: "sergi")
        XCTAssertFalse(script.contains("\""), script)
        XCTAssertFalse(script.contains("\\"), script)
    }

    func testOnlyTheTemporaryFileHasADotInItsName() {
        // sudo ignora los archivos de `sudoers.d` con punto en el nombre: el temporal lo
        // lleva para no valer hasta que se valida, y la regla definitiva no puede llevarlo.
        XCTAssertTrue(URL(fileURLWithPath: ClosedLidRule.temporaryPath).lastPathComponent.contains("."))
        XCTAssertFalse(URL(fileURLWithPath: ClosedLidRule.path).lastPathComponent.contains("."))
    }

    // MARK: - Apagado de fábrica

    /// Un `UserDefaults` propio de cada prueba: nunca toca las preferencias de la app.
    private func freshDefaults() throws -> UserDefaults {
        let suite = "omnimac-closedlid-tests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        return defaults
    }

    func testItIsOffWhenNothingHasBeenStored() throws {
        let defaults = try freshDefaults()
        XCTAssertFalse(ClosedLidRule.isOn(in: defaults))
    }

    func testOnlyOnWithTheNoticeAccepted() throws {
        let defaults = try freshDefaults()
        defaults.set(true, forKey: ClosedLidRule.modeKey)
        // Las versiones anteriores lo dejaban encendido de fábrica, sin aviso: ese
        // «encendido» guardado no vale como permiso.
        XCTAssertFalse(ClosedLidRule.isOn(in: defaults))
        defaults.set(true, forKey: ClosedLidRule.consentKey)
        XCTAssertTrue(ClosedLidRule.isOn(in: defaults))
    }

    func testTheNoticeAcceptedAloneDoesNotTurnItOn() throws {
        let defaults = try freshDefaults()
        defaults.set(true, forKey: ClosedLidRule.consentKey)
        XCTAssertFalse(ClosedLidRule.isOn(in: defaults))
    }

    func testTheStoredKeysAreTheOnesTheAppAlreadyUsed() {
        // Cambiar el nombre de la clave devolvería a cada usuario al valor de fábrica.
        XCTAssertEqual(ClosedLidRule.modeKey, "keepawake.closedLid")
        XCTAssertEqual(ClosedLidRule.consentKey, "keepawake.closedLidConsent")
    }

    // MARK: - Decisiones

    func testTurningItOffNeverAsks() {
        XCTAssertEqual(ClosedLidRule.switchAction(turningOn: false, consented: false), .turnOff)
        XCTAssertEqual(ClosedLidRule.switchAction(turningOn: false, consented: true), .turnOff)
    }

    func testTurningItOnAsksUntilTheNoticeIsAccepted() {
        XCTAssertEqual(ClosedLidRule.switchAction(turningOn: true, consented: false), .askFirst)
        XCTAssertEqual(ClosedLidRule.switchAction(turningOn: true, consented: true), .turnOn)
    }

    func testNothingPrivilegedWithoutConsent() {
        // Ni se usa la regla que ya hubiera ni se instala una nueva.
        XCTAssertEqual(ClosedLidRule.activation(ruleInstalled: false, consented: false), .refuse)
        XCTAssertEqual(ClosedLidRule.activation(ruleInstalled: true, consented: false), .refuse)
    }

    func testWithConsentTheRuleIsUsedIfItIsThereAndInstalledIfNot() {
        XCTAssertEqual(ClosedLidRule.activation(ruleInstalled: true, consented: true), .useInstalledRule)
        XCTAssertEqual(ClosedLidRule.activation(ruleInstalled: false, consented: true), .installRuleWithAdminPrompt)
    }

    // MARK: - Los textos

    func testTheNoticeSaysExactlyWhatTheRuleAllows() {
        for spanish in [true, false] {
            let text = ClosedLidRule.consentMessage(user: "sergi", spanish: spanish)
            XCTAssertTrue(text.contains(ClosedLidRule.path), text)
            XCTAssertTrue(text.contains("sergi"), text)
            for command in ClosedLidRule.allowedCommands {
                XCTAssertTrue(text.contains(command), "\(command) falta en: \(text)")
            }
            // Y ninguna orden más: el aviso no nombra nada que la regla no permita.
            let commandsNamed = text.components(separatedBy: "/usr/").count - 1
            XCTAssertEqual(commandsNamed, ClosedLidRule.allowedCommands.count, text)
        }
    }

    func testTheNoticeAdmitsWhatTheRuleCostsAndHowToRemoveIt() {
        let es = ClosedLidRule.consentMessage(user: "sergi", spanish: true)
        let en = ClosedLidRule.consentMessage(user: "sergi", spanish: false)
        XCTAssertTrue(es.contains("cualquier programa que se ejecute con tu usuario"), es)
        XCTAssertTrue(en.contains("any program running as your user"), en)
        XCTAssertTrue(es.contains("sudo rm \(ClosedLidRule.path)"), es)
        XCTAssertTrue(en.contains("sudo rm \(ClosedLidRule.path)"), en)
        // Y que cancelar es gratis.
        XCTAssertTrue(es.contains("no se instala nada"), es)
        XCTAssertTrue(en.contains("nothing is installed"), en)
    }

    func testEachLanguageStaysInItsOwn() {
        let es = ClosedLidRule.consentMessage(user: "sergi", spanish: true)
        let en = ClosedLidRule.consentMessage(user: "sergi", spanish: false)
        XCTAssertTrue(es.contains("contraseña"))
        XCTAssertFalse(es.contains("password"))
        XCTAssertTrue(en.contains("password"))
        XCTAssertFalse(en.contains("contraseña"))
        XCTAssertNotEqual(ClosedLidRule.consentTitle(spanish: true), ClosedLidRule.consentTitle(spanish: false))
        XCTAssertNotEqual(ClosedLidRule.settingsFooter(spanish: true), ClosedLidRule.settingsFooter(spanish: false))
    }

    func testTheSettingsFooterNamesTheSameRule() {
        for spanish in [true, false] {
            let footer = ClosedLidRule.settingsFooter(spanish: spanish)
            XCTAssertTrue(footer.contains(ClosedLidRule.path), footer)
            XCTAssertTrue(footer.contains("sudo rm \(ClosedLidRule.path)"), footer)
            for command in ClosedLidRule.allowedCommands {
                XCTAssertTrue(footer.contains(command), "\(command) falta en: \(footer)")
            }
            // El pie antiguo decía que la regla solo permitía a OmniMac cambiar el ajuste, y
            // no es cierto: la regla es de tu usuario, no de la app.
            XCTAssertFalse(footer.contains("OmniMac change"), footer)
            XCTAssertFalse(footer.contains("solo permite a OmniMac"), footer)
        }
    }
}
