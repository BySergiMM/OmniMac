import SwiftUI

/// Página Sonido de Ajustes: dispositivo de salida y entrada, volumen, balance, silencio y volumen por app.
struct SoundPage: View {
    @ObservedObject var feature: SoundFeature
    @State private var boost = AppVolumeMixer.boostEnabled

    var body: some View {
        Form {
            ModuleHeader(feature: feature, page: .sound)

            if feature.isEnabled {
                Section(L("Salida", "Output")) {
                    SettingRow(title: L("Dispositivo", "Device"), subtitle: L("Altavoces, auriculares, monitor, AirPods…", "Speakers, headphones, monitor, AirPods…")) {
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
                    SettingRow(title: L("Volumen", "Volume")) {
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
                        SettingRow(title: "Balance", subtitle: L("Izquierda – derecha", "Left – right")) {
                            HStack(spacing: 8) {
                                Text("I").font(.caption).foregroundStyle(.secondary)
                                Slider(value: $feature.balance, in: 0...1).frame(width: 140)
                                Text("D").font(.caption).foregroundStyle(.secondary)
                                Button(L("Centrar", "Center")) { feature.balance = 0.5 }.controlSize(.small)
                            }
                        }
                    }
                    SettingToggle(title: L("Silenciar la salida", "Mute the output"), isOn: $feature.outputMuted)
                }

                Section {
                    SettingToggle(title: L("Amplificar por encima del 100 %", "Boost above 100%"),
                                  subtitle: L("Sube una app hasta cuatro veces su volumen, para vídeos grabados muy bajos. Un limitador evita que cruja.",
                                              "Raises an app up to four times its volume, for videos recorded too quietly. A limiter keeps it from crackling."),
                                  isOn: $boost)
                        .onChange(of: boost) { _, new in
                            UserDefaults.standard.set(new, forKey: "sound.boost")
                            // Al apagarla, lo que estuviera amplificado vuelve al 100 %.
                            if !new { feature.mixer.clampToNormal() }
                        }
                    AppVolumeList(mixer: feature.mixer)
                } header: {
                    Text(L("Volumen por app", "Per-app volume"))
                } footer: {
                    Text(L("Capta el audio de esa app (macOS pide permiso una vez, «grabar el audio del sistema») y lo reproduce al nivel elegido; las apps al 100 % no se tocan. También desde la pestaña Sonido del notch.", "Captures that app's audio (macOS asks once for “record system audio”) and plays it at the chosen level; apps at 100 % are left alone. Also from the notch's Sound tab."))
                }

                Section {
                    EqualizerView(mixer: feature.mixer)
                } header: {
                    Text(L("Ecualizador", "Equalizer"))
                } footer: {
                    Text(L("Diez bandas para todo lo que suena en el Mac. Con alguna banda movida, OmniMac capta el audio del sistema (el mismo permiso que el volumen por app) para poder filtrarlo; con todo a cero no capta nada.",
                           "Ten bands for everything playing on the Mac. With any band moved, OmniMac captures system audio (the same permission as per-app volume) so it can filter it; with everything at zero it captures nothing."))
                }

                Section(L("Entrada", "Input")) {
                    SettingRow(title: L("Micrófono", "Microphone"), subtitle: L("El que usan las videollamadas y las grabaciones.", "The one video calls and recordings use.")) {
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
                    SettingRow(title: L("Volumen de entrada", "Input volume")) {
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
                    ShortcutRow(keys: "⌃⌥⌘ M", text: L("silencia o activa el micrófono (en Utilidades)", "mutes or unmutes the microphone (in Tools)"))
                } header: {
                    Text(L("Atajos", "Shortcuts"))
                } footer: {
                    Text(L("Lo mismo que Ajustes del Sistema › Sonido, pero a un clic y también desde el menú de OmniMac. El balance solo aparece si el dispositivo lo admite.", "The same as System Settings › Sound, one click away and also from OmniMac's menu. Balance only appears if the device supports it."))
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
                Text(L("Ninguna app está sonando ahora mismo. Cuando alguna reproduzca audio aparecerá aquí con su propio volumen.", "No app is playing right now. When one plays audio it will appear here with its own volume."))
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
                               in: 0...Double(AppVolumeMixer.maxVolume))
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
