import XCTest
@testable import OmniMac

/// El limpiador de enlaces. La mitad de estas pruebas son de lo que **no** debe
/// tocar: romper un enlace es mucho peor que dejar pasar un parámetro de rastreo.
final class URLCleanerTests: XCTestCase {
    func testStripsCampaignParameters() {
        XCTAssertEqual(URLCleaner.clean("https://ejemplo.com/articulo?utm_source=twitter&utm_medium=social"),
                       "https://ejemplo.com/articulo")
    }

    func testKeepsWhatMatters() {
        XCTAssertEqual(URLCleaner.clean("https://ejemplo.com/buscar?q=swift&utm_campaign=x"),
                       "https://ejemplo.com/buscar?q=swift")
    }

    func testSpotifyShareID() {
        XCTAssertEqual(URLCleaner.clean("https://open.spotify.com/track/abc?si=9f2c1d"),
                       "https://open.spotify.com/track/abc")
    }

    /// `t` en YouTube es el segundo por el que empieza el vídeo: quitarlo rompería
    /// justo lo que la persona quería compartir.
    func testYouTubeTimestampSurvives() {
        XCTAssertEqual(URLCleaner.clean("https://youtu.be/dQw4w9WgXcQ?si=abc&t=42"),
                       "https://youtu.be/dQw4w9WgXcQ?t=42")
    }

    /// `si` solo es rastreo en los sitios donde lo sabemos. En otro cualquiera puede
    /// significar lo que sea.
    func testHostSpecificRulesDoNotLeak() {
        XCTAssertNil(URLCleaner.clean("https://otrositio.com/p?si=hola"))
    }

    func testSubdomainsUseTheSameRules() {
        XCTAssertEqual(URLCleaner.clean("https://www.amazon.es/dp/B0123?ref=nav&th=1"),
                       "https://www.amazon.es/dp/B0123")
    }

    func testNilWhenThereIsNothingToClean() {
        XCTAssertNil(URLCleaner.clean("https://ejemplo.com/limpio"))
        XCTAssertNil(URLCleaner.clean("https://ejemplo.com/buscar?q=swift"))
    }

    /// Un párrafo con un enlace dentro se deja en paz: reescribir texto ajeno da
    /// más sustos que alegrías.
    func testOnlyWholeURLs() {
        XCTAssertNil(URLCleaner.clean("mira esto https://ejemplo.com?utm_source=x qué bueno"))
    }

    func testIgnoresNonWebSchemes() {
        XCTAssertNil(URLCleaner.clean("mailto:hola@ejemplo.com?utm_source=x"))
        XCTAssertNil(URLCleaner.clean("no soy una url"))
    }

    func testRemovesTheQuestionMarkWhenNothingIsLeft() {
        XCTAssertEqual(URLCleaner.clean("https://ejemplo.com/a?fbclid=123"), "https://ejemplo.com/a")
    }
}

/// El instalador de .dmg. Todo lo probable de él es «cuándo NO tocar nada».
final class DiskImageRulesTests: XCTestCase {
    func testOnlyFinishedDiskImages() {
        XCTAssertTrue(DiskImageRules.isCandidate("Ice.dmg"))
        XCTAssertFalse(DiskImageRules.isCandidate("Ice.dmg.download"))  // Safari, a medias
        XCTAssertFalse(DiskImageRules.isCandidate("Ice.crdownload"))    // Chrome, a medias
        XCTAssertFalse(DiskImageRules.isCandidate(".oculto.dmg"))
        XCTAssertFalse(DiskImageRules.isCandidate("foto.png"))
    }

    func testInstallsOnlyWhenThereIsExactlyOneApp() {
        XCTAssertEqual(DiskImageRules.appToInstall(in: ["Ice.app", "Applications"]), "Ice.app")
        // Dos apps: no hay forma de acertar sin preguntar.
        XCTAssertNil(DiskImageRules.appToInstall(in: ["Uno.app", "Dos.app"]))
        XCTAssertNil(DiskImageRules.appToInstall(in: ["Léeme.txt"]))
    }

    /// Un `.pkg` dentro significa instalador de verdad, con sus pasos y sus
    /// permisos: eso no se automatiza.
    func testGivesUpWhenThereIsAnInstaller() {
        XCTAssertNil(DiskImageRules.appToInstall(in: ["Cosa.app", "Instalar.pkg"]))
    }

    func testFallsBackToTheUserFolderWhenApplicationsIsReadOnly() {
        XCTAssertEqual(DiskImageRules.destination(canWriteToApplications: true, home: "/Users/x"), "/Applications")
        XCTAssertEqual(DiskImageRules.destination(canWriteToApplications: false, home: "/Users/x"), "/Users/x/Applications")
    }
}
