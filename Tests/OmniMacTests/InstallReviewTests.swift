import XCTest
@testable import OmniMac

/// La confirmación al instalar desde un `.dmg`: qué se concluye de quién firmó cada app,
/// qué se le enseña al usuario y qué pasa con la marca de «descargado de Internet».
/// Nada de esto toca el sistema: son decisiones y textos.
final class InstallReviewTests: XCTestCase {

    private let teamA = "ABCDE12345"
    private let teamB = "ZYXWV98765"

    /// Todas las formas en que puede estar firmada la app que ya hay instalada.
    private var allInstalled: [AppSigner?] {
        [nil, .team("ABCDE12345"), .team("ZYXWV98765"), .unverified, .unsigned, .broken]
    }

    private var allIncoming: [AppSigner] {
        [.team("ABCDE12345"), .team("ZYXWV98765"), .unverified, .unsigned, .broken]
    }

    // MARK: - El veredicto

    func testAFirstInstallShowsWhoSignedIt() {
        XCTAssertEqual(InstallReview.verdict(incoming: .team(teamA), installed: nil),
                       .firstInstall(team: teamA))
    }

    func testTheSameTeamIsTheSameDeveloper() {
        XCTAssertEqual(InstallReview.verdict(incoming: .team(teamA), installed: .team(teamA)),
                       .sameDeveloper(team: teamA))
    }

    func testADifferentTeamIsFlaggedWithBothIds() {
        XCTAssertEqual(InstallReview.verdict(incoming: .team(teamA), installed: .team(teamB)),
                       .differentDeveloper(new: teamA, installed: teamB))
    }

    func testReplacingSomethingWithoutATeamCannotBeCompared() {
        for installed in [AppSigner.unverified, .unsigned, .broken] {
            XCTAssertEqual(InstallReview.verdict(incoming: .team(teamA), installed: installed),
                           .installedNotComparable(new: teamA, installed: installed))
        }
    }

    func testAnAppWithoutATrustedSignatureIsFlaggedWhetherOrNotItReplacesSomething() {
        for incoming in [AppSigner.unsigned, .unverified] {
            XCTAssertEqual(InstallReview.verdict(incoming: incoming, installed: nil),
                           .incomingNotTrusted(incoming, replacing: false))
            for installed in [AppSigner.team(teamA), .unverified, .unsigned, .broken] {
                XCTAssertEqual(InstallReview.verdict(incoming: incoming, installed: installed),
                               .incomingNotTrusted(incoming, replacing: true))
            }
        }
    }

    func testABrokenSignatureIsAlwaysRefused() {
        for installed in allInstalled {
            XCTAssertEqual(InstallReview.verdict(incoming: .broken, installed: installed), .brokenSignature)
        }
    }

    func testOnlyAFirstInstallOrTheSameTeamPassesWithoutAWarning() {
        // La regla entera, probada contra todas las combinaciones: sin aviso solo si la app
        // nueva trae un Team ID de Apple y, o no hay nada que sustituir, o es el mismo.
        for incoming in allIncoming {
            for installed in allInstalled {
                let severity = InstallReview.verdict(incoming: incoming, installed: installed).severity
                var expected = InstallVerdict.Severity.warning
                if incoming == .broken {
                    expected = .refused
                } else if case .team = incoming, installed == nil || installed == incoming {
                    expected = .fine
                }
                XCTAssertEqual(severity, expected, "\(incoming) sobre \(String(describing: installed))")
            }
        }
    }

    // MARK: - Los botones

    func testWithoutAWarningTheDefaultButtonInstalls() {
        let verdict = InstallVerdict.firstInstall(team: teamA)
        XCTAssertEqual(InstallReview.buttons(for: verdict, spanish: true),
                       InstallReview.Buttons(titles: ["Instalar", "Cancelar"], installIndex: 0))
        XCTAssertEqual(InstallReview.buttons(for: verdict, spanish: false),
                       InstallReview.Buttons(titles: ["Install", "Cancel"], installIndex: 0))
    }

    func testWithAWarningTheDefaultButtonDoesNotInstall() {
        let verdicts: [InstallVerdict] = [
            .differentDeveloper(new: teamA, installed: teamB),
            .installedNotComparable(new: teamA, installed: .unsigned),
            .incomingNotTrusted(.unsigned, replacing: false),
        ]
        for verdict in verdicts {
            for spanish in [true, false] {
                let buttons = InstallReview.buttons(for: verdict, spanish: spanish)
                // El primero es el que se activa con Intro, y es el de no instalar.
                XCTAssertEqual(buttons.installIndex, 1, "\(verdict)")
                XCTAssertEqual(buttons.titles.first, spanish ? "No instalar" : "Don’t install")
                XCTAssertEqual(buttons.titles.last, spanish ? "Instalar igualmente" : "Install anyway")
            }
        }
    }

