import CoreGraphics

/// Cose las capturas de una captura con scroll: dice cuánto se ha desplazado el
/// contenido entre dos capturas y qué filas son nuevas.
///
/// No compara píxeles enteros (una zona de 800 puntos en Retina son 1600 filas de
/// 3000 píxeles): cada fila se reduce a 1024 muestras de luminancia como mucho, su
/// «firma». Con menos (se probó con 48 y con 256) los números de un texto se
/// difuminan, «Línea 147» y «Línea 153» dan la misma firma y el texto, que se repite
/// línea a línea, encajaba desplazado una o varias líneas.
///
/// Lo difícil son las partes que no se mueven: la barra de una web, la cabecera de
/// una tabla, una barra de herramientas abajo. Si se cosieran tal cual, saldrían
/// repetidas en cada tramo. Se detectan como filas idénticas en la misma posición
/// entre dos capturas y se dejan fuera de la búsqueda y de lo que se añade.
enum ScrollStitcher {
    /// Por fila, `columns` muestras de luminancia (0–255), fila a fila de arriba abajo.
    struct Signature: Equatable {
        let columns: Int
        let rows: Int
        let values: [UInt8]

        func row(_ index: Int) -> ArraySlice<UInt8> {
            values[(index * columns)..<((index + 1) * columns)]
        }
    }

    /// Lo que se ha movido de una captura a la siguiente.
    struct Step: Equatable {
        /// Filas que ha subido el contenido. 0 = no se ha movido (fin de la página).
        let shift: Int
        /// Filas de arriba y de abajo que no se mueven (cabeceras y pies fijos).
        let top: Int
        let bottom: Int
    }

    /// Dos muestras son distintas si se separan más que esto (de 0 a 255).
    static let sampleThreshold = 24
    /// Columnas distintas que todavía cuentan como «la misma fila». Las capturas de
    /// pantalla son exactas; el margen es para el cursor de texto, que parpadea.
    static let rowTolerance = 1
    /// Media de columnas distintas por fila en una franja que encaja.
    static let tolerance = 0.5

