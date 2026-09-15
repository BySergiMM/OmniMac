import Foundation

/// Empareja lo que escribes con los nombres de la lista.
///
/// No es una búsqueda por «contiene»: se buscan las letras **en orden**, aunque
/// estén sueltas, para que «slmi» encuentre «Silenciar el micrófono». Eso es lo que
/// hace que un buscador de comandos se sienta rápido: escribes tres letras y ya está
/// lo que querías.
///
/// La puntuación premia, por este orden: que lo escrito aparezca **tal cual**,
/// empezar por ahí, caer al principio de una palabra, y que las letras vayan
/// seguidas. Sin lo primero, «mail» encontraba antes «Mantener el Mac despierto»
/// (m-a-i-l sueltas por toda la frase) que la app Mail.
enum CommandMatcher {

    /// Puntúa un candidato, o `nil` si no encaja.
    ///
    /// Con la consulta vacía todo encaja con 0: la lista se enseña entera y ordenada
    /// por su orden natural.
    static func score(_ candidate: String, query: String) -> Int? {
        let needle = normalize(query)
        guard !needle.isEmpty else { return 0 }
        let hay = Array(normalize(candidate))
        let pins = Array(needle)

        var total = 0
        var index = 0
        var previousMatch: Int?

        for pin in pins {
            var found: Int?
            var cursor = index
            while cursor < hay.count {
                if hay[cursor] == pin { found = cursor; break }
                cursor += 1
            }
            guard let position = found else { return nil }

            if position == 0 {
                total += 12                        // empieza por ahí
            } else if hay[position - 1] == " " {
                total += 8                         // principio de palabra
            }
            if let previous = previousMatch, position == previous + 1 {
                total += 6                         // letras seguidas
            }
            // Cuanto más lejos, peor, pero sin que llegue a doler.
            total -= min(3, position - index)
            previousMatch = position
            index = position + 1
        }

        // Lo escrito aparece tal cual, sin nada en medio: eso es lo que la gente
        // espera de verdad cuando teclea el nombre de una app. Pesa más que todo lo
        // demás junto, y más aún si empieza ahí o abre palabra.
        if let start = firstIndex(of: pins, in: hay) {
            total += 25
            if start == 0 || hay[start - 1] == " " { total += 15 }
        }

        // Entre dos que encajan, gana el nombre más corto: «Sonido» antes que
        // «Sonido: cambiar de salida».
        return total + max(0, 20 - hay.count / 2)
    }

    /// Ordena y recorta. Con empate, alfabético, para que la lista no baile.
    ///
    /// - Parameter bonus: puntos extra por candidato, para inclinar la balanza sin
    ///   separar la lista en grupos (los comandos de OmniMac los llevan).
    ///
    /// Lo que apenas encaja se queda fuera aunque sobre sitio: si la mejor
    /// coincidencia es buena, enseñar detrás cosas que solo comparten letras sueltas
    /// es lo que hacía que Intro ejecutara algo que no tenía nada que ver.
    static func rank<T>(_ items: [T], query: String, limit: Int = 12,
                        bonus: (T) -> Int = { _ in 0 },
                        name: (T) -> String) -> [T] {
        let scored = items.compactMap { item -> (T, Int, String)? in
            guard let score = score(name(item), query: query) else { return nil }
            return (item, score + bonus(item), name(item))
        }
        let best = scored.map(\.1).max() ?? 0
        let floor = best > 0 ? best * 2 / 5 : Int.min
        return scored
            .filter { $0.1 >= floor }
            .sorted { left, right in
                left.1 == right.1 ? left.2.localizedCaseInsensitiveCompare(right.2) == .orderedAscending
                                  : left.1 > right.1
            }
            .prefix(limit)
            .map(\.0)
    }

    /// Minúsculas, sin acentos y sin signos: escribir «micro» tiene que encontrar
    /// «Micrófono», y un punto de más («mic.») no puede dejar la lista vacía.
    static func normalize(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "es"))
            .map { $0.isLetter || $0.isNumber || $0 == " " ? $0 : " " }
            .reduce(into: "") { result, character in
                if character == " " && result.last == " " { return }
                result.append(character)
            }
            .trimmingCharacters(in: .whitespaces)
    }

    /// Dónde empieza `needle` dentro de `hay`, si es que está tal cual.
    private static func firstIndex(of needle: [Character], in hay: [Character]) -> Int? {
        guard !needle.isEmpty, hay.count >= needle.count else { return nil }
        for start in 0...(hay.count - needle.count) where Array(hay[start..<start + needle.count]) == needle {
            return start
        }
        return nil
    }
}