    func testABrokenSignatureHasNoButtonThatInstalls() {
        for spanish in [true, false] {
            let buttons = InstallReview.buttons(for: .brokenSignature, spanish: spanish)
            XCTAssertNil(buttons.installIndex)
            XCTAssertEqual(buttons.titles.count, 1)
        }
    }

    func testTheInstallButtonAlwaysExistsWhenThereIsOne() {
        for incoming in allIncoming {
            for installed in allInstalled {
                let buttons = InstallReview.buttons(for: InstallReview.verdict(incoming: incoming, installed: installed),
                                                    spanish: true)
                if let index = buttons.installIndex {
                    XCTAssertTrue(buttons.titles.indices.contains(index))
                }
            }
        }
    }

    // MARK: - Los textos

    private func message(_ verdict: InstallVerdict, spanish: Bool, folder: String = "/Applications") -> String {
        InstallReview.message(app: "Ice", verdict: verdict, folder: folder, spanish: spanish)
    }

    func testTheNewAppsTeamIdIsAlwaysOnScreen() {
        // Es lo que se pidió enseñar en la confirmación: en toda ocasión en que hay uno.
        let verdicts: [InstallVerdict] = [
            .firstInstall(team: teamA),
            .sameDeveloper(team: teamA),
            .differentDeveloper(new: teamA, installed: teamB),
            .installedNotComparable(new: teamA, installed: .unsigned),
        ]
        for verdict in verdicts {
            for spanish in [true, false] {
                XCTAssertTrue(message(verdict, spanish: spanish).contains(teamA), "\(verdict)")
            }
        }
    }

    func testADifferentDeveloperShowsBothTeamIds() {
        let verdict = InstallVerdict.differentDeveloper(new: teamA, installed: teamB)
        for spanish in [true, false] {
            let text = message(verdict, spanish: spanish)
            XCTAssertTrue(text.contains(teamA), text)
            XCTAssertTrue(text.contains(teamB), text)
        }
    }

    func testEveryWarningAdvisesAgainstInstallingWhenInDoubt() {
        let verdicts: [InstallVerdict] = [
            .differentDeveloper(new: teamA, installed: teamB),
            .installedNotComparable(new: teamA, installed: .unverified),
            .incomingNotTrusted(.unsigned, replacing: true),
            .incomingNotTrusted(.unverified, replacing: false),
        ]
        for verdict in verdicts {
            XCTAssertTrue(message(verdict, spanish: true).contains("no la instales"), "\(verdict)")
            XCTAssertTrue(message(verdict, spanish: false).contains("don’t install it"), "\(verdict)")
        }
    }

    func testTheTextSaysWhenTheCurrentAppGoesToTheTrash() {
        let replacing: [InstallVerdict] = [
            .sameDeveloper(team: teamA),
            .differentDeveloper(new: teamA, installed: teamB),
            .installedNotComparable(new: teamA, installed: .unsigned),
            .incomingNotTrusted(.unsigned, replacing: true),
        ]
        for verdict in replacing {
            XCTAssertTrue(message(verdict, spanish: true).contains("papelera"), "\(verdict)")
            XCTAssertTrue(message(verdict, spanish: false).contains("Trash"), "\(verdict)")
        }
        // Y cuando no hay nada que sustituir, no habla de ello.
        let es = message(.incomingNotTrusted(.unsigned, replacing: false), spanish: true)
        XCTAssertFalse(es.contains("la que tienes"), es)
    }

    func testTheFolderIsNamedWhereTheAppWillBeCopied() {
        XCTAssertTrue(message(.firstInstall(team: teamA), spanish: true, folder: "/Users/x/Applications")
            .contains("/Users/x/Applications"))
        XCTAssertTrue(message(.incomingNotTrusted(.unverified, replacing: false), spanish: false, folder: "/Applications")
            .contains("/Applications"))
    }

    func testAnUnsignedAppAndAnAdHocOneAreToldApart() {
        let unsigned = message(.incomingNotTrusted(.unsigned, replacing: false), spanish: false)
        let adHoc = message(.incomingNotTrusted(.unverified, replacing: false), spanish: false)
        XCTAssertNotEqual(unsigned, adHoc)
        XCTAssertTrue(unsigned.contains("isn’t signed"), unsigned)
        XCTAssertTrue(adHoc.contains("ad-hoc"), adHoc)
    }

    func testABrokenSignatureSaysNothingIsInstalled() {
        let es = message(.brokenSignature, spanish: true)
        let en = message(.brokenSignature, spanish: false)
        XCTAssertTrue(es.contains("no la instala"), es)
        XCTAssertTrue(en.contains("won’t install it"), en)
    }

    func testTheTitleNamesTheApp() {
        let verdicts: [InstallVerdict] = [
            .firstInstall(team: teamA),
            .sameDeveloper(team: teamA),
            .differentDeveloper(new: teamA, installed: teamB),
            .installedNotComparable(new: teamA, installed: .unsigned),
            .incomingNotTrusted(.unsigned, replacing: false),
            .brokenSignature,
        ]
        for verdict in verdicts {
            for spanish in [true, false] {
                XCTAssertTrue(InstallReview.title(app: "Ice", verdict: verdict, spanish: spanish).contains("Ice"))
            }
        }
    }