    /// `ignoringTrailing`: píxeles de la derecha que no cuentan. Ahí aparece la barra
    /// de desplazamiento flotante de macOS al hacer scroll y se va a los segundos: si
    /// sale en una captura y en la otra no, ninguna fila encajaría.
    static func signature(of image: CGImage, columns maximum: Int = 1024, ignoringTrailing: Int = 0) -> Signature? {
        let image = ignoringTrailing > 0 && ignoringTrailing < image.width / 2
            ? (image.cropping(to: CGRect(x: 0, y: 0, width: image.width - ignoringTrailing, height: image.height)) ?? image)
            : image
        let rows = image.height
        let columns = min(maximum, image.width)
        guard rows > 0, columns > 0 else { return nil }
        var values = [UInt8](repeating: 0, count: rows * columns)
        let drawn = values.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: columns, height: rows,
                                          bitsPerComponent: 8, bytesPerRow: columns,
                                          space: CGColorSpaceCreateDeviceGray(),
                                          bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return false }
            // Solo se encoge a lo ancho: cada fila sigue siendo una fila.
            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: columns, height: rows))
            return true
        }
        return drawn ? Signature(columns: columns, rows: rows, values: values) : nil
    }

    /// Cuántas columnas cambian de verdad entre dos filas. Contar, y no promediar: una
    /// cifra distinta son pocas columnas muy distintas, y en una media se diluye.
    /// Firma de la franja de la derecha, donde vive la barra de desplazamiento flotante.
    static func trailingSignature(of image: CGImage, trailing: Int) -> Signature? {
        guard trailing > 0, trailing < image.width,
              let strip = image.cropping(to: CGRect(x: image.width - trailing, y: 0, width: trailing, height: image.height))
        else { return nil }
        return signature(of: strip, columns: trailing)
    }

    /// ¿La franja de la derecha de `next` es la de `previous` desplazada como el resto?
    ///
    /// Mientras se ve la barra de desplazamiento flotante, no: ahí hay algo que antes no
    /// estaba. Comparar dos capturas seguidas no sirve, porque la barra se queda quieta
    /// un rato antes de irse y dos capturas con ella son iguales.
    static func trailingMatches(_ previous: Signature, _ next: Signature, step: Step) -> Bool {
        guard previous.rows == next.rows, previous.columns == next.columns, step.shift > 0 else { return true }
        let overlap = previous.rows - step.top - step.bottom - step.shift
        guard overlap > 0 else { return true }
        var changed = 0
        for i in 0..<overlap
        where difference(previous.row(step.top + step.shift + i), next.row(step.top + i)) > rowTolerance {
            changed += 1
            if changed > 2 { return false }
        }
        return true
    }

    static func difference(_ a: ArraySlice<UInt8>, _ b: ArraySlice<UInt8>) -> Int {
        var count = 0
        for (x, y) in zip(a, b) where abs(Int(x) - Int(y)) > sampleThreshold { count += 1 }
        return count
    }

    /// Media de columnas distintas por fila entre `count` filas seguidas de cada firma.
    /// Se corta en cuanto pasa del límite: la mayoría de posiciones no encajan.
    static func bandDifference(_ a: Signature, from aStart: Int, _ b: Signature, from bStart: Int, count: Int,
                               limit: Double = .infinity) -> Double {
        var total = 0
        let cap = limit.isFinite ? Int(limit * Double(count)) : Int.max
        for i in 0..<count {
            total += difference(a.row(aStart + i), b.row(bStart + i))
            if total > cap { return Double(total) / Double(max(1, count)) }
        }
        return Double(total) / Double(max(1, count))
    }

    /// Cuánto se ha desplazado el contenido de `previous` a `next`.
    ///
    /// - `expected`: las filas que se pidió desplazar. Con contenido repetido (una
    ///   lista de filas iguales) hay varios solapes posibles y se elige el más cercano.
    /// - Devuelve `nil` si no hay forma fiable de coserlas (cambió algo más que el
    ///   desplazamiento, o se desplazó más de lo que se ve): mejor parar que inventar.
    static func step(from previous: Signature, to next: Signature, expected: Int? = nil) -> Step? {
        guard previous.rows == next.rows, previous.columns == next.columns, previous.rows > 8 else { return nil }
        let height = previous.rows
        let same = (0..<height).map { difference(previous.row($0), next.row($0)) <= rowTolerance }
        if !same.contains(false) { return Step(shift: 0, top: 0, bottom: 0) }

        // Las partes fijas, como mucho un 40 % arriba y otro abajo: más que eso ya no
        // es una cabecera, es contenido en blanco que casualmente coincide.
        let limit = height * 2 / 5
        let top = min(limit, same.prefix { $0 }.count)
        let bottom = min(limit, same.reversed().prefix { $0 }.count)
        let bodyEnd = height - bottom
        let body = bodyEnd - top
        guard body > 8 else { return nil }

        // Una franja de la captura nueva con algo dentro (una franja en blanco encaja
        // en cualquier sitio) y se busca dónde estaba en la anterior.
        let band = max(4, min(32, body / 4))
        guard let probe = probeStart(in: next, from: top, to: bodyEnd - band, band: band) else { return nil }

        var best: (shift: Int, score: Double)?
        var candidates: [(shift: Int, score: Double)] = []
        for position in top...(bodyEnd - band) {
            let shift = position - probe
            guard shift > 0 else { continue }
            let score = bandDifference(previous, from: position, next, from: probe, count: band, limit: tolerance)
            guard score <= tolerance else { continue }
            candidates.append((shift, score))
            if best == nil || score < best!.score { best = (shift, score) }
        }
        guard let best else { return nil }
        // Empates (contenido repetido): el desplazamiento más parecido al pedido.
        let near = candidates.filter { $0.score <= best.score + 0.1 }
        let chosen = expected.flatMap { wanted in near.min { abs($0.shift - wanted) < abs($1.shift - wanted) } } ?? best
        let shift = chosen.shift

        // Comprobación: todo el solape tiene que coincidir, no solo la franja.
        let overlap = body - shift
        guard overlap > 0,
              bandDifference(previous, from: top + shift, next, from: top, count: overlap, limit: tolerance) <= tolerance
        else { return nil }
        return Step(shift: shift, top: top, bottom: bottom)
    }

    /// Primera franja con contraste suficiente para que su posición no sea ambigua.
    private static func probeStart(in signature: Signature, from start: Int, to end: Int, band: Int) -> Int? {
        guard end >= start else { return nil }
        var row = start
        while row <= end {
            let slice = signature.values[(row * signature.columns)..<((row + band) * signature.columns)]
            if let low = slice.min(), let high = slice.max(), Int(high) - Int(low) > 24 { return row }
            row += max(1, band / 2)
        }
        return nil
    }

    // MARK: - Montaje

    /// Qué filas de cada captura forman la imagen final, de arriba abajo.
    struct Piece: Equatable {
        let frame: Int
        let rows: Range<Int>
    }

    /// De la primera captura, todo menos su pie fijo; de cada siguiente, solo las filas
    /// nuevas (las que asoman por encima del pie); y al final, el pie una sola vez.
    ///
    /// Todos los tramos se cortan con **el mismo** pie, el mayor que se haya visto. Lo
    /// que se detecta como pie cambia de un paso a otro (una fila en blanco del
    /// contenido que coincide junto a la barra), y cortar cada tramo con el suyo dejaba
    /// huecos o filas repetidas entre tramos. Pasarse es seguro: lo que haya de
    /// contenido en esa franja sale al final, con el pie de la última captura.
    static func pieces(height: Int, steps: [Step]) -> [Piece] {
        let moving = steps.filter { $0.shift > 0 }
        guard let bottom = moving.map(\.bottom).max() else { return [Piece(frame: 0, rows: 0..<height)] }
        var result = [Piece(frame: 0, rows: 0..<(height - bottom))]
        var frame = 0
        var footer = 0
        // `steps[i]` va de la captura i a la i+1; las que no se movieron no añaden nada.
        for (index, step) in steps.enumerated() {
            let current = index + 1
            guard step.shift > 0 else { continue }
            let end = height - bottom
            result.append(Piece(frame: current, rows: (end - step.shift)..<end))
            frame = current
            footer = bottom
        }
        if footer > 0 { result.append(Piece(frame: frame, rows: (height - footer)..<height)) }
        return result
    }
}
