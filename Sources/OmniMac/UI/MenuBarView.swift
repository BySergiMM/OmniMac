import SwiftUI

/// Ajustes › Barra de menús.
struct MenuBarPage: View {
    @ObservedObject var feature: MenuBarFeature

    var body: some View {
        Form {
            Section {
                SettingToggle(title: L("Esconder iconos de la barra de menús", "Hide menu bar icons"),
                              subtitle: L("Añade una flecha a la barra. Todo lo que quede a su izquierda se esconde.",
                                          "Adds an arrow to the menu bar. Everything to its left gets hidden."),
                              isOn: $feature.isEnabled)
            } footer: {
                Text(L("No necesita ningún permiso: OmniMac solo coloca dos iconos suyos y usa el ancho de uno de ellos para empujar a los demás fuera de la vista.",
                       "It needs no permissions: OmniMac just places two icons of its own and uses the width of one of them to push the others out of sight."))
                .font(.caption).foregroundStyle(.secondary)
            }

            if feature.isEnabled {
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        Label(L("Mantén ⌘ pulsado y arrastra los iconos que quieras esconder a la **izquierda** de la flecha.",
                                "Hold ⌘ and drag the icons you want hidden to the **left** of the arrow."),
                              systemImage: "hand.draw")
                        Label(L("Pulsa la flecha (o ⌃⌥⌘B) para verlos un momento.",
                                "Click the arrow (or press ⌃⌥⌘B) to peek at them."),
                              systemImage: "cursorarrow.click")
                        Label(L("macOS recuerda dónde dejaste cada icono, así que esto se hace una sola vez.",
                                "macOS remembers where you left each icon, so you only do this once."),
                              systemImage: "checkmark.circle")
                    }
                    .font(.callout)
                    .labelStyle(.titleAndIcon)
                } header: {
                    Text(L("Cómo se usa", "How it works"))
                }

                Section {
                    SettingRow(title: L("Estado", "State")) {
                        Button(feature.collapsed
                               ? L("Mostrar los iconos", "Show the icons")
                               : L("Esconder los iconos", "Hide the icons")) {
                            feature.toggle()
                        }
                    }
                    SettingToggle(title: L("Volver a esconderlos solos", "Hide them again on their own"),
                                  subtitle: L("Después de mirarlos, se cierran pasado un rato.",
                                              "After a peek, they close again after a while."),
                                  isOn: $feature.autoHide)
                    if feature.autoHide {
                        SettingRow(title: L("Pasados", "After"),
                                   subtitle: L("Segundos que tardan en esconderse otra vez.",
                                               "Seconds before they hide again.")) {
                            Picker("", selection: $feature.autoHideDelay) {
                                ForEach([5.0, 10.0, 15.0, 30.0, 60.0], id: \.self) { seconds in
                                    Text(L("\(Int(seconds)) s", "\(Int(seconds))s")).tag(seconds)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 90)
                        }
                    }
                } header: {
                    Text(L("Comportamiento", "Behaviour"))
                }
            }
        }
    }
}
