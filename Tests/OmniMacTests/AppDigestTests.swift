import XCTest
@testable import OmniMac

/// La huella que ata lo que se revisó con lo que se instala. Usa carpetas de verdad: lo que se
/// comprueba es qué cuenta (y qué no) al calcularla.
final class AppDigestTests: XCTestCase {

    private let files = FileManager.default
    private var root: URL!

    override func setUpWithError() throws {
        let folder = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "omnimac-digest-\(UUID().uuidString)")
        try files.createDirectory(at: folder, withIntermediateDirectories: true)
        root = folder
        addTeardownBlock { try? FileManager.default.removeItem(at: folder) }
    }

    // MARK: - Ayudas

    private func write(_ text: String, to url: URL, executable: Bool = false) throws {
        try files.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
        try files.setAttributes([.posixPermissions: executable ? 0o755 : 0o644], ofItemAtPath: url.path)
    }

    /// Una app de mentira con lo que suele tener una de verdad: ejecutable, recursos y un
    /// framework con su enlace «Current».
    @discardableResult
    private func makeApp(_ name: String = "Foo.app") throws -> URL {
        let app = root.appending(path: name)
        try write("plist", to: app.appending(path: "Contents/Info.plist"))
        try write("binario", to: app.appending(path: "Contents/MacOS/Foo"), executable: true)
        try write("recurso", to: app.appending(path: "Contents/Resources/a.txt"))
        try write("lib", to: app.appending(path: "Contents/Frameworks/Lib.framework/Versions/A/Lib"), executable: true)
        try files.createSymbolicLink(
            at: app.appending(path: "Contents/Frameworks/Lib.framework/Versions/Current"),
            withDestinationURL: URL(fileURLWithPath: "A"))
        return app
    }

    private func digest(_ app: URL) throws -> String {
        try XCTUnwrap(AppDigest.of(app))
    }

    // MARK: - Lo que no cambia

    func testItIsAHexSha256() throws {
        let value = try digest(makeApp())
        XCTAssertEqual(value.count, 64)
        XCTAssertNotNil(value.range(of: "^[0-9a-f]{64}$", options: .regularExpression))
    }

    func testTheSameContentGivesTheSameDigest() throws {
        let one = try makeApp("Uno.app")
        let two = try makeApp("Dos.app")
        XCTAssertEqual(try digest(one), try digest(two))
        XCTAssertEqual(try digest(one), try digest(one))
    }

    func testACopyHasTheSameDigest() throws {
        // Es lo que hace la instalación: se calcula en el disco y otra vez en la copia, y
        // tienen que coincidir. Si `copyItem` cambiara algo de lo que se cuenta, toda
        // instalación legítima se rechazaría.
        let app = try makeApp()
        let copy = root.appending(path: "Copia/Foo.app")
        try files.createDirectory(at: copy.deletingLastPathComponent(), withIntermediateDirectories: true)
        try files.copyItem(at: app, to: copy)
        XCTAssertEqual(try digest(copy), try digest(app))
    }

    func testTheOrderFilesWereCreatedInDoesNotMatter() throws {
        let one = root.appending(path: "Uno.app")
        let two = root.appending(path: "Dos.app")
        for name in ["a", "b", "c"] { try write(name, to: one.appending(path: name)) }
        for name in ["c", "a", "b"] { try write(name, to: two.appending(path: name)) }
        XCTAssertEqual(try digest(one), try digest(two))
    }

    func testTheSameNameInDifferentUnicodeFormsIsTheSameFile() throws {
        // Un disco HFS+ guarda los nombres descompuestos y uno APFS conserva los que le dan.
        let composed = root.appending(path: "Uno.app")
        let decomposed = root.appending(path: "Dos.app")
        try write("x", to: composed.appending(path: "caf\u{e9}.txt"))
        try write("x", to: decomposed.appending(path: "cafe\u{301}.txt"))
        XCTAssertEqual(try digest(composed), try digest(decomposed))
    }

    func testAFolderWithoutFilesHasADigest() throws {
        let empty = root.appending(path: "Vacia.app")
        try files.createDirectory(at: empty, withIntermediateDirectories: true)
        XCTAssertNotNil(AppDigest.of(empty))
    }

    func testALinkIsNotFollowed() throws {
        // Lo de fuera del paquete no es del paquete: si el enlace se siguiera, un cambio en
        // otra parte cambiaría la huella (y, peor, un enlace a `/` leería todo el disco).
        let outside = root.appending(path: "fuera")
        try write("uno", to: outside.appending(path: "dato.txt"))
        let app = try makeApp()
        try files.createSymbolicLink(at: app.appending(path: "Contents/Enlace"), withDestinationURL: outside)
        let before = try digest(app)
        try write("dos", to: outside.appending(path: "dato.txt"))
        XCTAssertEqual(try digest(app), before)
    }

    // MARK: - Lo que sí cambia

    func testChangingOneByteChangesIt() throws {
        let app = try makeApp()
        let before = try digest(app)
        try write("binarИ", to: app.appending(path: "Contents/MacOS/Foo"), executable: true)
        XCTAssertNotEqual(try digest(app), before)
        try write("binario", to: app.appending(path: "Contents/MacOS/Foo"), executable: true)
        XCTAssertEqual(try digest(app), before)
    }

    func testAddingAFileOrAFolderChangesIt() throws {
        let app = try makeApp()
        let before = try digest(app)
        try write("", to: app.appending(path: "Contents/Resources/extra.txt"))
        let withFile = try digest(app)
        XCTAssertNotEqual(withFile, before)
        try files.createDirectory(at: app.appending(path: "Contents/Vacia"), withIntermediateDirectories: true)
        XCTAssertNotEqual(try digest(app), withFile)
    }

    func testRemovingAFileChangesIt() throws {
        let app = try makeApp()
        let before = try digest(app)
        try files.removeItem(at: app.appending(path: "Contents/Resources/a.txt"))
        XCTAssertNotEqual(try digest(app), before)
    }

    func testRenamingAFileChangesIt() throws {
        let app = try makeApp()
        let before = try digest(app)
        try files.moveItem(at: app.appending(path: "Contents/Resources/a.txt"),
                           to: app.appending(path: "Contents/Resources/b.txt"))
        XCTAssertNotEqual(try digest(app), before)
    }

    func testMovingAFileToAnotherFolderChangesIt() throws {
        let app = try makeApp()
        let before = try digest(app)
        try files.createDirectory(at: app.appending(path: "Contents/Otra"), withIntermediateDirectories: true)
        try files.moveItem(at: app.appending(path: "Contents/Resources/a.txt"),
                           to: app.appending(path: "Contents/Otra/a.txt"))
        XCTAssertNotEqual(try digest(app), before)
    }

    func testSwappingTheContentsOfTwoFilesChangesIt() throws {
        let one = root.appending(path: "Uno.app")
        let two = root.appending(path: "Dos.app")
        try write("1", to: one.appending(path: "a")); try write("2", to: one.appending(path: "b"))
        try write("2", to: two.appending(path: "a")); try write("1", to: two.appending(path: "b"))
        XCTAssertNotEqual(try digest(one), try digest(two))
    }

    func testTheExecutableBitCounts() throws {
        let app = try makeApp()
        let before = try digest(app)
        try files.setAttributes([.posixPermissions: 0o644],
                                ofItemAtPath: app.appending(path: "Contents/MacOS/Foo").path)
        XCTAssertNotEqual(try digest(app), before)
    }

    func testWhereALinkPointsCounts() throws {
        let app = try makeApp()
        let before = try digest(app)
        let link = app.appending(path: "Contents/Frameworks/Lib.framework/Versions/Current")
        try files.removeItem(at: link)
        try files.createSymbolicLink(at: link, withDestinationURL: URL(fileURLWithPath: "B"))
        XCTAssertNotEqual(try digest(app), before)
    }

    func testAFileAndALinkWithTheSameNameAreNotTheSame() throws {
        let one = root.appending(path: "Uno.app")
        let two = root.appending(path: "Dos.app")
        try write("x", to: one.appending(path: "a"))
        try files.createDirectory(at: two, withIntermediateDirectories: true)
        try files.createSymbolicLink(at: two.appending(path: "a"), withDestinationURL: URL(fileURLWithPath: "x"))
        XCTAssertNotEqual(try digest(one), try digest(two))
    }

    func testNamesAndContentsCannotBeShuffledIntoTheSameDigest() throws {
        // Dos archivos vacíos «a» y «b» frente a uno solo «ab», y un archivo «a» con el
        // texto «b» frente a esos dos: la longitud por delante lo impide.
        let pair = root.appending(path: "Par.app")
        try write("", to: pair.appending(path: "a")); try write("", to: pair.appending(path: "b"))
        let joined = root.appending(path: "Junto.app")
        try write("", to: joined.appending(path: "ab"))
        let text = root.appending(path: "Texto.app")
        try write("b", to: text.appending(path: "a"))
        let all = [try digest(pair), try digest(joined), try digest(text)]
        XCTAssertEqual(Set(all).count, 3)
    }

    // MARK: - Lo que no se puede leer

    func testWhatIsNotARealFolderHasNoDigest() throws {
        let app = try makeApp()
        let plain = root.appending(path: "suelto.txt")
        try write("x", to: plain)
        let link = root.appending(path: "Enlace.app")
        try files.createSymbolicLink(at: link, withDestinationURL: app)
        XCTAssertNil(AppDigest.of(plain))
        XCTAssertNil(AppDigest.of(link))
        XCTAssertNil(AppDigest.of(root.appending(path: "no-existe.app")))
    }

    func testAnUnreadableFileMeansNoDigest() throws {
        try XCTSkipIf(geteuid() == 0, "como administrador se lee todo")
        let app = try makeApp()
        let secret = app.appending(path: "Contents/Resources/a.txt")
        try files.setAttributes([.posixPermissions: 0o000], ofItemAtPath: secret.path)
        XCTAssertNil(AppDigest.of(app))
        try files.setAttributes([.posixPermissions: 0o644], ofItemAtPath: secret.path)
        XCTAssertNotNil(AppDigest.of(app))
    }
}
