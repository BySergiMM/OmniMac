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
