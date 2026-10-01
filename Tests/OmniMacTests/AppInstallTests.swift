import XCTest
@testable import OmniMac

/// Instalar una app desde un `.dmg`: el orden de los pasos y qué pasa cuando uno falla.
/// Usa carpetas de verdad en un directorio temporal; lo que depende del sistema (firmas,
/// papelera, marca de cuarentena) es de mentira y deja constancia de lo que se le pidió.
final class AppInstallTests: XCTestCase {

    private let team = AppSigner.team("ABCDE12345")
    private let files = FileManager.default

    private var disk: URL!          // el .dmg «montado»
    private var applications: URL!  // el destino
    private var trashFolder: URL!   // la papelera de mentira

    override func setUpWithError() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "omnimac-appinstall-\(UUID().uuidString)")
        disk = root.appending(path: "disk")
        applications = root.appending(path: "Applications")
        trashFolder = root.appending(path: "Trash")
        for folder in [disk!, applications!, trashFolder!] {
            try files.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        try makeApp(at: disk.appending(path: "Foo.app"), content: "nuevo")
    }

    // MARK: - Ayudas

    private func makeApp(at url: URL, content: String) throws {
        let executable = url.appending(path: "Contents/MacOS/Foo")
        try files.createDirectory(at: executable.deletingLastPathComponent(), withIntermediateDirectories: true)
        try content.write(to: executable, atomically: true, encoding: .utf8)
    }

    private func content(of app: URL) -> String? {
        try? String(contentsOf: app.appending(path: "Contents/MacOS/Foo"), encoding: .utf8)
    }

    private func names(in folder: URL) -> [String] {
        ((try? files.contentsOfDirectory(atPath: folder.path)) ?? []).sorted()
    }

    /// El sistema de mentira: apunta lo que se le pide.
    private final class FakeSystem {
        var signerOfTheCopy: AppSigner
        var copyAlreadyMarked: String?
        var writeSucceeds = true
        var written: [(value: String, url: URL)] = []
        var trashed: [URL] = []
        let trashFolder: URL

        init(signer: AppSigner, trashFolder: URL) {
            self.signerOfTheCopy = signer
            self.trashFolder = trashFolder
        }

        var environment: AppInstall.Environment {
            AppInstall.Environment(
                signer: { [unowned self] _ in self.signerOfTheCopy },
                trash: { [unowned self] url in
                    self.trashed.append(url)
                    let destination = self.trashFolder.appending(path: UUID().uuidString)
                    try FileManager.default.moveItem(at: url, to: destination)
                    return destination
                },
                readQuarantine: { [unowned self] _ in self.copyAlreadyMarked },
                writeQuarantine: { [unowned self] value, url in
                    self.written.append((value: value, url: url))
                    return self.writeSucceeds
                }
            )
        }
    }

    private func run(_ system: FakeSystem, expecting: AppSigner? = nil, imageQuarantine: String? = nil,
                     source: URL? = nil) -> Result<URL, AppInstall.Failure> {
        AppInstall.install(source: source ?? disk.appending(path: "Foo.app"), into: applications,
                           expecting: expecting ?? team, imageQuarantine: imageQuarantine,
                           using: system.environment)
    }

    // MARK: - El camino normal

    func testItInstallsIntoAnEmptyFolder() throws {
        let system = FakeSystem(signer: team, trashFolder: trashFolder)
        let result = run(system)
        XCTAssertEqual(try result.get().path, applications.appending(path: "Foo.app").path)
        XCTAssertEqual(content(of: applications.appending(path: "Foo.app")), "nuevo")
        // Ni rastro de la carpeta provisional, y nada a la papelera.
        XCTAssertEqual(names(in: applications), ["Foo.app"])
        XCTAssertTrue(system.trashed.isEmpty)
    }

    func testTheCurrentVersionGoesToTheTrashAndTheNewOneTakesItsPlace() throws {
        try makeApp(at: applications.appending(path: "Foo.app"), content: "viejo")
        let system = FakeSystem(signer: team, trashFolder: trashFolder)
        _ = try run(system).get()
        XCTAssertEqual(content(of: applications.appending(path: "Foo.app")), "nuevo")
        XCTAssertEqual(names(in: applications), ["Foo.app"])
        // La anterior se puede recuperar: está en la papelera, entera.
        let inTrash = names(in: trashFolder)
        XCTAssertEqual(inTrash.count, 1)
        XCTAssertEqual(content(of: trashFolder.appending(path: inTrash[0])), "viejo")
    }

    func testTheOriginalOnTheDiskIsNotMoved() throws {
        let system = FakeSystem(signer: team, trashFolder: trashFolder)
        _ = try run(system).get()
        XCTAssertEqual(content(of: disk.appending(path: "Foo.app")), "nuevo")
    }

    // MARK: - Lo que sale mal no toca lo que ya había

    func testACopyThatIsNotWhatWasReviewedInstallsNothing() throws {
        try makeApp(at: applications.appending(path: "Foo.app"), content: "viejo")
        let system = FakeSystem(signer: .team("OTRO000000"), trashFolder: trashFolder)
        let result = run(system, expecting: team)
        XCTAssertEqual(result, .failure(.signerChanged))
        // La que había sigue donde estaba, sin tocar, y no queda nada a medias.
        XCTAssertEqual(content(of: applications.appending(path: "Foo.app")), "viejo")
        XCTAssertTrue(system.trashed.isEmpty)
        XCTAssertEqual(names(in: applications), ["Foo.app"])
    }

    func testACopyThatBecameUnsignedIsNotInstalled() {
        let system = FakeSystem(signer: .unsigned, trashFolder: trashFolder)
        XCTAssertEqual(run(system, expecting: team), .failure(.signerChanged))
        XCTAssertEqual(names(in: applications), [])
    }

    func testIfTheSourceCannotBeCopiedTheCurrentAppIsUntouched() throws {
        try makeApp(at: applications.appending(path: "Foo.app"), content: "viejo")
        let system = FakeSystem(signer: team, trashFolder: trashFolder)
        let result = run(system, source: disk.appending(path: "NoExiste.app"))
        guard case .failure(.copyFailed) = result else {
            return XCTFail("debía fallar al copiar: \(result)")
        }
        XCTAssertEqual(content(of: applications.appending(path: "Foo.app")), "viejo")
        XCTAssertTrue(system.trashed.isEmpty)
        XCTAssertEqual(names(in: applications), ["Foo.app"])
    }

    // MARK: - La marca de «descargado de Internet»

    func testAnImageInQuarantineLeavesTheCopyInQuarantineToo() throws {
        let system = FakeSystem(signer: team, trashFolder: trashFolder)
        _ = try run(system, imageQuarantine: "0083;66a1b2c3;Safari;ID").get()
        XCTAssertEqual(system.written.count, 1)
        XCTAssertEqual(system.written.first?.value, "0083;66a1b2c3;Safari;ID")
        // Se marca la copia provisional, antes de que ocupe su sitio: nunca hay un momento
        // en que la app esté instalada sin la marca.
        XCTAssertEqual(system.written.first?.url.lastPathComponent, "Foo.app")
        XCTAssertTrue(system.written.first?.url.deletingLastPathComponent().lastPathComponent
            .hasPrefix(".omnimac-instalando-") ?? false)
    }

    func testTheUserApprovalOfTheImageIsNotCopiedToTheApp() throws {
        let system = FakeSystem(signer: team, trashFolder: trashFolder)
        _ = try run(system, imageQuarantine: "00c1;66a1b2c3;Safari;ID").get()
        XCTAssertEqual(system.written.first?.value, "0081;66a1b2c3;Safari;ID")
    }

    func testAnImageThatWasNotInQuarantineWritesNothing() throws {
        let system = FakeSystem(signer: team, trashFolder: trashFolder)
        _ = try run(system, imageQuarantine: nil).get()
        XCTAssertTrue(system.written.isEmpty)
    }

    func testACopyTheSystemAlreadyMarkedIsLeftAsItIs() throws {
        let system = FakeSystem(signer: team, trashFolder: trashFolder)
        system.copyAlreadyMarked = "0081;66a1b2c3;Chrome;OTRO"
        _ = try run(system, imageQuarantine: "0083;66a1b2c3;Safari;ID").get()
        XCTAssertTrue(system.written.isEmpty)
    }

    func testIfTheMarkCannotBeKeptNothingIsInstalledAndTheCurrentAppStays() throws {
        try makeApp(at: applications.appending(path: "Foo.app"), content: "viejo")
        let system = FakeSystem(signer: team, trashFolder: trashFolder)
        system.writeSucceeds = false
        let result = run(system, imageQuarantine: "0083;66a1b2c3;Safari;ID")
        XCTAssertEqual(result, .failure(.quarantineNotApplied))
        // Es preferible no instalar a instalar sin que Gatekeeper la revise.
        XCTAssertEqual(content(of: applications.appending(path: "Foo.app")), "viejo")
        XCTAssertTrue(system.trashed.isEmpty)
        XCTAssertEqual(names(in: applications), ["Foo.app"])
    }
}
