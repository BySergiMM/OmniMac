import AppKit
import Carbon.HIToolbox
import Combine
import CoreAudio

/// Sonido avanzado: cambiar de altavoces o micrófono al instante, volumen, balance
/// y silencio por dispositivo, y un atajo para ciclar la salida (auriculares ↔
/// altavoces ↔ monitor). Nada que ver con el notch: es otro módulo.
final class SoundFeature: BaseFeature {
    @Published private(set) var devices: [AudioDevice] = []
    @Published private(set) var output: AudioDeviceID?
    @Published private(set) var input: AudioDeviceID?
    @Published private(set) var balanceSupported = false

    @Published var outputVolume: Float = 0.5 {
        didSet {
            guard !refreshing, let output else { return }
            AudioSystem.setVolume(outputVolume, of: output, input: false)
        }
    }
    @Published var inputVolume: Float = 0.5 {
        didSet {
            guard !refreshing, let input else { return }
            AudioSystem.setVolume(inputVolume, of: input, input: true)
        }
    }
    @Published var balance: Float = 0.5 {
        didSet {
            guard !refreshing, let output else { return }
            AudioSystem.setBalance(balance, of: output)
        }
    }
    @Published var outputMuted = false {
        didSet {
            guard !refreshing, let output else { return }
            AudioSystem.setMuted(outputMuted, output, input: false)
        }
    }

    /// Volumen por app (taps de proceso, macOS 14.2+).
    let mixer = AppVolumeMixer()
    private var refreshing = false
    private var lastOutput: AudioDeviceID?
    private static let cycleHotKey: UInt32 = 400

    static let shortcutHelp: [(shortcut: String, action: String)] = [
        ("⌃⌥⌘ O", "Cambia a la siguiente salida de audio (altavoces, auriculares, monitor…)"),
    ]

    var outputDevices: [AudioDevice] { devices.filter(\.hasOutput) }
    var inputDevices: [AudioDevice] { devices.filter(\.hasInput) }
    var outputName: String { devices.first { $0.id == output }?.name ?? "—" }
    var inputName: String { devices.first { $0.id == input }?.name ?? "—" }

    init() {
        super.init(id: "sound",
                   name: "Sonido",
                   symbol: "speaker.wave.3.fill",
                   blurb: "Volumen distinto para cada app, cambio de altavoces o micrófono al instante, balance y silencio por dispositivo, y un atajo para ciclar la salida.",
                   defaultEnabled: true)
    }

    /// Solo para las capturas de la web: nivel visible sin tocar el hardware.
    private var sampleMode = false

    func useSample(outputVolume: Float) {
        sampleMode = true
        refreshing = true
        self.outputVolume = outputVolume
        outputMuted = false
        refreshing = false
    }

    override func start() {
        refresh()
        mixer.start()
        AudioSystem.startObserving { [weak self] in self?.refresh() }
        HotKeyCenter.shared.register(id: Self.cycleHotKey,
                                     keyCode: UInt32(kVK_ANSI_O),
                                     modifiers: UInt32(controlKey | optionKey | cmdKey)) { [weak self] in
            self?.cycleOutput()
        }
    }

    override func stop() {
        HotKeyCenter.shared.unregister(id: Self.cycleHotKey)
        AudioSystem.stopObserving()
        AudioSystem.stopObservingLevels()
        mixer.stop()
    }

    /// Relee todo desde CoreAudio (sin disparar los `didSet`).
    func refresh() {
        guard !sampleMode else { return }
        refreshing = true
        defer { refreshing = false }
        devices = AudioSystem.devices()
        output = AudioSystem.defaultDevice(input: false)
        input = AudioSystem.defaultDevice(input: true)
        if let output {
            outputVolume = AudioSystem.volume(of: output, input: false) ?? outputVolume
            outputMuted = AudioSystem.isMuted(output, input: false)
            if let value = AudioSystem.balance(of: output) {
                balance = value
                balanceSupported = true
            } else {
                balanceSupported = false
            }
        }
        if let input {
            inputVolume = AudioSystem.volume(of: input, input: true) ?? inputVolume
        }
        if output != lastOutput {
            lastOutput = output
            mixer.outputDeviceChanged()
        }
        // Volumen y silencio en tiempo real (teclas de volumen, Ajustes del Sistema…).
        AudioSystem.startObservingLevels(output: output, input: input) { [weak self] in self?.refreshLevels() }
    }

    /// Solo los niveles (volumen, balance, silencio), sin releer dispositivos.
    private func refreshLevels() {
        guard !sampleMode else { return }
        refreshing = true
        defer { refreshing = false }
        if let output {
            outputVolume = AudioSystem.volume(of: output, input: false) ?? outputVolume
            outputMuted = AudioSystem.isMuted(output, input: false)
            if let value = AudioSystem.balance(of: output) { balance = value }
        }
        if let input {
            inputVolume = AudioSystem.volume(of: input, input: true) ?? inputVolume
        }
    }

    func selectOutput(_ id: AudioDeviceID) {
        AudioSystem.setDefaultDevice(id, input: false)
        refresh()
    }

    func selectInput(_ id: AudioDeviceID) {
        AudioSystem.setDefaultDevice(id, input: true)
        refresh()
    }

    func cycleOutput() {
        let outputs = outputDevices
        guard outputs.count > 1 else {
            Toast.show("Solo hay una salida de audio", symbol: "speaker.wave.2.fill")
            return
        }
        let index = outputs.firstIndex { $0.id == output } ?? -1
        let next = outputs[(index + 1) % outputs.count]
        selectOutput(next.id)
        Toast.show("Salida: \(next.name)", symbol: "speaker.wave.2.fill")
    }
}
