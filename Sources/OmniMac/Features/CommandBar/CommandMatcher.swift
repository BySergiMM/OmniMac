import Foundation

/// Empareja lo que escribes con los nombres de la lista.
///
/// No es una búsqueda por «contiene»: se buscan las letras **en orden**, aunque
/// estén sueltas, para que «slmi» encuentre «Silenciar el micrófono». Eso es lo que
/// hace que un buscador de comandos se sienta rápido: escribes tres letras y ya está
/// lo que querías.
///
/// La puntuación premia tres cosas, por este orden: empezar por ahí, caer al
/// principio de una palabra, y que las letras vayan seguidas. Sin eso, «mic»
/// encontraría antes «Historial del portapapeles» (m-i-c sueltas) que «Micrófono».
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

        // Entre dos que encajan, gana el nombre más corto: «Sonido» antes que
        // «Sonido: cambiar de salida».
        return total + max(0, 20 - hay.count / 2)
    }

    /// Ordena y recorta. Con empate, alfabético, para que la lista no baile.
    static func rank<T>(_ items: [T], query: String, limit: Int = 12,
                        name: (T) -> String) -> [T] {
        items.compactMap { item -> (T, Int, String)? in
            guard let score = score(name(item), query: query) else { return nil }
            return (item, score, name(item))
        }
        .sorted { left, right in
            left.1 == right.1 ? left.2.localizedCaseInsensitiveCompare(right.2) == .orderedAscending
                              : left.1 > right.1
        }
        .prefix(limit)
        .map(\.0)
    }

    /// Minúsculas y sin acentos: escribir «micro» tiene que encontrar «Micrófono».
    static func normalize(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "es"))
    }
}
