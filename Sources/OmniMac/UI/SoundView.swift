import SwiftUI

struct SoundPage: View {
    @ObservedObject var feature: SoundFeature

    var body: some View {
        Form {
            ModuleHeader(feature: feature, page: .sound)

            if feature.isEnabled {
                Section("Salida") {
                    SettingRow(title: "Dispositivo", subtitle: "Altavoces, auriculares, monitor, AirPods…") {
                        Picker("", selection: Binding(
                            get: { feature.output ?? 0 },
                            set: { feature.selectOutput($0) }
                        )) {
                            ForEach(feature.outputDevices) { device in
                                Text(device.name).tag(device.id)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 230)
                    }
                    SettingRow(title: "Volumen") {
                        HStack(spacing: 10) {
                            Slider(value: $feature.outputVolume, in: 0...1)
                                .frame(width: 170)
                            Text("\(Int(feature.outputVolume * 100)) %")
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                                .frame(width: 44, alignment: .trailing)
                        }
                    }
                    if feature.balanceSupported {
                        SettingRow(title: "Balance", subtitle: "Izquierda – derecha") {
                            HStack(spacing: 8) {
                                Text("I").font(.caption).foregroundStyle(.secondary)
                                Slider(value: $feature.balance, in: 0...1).frame(width: 140)
                                Text("D").font(.caption).foregroundStyle(.secondary)
                                Button("Centrar") { feature.balance = 0.5 }.controlSize(.small)
                            }
                        }
                    }
                    SettingToggle(title: "Silenciar la salida", isOn: $feature.outputMuted)
                }

                Section {
                    AppVolumeList(mixer: feature.mixer)
                } header: {
                    Text("Volumen por app")
                } footer: {
                    Text("Capta el audio de esa app (macOS pide permiso una vez, «grabar el audio del sistema») y lo reproduce al nivel elegido; las apps al 100 % no se tocan. También desde la pestaña Sonido del notch.")
                }

                Section("Entrada") {
                    SettingRow(title: "Micrófono", subtitle: "El que usan las videollamadas y las grabaciones.") {
                        Picker("", selection: Binding(
                            get: { feature.input ?? 0 },
                            set: { feature.selectInput($0) }
                        )) {
                            ForEach(feature.inputDevices) { device in
                                Text(device.name).tag(device.id)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 230)
                    }
                    SettingRow(title: "Volumen de entrada") {
                        HStack(spacing: 10) {
                            Slider(value: $feature.inputVolume, in: 0...1)
                                .frame(width: 170)
                            Text("\(Int(feature.inputVolume * 100)) %")
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                                .frame(width: 44, alignment: .trailing)
                        }
                    }
                }

                Section {
                    ForEach(SoundFeature.shortcutHelp, id: \.shortcut) { item in
                        ShortcutRow(keys: item.shortcut, text: item.action)
                    }
                    ShortcutRow(keys: "⌃⌥⌘ M", text: "silencia o activa el micrófono (en Utilidades)")
                } header: {
                    Text("Atajos")
                } footer: {
                    Text("Lo mismo que Ajustes del Sistema › Sonido, pero a un clic y también desde el menú de OmniMac. El balance solo aparece si el dispositivo lo admite.")
                }
            }
        }
        .onAppear { feature.refresh() }
    }
}

/// Apps que están sonando (o tienen volumen propio) con su deslizador.
struct AppVolumeList: View {
    @ObservedObject var mixer: AppVolumeMixer

    var body: some View {
        Group {
            if mixer.apps.isEmpty {
                Text("Ninguna app está sonando ahora mismo. Cuando alguna reproduzca audio aparecerá aquí con su propio volumen.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(mixer.apps) { app in
                    HStack(spacing: 10) {
                        if let icon = app.icon {
                            Image(nsImage: icon).resizable().frame(width: 22, height: 22)
                        } else {
                            Image(systemName: "app.fill").foregroundStyle(.secondary).frame(width: 22, height: 22)
                        }
                        Text(app.name)
                            .lineLimit(1)
                            .foregroundStyle(app.isPlaying ? .primary : .secondary)
                            .frame(width: 150, alignment: .leading)
                        Slider(value: Binding(get: { Double(app.volume) },
                                              set: { mixer.setVolume(Float($0), for: app) }),
                               in: 0...1)
                        Text("\(Int(app.volume * 100)) %")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 44, alignment: .trailing)
                    }
                }
            }
            if let error = mixer.lastError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .onAppear { mixer.beginWatching() }
        .onDisappear { mixer.endWatching() }
    }
}
