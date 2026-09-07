import SwiftUI

/// Sección «Prioridad de salidas» de Ajustes › Sonido.
///
/// Va en su propia vista con `@ObservedObject` a propósito: la lista vive en
/// `OutputPriority`, que es un objeto aparte de `SoundFeature`, y si la observa solo
/// la página entera los cambios de la lista no repintan nada.
struct OutputPrioritySection: View {
    @ObservedObject var priority: OutputPriority
    let available: [AudioDevice]

    private func isAvailable(_ item: PreferredOutput) -> Bool {
        available.contains { AudioSystem.uid(of: $0.id) == item.uid }
    }

    var body: some View {
        Section {
            SettingToggle(title: L("Elegir la salida por prioridad", "Pick the output by priority"),
                          subtitle: L("Al conectar o desconectar un aparato, se pone el primero de tu lista que esté disponible. Cuando cambias de salida a mano, no se toca nada.",
                                      "When a device connects or disconnects, the first available one on your list is selected. When you switch outputs by hand, nothing is touched."),
                          isOn: $priority.isEnabled)
            if priority.isEnabled {
                ForEach(Array(priority.order.enumerated()), id: \.element.id) { index, item in
                    OutputPriorityRow(item: item, index: index, priority: priority,
                                      available: isAvailable(item))
                }
                if let last = priority.lastSwitch {
                    Text(last).font(.caption).foregroundStyle(.secondary)
                }
            }
        } header: {
            Text(L("Prioridad de salidas", "Output priority"))
        } footer: {
            if priority.isEnabled {
                Text(L("Arrastra para ordenar, o botón derecho › Subir / Bajar. Los que estén desconectados se recuerdan igual.",
                       "Drag to reorder, or right-click › Move up / Move down. Disconnected ones are remembered too."))
                .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

/// Una salida en la lista de prioridad: se ordena arrastrando o con el botón derecho,
/// igual que las pestañas del notch.
struct OutputPriorityRow: View {
    let item: PreferredOutput
    let index: Int
    @ObservedObject var priority: OutputPriority
    let available: Bool
    @State private var targeted = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.tertiary)
            Text("\(index + 1)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 14, alignment: .trailing)
            Image(systemName: available ? "speaker.wave.2.fill" : "speaker.slash")
                .foregroundStyle(available ? Color.accentColor : .secondary)
                .frame(width: 18)
            Text(item.name)
                .foregroundStyle(available ? .primary : .secondary)
            Spacer(minLength: 12)
            if !available {
                Text(L("desconectado", "disconnected"))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .contentShape(Rectangle())
        .padding(.vertical, 1)
        .background(targeted ? Color.accentColor.opacity(0.15) : .clear)
        .draggable(item.uid) { Text(item.name) }
        .dropDestination(for: String.self) { items, _ in
            guard let uid = items.first,
                  let from = priority.order.firstIndex(where: { $0.uid == uid }) else { return false }
            priority.move(from: from, to: index)
            return true
        } isTargeted: { targeted = $0 }
        .contextMenu {
            Button(L("Subir", "Move up")) { priority.move(from: index, to: index - 1) }
                .disabled(index == 0)
            Button(L("Bajar", "Move down")) { priority.move(from: index, to: index + 1) }
                .disabled(index == priority.order.count - 1)
            Divider()
            Button(L("Quitar de la lista", "Remove from the list"), role: .destructive) {
                priority.remove(item)
            }
        }
    }
}
