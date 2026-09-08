import Combine
import Darwin
import Foundation

/// El histórico del último minuto y el temporizador que lo llena.
///
/// Las lecturas viven en `SystemProbes`; aquí solo hay series, restas y la regla de
/// oro del módulo: **solo se mide mientras algo está a la vista**. Cerrada la página
/// y plegado el notch, no queda ni un temporizador vivo.
///
/// Los procesos que más consumen se miran a la mitad de ritmo que el resto: recorrer
/// todos los PID del sistema cuesta bastante más que leer cuatro contadores, y a
/// nadie le urge saber en menos de cuatro segundos quién le está calentando el Mac.
final class SystemStats: ObservableObject {
    /// Cuánto hay que medir.
    ///
    /// El icono de la barra de menús solo enseña una línea de CPU: leerle además la
    /// GPU, el disco, los 47 sensores de temperatura y los 445 procesos del sistema
    /// cada dos segundos costaba un **1,9 % de CPU en reposo**, y nada de eso se veía
    /// en ningún sitio. La página y el notch sí lo enseñan todo, y solo mientras
    /// están abiertos.
    enum Detail {
        /// Solo CPU. Para el icono de la barra.
        case minimal
        /// Todo. Para la página de Rendimiento y la pestaña del notch.
        case full
    }

    static let capacity = 60
    /// Cada cuánto se toma una muestra normal.
    private static let interval: TimeInterval = 2
    /// Una de cada dos muestras se mira también la lista de procesos.
    private static let processEvery = 2

    // Series del último minuto.
    //
    // Ninguna lleva `@Published` a propósito. Antes lo llevaban las doce, y cada
    // una avisaba por su cuenta: doce actualizaciones de SwiftUI por muestra, con
    // la página entera recalculando el diseño doce veces. Costaba un 5,7 % de CPU
    // con la página abierta, y ni una décima era de medir. Ahora se avisa **una
    // vez**, cuando la muestra está completa.
    private(set) var cpu: [Double] = []          // % (0–100)
    private(set) var gpu: [Double] = []           // % (0–100)
    private(set) var memory: [Double] = []        // GB en uso
    private(set) var networkIn: [Double] = []     // KB/s
    private(set) var networkOut: [Double] = []    // KB/s
    private(set) var diskRead: [Double] = []      // KB/s
    private(set) var diskWrite: [Double] = []     // KB/s
    private(set) var temperature: [Double] = []   // °C del chip

    // Instantáneas
    /// Ocupación de cada núcleo ahora mismo, en el orden del sistema.
    private(set) var cores: [Double] = []
    private(set) var pressure: MemoryPressure = .normal
    private(set) var swap: Double = 0             // GB
    private(set) var diskFree: Double = 0         // GB
    private(set) var topCPU: [TopProcesses.Usage] = []
    private(set) var topMemory: [TopProcesses.Usage] = []
    private(set) var batteryTemperature: Double?
    /// El diodo más caliente del chip: el que decide si el Mac baja el reloj.
    private(set) var socMaxTemperature: Double?
    private(set) var ssdTemperature: Double?
    /// Todos los sensores, de más caliente a menos.
    private(set) var sensors: [Temperature.Sensor] = []
    private(set) var thermalState: ProcessInfo.ThermalState = .nominal
    /// ¿Este macOS deja leer los grados? Si no, se enseña solo el estado térmico.
    ///
    /// Calculada y no guardada: mirarlo crea el cliente de IOKit de los sensores, y
    /// no hay por qué hacerlo al arrancar la app si nadie va a ver la temperatura.
    var temperatureAvailable: Bool { Temperature.available }

    /// ¿Publica el sistema el uso de GPU? En algunos Macs no aparece y entonces no
    /// se enseña la gráfica, en vez de enseñar una línea plana que parece un fallo.
    private(set) var gpuAvailable = false

    let memoryTotal = Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824
    let diskTotal: Double = (SystemProbes.diskSpace()?.total ?? 0) / 1_073_741_824
    /// Cuántos núcleos de eficiencia y cuántos de rendimiento tiene este Mac.
    let coreLayout = SystemProbes.coreLayout()

    /// Aviso de «hay muestra nueva», con el último valor de CPU.
    ///
    /// Lo usa el icono de la barra de menús, que no es una vista de SwiftUI y no
    /// puede depender de `objectWillChange`.
    let sampled = PassthroughSubject<Double, Never>()

    private var detail: Detail = .full
    private var timer: Timer?
    private var ticks = 0
    private var lastCores: [CPUTicks] = []
    private var lastNetwork: (received: UInt64, sent: UInt64, at: Date)?
    private var lastDisk: (read: UInt64, written: UInt64, at: Date)?
    private var lastProcesses: (samples: [TopProcesses.Sample], at: Date)?

