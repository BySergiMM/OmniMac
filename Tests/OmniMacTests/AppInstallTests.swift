import XCTest
@testable import OmniMac

/// Instalar una app desde un `.dmg`: el orden de los pasos y qué pasa cuando uno falla.
/// Usa carpetas de verdad en un directorio temporal; lo que depende del sistema (firmas,
/// papelera, marca de cuarentena) es de mentira y deja constancia de lo que se le pidió.
final class AppInstallTests: XCTestCase {

    private let team = AppSigner.team("ABCDE12345")
    private let files = FileManager.default

    /// Lo que se le enseñó al usuario: firmante y huella del contenido.
    private var reviewed: AppIdentity { AppIdentity(signer: team, digest: "aaaa") }

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
        var identityOfTheCopy: AppIdentity?
        var copyAlreadyMarked: String?
        var writeSucceeds = true
        var placeFails = false
        var written: [(value: String, url: URL)] = []
        var trashed: [URL] = []
        let trashFolder: URL

        init(identity: AppIdentity?, trashFolder: URL) {
            self.identityOfTheCopy = identity
            self.trashFolder = trashFolder
        }

        var environment: AppInstall.Environment {
            AppInstall.Environment(
                identity: { [unowned self] _ in self.identityOfTheCopy },
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
                },
                place: { [unowned self] source, destination in
                    if self.placeFails { throw CocoaError(.fileWriteUnknown) }
                    try FileManager.default.moveItem(at: source, to: destination)
                }
            )
        }
    }

    /// Un sistema donde la copia es exactamente lo que se revisó.
    private func makeSystem() -> FakeSystem {
        FakeSystem(identity: reviewed, trashFolder: trashFolder)
    }

    private func run(_ system: FakeSystem, expecting: AppIdentity? = nil, imageQuarantine: String? = nil,
                     source: URL? = nil) -> Result<URL, AppInstall.Failure> {
        AppInstall.install(source: source ?? disk.appending(path: "Foo.app"), into: applications,
                           expecting: expecting ?? reviewed, imageQuarantine: imageQuarantine,
                           using: system.environment)
    }

    // MARK: - El camino normal

    func testItInstallsIntoAnEmptyFolder() throws {
        let system = makeSystem()
        let result = run(system)
        XCTAssertEqual(try result.get().path, applications.appending(path: "Foo.app").path)
        XCTAssertEqual(content(of: applications.appending(path: "Foo.app")), "nuevo")
        // Ni rastro de la carpeta provisional, y nada a la papelera.
        XCTAssertEqual(names(in: applications), ["Foo.app"])
        XCTAssertTrue(system.trashed.isEmpty)
    }

    func testTheCurrentVersionGoesToTheTrashAndTheNewOneTakesItsPlace() throws {
        try makeApp(at: applications.appending(path: "Foo.app"), content: "viejo")
        let system = makeSystem()
        _ = try run(system).get()
        XCTAssertEqual(content(of: applications.appending(path: "Foo.app")), "nuevo")
        XCTAssertEqual(names(in: applications), ["Foo.app"])
        // La anterior se puede recuperar: está en la papelera, entera.
        let inTrash = names(in: trashFolder)
        XCTAssertEqual(inTrash.count, 1)
        XCTAssertEqual(content(of: trashFolder.appending(path: inTrash[0])), "viejo")
    }

    func testTheOriginalOnTheDiskIsNotMoved() throws {
        let system = makeSystem()
        _ = try run(system).get()
        XCTAssertEqual(content(of: disk.appending(path: "Foo.app")), "nuevo")
    }

    // MARK: - Solo se instala lo que se revisó

    func testACopyWithAnotherSignerInstallsNothing() throws {
        try makeApp(at: applications.appending(path: "Foo.app"), content: "viejo")
        let system = FakeSystem(identity: AppIdentity(signer: .team("OTRO000000"), digest: "aaaa"),
                                trashFolder: trashFolder)
        XCTAssertEqual(run(system), .failure(.changedSinceReview))
        // La que había sigue donde estaba, sin tocar, y no queda nada a medias.
        XCTAssertEqual(content(of: applications.appending(path: "Foo.app")), "viejo")
        XCTAssertTrue(system.trashed.isEmpty)
        XCTAssertEqual(names(in: applications), ["Foo.app"])
    }

    func testACopyThatBecameUnsignedIsNotInstalled() {
        let system = FakeSystem(identity: AppIdentity(signer: .unsigned, digest: "aaaa"), trashFolder: trashFolder)
        XCTAssertEqual(run(system), .failure(.changedSinceReview))
        XCTAssertEqual(names(in: applications), [])
    }

    func testTheSameSignerWithOtherContentIsAnotherApp() throws {
        try makeApp(at: applications.appending(path: "Foo.app"), content: "viejo")
        let system = FakeSystem(identity: AppIdentity(signer: team, digest: "bbbb"), trashFolder: trashFolder)
        XCTAssertEqual(run(system), .failure(.changedSinceReview))
        XCTAssertEqual(content(of: applications.appending(path: "Foo.app")), "viejo")
        XCTAssertTrue(system.trashed.isEmpty)
    }

    func testAnUnsignedAppCannotBeSwappedForAnotherUnsignedOne() {
        // Para `AppSigner` las dos son lo mismo; solo la huella del contenido las distingue.
        let shown = AppIdentity(signer: .unsigned, digest: "aaaa")
        let other = FakeSystem(identity: AppIdentity(signer: .unsigned, digest: "bbbb"), trashFolder: trashFolder)
        XCTAssertEqual(run(other, expecting: shown), .failure(.changedSinceReview))
        XCTAssertEqual(names(in: applications), [])

        let same = FakeSystem(identity: shown, trashFolder: trashFolder)
        XCTAssertEqual(try? run(same, expecting: shown).get().lastPathComponent, "Foo.app")
    }

    func testAnAdHocAppCannotBeSwappedForAnotherAdHocOne() {
        let shown = AppIdentity(signer: .unverified, digest: "aaaa")
        let other = FakeSystem(identity: AppIdentity(signer: .unverified, digest: "bbbb"), trashFolder: trashFolder)
        XCTAssertEqual(run(other, expecting: shown), .failure(.changedSinceReview))
        XCTAssertEqual(names(in: applications), [])
    }

    func testACopyThatCannotBeReadIsNotInstalled() {
        let system = FakeSystem(identity: nil, trashFolder: trashFolder)
        XCTAssertEqual(run(system), .failure(.changedSinceReview))
        XCTAssertEqual(names(in: applications), [])
    }

    func testASourceThatDoesNotExistInstallsNothingAndLeavesTheCurrentApp() throws {
        try makeApp(at: applications.appending(path: "Foo.app"), content: "viejo")
        let system = makeSystem()
        // Una ruta que no existe no es una carpeta de verdad.
        let result = run(system, source: disk.appending(path: "NoExiste.app"))
        XCTAssertEqual(result, .failure(.notAnApp))
        XCTAssertEqual(content(of: applications.appending(path: "Foo.app")), "viejo")
        XCTAssertTrue(system.trashed.isEmpty)
        XCTAssertEqual(names(in: applications), ["Foo.app"])
    }

    // MARK: - Lo que no es una app de verdad

    func testASymbolicLinkIsNotInstalled() throws {
        // «Foo.app» es un enlace a otra carpeta: se copiaría como enlace, y lo que se
        // revisara después sería su destino, que puede cambiar.
        let link = disk.appending(path: "Enlace.app")
        try files.createSymbolicLink(at: link, withDestinationURL: disk.appending(path: "Foo.app"))
        let system = makeSystem()
        XCTAssertEqual(run(system, source: link), .failure(.notAnApp))
        XCTAssertEqual(names(in: applications), [])
        XCTAssertTrue(system.trashed.isEmpty)
    }

    func testAPlainFileNamedLikeAnAppIsNotInstalled() throws {
        let fake = disk.appending(path: "Falsa.app")
        try "no soy una carpeta".write(to: fake, atomically: true, encoding: .utf8)
        let system = makeSystem()
        XCTAssertEqual(run(system, source: fake), .failure(.notAnApp))
        XCTAssertEqual(names(in: applications), [])
    }

    func testItemKindDoesNotFollowLinks() throws {
        let folder = disk.appending(path: "Foo.app")
        let link = disk.appending(path: "Enlace.app")
        let dangling = disk.appending(path: "Roto.app")
        let plain = disk.appending(path: "suelto.txt")
        try files.createSymbolicLink(at: link, withDestinationURL: folder)
        try files.createSymbolicLink(at: dangling, withDestinationURL: disk.appending(path: "no-existe"))
        try "x".write(to: plain, atomically: true, encoding: .utf8)

        XCTAssertEqual(ItemKind.of(folder), .folder)
        XCTAssertEqual(ItemKind.of(link), .symbolicLink)
        XCTAssertEqual(ItemKind.of(dangling), .symbolicLink)
        XCTAssertEqual(ItemKind.of(plain), .file)
        XCTAssertEqual(ItemKind.of(disk.appending(path: "nada")), .missing)
    }

    // MARK: - Si falla el último paso, lo que había vuelve

    func testIfPlacingTheCopyFailsTheCurrentAppComesBackFromTheTrash() throws {
        try makeApp(at: applications.appending(path: "Foo.app"), content: "viejo")
        let system = makeSystem()
        system.placeFails = true

        let result = run(system)
        guard case .failure(.replaceFailed) = result else {
            return XCTFail("debía fallar al colocar: \(result)")
        }
        // Se mandó a la papelera para dejar sitio y, al fallar, volvió entera a su sitio.
        XCTAssertEqual(system.trashed.count, 1)
        XCTAssertEqual(content(of: applications.appending(path: "Foo.app")), "viejo")
        XCTAssertEqual(names(in: trashFolder), [])
        // Y no queda la copia a medias.
        XCTAssertEqual(names(in: applications), ["Foo.app"])
    }

    func testIfPlacingTheCopyFailsOnAFirstInstallNothingIsLeftBehind() {
        let system = makeSystem()
        system.placeFails = true
        guard case .failure(.replaceFailed) = run(system) else { return XCTFail("debía fallar al colocar") }
        XCTAssertTrue(system.trashed.isEmpty)
        XCTAssertEqual(names(in: applications), [])
    }

    // MARK: - La marca de «descargado de Internet»

    func testAnImageInQuarantineLeavesTheCopyInQuarantineToo() throws {
        let system = makeSystem()
        _ = try run(system, imageQuarantine: "0083;66a1b2c3;Safari;ID").get()
        XCTAssertEqual(system.written.count, 1)
        // Mismo origen, y marcada como «ya no está donde llegó» (lo que hace el Finder).
        XCTAssertEqual(system.written.first?.value, "0183;66a1b2c3;Safari;ID")
        // Se marca la copia provisional, antes de que ocupe su sitio: nunca hay un momento
        // en que la app esté instalada sin la marca.
        XCTAssertEqual(system.written.first?.url.lastPathComponent, "Foo.app")
        XCTAssertTrue(system.written.first?.url.deletingLastPathComponent().lastPathComponent
            .hasPrefix(".omnimac-instalando-") ?? false)
    }

    func testTheUserApprovalOfTheImageIsNotCopiedToTheApp() throws {
        let system = makeSystem()
        _ = try run(system, imageQuarantine: "00c1;66a1b2c3;Safari;ID").get()
        XCTAssertEqual(system.written.first?.value, "0181;66a1b2c3;Safari;ID")
    }

    func testAnImageThatWasNotInQuarantineWritesNothing() throws {
        let system = makeSystem()
        _ = try run(system, imageQuarantine: nil).get()
        XCTAssertTrue(system.written.isEmpty)
    }

    func testACopyTheSystemAlreadyMarkedWithoutApprovalIsLeftAsItIs() throws {
        let system = makeSystem()
        system.copyAlreadyMarked = "0081;66a1b2c3;Chrome;OTRO"
        _ = try run(system, imageQuarantine: "0083;66a1b2c3;Safari;ID").get()
        XCTAssertTrue(system.written.isEmpty)
    }

    func testACopyThatArrivedApprovedLosesTheApproval() throws {
        // El sistema pasó la marca de un .dmg que el usuario ya había aprobado.
        let system = makeSystem()
        system.copyAlreadyMarked = "00c1;66a1b2c3;Safari;ID"
        _ = try run(system, imageQuarantine: "00c1;66a1b2c3;Safari;ID").get()
        XCTAssertEqual(system.written.count, 1)
        // Se reescribe la suya sin el bit de aprobado, sin añadir nada más.
        XCTAssertEqual(system.written.first?.value, "0081;66a1b2c3;Safari;ID")
        XCTAssertEqual(system.written.first?.url.lastPathComponent, "Foo.app")
    }

    func testACopyThatArrivedApprovedLosesItEvenIfTheImageHasNoMark() throws {
        let system = makeSystem()
        system.copyAlreadyMarked = "01c3;66a1b2c3;Safari;ID"
        _ = try run(system, imageQuarantine: nil).get()
        XCTAssertEqual(system.written.first?.value, "0183;66a1b2c3;Safari;ID")
    }

    func testIfTheApprovalCannotBeRemovedNothingIsInstalled() throws {
        try makeApp(at: applications.appending(path: "Foo.app"), content: "viejo")
        let system = makeSystem()
        system.copyAlreadyMarked = "00c1;66a1b2c3;Safari;ID"
        system.writeSucceeds = false
        XCTAssertEqual(run(system, imageQuarantine: "00c1;66a1b2c3;Safari;ID"), .failure(.quarantineNotApplied))
        XCTAssertEqual(content(of: applications.appending(path: "Foo.app")), "viejo")
        XCTAssertTrue(system.trashed.isEmpty)
    }

    func testIfTheMarkCannotBeKeptNothingIsInstalledAndTheCurrentAppStays() throws {
        try makeApp(at: applications.appending(path: "Foo.app"), content: "viejo")
        let system = makeSystem()
        system.writeSucceeds = false
        let result = run(system, imageQuarantine: "0083;66a1b2c3;Safari;ID")
        XCTAssertEqual(result, .failure(.quarantineNotApplied))
        // Es preferible no instalar a instalar sin que Gatekeeper la revise.
        XCTAssertEqual(content(of: applications.appending(path: "Foo.app")), "viejo")
        XCTAssertTrue(system.trashed.isEmpty)
        XCTAssertEqual(names(in: applications), ["Foo.app"])
    }

    // MARK: - Lo que deja una instalación interrumpida

    private func stagingName(_ uuid: UUID = UUID()) -> String {
        AppInstall.stagingPrefix + uuid.uuidString
    }

    func testOnlyTheNamesThisInstallerCreatesCountAsLeftovers() {
        XCTAssertTrue(AppInstall.isStagingFolderName(stagingName()))
        XCTAssertTrue(AppInstall.isStagingFolderName(AppInstall.stagingPrefix + UUID().uuidString.lowercased()))

        let uuid = UUID().uuidString
        for other in ["", "Foo.app", AppInstall.stagingPrefix, AppInstall.stagingPrefix + "123",
                      AppInstall.stagingPrefix + "no-es-un-uuid-pero-mide-lo-mismo-123",
                      AppInstall.stagingPrefix + uuid + "x",
                      AppInstall.stagingPrefix + String(uuid.dropLast()),
                      "omnimac-instalando-" + uuid,       // sin el punto del principio
                      "x" + AppInstall.stagingPrefix + uuid] {
            XCTAssertFalse(AppInstall.isStagingFolderName(other), other)
        }
    }

    func testLeftoversAreSweptAndNothingElse() throws {
        let orphan1 = stagingName(), orphan2 = stagingName()
        for orphan in [orphan1, orphan2] {
            try makeApp(at: applications.appending(path: orphan).appending(path: "Foo.app"), content: "a medias")
        }
        // Lo que se parece pero no es: se queda.
        try makeApp(at: applications.appending(path: "Foo.app"), content: "mia")
        let notAFolder = stagingName()      // el mismo nombre, pero un archivo
        try "mio".write(to: applications.appending(path: notAFolder), atomically: true, encoding: .utf8)
        let notAnId = AppInstall.stagingPrefix + "mis-cosas"
        try files.createDirectory(at: applications.appending(path: notAnId), withIntermediateDirectories: true)
        let link = stagingName()            // un enlace con ese nombre: ni se sigue ni se toca
        try files.createSymbolicLink(at: applications.appending(path: link), withDestinationURL: disk)

        let removed = AppInstall.removeLeftovers(in: applications)

        XCTAssertEqual(removed, [orphan1, orphan2].sorted())
        XCTAssertEqual(names(in: applications), ["Foo.app", notAFolder, notAnId, link].sorted())
        XCTAssertEqual(content(of: disk.appending(path: "Foo.app")), "nuevo", "el destino del enlace no se toca")
        XCTAssertEqual(content(of: applications.appending(path: "Foo.app")), "mia")
    }

    func testSweepingAFolderThatDoesNotExistDoesNothing() {
        XCTAssertEqual(AppInstall.removeLeftovers(in: applications.appending(path: "no-existe")), [])
    }

    func testAnInstallLeavesNothingForTheSweepToFind() throws {
        _ = try run(makeSystem()).get()
        XCTAssertEqual(AppInstall.removeLeftovers(in: applications), [])
        XCTAssertEqual(names(in: applications), ["Foo.app"])
    }
}
