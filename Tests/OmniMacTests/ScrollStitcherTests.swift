import CoreGraphics
import XCTest
@testable import OmniMac

/// Coser las capturas de la captura con scroll, con páginas de mentira de las que se
/// sabe exactamente qué tiene que salir.
final class ScrollStitcherTests: XCTestCase {
    private let width = 96

    /// Una fila de «página» distinta de sus vecinas: rayas que cambian con el número.
    private func pageRow(_ y: Int) -> [UInt8] {
        (0..<width).map { x in UInt8(truncatingIfNeeded: (x * 7 + y * 13 + (x / 9) * y) % 251) }
    }

    private func uniformRow(_ value: UInt8) -> [UInt8] { [UInt8](repeating: value, count: width) }

    private func image(_ rows: [[UInt8]]) -> CGImage {
        var bytes = rows.flatMap { $0 }
        let context = bytes.withUnsafeMutableBytes { buffer in
            CGContext(data: buffer.baseAddress, width: width, height: rows.count, bitsPerComponent: 8,
                      bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(),
                      bitmapInfo: CGImageAlphaInfo.none.rawValue)!
        }
        return context.makeImage()!
    }

    /// Lo que se vería por una ventana de `viewport` filas con la página desplazada `offset`,
    /// con `header` filas fijas arriba y `footer` abajo.
    private func frame(offset: Int, viewport: Int, header: Int = 0, footer: Int = 0) -> [[UInt8]] {
        let headerRows = (0..<header).map { _ in uniformRow(30) }.enumerated().map { i, row in
            i % 2 == 0 ? row : uniformRow(220)
        }
        let body = (0..<(viewport - header - footer)).map { pageRow(offset + $0) }
        let footerRows = (0..<footer).map { i in i % 3 == 0 ? uniformRow(200) : uniformRow(60) }
        return headerRows + body + footerRows
    }

    private func signature(_ rows: [[UInt8]]) throws -> ScrollStitcher.Signature {
        try XCTUnwrap(ScrollStitcher.signature(of: image(rows), columns: width))
    }

    /// Junta las filas como lo haría el montaje final.
    private func assemble(_ frames: [[[UInt8]]], steps: [ScrollStitcher.Step]) -> [[UInt8]] {
        ScrollStitcher.pieces(height: frames[0].count, steps: steps).flatMap { piece in
            Array(frames[piece.frame][piece.rows])
        }
    }

    func testFindsTheShift() throws {
        let a = try signature(frame(offset: 0, viewport: 200))
        let b = try signature(frame(offset: 70, viewport: 200))
        let step = try XCTUnwrap(ScrollStitcher.step(from: a, to: b, expected: 70))
        XCTAssertEqual(step.shift, 70)
        XCTAssertEqual(step.top, 0)
        XCTAssertEqual(step.bottom, 0)
    }

    func testNoMovementMeansTheEnd() throws {
        let a = try signature(frame(offset: 300, viewport: 200))
        XCTAssertEqual(ScrollStitcher.step(from: a, to: a)?.shift, 0)
    }

    func testRebuildsThePage() throws {
        let offsets = [0, 70, 140, 210, 245]   // el último paso, más corto: el final de la página
        let frames = offsets.map { frame(offset: $0, viewport: 200) }
        var steps: [ScrollStitcher.Step] = []
        for i in 1..<frames.count {
            steps.append(try XCTUnwrap(ScrollStitcher.step(from: signature(frames[i - 1]), to: signature(frames[i]), expected: 70)))
        }
        XCTAssertEqual(steps.map(\.shift), [70, 70, 70, 35])
        let rows = assemble(frames, steps: steps)
        XCTAssertEqual(rows.count, 445)
        XCTAssertEqual(rows, (0..<445).map(pageRow))
    }

    /// La barra de arriba y la de abajo salen una sola vez, no en cada tramo.
    func testFixedHeaderAndFooterAppearOnce() throws {
        let frames = [0, 70, 140].map { frame(offset: $0, viewport: 200, header: 20, footer: 15) }
        var steps: [ScrollStitcher.Step] = []
        for i in 1..<frames.count {
            steps.append(try XCTUnwrap(ScrollStitcher.step(from: signature(frames[i - 1]), to: signature(frames[i]), expected: 70)))
        }
        XCTAssertEqual(steps.map(\.shift), [70, 70])
        XCTAssertEqual(steps.first?.top, 20)
        XCTAssertEqual(steps.first?.bottom, 15)

        let rows = assemble(frames, steps: steps)
        let body = 200 - 20 - 15
        let expected = Array(frames[0].prefix(20)) + (0..<(body + 140)).map(pageRow) + Array(frames[0].suffix(15))
        XCTAssertEqual(rows.count, expected.count)
        XCTAssertEqual(rows, expected)
    }

