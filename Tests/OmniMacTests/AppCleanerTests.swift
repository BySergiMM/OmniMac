import XCTest
@testable import OmniMac

/// Las reglas que deciden qué se manda a la papelera. Son las pruebas más
/// importantes del proyecto: un falso positivo aquí le borra a alguien datos de
/// otra app.
final class LeftoverMatcherTests: XCTestCase {

    private func belongs(_ file: String, allowNameMatch: Bool = false) -> Bool {
        LeftoverMatcher.belongs(fileName: file,
                                bundleID: "com.spotify.client",
                                appName: "Spotify",
                                allowNameMatch: allowNameMatch)
    }

    func testExactBundleIdentifier() {
        XCTAssertTrue(belongs("com.spotify.client"))
    }

    func testPreferencesAndStateFilesLoseTheirExtension() {
        XCTAssertTrue(belongs("com.spotify.client.plist"))
        XCTAssertTrue(belongs("com.spotify.client.savedState"))
        XCTAssertTrue(belongs("com.spotify.client.binarycookies"))
    }

    func testHelpersAndSubBundles() {
        XCTAssertTrue(belongs("com.spotify.client.helper"))
        XCTAssertTrue(belongs("com.spotify.client-updater"))
        XCTAssertTrue(belongs("com.spotify.client_agent"))
    }

    func testGroupContainers() {
        XCTAssertTrue(belongs("ABCDE12345.com.spotify.client"), "prefijo de equipo")
        XCTAssertTrue(belongs("group.com.spotify.client"))
    }

    func testNameMatchOnlyWhereItIsAllowed() {
        XCTAssertTrue(belongs("Spotify", allowNameMatch: true))
        XCTAssertTrue(belongs("spotify", allowNameMatch: true), "sin distinguir mayúsculas")
        XCTAssertFalse(belongs("Spotify"), "en Preferencias o Contenedores no vale por nombre")
    }

    // MARK: - Lo que NUNCA debe coincidir

    func testAnotherAppWithASimilarIdentifier() {
        XCTAssertFalse(belongs("com.spotifyfake.client"))
        XCTAssertFalse(belongs("com.spotify.clientele"))
        XCTAssertFalse(belongs("com.spotify.client2"))
    }

    func testUnrelatedApps() {
        XCTAssertFalse(belongs("com.google.Chrome"))
        XCTAssertFalse(belongs("com.apple.Safari.plist"))
    }

    func testAPrefixThatIsNotATeamIdentifier() {
        // Un identificador de equipo son 10 caracteres alfanuméricos; cualquier otra
        // cosa delante es otra app, no un contenedor de grupo nuestro.
        XCTAssertFalse(belongs("com.otra.empresa.com.spotify.client"))
    }

    func testAppleIsUntouchable() {
        XCTAssertTrue(LeftoverMatcher.isProtected(bundleID: "com.apple.Safari"))
        XCTAssertTrue(LeftoverMatcher.isProtected(bundleID: "COM.APPLE.Finder"))
        XCTAssertTrue(LeftoverMatcher.isProtected(bundleID: ""))
        XCTAssertFalse(LeftoverMatcher.isProtected(bundleID: "com.spotify.client"))
        XCTAssertFalse(LeftoverMatcher.belongs(fileName: "com.apple.Safari.plist",
                                               bundleID: "com.apple.Safari",
                                               appName: "Safari",
                                               allowNameMatch: true))
    }

    func testEmptyAppNameNeverMatchesEverything() {
        XCTAssertFalse(LeftoverMatcher.belongs(fileName: "",
                                               bundleID: "com.spotify.client",
                                               appName: "",
                                               allowNameMatch: true))
    }

    // MARK: - Sitios donde se busca

    func testSystemPlacesAreMarkedAsNeedingAdmin() {
        let system = LeftoverPlace.all.filter { !$0.inHome }
        XCTAssertFalse(system.isEmpty)
        for place in system {
            XCTAssertTrue(place.url.path.hasPrefix("/Library/"), "fuera de /Library no se busca: \(place.url.path)")
        }
    }

    func testHomePlacesStayInsideTheUserFolder() {
        for place in LeftoverPlace.all where place.inHome {
            XCTAssertTrue(place.url.path.hasPrefix(NSHomeDirectory() + "/Library/"),
                          "solo se mira dentro de la biblioteca del usuario: \(place.url.path)")
        }
    }
}

/// Las apps que guardan sus datos en una carpeta con el nombre del fabricante.
final class VendorFolderTests: XCTestCase {

