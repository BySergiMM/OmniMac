import Accelerate

/// Limitador de picos para la salida del mezclador.
///
/// Hace falta en cuanto se permite subir una app por encima del 100 %: al sumar
/// varias fuentes amplificadas, las muestras se pasan de 1.0 y la tarjeta las recorta
/// en seco, que es ese crujido feísimo. Esto baja la ganancia lo justo para que el
/// pico quepa, y la devuelve poco a poco.
///
/// Está aparte del motor a propósito: así se puede probar sin reproducir nada (ver
/// `LimiterTests`). Se usa desde el hilo de audio, así que no reserva memoria ni
/// bloquea.
struct Limiter {
    /// Ganancia aplicada ahora mismo (1 = no está haciendo nada).
    private(set) var gain: Float = 1

    /// Lo rápido que baja al encontrar un pico. Casi inmediato, para no dejar pasar
    /// el recorte.
    var attack: Float = 0.5
    /// Lo despacio que vuelve a subir. Lento, para que no se note bombeo.
    var release: Float = 0.02

    /// Techo: por encima de esto se recorta, así que apuntamos un pelo por debajo.
    static let ceiling: Float = 0.995

    /// Ajusta la ganancia para este bloque y la aplica. Devuelve la ganancia usada.
    @discardableResult
    mutating func process(_ samples: UnsafeMutablePointer<Float>, stride: Int, count: Int) -> Float {
        guard count > 0 else { return gain }

        var peak: Float = 0
        vDSP_maxmgv(samples, stride, &peak, vDSP_Length(count))

        // Con el pico ya amplificado por la ganancia actual, ¿cuánto cabe?
        let projected = peak * gain
        let target: Float = projected > Self.ceiling ? Self.ceiling / peak : 1
        let speed = target < gain ? attack : release
        gain += (target - gain) * speed
        gain = min(1, max(0.02, gain))

        if gain < 0.9999 {
            var value = gain
            vDSP_vsmul(samples, stride, &value, samples, stride, vDSP_Length(count))
        }
        return gain
    }

    /// Vuelve al estado de reposo (al parar o al cambiar de salida).
    mutating func reset() { gain = 1 }
}