    private var sampleMode = false

    /// Solo para las capturas de la web.
    ///
    /// La GPU entra aquí porque, si no, la captura enseñaba tres gráficas mientras
    /// la web prometía cuatro: la pestaña solo dibuja la GPU cuando el sistema la
    /// publica, y en modo muestra nadie la lee.
    func useSample(cpu: [Double], gpu: [Double], memory: [Double],
                   networkIn: [Double], networkOut: [Double]) {
        sampleMode = true
        self.cpu = cpu
        self.gpu = gpu
        self.gpuAvailable = !gpu.isEmpty
        self.memory = memory
        self.networkIn = networkIn
        self.networkOut = networkOut
    }

    deinit { stop() }   // un Timer repetitivo se retiene solo: hay que invalidarlo

    func start(detail: Detail = .full) {
        guard !sampleMode, timer == nil else { return }
        self.detail = detail
        sample()
        let t = Timer.scheduledTimer(withTimeInterval: Self.interval, repeats: true) { [weak self] _ in
            self?.sample()
        }
        t.tolerance = 0.5
        timer = t
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: - Una muestra

    private func sample() {
        ticks += 1
        // SwiftUI quiere el aviso **antes** del cambio, así que va primero y las
        // lecturas después: entre las dos cosas no hay ningún redibujado.
        objectWillChange.send()
        sampleCPU()
        if detail == .full {
            sampleMemory()
            sampleGPU()
            sampleNetwork()
            sampleDisk()
            sampleTemperature()
            if ticks % Self.processEvery == 0 { sampleProcesses() }
        }
        if let last = cpu.last { sampled.send(last) }
    }

    private func sampleCPU() {
        let now = SystemProbes.coreTicks()
        defer { lastCores = now }
        guard lastCores.count == now.count, !now.isEmpty else { return }
        let perCore = zip(now, lastCores).map { $0.usage(since: $1) ?? 0 }
        cores = perCore
        push(&cpu, perCore.reduce(0, +) / Double(perCore.count))
    }

    private func sampleMemory() {
        guard let sample = SystemProbes.memory() else { return }
        push(&memory, sample.used / 1_073_741_824)
        pressure = sample.pressure
        swap = SystemProbes.swapUsed() / 1_073_741_824
    }

    private func sampleGPU() {
        guard let usage = SystemProbes.gpuUsage() else { return }
        gpuAvailable = true
        push(&gpu, usage)
    }

    private func sampleNetwork() {
        let totals = SystemProbes.networkTotals()
        let now = Date()
        defer { lastNetwork = (totals.received, totals.sent, now) }
        guard let last = lastNetwork else { return }
        let seconds = now.timeIntervalSince(last.at)
        push(&networkIn, Rate.perSecond(from: last.received, to: totals.received, seconds: seconds) / 1024)
        push(&networkOut, Rate.perSecond(from: last.sent, to: totals.sent, seconds: seconds) / 1024)
    }

    private func sampleDisk() {
        guard let totals = SystemProbes.diskTotals() else { return }
        let now = Date()
        defer { lastDisk = (totals.read, totals.written, now) }
        if let space = SystemProbes.diskSpace() { diskFree = space.free / 1_073_741_824 }
        guard let last = lastDisk else { return }
        let seconds = now.timeIntervalSince(last.at)
        push(&diskRead, Rate.perSecond(from: last.read, to: totals.read, seconds: seconds) / 1024)
        push(&diskWrite, Rate.perSecond(from: last.written, to: totals.written, seconds: seconds) / 1024)
    }

    private func sampleTemperature() {
        // El estado térmico es público y siempre está; los grados, solo si este
        // macOS los deja leer.
        thermalState = Temperature.thermalState
        guard let reading = Temperature.read() else { return }
        if let soc = reading.soc { push(&temperature, soc) }
        socMaxTemperature = reading.socMax
        ssdTemperature = reading.ssd
        batteryTemperature = reading.battery
        sensors = reading.sensors
    }

    private func sampleProcesses() {
        let samples = TopProcesses.sample()
        let now = Date()
        defer { lastProcesses = (samples, now) }
        guard let last = lastProcesses else { return }
        let usage = TopProcesses.cpuUsage(from: last.samples, to: samples,
                                          seconds: now.timeIntervalSince(last.at))
        topCPU = TopProcesses.topByCPU(usage)
        topMemory = TopProcesses.topByMemory(usage)
    }

    private func push(_ array: inout [Double], _ value: Double) {
        array.append(value)
        if array.count > Self.capacity {
            array.removeFirst(array.count - Self.capacity)
        }
    }
}
