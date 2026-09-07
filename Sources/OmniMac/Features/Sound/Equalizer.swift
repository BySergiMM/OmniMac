import Foundation

/// Un filtro de pico: sube o baja una banda estrecha dejando el resto igual.
///
/// Los coeficientes salen del «Audio EQ Cookbook» de Robert Bristow-Johnson, que es
/// la receta estándar para esto desde hace treinta años. Se calculan en el hilo
/// principal (cada vez que se mueve un deslizador) y el hilo de audio solo los lee.
struct Biquad: Equatable {
    var b0: Float = 1
    var b1: Float = 0
    var b2: Float = 0
    var a1: Float = 0
    var a2: Float = 0

    /// Filtro plano: deja pasar el sonido tal cual.
    static let identity = Biquad()

    /// - Parameters:
    ///   - frequency: centro de la banda, en Hz.
    ///   - gainDB: cuánto se sube (+) o se baja (−), en decibelios.
    ///   - q: lo estrecha que es la campana. 1,4 deja diez bandas que se solapan poco.
    ///   - sampleRate: muestras por segundo del audio.
    static func peaking(frequency: Double, gainDB: Double, q: Double = 1.4, sampleRate: Double) -> Biquad {
        // Sin ganancia no hay filtro: así el caso normal (todo a cero) no cuesta nada
        // y no arrastra ruido de redondeo.
        guard abs(gainDB) > 0.001, sampleRate > 0 else { return .identity }
        // Por encima de la mitad de la frecuencia de muestreo no hay nada que ecualizar.
        guard frequency > 0, frequency < sampleRate / 2 else { return .identity }

        let a = pow(10, gainDB / 40)
        let w0 = 2 * Double.pi * frequency / sampleRate
        let alpha = sin(w0) / (2 * max(q, 0.1))
        let cosW0 = cos(w0)

        let b0 = 1 + alpha * a
        let b1 = -2 * cosW0
        let b2 = 1 - alpha * a
        let a0 = 1 + alpha / a
        let a1 = -2 * cosW0
        let a2 = 1 - alpha / a

        return Biquad(b0: Float(b0 / a0), b1: Float(b1 / a0), b2: Float(b2 / a0),
                      a1: Float(a1 / a0), a2: Float(a2 / a0))
    }

    /// Cuánto amplifica (en veces, no en decibelios) una señal de esa frecuencia.
    /// Solo se usa en las pruebas y para dibujar la curva en Ajustes.
    func magnitude(at frequency: Double, sampleRate: Double) -> Double {
        let w = 2 * Double.pi * frequency / sampleRate
        let cosW = cos(w), sinW = sin(w)
        let cos2W = cos(2 * w), sin2W = sin(2 * w)
        let numeratorReal = Double(b0) + Double(b1) * cosW + Double(b2) * cos2W
        let numeratorImaginary = -(Double(b1) * sinW + Double(b2) * sin2W)
        let denominatorReal = 1 + Double(a1) * cosW + Double(a2) * cos2W
        let denominatorImaginary = -(Double(a1) * sinW + Double(a2) * sin2W)
        let numerator = sqrt(numeratorReal * numeratorReal + numeratorImaginary * numeratorImaginary)
        let denominator = sqrt(denominatorReal * denominatorReal + denominatorImaginary * denominatorImaginary)
        return denominator == 0 ? 0 : numerator / denominator
    }
}

/// Las diez bandas del ecualizador, las de toda la vida (una por octava).
enum EqualizerBands {
    static let frequencies: [Double] = [32, 64, 125, 250, 500, 1_000, 2_000, 4_000, 8_000, 16_000]
    static let count = frequencies.count
    /// Tope de subida y bajada por banda.
    static let limitDB: Double = 12

    /// Nombre corto para la etiqueta de cada deslizador.
    static func label(_ index: Int) -> String {
        let hz = frequencies[index]
        return hz >= 1000 ? "\(Int(hz / 1000))k" : "\(Int(hz))"
    }
}

/// El ecualizador tal y como lo usa el hilo de audio: diez filtros en cascada por
/// canal, con su memoria de las dos muestras anteriores.
///
/// Es una `class` con memoria reservada de una vez porque el hilo de audio no puede
/// reservar ni bloquear. Los coeficientes se cambian desde el hilo principal con
/// `setGains`, que escribe en el juego que no se está usando y luego cambia el
/// índice: así el hilo de audio nunca ve media actualización.
final class Equalizer {
    static let maxChannels = 8

    /// Dos juegos de coeficientes seguidos en memoria; `active` dice cuál vale.
    ///
    /// Memoria reservada de una vez y punteros en vez de `Array`: leer un `Array` de
    /// Swift desde el hilo de audio puede copiar y tocar el contador de referencias,
    /// y ahí no se puede reservar memoria ni bloquear.
    private let coefficients: UnsafeMutablePointer<Biquad>
    private let state: UnsafeMutablePointer<Float>
    private var active = 0
    /// Con todas las bandas a cero no hay nada que hacer y se salta el filtro entero.
    private(set) var isFlat = true
    private(set) var sampleRate: Double = 48_000

