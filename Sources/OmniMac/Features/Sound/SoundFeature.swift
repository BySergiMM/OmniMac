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
        ("⌃⌥⌘ O", L("Cambia a la siguiente salida de audio (altavoces, auriculares, monitor…)", "Switches to the next audio output (speakers, headphones, monitor…)")),
    ]

    var outputDevices: [AudioDevice] { devices.filter(\.hasOutput) }

    /// Qué salida se elige al conectar o desconectar algo.
    let priority = OutputPriority()
    /// Qué dispositivos había en la última relectura, para no repetir trabajo.
    private var lastDeviceSignature: [AudioDeviceID] = []
    var inputDevices: [AudioDevice] { devices.filter(\.hasInput) }
    var outputName: String { devices.first { $0.id == output }?.name ?? "—" }
    var inputName: String { devices.first { $0.id == input }?.name ?? "—" }

    init() {
        super.init(id: "sound",
                   name: L("Sonido", "Sound"),
                   symbol: "speaker.wave.3.fill",
                   blurb: L("Volumen distinto para cada app, cambio de altavoces o micrófono al instante, balance y silencio por dispositivo, y un atajo para ciclar la salida.", "A different volume for every app, instant switching of speakers or microphone, balance and mute per device, and a shortcut to cycle the output."),
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
        let tRefresh = CFAbsoluteTimeGetCurrent()
        refreshing = true
        defer {
            refreshing = false
            let ms = (CFAbsoluteTimeGetCurrent() - tRefresh) * 1000
            // Deja rastro si alguna vez tarda de verdad: es lo que hay que mirar si
            // alguien dice que un menú se ha quedado colgado.
            if ms > 100 { NSLog("OmniMac: releer el sonido tardó %.0f ms", ms) }
        }
        devices = AudioSystem.devices()
        // La prioridad de salidas solo se toca cuando la lista cambia de verdad:
        // preguntar el identificador de cada dispositivo cuesta, y con Bluetooth
        // puede costar mucho. Antes se hacía en cada relectura.
        let signature = devices.map(\.id).sorted()
        if signature != lastDeviceSignature {
            lastDeviceSignature = signature
            priority.addMissing(from: outputDevices)
            priority.devicesChanged(devices)
        }
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
            Toast.show(L("Solo hay una salida de audio", "There is only one audio output"), symbol: "speaker.wave.2.fill")
            return
        }
        let index = outputs.firstIndex { $0.id == output } ?? -1
        let next = outputs[(index + 1) % outputs.count]
        selectOutput(next.id)
        Toast.show(L("Salida: \(next.name)", "Output: \(next.name)"), symbol: "speaker.wave.2.fill")
    }
}
