import SwiftUI

/// Ajustes › Inicio › «Iconos en la barra de menús».
///
/// El icono general de OmniMac lleva a todo, pero cada cosa está a un menú de
/// distancia. Aquí se saca a la barra el módulo que se use a diario, con su propio
/// icono y sus acciones a un clic.
///
/// Es opcional uno a uno y de fábrica no hay ninguno: ocho iconos de la misma app
/// llenarían la barra, que es justo el problema que resuelve el escondedor de
/// iconos. Que elija cada uno cuáles le compensan.
struct ModuleIconsSection: View {
    @ObservedObject var manager: FeatureManager
    @ObservedObject private var icons = ModuleIcons.shared

    private var modules: [BaseFeature] {
        ModuleIcons.available.compactMap { id in
            manager.all.first { $0.featureID == id }
        }
    }

    var body: some View {
        Section {
            ForEach(modules) { feature in
                SettingRow(title: feature.displayName,
                           subtitle: feature.isEnabled ? nil : L("El módulo está apagado.", "The module is off.")) {
                    Toggle("", isOn: Binding(
                        get: { icons.isEnabled(feature.featureID) },
                        set: { icons.set(feature.featureID, enabled: $0) }))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .disabled(!feature.isEnabled)
                }
            }
        } header: {
            Text(L("Iconos en la barra de menús", "Menu bar icons"))
        } footer: {
            Text(L("Cada módulo puede tener su propio icono, con sus acciones a un clic. Ojo con llenar la barra: en un Mac con notch, los iconos de más acaban debajo de él.",
                   "Each module can have its own icon, with its actions one click away. Careful not to fill the bar: on a Mac with a notch, the extra icons end up underneath it."))
            .font(.caption).foregroundStyle(.secondary)
        }
    }
}
