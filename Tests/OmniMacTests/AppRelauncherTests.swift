import XCTest
@testable import OmniMac

/// El proceso que reabre OmniMac: que espere a que salga la vieja y que ninguna ruta
/// pueda romper el script.
final class AppRelauncherTests: XCTestCase {

    func testPidAndPathGoAsParametersNotInsideTheScript() {
        let path = "/Applications/Omni \"Mac\" $(rm -rf ~).app"
        let args = AppRelauncher.arguments(pid: 4242, bundlePath: path)
        XCTAssertEqual(args.first, "-c")
        XCTAssertEqual(Array(args.suffix(2)), ["4242", path])
        XCTAssertFalse(args[1].contains("4242"))
        XCTAssertFalse(args[1].contains("Omni"))
    }

    /// Lo ejecuta de verdad con un proceso que ya ha salido: no debe quedarse esperando
    /// y debe llegar a `open` con la ruta intacta (aquí `open` se sustituye por `echo`).
    func testScriptWaitsForTheOldProcessThenOpensThePath() throws {
        let path = "/tmp/Omni Mac.app"
        var args = AppRelauncher.arguments(pid: 999_999, bundlePath: path)
        args[1] = args[1].replacingOccurrences(of: "open \"$2\"", with: "echo \"$2\"")
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = args
        let pipe = Pipe()
        task.standardOutput = pipe
        let start = Date()
        try task.run()
        task.waitUntilExit()
        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)
        XCTAssertEqual(output, path + "\n")
        // El proceso no existe: ni un ciclo de espera.
        XCTAssertLessThan(Date().timeIntervalSince(start), 1)
    }

    func testWaitsLongerWhileTheOldProcessIsAlive() throws {
        // Un `sleep` de 0,5 s hace de OmniMac cerrándose.
        let old = Process()
        old.executableURL = URL(fileURLWithPath: "/bin/sleep")
        old.arguments = ["0.5"]
        try old.run()
        var args = AppRelauncher.arguments(pid: old.processIdentifier, bundlePath: "/x.app")
        args[1] = args[1].replacingOccurrences(of: "open \"$2\"", with: "true")
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = args
        let start = Date()
        try task.run()
        task.waitUntilExit()
        old.waitUntilExit()
        XCTAssertGreaterThanOrEqual(Date().timeIntervalSince(start), 0.3)
    }
}