    func testVendorComesFromTheBundleIdentifier() {
        XCTAssertEqual(LeftoverMatcher.vendor(bundleID: "com.google.Chrome"), "google")
        XCTAssertEqual(LeftoverMatcher.vendor(bundleID: "com.microsoft.VSCode"), "microsoft")
    }

    func testNoVendorWhenItWouldBeMeaningless() {
        XCTAssertNil(LeftoverMatcher.vendor(bundleID: "com.apple.Safari"), "Apple nunca")
        XCTAssertNil(LeftoverMatcher.vendor(bundleID: "Spotify"), "sin puntos no hay fabricante")
        XCTAssertNil(LeftoverMatcher.vendor(bundleID: "com.io.thing"), "«io» es genérico")
        XCTAssertNil(LeftoverMatcher.vendor(bundleID: "a.b.c"), "demasiado corto")
    }

    func testOnlyTheAppFolderInsideTheVendorFolder() {
        // ~/Library/Application Support/Google/Chrome  → sí
        XCTAssertTrue(LeftoverMatcher.belongsInsideVendorFolder(fileName: "Chrome",
                                                                bundleID: "com.google.Chrome",
                                                                appName: "Chrome"))
        XCTAssertTrue(LeftoverMatcher.belongsInsideVendorFolder(fileName: "com.google.Chrome",
                                                                bundleID: "com.google.Chrome",
                                                                appName: "Chrome"))
    }

    func testOtherAppsFromTheSameVendorAreLeftAlone() {
        // Lo importante: desinstalar Chrome no puede llevarse Google Drive ni
        // Chrome Canary, que viven en la misma carpeta «Google».
        for other in ["Drive", "GoogleUpdater", "Chrome Canary", "ChromeBeta"] {
            XCTAssertFalse(LeftoverMatcher.belongsInsideVendorFolder(fileName: other,
                                                                     bundleID: "com.google.Chrome",
                                                                     appName: "Chrome"),
                           "\(other) no es de Chrome")
        }
    }
}

/// Restos de apps que ya no están instaladas.
final class OrphanRulesTests: XCTestCase {

    func testRecognisesABundleIdentifier() {
        XCTAssertEqual(OrphanRules.bundleID(from: "com.spotify.client"), "com.spotify.client")
        XCTAssertEqual(OrphanRules.bundleID(from: "com.spotify.client.plist"), "com.spotify.client")
        XCTAssertEqual(OrphanRules.bundleID(from: "com.spotify.client.savedState"), "com.spotify.client")
    }

    func testStripsTheTeamOrGroupPrefix() {
        XCTAssertEqual(OrphanRules.bundleID(from: "ABCDE12345.com.spotify.client"), "com.spotify.client")
        XCTAssertEqual(OrphanRules.bundleID(from: "group.com.spotify.client"), "com.spotify.client")
        // Capas encadenadas: identificador de equipo + «groups.». Si queda una capa,
        // «com.apple» no se reconoce y Podcasts sale como resto de una app borrada.
        XCTAssertEqual(OrphanRules.bundleID(from: "243LU875E5.groups.com.apple.podcasts"), nil)
        XCTAssertEqual(OrphanRules.bundleID(from: "groups.com.spotify.client"), "com.spotify.client")
        XCTAssertEqual(OrphanRules.bundleID(from: "systemgroup.com.spotify.client"), "com.spotify.client")
    }

    func testOrdinaryFolderNamesAreNotIdentifiers() {
        // Lo importante: una carpeta con nombre normal puede ser de cualquiera, así
        // que no se toca.
        for name in ["Google", "Adobe", "Datos de usuario", "com.dos", "Mi carpeta.txt"] {
            XCTAssertNil(OrphanRules.bundleID(from: name), "\(name) no es un identificador")
        }
    }

    func testAppleIsNeverAnOrphan() {
        XCTAssertNil(OrphanRules.bundleID(from: "com.apple.Safari"))
        XCTAssertNil(OrphanRules.bundleID(from: "com.apple.dt.Xcode.plist"))
    }

    func testReadableName() {
        // El último trozo es el nombre de la app, salvo que no diga nada.
        XCTAssertEqual(OrphanRules.displayName(for: "com.google.Chrome"), "Chrome")
        XCTAssertEqual(OrphanRules.displayName(for: "org.p0deje.Maccy"), "Maccy")
        XCTAssertEqual(OrphanRules.displayName(for: "com.if.Amphetamine"), "Amphetamine")
        XCTAssertEqual(OrphanRules.displayName(for: "com.spotify.client"), "Spotify")
        XCTAssertEqual(OrphanRules.displayName(for: "com.vercel.cli"), "Vercel")
    }

