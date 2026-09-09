import AppKit
import Carbon.HIToolbox
import SwiftUI

/// Un botón que enseña el atajo y, al pulsarlo, se queda esperando a que teclees uno
/// nuevo.
///
/// Mientras graba se traga las pulsaciones (el monitor devuelve `nil`) para que no
/// lleguen a la ventana: si no, escribir ⌘W cerraría Ajustes en vez de asignarse.
struct ShortcutRecorder: View {
    let binding: ShortcutBinding
    @ObservedObject private var store = ShortcutStore.shared
    @State private var recording = false
    @State private var monitor: Any?

    init(_ binding: ShortcutBinding) { self.binding = binding }

    private var current: Shortcut? { store.shortcut(for: binding) }

    var body: some View {
        HStack(spacing: 6) {
            Button(action: toggle) {
                Text(label)
                    .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(recording ? Color.accentColor : .primary)
                    .frame(minWidth: 92)
                    .padding(.vertical, 3)
            }
            .help(L("Púlsalo y teclea el atajo que quieras. ⎋ cancela, ⌫ lo deja sin atajo.",
                    "Click it and type the shortcut you want. ⎋ cancels, ⌫ leaves it with none."))

            // Solo aparece si hay algo que devolver: un botón que no hace nada estorba.
            if !store.isDefault(binding) {
                Button {
                    store.reset(binding)
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                }
                .buttonStyle(.borderless)
                .help(L("Volver al atajo de fábrica", "Back to the default shortcut"))
            }
        }
        .onDisappear(perform: stopRecording)
    }

    private var label: String {
        if recording { return L("Teclea…", "Type it…") }
        return current?.display ?? L("Sin atajo", "None")
    }

    private func toggle() {
        recording ? stopRecording() : startRecording()
    }

    private func startRecording() {
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let code = UInt32(event.keyCode)
            if code == UInt32(kVK_Escape) { stopRecording(); return nil }
            // ⌫ a secas: quitarle el atajo. Es una decisión válida — el usuario
            // quiere esa combinación para otra app.
            if code == UInt32(kVK_Delete), event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty {
                store.set(nil, for: binding)
                stopRecording()
                return nil
            }
            let mods = Shortcut.carbonModifiers(fromCocoa: event.modifierFlags.rawValue)
            let candidate = Shortcut(keyCode: code, modifiers: mods)
            guard candidate.isValid else { return nil }   // sigue esperando uno válido
            store.set(candidate, for: binding)
            stopRecording()
            return nil
        }
    }

    private func stopRecording() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        recording = false
    }
}

/// Fila de Ajustes para un atajo: qué hace, el editor, y los avisos cuando no se
/// puede usar.
struct ShortcutSettingRow: View {
    let binding: ShortcutBinding
    @ObservedObject private var store = ShortcutStore.shared

    init(_ binding: ShortcutBinding) { self.binding = binding }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(binding.title)
                Spacer(minLength: 12)
                ShortcutRecorder(binding)
            }
            // El choque interno va primero **aunque también esté marcado como no
            // disponible**: cuando dos acciones de OmniMac piden lo mismo, la segunda
            // falla al registrarse y acaba en las dos listas. Decir «lo tiene otra
            // app» ahí sería mentir y mandaría al usuario a buscar fuera.
            if let other = store.conflict(for: binding) {
                warning(L("Choca con «\(other.title)», aquí dentro. Cámbiale el atajo a una de las dos.",
                          "Clashes with “\(other.title)”, inside OmniMac. Give one of the two a different shortcut."))
            } else if store.isUnavailable(binding) {
                warning(L("Este atajo lo tiene otra app: OmniMac no ha podido reservarlo. Ponle otro y funcionará.",
                          "Another app already owns this shortcut, so OmniMac couldn't claim it. Give it a different one and it'll work."))
            }
        }
        .padding(.vertical, 1)
    }

    private func warning(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Image(systemName: "exclamationmark.triangle.fill")
            Text(text)
        }
        .font(.caption)
        .foregroundStyle(.orange)
    }
}