    private static let stateSize = maxChannels * EqualizerBands.count * 4

    init() {
        coefficients = .allocate(capacity: 2 * EqualizerBands.count)
        coefficients.initialize(repeating: .identity, count: 2 * EqualizerBands.count)
        state = .allocate(capacity: Self.stateSize)
        state.initialize(repeating: 0, count: Self.stateSize)
    }

    deinit {
        coefficients.deinitialize(count: 2 * EqualizerBands.count)
        coefficients.deallocate()
        state.deinitialize(count: Self.stateSize)
        state.deallocate()
    }

    /// Cambia las ganancias (en dB, una por banda). Se llama desde el hilo principal:
    /// escribe en el juego que no se está usando y luego cambia el índice, así el
    /// hilo de audio nunca ve media actualización.
    func setGains(_ gains: [Double], sampleRate: Double? = nil) {
        if let sampleRate, sampleRate > 0 { self.sampleRate = sampleRate }
        let inactive = 1 - active
        let base = coefficients + inactive * EqualizerBands.count
        var flat = true
        for band in 0..<EqualizerBands.count {
            let gain = band < gains.count ? gains[band] : 0
            let filter = Biquad.peaking(frequency: EqualizerBands.frequencies[band],
                                        gainDB: min(max(gain, -EqualizerBands.limitDB), EqualizerBands.limitDB),
                                        sampleRate: self.sampleRate)
            base[band] = filter
            if filter != .identity { flat = false }
        }
        isFlat = flat
        active = inactive
    }

    /// Olvida las muestras anteriores (al arrancar o al cambiar de salida): si no, el
    /// filtro arrastra un chasquido del audio de antes.
    func reset() {
        state.update(repeating: 0, count: Self.stateSize)
    }

    /// Filtra un canal. `samples` puede ir entrelazado con otros, de ahí el salto.
    func process(_ samples: UnsafeMutablePointer<Float>, stride: Int, count: Int, channel: Int) {
        guard !isFlat, count > 0, channel < Self.maxChannels else { return }
        let filters = coefficients + active * EqualizerBands.count
        for band in 0..<EqualizerBands.count {
            let filter = filters[band]
            if filter == .identity { continue }
            let base = state + (channel * EqualizerBands.count + band) * 4
            var x1 = base[0], x2 = base[1]
            var y1 = base[2], y2 = base[3]
            for index in 0..<count {
                let position = index * stride
                let x = samples[position]
                let y = filter.b0 * x + filter.b1 * x1 + filter.b2 * x2 - filter.a1 * y1 - filter.a2 * y2
                x2 = x1; x1 = x
                y2 = y1; y1 = y
                samples[position] = y
            }
            base[0] = x1; base[1] = x2
            base[2] = y1; base[3] = y2
        }
    }
}

/// Ajustes preparados del ecualizador. Son diez valores en dB, uno por banda:
/// 32, 64, 125, 250, 500, 1k, 2k, 4k, 8k y 16k Hz.
struct EqualizerPreset: Identifiable, Equatable {
    let id: String
    let name: String
    let gains: [Double]

    static let flat = EqualizerPreset(id: "flat", name: L("Plano", "Flat"),
                                      gains: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0])

    static let all: [EqualizerPreset] = [
        .flat,
        .init(id: "bass", name: L("Más graves", "More bass"),
              gains: [6, 5, 4, 2, 0, 0, 0, 0, 0, 0]),
        .init(id: "lessBass", name: L("Menos graves", "Less bass"),
              gains: [-6, -5, -3, -1, 0, 0, 0, 0, 0, 0]),
        .init(id: "voice", name: L("Voz y pódcast", "Voice and podcasts"),
              gains: [-4, -3, -1, 1, 3, 4, 3, 1, 0, -1]),
        .init(id: "treble", name: L("Más agudos", "More treble"),
              gains: [0, 0, 0, 0, 0, 1, 2, 4, 5, 5]),
        .init(id: "rock", name: L("Rock", "Rock"),
              gains: [5, 4, 2, -1, -2, 0, 2, 4, 5, 5]),
        .init(id: "electronic", name: L("Electrónica", "Electronic"),
              gains: [6, 5, 1, 0, -2, 1, 2, 4, 5, 6]),
        .init(id: "laptop", name: L("Altavoces del portátil", "Laptop speakers"),
              gains: [7, 6, 3, 0, -1, 0, 2, 3, 4, 2]),
        .init(id: "night", name: L("Modo noche", "Night mode"),
              gains: [-3, -2, 0, 2, 3, 3, 2, 0, -2, -3]),
    ]

    /// Qué ajuste coincide con estas ganancias (o nada, si el usuario las ha tocado).
    static func matching(_ gains: [Double]) -> EqualizerPreset? {
        all.first { preset in
            zip(preset.gains, gains).allSatisfy { abs($0 - $1) < 0.01 } && preset.gains.count == gains.count
        }
    }
}