    /// Apple no siempre se llama «com.apple».
    func testAppleWithoutSayingSo() {
        XCTAssertTrue(OrphanRules.isSystem("is.workflow.my.app"))
        XCTAssertTrue(OrphanRules.isSystem("tvappservices.container"))
        XCTAssertTrue(OrphanRules.isSystem("com.apple.finder"))
        XCTAssertFalse(OrphanRules.isSystem("com.appleseed.app"))   // no confundir el prefijo
        XCTAssertFalse(OrphanRules.isSystem("org.p0deje.Maccy"))
    }

    func testSharedComponentsAreNotUninstalledApps() {
        XCTAssertTrue(OrphanRules.isSharedComponent("org.sparkle-project.Sparkle"))
        XCTAssertTrue(OrphanRules.isSharedComponent("com.plausiblelabs.crashreporter.data"))
        XCTAssertFalse(OrphanRules.isSharedComponent("com.operasoftware.Opera"))
    }

    func testVendor() {
        XCTAssertEqual(OrphanRules.vendor(of: "net.whatsapp.family"), "net.whatsapp")
        XCTAssertEqual(OrphanRules.vendor(of: "com.Spotify.Client"), "com.spotify")   // sin distinguir mayúsculas
        XCTAssertNil(OrphanRules.vendor(of: "suelto"))
    }
}

/// Lo que macOS no deja tocar, y cómo se cuenta.
///
/// Sergi intentó quitar el resto de Maccy y no pasó nada. La causa: los contenedores
/// los gestiona `containermanagerd` y ni el dueño puede moverlos —falla con
/// `NSCocoaErrorDomain 513` y un `OSStatus -5000` por debajo—. Y de paso salió otro
/// fallo: se contaba el tamaño como liberado aunque la operación hubiera fallado.
final class TrashOutcomeTests: XCTestCase {
    private func denied() -> NSError {
        NSError(domain: NSCocoaErrorDomain, code: NSFileWriteNoPermissionError)
    }

    func testContainersAreSystemProtected() {
        let container = URL(fileURLWithPath: "/Users/x/Library/Containers/org.p0deje.Maccy")
        XCTAssertTrue(AppCleaner.isSystemProtected(container, error: denied()))
        let group = URL(fileURLWithPath: "/Users/x/Library/Group Containers/group.com.x")
        XCTAssertTrue(AppCleaner.isSystemProtected(group, error: denied()))
    }

    /// Fuera de los contenedores, «sin permiso» sí se arregla con la contraseña de
    /// administrador: no hay que decirle a nadie que vaya al Finder.
    func testOtherPlacesAreJustPermissions() {
        let preference = URL(fileURLWithPath: "/Users/x/Library/Preferences/org.p0deje.Maccy.plist")
        XCTAssertFalse(AppCleaner.isSystemProtected(preference, error: denied()))
        let system = URL(fileURLWithPath: "/Library/Application Support/Algo")
        XCTAssertFalse(AppCleaner.isSystemProtected(system, error: denied()))
    }

    /// Un error que no sea de permisos no convierte un contenedor en «protegido».
    func testOnlyPermissionErrorsCount() {
        let container = URL(fileURLWithPath: "/Users/x/Library/Containers/algo")
        let missing = NSError(domain: NSCocoaErrorDomain, code: NSFileNoSuchFileError)
        XCTAssertFalse(AppCleaner.isSystemProtected(container, error: missing))
    }

    func testSummaryTellsTheThreeCasesApart() {
        var outcome = AppCleaner.TrashOutcome(freed: 1_048_576)
        XCTAssertTrue(AppCleaner.summary(outcome).contains("1"))
        XCTAssertTrue(outcome.allGood)

        outcome.protected = [URL(fileURLWithPath: "/a")]
        XCTAssertFalse(outcome.allGood)
        XCTAssertTrue(AppCleaner.summary(outcome).lowercased().contains("finder"))

        outcome.failed = [URL(fileURLWithPath: "/b")]
        let text = AppCleaner.summary(outcome).lowercased()
        XCTAssertTrue(text.contains("finder"))
        XCTAssertTrue(text.contains("administrador") || text.contains("administrator"))
    }

    /// Nada movido, nada liberado: el contador no puede mentir.
    func testNothingMovedFreesNothing() {
        let outcome = AppCleaner.trash([(url: URL(fileURLWithPath: "/no/existe/de/verdad"), size: 999_999)])
        XCTAssertEqual(outcome.freed, 0)
        XCTAssertEqual(outcome.failed.count, 1)
    }
}
