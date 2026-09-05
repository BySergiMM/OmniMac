import Combine
import Darwin
import Foundation

/// Muestras muy básicas del sistema (CPU, memoria y red) para la página Rendimiento.
/// Solo mide mientras la página está abierta: cada 2 s, con tolerancia.
final class SystemStats: ObservableObject {
    static let capacity = 60

    @Published private(set) var cpu: [Double] = []         // % (0–100)
    @Published private(set) var memory: [Double] = []      // GB en uso
    @Published private(set) var networkIn: [Double] = []   // KB/s
    @Published private(set) var networkOut: [Double] = []  // KB/s
    let memoryTotal = Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824

    private var timer: Timer?
    private var lastTicks: (user: UInt64, system: UInt64, idle: UInt64, nice: UInt64)?
    private var lastBytes: (received: UInt64, sent: UInt64, at: Date)?

    private var sampleMode = false

    /// Solo para las capturas de la web.
    func useSample(cpu: [Double], memory: [Double], networkIn: [Double], networkOut: [Double]) {
        sampleMode = true
        self.cpu = cpu
        self.memory = memory
        self.networkIn = networkIn
        self.networkOut = networkOut
    }

    deinit { stop() }   // un Timer repetitivo se retiene solo: hay que invalidarlo

    func start() {
        guard !sampleMode else { return }
        guard timer == nil else { return }
        sample()
        let t = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.sample() }
        t.tolerance = 0.5
        timer = t
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func sample() {
        if let value = cpuUsage() { push(&cpu, value) }
        push(&memory, memoryUsed())
        let rates = networkRates()
        push(&networkIn, rates.received)
        push(&networkOut, rates.sent)
    }

    private func push(_ array: inout [Double], _ value: Double) {
        array.append(value)
        if array.count > Self.capacity {
            array.removeFirst(array.count - Self.capacity)
        }
    }

    private func cpuUsage() -> Double? {
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size)
        var info = host_cpu_load_info_data_t()
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        let user = UInt64(info.cpu_ticks.0)
        let system = UInt64(info.cpu_ticks.1)
        let idle = UInt64(info.cpu_ticks.2)
        let nice = UInt64(info.cpu_ticks.3)
        defer { lastTicks = (user, system, idle, nice) }
        guard let last = lastTicks else { return nil }
        let busy = Double((user &- last.user) + (system &- last.system) + (nice &- last.nice))
        let total = busy + Double(idle &- last.idle)
        return total > 0 ? min(100, busy / total * 100) : 0
    }

    private func memoryUsed() -> Double {
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        var stats = vm_statistics64_data_t()
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }
        let page = Double(vm_kernel_page_size)
        let used = (Double(stats.active_count) + Double(stats.wire_count) + Double(stats.compressor_page_count)) * page
        return used / 1_073_741_824
    }

    private func networkRates() -> (received: Double, sent: Double) {
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let first = list else { return (0, 0) }
        defer { freeifaddrs(list) }

        var received: UInt64 = 0
        var sent: UInt64 = 0
        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let entry = cursor {
            let interface = entry.pointee
            if let address = interface.ifa_addr, address.pointee.sa_family == UInt8(AF_LINK),
               let data = interface.ifa_data {
                let name = String(cString: interface.ifa_name)
                if !name.hasPrefix("lo") {
                    let stats = data.assumingMemoryBound(to: if_data.self).pointee
                    received += UInt64(stats.ifi_ibytes)
                    sent += UInt64(stats.ifi_obytes)
                }
            }
            cursor = interface.ifa_next
        }

        let now = Date()
        defer { lastBytes = (received, sent, now) }
        guard let last = lastBytes else { return (0, 0) }
        let seconds = max(0.5, now.timeIntervalSince(last.at))
        let down = Double(received &- last.received) / 1024 / seconds
        let up = Double(sent &- last.sent) / 1024 / seconds
        return (max(0, down), max(0, up))
    }
}
