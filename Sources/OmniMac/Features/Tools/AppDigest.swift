import CryptoKit
import Foundation

/// La huella del contenido de una app, para reconocerla entre el aviso y la copia.
///
/// Es un SHA-256 de todo lo que hay dentro del paquete: nombres, tipo de cada elemento,
/// contenido de los archivos, destino de los enlaces y si un archivo es ejecutable. No mira
/// las marcas extendidas (la de cuarentena es distinta en el disco y en la copia a propósito),
/// ni fechas, ni propietario.
///
/// Por qué no basta el cdhash de la firma (`kSecCodeInfoUnique`): una app sin firma no tiene
/// cdhash, y justo esas son las que hay que poder distinguir de otra sin firma. Esto además
/// cubre lo que la firma no sella (archivos añadidos fuera de lo sellado).
///
/// Cada elemento entra con una etiqueta y su longitud por delante, para que dos árboles
/// distintos no puedan dar la misma secuencia de bytes.
enum AppDigest {

    /// Cuánto se lee de golpe de cada archivo.
    private static let chunk = 1 << 20

    /// `nil` si algo no se pudo leer, o si la ruta no es una carpeta de verdad: sin huella
    /// no hay con qué comparar, y quien la llame tiene que tratarlo como «no coincide».
    static func of(_ root: URL) -> String? {
        guard ItemKind.of(root) == .folder else { return nil }
        var hasher = SHA256()
        guard feed(folder: root, relative: "", into: &hasher) else { return nil }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Recorrido

    private static func feed(folder: URL, relative: String, into hasher: inout SHA256) -> Bool {
        let files = FileManager.default
        guard let names = try? files.contentsOfDirectory(atPath: folder.path) else { return false }

        // Orden fijo, el de los bytes del nombre: el que devuelve el sistema no está
        // garantizado. Y nombres en forma compuesta (NFC): un disco HFS+ los guarda
        // descompuestos y uno APFS conserva los que le dan, y el mismo archivo no debe dar
        // dos huellas por eso.
        let entries = names
            .map { (name: $0, normalized: $0.precomposedStringWithCanonicalMapping) }
            .map { (name: $0.name, normalized: $0.normalized, key: Array($0.normalized.utf8)) }
            .sorted { $0.key.lexicographicallyPrecedes($1.key) }

        for entry in entries {
            let url = folder.appending(path: entry.name)
            let path = relative.isEmpty ? entry.normalized : relative + "/" + entry.normalized
            guard let attributes = try? files.attributesOfItem(atPath: url.path),
                  let type = attributes[.type] as? FileAttributeType else { return false }

            switch type {
            case .typeDirectory:
                feed(tag: 0x44, path, into: &hasher)   // D
                guard feed(folder: url, relative: path, into: &hasher) else { return false }

            case .typeRegular:
                let permissions = (attributes[.posixPermissions] as? NSNumber)?.intValue ?? 0
                let size = (attributes[.size] as? NSNumber)?.uint64Value ?? 0
                feed(tag: 0x46, path, into: &hasher)   // F
                feed(tag: 0x58, number: permissions & 0o100 != 0 ? 1 : 0, into: &hasher)   // X
                feed(tag: 0x53, number: size, into: &hasher)   // S
                guard feed(file: url, expectedSize: size, into: &hasher) else { return false }

            case .typeSymbolicLink:
                // El destino tal cual está escrito: no se sigue el enlace.
                guard let target = try? files.destinationOfSymbolicLink(atPath: url.path) else { return false }
                feed(tag: 0x4C, path, into: &hasher)   // L
                feed(tag: 0x54, target, into: &hasher) // T

            default:
                // Sockets, tuberías, dispositivos: no los hay en una app. Cuentan por su nombre.
                feed(tag: 0x4F, path, into: &hasher)   // O
            }
        }
        return true
    }

    /// El contenido de un archivo. `false` si no se pudo leer entero o si su tamaño no es el
    /// que se le vio al listarlo (alguien lo está cambiando mientras se lee).
    private static func feed(file url: URL, expectedSize: UInt64, into hasher: inout SHA256) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }

        var total: UInt64 = 0
        var failed = false
        var finished = false
        while !finished && !failed {
            // Con `autoreleasepool` un archivo grande no va acumulando los bloques leídos.
            autoreleasepool {
                do {
                    guard let data = try handle.read(upToCount: chunk), !data.isEmpty else {
                        finished = true
                        return
                    }
                    total += UInt64(data.count)
                    hasher.update(data: data)
                } catch {
                    failed = true
                }
            }
        }
        return !failed && total == expectedSize
    }

    // MARK: - Piezas

    private static func feed(tag: UInt8, _ text: String, into hasher: inout SHA256) {
        let bytes = Array(text.utf8)
        var frame = Data([tag])
        withUnsafeBytes(of: UInt64(bytes.count).littleEndian) { frame.append(contentsOf: $0) }
        frame.append(contentsOf: bytes)
        hasher.update(data: frame)
    }

    private static func feed(tag: UInt8, number: UInt64, into hasher: inout SHA256) {
        var frame = Data([tag])
        withUnsafeBytes(of: number.littleEndian) { frame.append(contentsOf: $0) }
        hasher.update(data: frame)
    }
}
