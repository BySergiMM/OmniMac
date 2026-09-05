import Foundation

/// Hilo dedicado, con run loop propio, en el que se ejecutan todos los AppleScript
/// de la app (control de Spotify y Música).
///
/// ¿Por qué no una cola de GCD? Al enviar un AppleEvent, el sistema crea en el hilo
/// que lo envía un run loop con sus modos, puertos y fuentes, y lo deja ahí para
/// reutilizarlo. Con GCD cada envío puede caer en un hilo de trabajo distinto, así que
/// esos restos se iban acumulando (medido en 0.4.1 con `heap`: un run loop, un modo y
/// varias fuentes más por cada sondeo con Spotify abierto). En un único hilo el run
/// loop se crea una vez y se reutiliza.
///
/// Uso: `ScriptThread.shared.async { … }`. Los bloques se ejecutan en serie y en orden.
final class ScriptThread {
    static let shared = ScriptThread()

    private let thread: Thread
    private var runLoop: CFRunLoop!

    private init() {
        let ready = DispatchSemaphore(value: 0)
        var loop: CFRunLoop!
        thread = Thread {
            loop = CFRunLoopGetCurrent()
            // Un run loop sin fuentes termina al instante: una fuente vacía lo mantiene vivo.
            var context = CFRunLoopSourceContext()
            let keepAlive = CFRunLoopSourceCreate(kCFAllocatorDefault, 0, &context)
            CFRunLoopAddSource(CFRunLoopGetCurrent(), keepAlive, .defaultMode)
            ready.signal()
            CFRunLoopRun()
        }
        thread.name = "com.seergiii.omnimac.scripting"
        thread.qualityOfService = .userInitiated
        thread.start()
        ready.wait()
        runLoop = loop
    }

    /// true si el código actual ya corre en este hilo.
    var isCurrent: Bool { Thread.current === thread }

    /// Encola un bloque en el hilo de scripts y vuelve enseguida.
    func async(_ block: @escaping () -> Void) {
        CFRunLoopPerformBlock(runLoop, CFRunLoopMode.defaultMode.rawValue, block)
        CFRunLoopWakeUp(runLoop)
    }
}