    func testEachLanguageStaysInItsOwn() {
        let verdicts: [InstallVerdict] = [
            .firstInstall(team: teamA),
            .sameDeveloper(team: teamA),
            .differentDeveloper(new: teamA, installed: teamB),
            .installedNotComparable(new: teamA, installed: .unverified),
            .incomingNotTrusted(.unsigned, replacing: true),
            .incomingNotTrusted(.unverified, replacing: false),
            .brokenSignature,
        ]
        for verdict in verdicts {
            let es = message(verdict, spanish: true) + InstallReview.title(app: "Ice", verdict: verdict, spanish: true)
            let en = message(verdict, spanish: false) + InstallReview.title(app: "Ice", verdict: verdict, spanish: false)
            XCTAssertFalse(es.contains("Trash"), es)
            XCTAssertFalse(es.contains("signed"), es)
            XCTAssertFalse(es.contains("developer"), es)
            XCTAssertFalse(en.contains("papelera"), en)
            XCTAssertFalse(en.contains("firma"), en)
            XCTAssertFalse(en.contains("desarrollador"), en)
        }
    }

    // MARK: - La marca de «descargado de Internet»

    private let safari = "0083;66a1b2c3;Safari;5F2C0C5E-8B6A-4D0B-9E55-0123456789AB"

    func testTheAttributeIsTheOneGatekeeperReads() {
        XCTAssertEqual(QuarantineMark.attribute, "com.apple.quarantine")
    }

    func testAnImageThatWasNotQuarantinedLeavesTheCopyAlone() {
        XCTAssertNil(QuarantineMark.valueForCopy(image: nil, app: nil))
        XCTAssertNil(QuarantineMark.valueForCopy(image: "", app: nil))
    }

    func testAnImageThatWasQuarantinedMarksTheCopyWithTheSameValue() {
        XCTAssertEqual(QuarantineMark.valueForCopy(image: safari, app: nil), safari)
    }

    func testACopyTheSystemAlreadyMarkedIsNeverTouched() {
        // Ni se sustituye ni se completa: lo que puso el sistema se queda como está.
        XCTAssertNil(QuarantineMark.valueForCopy(image: safari, app: "0081;66a1b2c3;Chrome;OTRO"))
        XCTAssertNil(QuarantineMark.valueForCopy(image: nil, app: "0081;66a1b2c3;Chrome;OTRO"))
    }

    func testTheUserApprovalOfTheImageDoesNotPassToTheApp() {
        // 0x00c1 = descargado + aprobado. La app tiene que pasar su propia revisión.
        XCTAssertEqual(QuarantineMark.withoutApproval("00c1;66a1b2c3;Safari;ID"), "0081;66a1b2c3;Safari;ID")
        XCTAssertEqual(QuarantineMark.withoutApproval("01c1;66a1b2c3;Safari;ID"), "0181;66a1b2c3;Safari;ID")
        XCTAssertEqual(QuarantineMark.valueForCopy(image: "00c1;66a1b2c3;Safari;ID", app: nil), "0081;66a1b2c3;Safari;ID")
    }

    func testAValueWithoutApprovalIsCopiedUnchanged() {
        XCTAssertEqual(QuarantineMark.withoutApproval(safari), safari)
        XCTAssertEqual(QuarantineMark.withoutApproval("0081;66a1b2c3;Chrome;ID"), "0081;66a1b2c3;Chrome;ID")
    }

    func testOnlyTheApprovalBitChangesForEveryPossibleFlagValue() {
        // Todas las banderas posibles en las cuatro cifras: se quita el bit de aprobado y
        // ninguno más, y el resto del valor (fecha, origen, identificador) no se toca.
        for flags in UInt32(0)...0x0fff {
            var digits = String(flags, radix: 16)
            digits = String(repeating: "0", count: 4 - digits.count) + digits
            let result = QuarantineMark.withoutApproval("\(digits);66a1b2c3;Safari;ID")
            let parts = result.split(separator: ";", omittingEmptySubsequences: false).map { String($0) }
            XCTAssertEqual(parts.count, 4, result)
            XCTAssertEqual(Array(parts.dropFirst()), ["66a1b2c3", "Safari", "ID"], result)
            XCTAssertEqual(parts[0].count, 4, result)
            XCTAssertEqual(UInt32(parts[0], radix: 16), flags & ~QuarantineMark.userApprovedFlag, result)
        }
    }

    func testAValueThatIsNotUnderstoodStillMarksTheCopy() {
        // Mejor una marca que no se entiende que ninguna: la cuarentena sigue puesta.
        for odd in ["basura", ";;;", "zz;1;2;3"] {
            XCTAssertEqual(QuarantineMark.withoutApproval(odd), odd)
            XCTAssertEqual(QuarantineMark.valueForCopy(image: odd, app: nil), odd)
        }
    }
}