    /// Si entre dos capturas cambia algo más que el desplazamiento, no se cose a ciegas.
    func testRefusesWhatDoesNotMatch() throws {
        let a = try signature(frame(offset: 0, viewport: 200))
        let other = (0..<200).map { y in (0..<width).map { x in UInt8(truncatingIfNeeded: (x * x + y * 31) % 241) } }
        XCTAssertNil(ScrollStitcher.step(from: a, to: try signature(other)))
    }

    /// Una sola captura (la página no se movía) es la propia captura.
    func testASingleFrameIsTheFrame() {
        XCTAssertEqual(ScrollStitcher.pieces(height: 200, steps: []), [.init(frame: 0, rows: 0..<200)])
        XCTAssertEqual(ScrollStitcher.pieces(height: 200, steps: [.init(shift: 0, top: 0, bottom: 0)]),
                       [.init(frame: 0, rows: 0..<200)])
    }

    /// Como un texto: cada línea mide 12 filas y todas son iguales salvo unas pocas
    /// columnas, su número. Con una firma basta (48 muestras, diferencia media) las
    /// líneas se confundían y el texto encajaba desplazado una o varias líneas.
    func testTextLinesThatOnlyDifferInTheirNumber() throws {
        let wide = 1000
        func textRow(_ y: Int) -> [UInt8] {
            let line = y / 12, inLine = y % 12
            var row = [UInt8](repeating: 250, count: wide)
            guard (2...9).contains(inLine) else { return row }           // espacio entre líneas
            for x in stride(from: 120, to: 900, by: 9) { row[x] = 20 }   // el texto, igual en todas
            // El número: cuatro cifras de 6 columnas cada una, distintas por línea.
            for digit in 0..<4 {
                let value = (line / Int(pow(10.0, Double(digit)))) % 10
                for x in 0..<6 where (value + x + inLine) % 3 == 0 { row[40 + digit * 8 + x] = 10 }
            }
            return row
        }
        func frame(_ offset: Int) -> CGImage {
            var bytes = (0..<300).flatMap { textRow(offset + $0) }
            return bytes.withUnsafeMutableBytes { buffer in
                CGContext(data: buffer.baseAddress, width: wide, height: 300, bitsPerComponent: 8, bytesPerRow: wide,
                          space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)!.makeImage()!
            }
        }
        // Se pide desplazar 160 y la app desplaza 168 (catorce líneas): no tiene que
        // quedarse con 156 o 168±12 por parecerse más a lo pedido.
        let a = try XCTUnwrap(ScrollStitcher.signature(of: frame(0)))
        let b = try XCTUnwrap(ScrollStitcher.signature(of: frame(168)))
        XCTAssertEqual(ScrollStitcher.step(from: a, to: b, expected: 160)?.shift, 168)
    }

    /// El pie detectado cambia de un paso a otro (filas en blanco que coinciden junto a
    /// la barra). Aunque un paso crea que el pie mide más, la página sale entera y sin
    /// filas repetidas.
    func testAFooterThatLooksBiggerSomeStepsDoesNotLeaveGaps() throws {
        let frames = [0, 70, 140, 210].map { frame(offset: $0, viewport: 200, header: 20, footer: 15) }
        let steps: [ScrollStitcher.Step] = [
            .init(shift: 70, top: 20, bottom: 15),
            .init(shift: 70, top: 20, bottom: 24),   // nueve filas de contenido tomadas por pie
            .init(shift: 70, top: 26, bottom: 15),
        ]
        let rows = assemble(frames, steps: steps)
        let body = 200 - 20 - 15
        let expected = Array(frames[0].prefix(20)) + (0..<(body + 210)).map(pageRow) + Array(frames[0].suffix(15))
        XCTAssertEqual(rows.count, expected.count)
        XCTAssertEqual(rows, expected)
    }

    /// La barra de desplazamiento flotante: si aparece en la franja de la derecha de la
    /// captura nueva, esa franja ya no es la anterior desplazada.
    func testNoticesTheFloatingScrollbar() throws {
        let previous = frame(offset: 0, viewport: 200)
        let next = frame(offset: 70, viewport: 200)
        var withBar = next
        for y in 60..<120 { for x in (width - 6)..<(width - 2) { withBar[y][x] = 90 } }
        let step = ScrollStitcher.Step(shift: 70, top: 0, bottom: 0)
        let a = try XCTUnwrap(ScrollStitcher.trailingSignature(of: image(previous), trailing: 12))
        let clean = try XCTUnwrap(ScrollStitcher.trailingSignature(of: image(next), trailing: 12))
        let barred = try XCTUnwrap(ScrollStitcher.trailingSignature(of: image(withBar), trailing: 12))
        XCTAssertEqual(clean.columns, 12)
        XCTAssertTrue(ScrollStitcher.trailingMatches(a, clean, step: step))
        XCTAssertFalse(ScrollStitcher.trailingMatches(a, barred, step: step))
    }
}
