import Combine
import CoreAudio
import Foundation

/// Un dispositivo recordado en la lista de prioridad.
///
/// Se guarda el identificador estable (UID), no el `AudioDeviceID`, que cambia cada
/// vez que el aparato se reconecta. El nombre se guarda solo para poder enseñar la
/// lista aunque el dispositivo esté desconectado.
struct PreferredOutput: Identifiable, Equatable, Codable {
    let uid: String
    var name: String

    var id: String { uid }
}

/// Prioridad de salidas de audio: qué se elige cuando conectas o desconectas algo.
///
/// macOS ya cambia solo a unos AirPods recién conectados, pero al quitarlos va
/// siempre a los altavoces, aunque tengas puesto un monitor con sonido o una barra.
/// Aquí decides tú el orden: al cambiar la lista de dispositivos se pone el primero
/// de tu lista que esté disponible.
///
/// **Solo actúa cuando aparece o desaparece un dispositivo**, nunca cuando eres tú
/// quien cambia la salida a mano: si no, sería imposible poner una salida que no
/// fuera la primera de la lista.
final class OutputPriority: ObservableObject {
    static let enabledKey = "sound.priority.enabled"
    static let listKey = "sound.priority.list"

    @Published var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: Self.enabledKey)
            if isEnabled { apply() }
        }
    }

    /// De más a menos preferido.
    @Published private(set) var order: [PreferredOutput] {
        didSet { save() }
    }

    /// Los UID que había la última vez, para saber si de verdad ha cambiado algo.
    private var lastSeen: Set<String> = []
    /// Qué se hizo por última vez, para poder contarlo en Ajustes.
    @Published private(set) var lastSwitch: String?

    init() {
        let defaults = UserDefaults.standard
        isEnabled = defaults.bool(forKey: Self.enabledKey)
        if let data = defaults.data(forKey: Self.listKey),
           let stored = try? JSONDecoder().decode([PreferredOutput].self, from: data) {
            order = stored
        } else {
            order = []
        }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(order) else { return }
        UserDefaults.standard.set(data, forKey: Self.listKey)
    }

    // MARK: - Editar la lista

    /// Añade a la lista los dispositivos que aún no estén.
    ///
    /// Lo que se enchufa (AirPods, un monitor, una barra de sonido) entra **arriba**,
    /// y los altavoces del propio Mac **abajo**. Si no, los altavoces internos, que
    /// siempre están disponibles, serían siempre los primeros y al conectar unos
    /// AirPods te devolvería a ellos al instante.
    func addMissing(from devices: [AudioDevice]) {
        for device in devices where device.hasOutput {
            guard let uid = AudioSystem.uid(of: device.id) else { continue }
            if let index = order.firstIndex(where: { $0.uid == uid }) {
                // El nombre puede haber cambiado (un monitor renombrado, por ejemplo).
                if order[index].name != device.name { order[index].name = device.name }
            } else if AudioSystem.isBuiltIn(device.id) {
                order.append(PreferredOutput(uid: uid, name: device.name))
            } else {
                order.insert(PreferredOutput(uid: uid, name: device.name), at: 0)
            }
        }
    }

    func move(from source: Int, to destination: Int) {
        guard order.indices.contains(source), order.indices.contains(destination), source != destination else { return }
        let item = order.remove(at: source)
        order.insert(item, at: destination)
    }

    func remove(_ item: PreferredOutput) {
        order.removeAll { $0.uid == item.uid }
    }

    // MARK: - Reaccionar a los cambios

    /// Se llama cada vez que CoreAudio avisa de algo. Decide si hay que hacer algo.
    func devicesChanged(_ devices: [AudioDevice]) {
        let available = Set(devices.filter(\.hasOutput).compactMap { AudioSystem.uid(of: $0.id) })
        let changed = available != lastSeen
        lastSeen = available
        // Sin cambios en la lista, el aviso era por otra cosa (el usuario cambiando
        // de salida a mano, por ejemplo): no tocamos nada.
        guard changed, isEnabled else { return }
        apply(devices: devices)
    }

    /// Pone la salida más preferida que esté disponible.
    func apply(devices: [AudioDevice]? = nil) {
        guard isEnabled else { return }
        let list = devices ?? AudioSystem.devices()
        let outputs = list.filter(\.hasOutput)
        guard !outputs.isEmpty else { return }

        var byUID: [String: AudioDevice] = [:]
        for device in outputs {
            if let uid = AudioSystem.uid(of: device.id) { byUID[uid] = device }
        }
        guard let preferred = order.compactMap({ byUID[$0.uid] }).first else { return }
        let current = AudioSystem.defaultDevice(input: false)
        guard current != preferred.id else { return }
        AudioSystem.setDefaultDevice(preferred.id, input: false)
        lastSwitch = L("Cambiado a \(preferred.name)", "Switched to \(preferred.name)")
    }
}
