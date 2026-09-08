import AppKit
import Darwin

/// Qué se está comiendo el Mac ahora mismo.
///
/// Una gráfica de CPU dice *cuánto*; esto dice *quién*, que es lo que uno quiere
/// saber cuando el ventilador se pone a soplar. Es la diferencia entre un monitor
/// bonito y una herramienta que sirve para algo.
///
/// La medición va en dos tiempos, como todo lo que sale de contadores acumulados:
/// se toma una foto, se espera, se toma otra y se restan. Un valor suelto de
/// `pti_total_user` no es un porcentaje de nada.
enum TopProcesses {

    /// Foto de un proceso en un instante.
    struct Sample: Equatable {
        let pid: pid_t
        let name: String
        /// Tiempo de CPU consumido desde que arrancó, en segundos.
        let cpuSeconds: Double
        /// Memoria residente, en bytes.
        let memory: Double
    }

    /// Lo que se enseña: ya con el porcentaje calculado.
    struct Usage: Identifiable, Equatable {
        let pid: pid_t
        let name: String
        /// Porcentaje de un núcleo. Puede pasar de 100 si usa varios, igual que en
        /// Monitor de Actividad.
        let cpu: Double
        let memory: Double
        var id: pid_t { pid }
    }

    // MARK: - Lectura

    /// Cuántos segundos vale un «tick» de los que devuelve el kernel.
    ///
    /// `pti_total_user` **no** está en nanosegundos, aunque lo parezca: está en
    /// unidades de `mach_absolute_time`. En este Mac una unidad son 41,67 ns
    /// (`numer=125, denom=3`), así que tomarlas por nanosegundos daba un **2,4 %**
    /// para un proceso que estaba comiéndose un núcleo entero. En Intel la
    /// proporción es 1:1 y el error no se habría visto nunca.
    private static let secondsPerTick: Double = {
        var info = mach_timebase_info_data_t()
        guard mach_timebase_info(&info) == KERN_SUCCESS, info.denom != 0 else { return 1e-9 }
        return Double(info.numer) / Double(info.denom) / 1_000_000_000
    }()

    /// Todos los procesos del usuario, con su tiempo de CPU y su memoria.
    static func sample() -> [Sample] {
        let count = proc_listpids(UInt32(PROC_ALL_PIDS), 0, nil, 0)
        guard count > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(count) / MemoryLayout<pid_t>.size)
        let written = proc_listpids(UInt32(PROC_ALL_PIDS), 0, &pids, Int32(pids.count * MemoryLayout<pid_t>.size))
        guard written > 0 else { return [] }

        // Los nombres bonitos («Google Chrome» y no «Google Chrome H»)  solo los
        // tienen las apps con interfaz; para el resto vale el del ejecutable.
        var niceNames: [pid_t: String] = [:]
        for app in NSWorkspace.shared.runningApplications {
            if let name = app.localizedName { niceNames[app.processIdentifier] = name }
        }

        var result: [Sample] = []
        result.reserveCapacity(pids.count)
        for pid in pids where pid > 0 {
            var info = proc_taskinfo()
            let size = Int32(MemoryLayout<proc_taskinfo>.size)
            // Falla en los procesos de otros usuarios y en los del sistema: no es un
            // error, es que no nos incumben.
            guard proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &info, size) == size else { continue }
            let name = niceNames[pid] ?? executableName(pid) ?? "PID \(pid)"
            let ticks = Double(info.pti_total_user) + Double(info.pti_total_system)
            result.append(Sample(pid: pid,
                                 name: name,
                                 cpuSeconds: ticks * secondsPerTick,
                                 memory: Double(info.pti_resident_size)))
        }
        return result
    }

    private static func executableName(_ pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(2 * MAXCOMLEN) + 1)
        guard proc_name(pid, &buffer, UInt32(buffer.count)) > 0 else { return nil }
        let name = String(cString: buffer)
        return name.isEmpty ? nil : name
    }

    // MARK: - Cuentas (sin tocar el sistema, para poder probarlas)

    /// Convierte dos fotos en porcentajes de CPU.
    ///
    /// Solo aparecen los procesos presentes en las dos: uno que acaba de arrancar no
    /// tiene con qué compararse, y meterlo con un 0 % lo colaría en la lista sin
    /// merecerlo. Los que han muerto desaparecen solos.
    static func cpuUsage(from previous: [Sample], to current: [Sample], seconds: TimeInterval) -> [Usage] {
        guard seconds > 0 else { return [] }
        var before: [pid_t: Double] = [:]
        before.reserveCapacity(previous.count)
        for sample in previous { before[sample.pid] = sample.cpuSeconds }

        return current.compactMap { sample in
            guard let old = before[sample.pid] else { return nil }
            // Si el contador baja, el PID se ha reciclado: es otro proceso distinto
            // con el mismo número. Se descarta en vez de enseñar un porcentaje loco.
            guard sample.cpuSeconds >= old else { return nil }
            let percent = (sample.cpuSeconds - old) / seconds * 100
            return Usage(pid: sample.pid, name: sample.name, cpu: percent, memory: sample.memory)
        }
    }

    /// Los que más CPU consumen, de mayor a menor.
    ///
    /// Se descarta lo que no llega al 0,5 %: una lista llena de ceros no informa de
    /// nada y hace parecer que pasa algo cuando no pasa.
    static func topByCPU(_ usage: [Usage], limit: Int = 5, threshold: Double = 0.5) -> [Usage] {
        usage.filter { $0.cpu >= threshold }
            .sorted { $0.cpu == $1.cpu ? $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                                       : $0.cpu > $1.cpu }
            .prefix(limit)
            .map { $0 }
    }

    /// Los que más memoria ocupan, de mayor a menor.
    static func topByMemory(_ usage: [Usage], limit: Int = 5) -> [Usage] {
        usage.sorted { $0.memory == $1.memory ? $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                                              : $0.memory > $1.memory }
            .prefix(limit)
            .map { $0 }
    }
}
