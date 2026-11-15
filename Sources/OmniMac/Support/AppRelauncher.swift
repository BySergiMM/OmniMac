import AppKit

/// Cierra OmniMac y la vuelve a abrir: para cuando algo se ha quedado raro (un módulo
/// que no responde, el notch descolocado…) y para aplicar el cambio de idioma.
///
/// El trabajo lo hace un proceso aparte, porque OmniMac no puede abrirse a sí misma
/// después de cerrarse. Ese proceso **espera a que la vieja haya salido de verdad**:
/// con una pausa fija, si el cierre tardaba más, `open` encontraba la app aún viva, se
/// limitaba a traerla delante y no arrancaba ninguna. Y si el cierre se atasca (que es
/// justo cuando más falta hace reiniciar), a los pocos segundos la fuerza a salir.
enum AppRelauncher {
    /// Lo que se espera a que salga por las buenas antes de forzarla.
    static let gracePeriod: Double = 5
    /// Cada cuánto mira si ya ha salido.
    static let pollInterval: Double = 0.1

    static func relaunch() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = arguments(pid: ProcessInfo.processInfo.processIdentifier,
                                   bundlePath: Bundle.main.bundlePath)
        // Que el proceso no herede nuestra salida ni nuestra entrada: si no, se quedaría
        // atado a una app que está a punto de desaparecer.
        task.standardInput = FileHandle.nullDevice
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        do {
            try task.run()
        } catch {
            Toast.show(L("No he podido reiniciar OmniMac", "Couldn't relaunch OmniMac"), symbol: "exclamationmark.triangle.fill")
            return
        }
        NSApp.terminate(nil)
        // Si algo retiene el cierre ordenado, salir igualmente: el proceso de fuera ya
        // está esperando para volver a abrirla.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { exit(0) }
    }

    /// Argumentos de `/bin/sh` para el proceso que reabre la app.
    ///
    /// El PID y la ruta van como parámetros (`$1`, `$2`) y no pegados dentro del
    /// script: una ruta con espacios o comillas no puede romperlo.
    static func arguments(pid: Int32, bundlePath: String) -> [String] {
        let tries = Int((gracePeriod / pollInterval).rounded())
        let script = """
        i=0
        while kill -0 "$1" 2>/dev/null && [ "$i" -lt \(tries) ]; do sleep \(pollInterval); i=$((i+1)); done
        kill -9 "$1" 2>/dev/null
        open "$2"
        """
        return ["-c", script, "omnimac-relaunch", String(pid), bundlePath]
    }
}
