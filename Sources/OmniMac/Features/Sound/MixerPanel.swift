import AppKit
import Carbon.HIToolbox
import Combine
import SwiftUI

/// Mezclador de volumen suelto: ⌃⌥⌘V y ahí está.
///
/// El mezclador ya vivía en dos sitios —la página de Ajustes y la pestaña del
/// notch—, pero los dos piden abrir algo antes. Esto es lo que uno quiere cuando el
/// vídeo del navegador tapa la música: un atajo, cuatro barras y fuera.
///
/// Como el buscador de comandos, la vista es **función pura del estado**: cuando
/// cambia algo se le entrega una vista nueva. Con un puñado de filas cuesta nada y
/// no depende de que las notificaciones de SwiftUI lleguen dentro de un panel sin
/// barra de título, que es donde ya nos falló una vez.
final class MixerPanelController {
    private var panel: KeyablePanel?
    private var host: FirstClickHostingView<MixerView>?
    private var keyMonitor: Any?
    private var cancellables: Set<AnyCancellable> = []
    private unowned let sound: SoundFeature
    private var mixer: AppVolumeMixer { sound.mixer }

    init(sound: SoundFeature) { self.sound = sound }

    var isVisible: Bool { panel?.isVisible ?? false }

    func toggle() { isVisible ? hide() : show() }

    func show() {
        // Mientras el panel está delante hace falta la lista al día; al cerrarlo se
        // suelta y el motor deja de refrescarse.
        mixer.beginWatching()
        // Se repinta cuando cambia la lista de apps o el volumen del sistema.
        mixer.objectWillChange.receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.render() }.store(in: &cancellables)
        sound.objectWillChange.receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.render() }.store(in: &cancellables)

        let panel = self.panel ?? makePanel()
        self.panel = panel
        let host = FirstClickHostingView(rootView: makeView())
        self.host = host
        panel.contentView = host
        resize()
        panel.makeKeyAndOrderFront(nil)
        installKeyMonitor()
    }

    func hide() {
        guard isVisible else { return }
        removeKeyMonitor()
        cancellables.removeAll()
        mixer.endWatching()
        panel?.orderOut(nil)
    }

    private func render() {
        host?.rootView = makeView()
        resize()
    }

    private func makeView() -> MixerView {
        MixerView(apps: mixer.apps,
                  systemVolume: sound.outputVolume,
                  maxVolume: AppVolumeMixer.maxVolume,
                  boostEnabled: AppVolumeMixer.boostEnabled,
                  onAppVolume: { [weak self] app, value in self?.mixer.setVolume(value, for: app) },
                  onSystemVolume: { [weak self] value in self?.sound.outputVolume = value })
    }

    private func makePanel() -> KeyablePanel {
        let panel = KeyablePanel(contentRect: .zero,
                                 styleMask: [.borderless, .nonactivatingPanel],
                                 backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = true
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .utilityWindow
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.level = .popUpMenu   // después de isFloatingPanel, que lo reinicia
        return panel
    }

    private func resize() {
        guard let panel, let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let width: CGFloat = 380
        let rows = max(1, mixer.apps.count)
        let height: CGFloat = 96 + CGFloat(min(rows, 8)) * 52
        // Arriba a la derecha, debajo de la barra de menús: es de donde sale.
        let frame = CGRect(x: screen.visibleFrame.maxX - width - 16,
                           y: screen.visibleFrame.maxY - height - 8,
                           width: width, height: height)
        panel.setFrame(frame, display: true)
    }

    private func installKeyMonitor() {
        removeKeyMonitor()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.isVisible else { return event }
            if Int(event.keyCode) == Int(kVK_Escape) { self.hide(); return nil }
            return event
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }

    deinit { removeKeyMonitor() }
}

// MARK: - Vista

struct MixerView: View {
    let apps: [AudioApp]
    let systemVolume: Float
    let maxVolume: Float
    let boostEnabled: Bool
    let onAppVolume: (AudioApp, Float) -> Void
    let onSystemVolume: (Float) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L("Mezclador", "Mixer"))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)

            row(icon: "speaker.wave.3.fill",
                name: L("Todo el Mac", "Everything"),
                value: systemVolume, max: 1, tint: .secondary) { onSystemVolume($0) }

            if apps.isEmpty {
                Text(L("No hay ninguna app sonando ahora mismo.", "Nothing is playing right now."))
                    .font(.callout).foregroundStyle(.secondary)
                    .padding(.vertical, 6)
            } else {
                Divider()
                ForEach(apps) { app in
                    row(icon: nil, name: app.name, value: app.volume, max: maxVolume,
                        tint: app.isPlaying ? Color.primary : Color.secondary,
                        image: app.icon) { onAppVolume(app, $0) }
                }
            }

            if boostEnabled {
                Text(L("La amplificación está activada: puedes pasar del 100 %.",
                       "Boost is on: you can go past 100%."))
                    .font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .strokeBorder(.white.opacity(0.12), lineWidth: 1))
    }

    @ViewBuilder
    private func row(icon: String?, name: String, value: Float, max: Float,
                     tint: Color, image: NSImage? = nil,
                     onChange: @escaping (Float) -> Void) -> some View {
        HStack(spacing: 9) {
            if let image {
                Image(nsImage: image).resizable().frame(width: 18, height: 18)
            } else if let icon {
                Image(systemName: icon).frame(width: 18)
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(name).font(.system(size: 12)).lineLimit(1).foregroundStyle(tint)
                    Spacer(minLength: 6)
                    Text("\(Int(value * 100)) %")
                        .font(.system(size: 11, design: .rounded).monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Slider(value: Binding(get: { Double(value) },
                                      set: { onChange(Float($0)) }),
                       in: 0...Double(max))
                    .controlSize(.small)
            }
        }
    }
}
