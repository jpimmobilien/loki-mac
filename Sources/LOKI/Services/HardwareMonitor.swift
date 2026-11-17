import Foundation
import Metal
import Darwin
import MLX

/// Echte Systemwerte: Chip, Arbeitsspeicher, frei verfügbarer Speicher, GPU-Budget, MLX-Belegung.
@MainActor
final class HardwareMonitor: ObservableObject {
    @Published private(set) var chipName: String = "Apple Silicon"
    @Published private(set) var physicalMemory: UInt64 = ProcessInfo.processInfo.physicalMemory
    @Published private(set) var gpuWorkingSet: UInt64 = 0
    @Published private(set) var availableMemory: UInt64 = 0
    @Published private(set) var mlxActiveMemory: UInt64 = 0
    @Published private(set) var cpuCores: Int = ProcessInfo.processInfo.activeProcessorCount
    @Published private(set) var osVersion: String = ProcessInfo.processInfo.operatingSystemVersionString

    private var timer: Timer?

    /// Mindestreserve für macOS und andere Apps
    static let systemReserve: UInt64 = 6_000_000_000

    init() {
        chipName = Self.sysctlString("machdep.cpu.brand_string") ?? "Apple Silicon"
        if let device = MTLCreateSystemDefaultDevice() {
            gpuWorkingSet = device.recommendedMaxWorkingSetSize
        }
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func refresh() {
        availableMemory = Self.availableMemoryBytes()
        mlxActiveMemory = UInt64(max(0, MLX.Memory.activeMemory))
    }

    /// Speicher, den ein (weiteres) Modell belegen darf.
    /// Bereits von LOKI geladene Modelle zählen als verfügbar, weil der Router sie bei Bedarf entlädt.
    var modelBudgetBytes: Int64 {
        let gpuCap = gpuWorkingSet > 0 ? gpuWorkingSet : UInt64(Double(physicalMemory) * 0.75)
        let free = availableMemory + mlxActiveMemory
        let byFree = free > Self.systemReserve ? free - Self.systemReserve : 0
        return Int64(min(gpuCap, byFree))
    }

    /// Speicherbandbreite für die Tempo-Schätzung. M5 Pro: 307 GB/s; sonst grob nach Chipname.
    var memoryBandwidth: Double {
        let name = chipName.lowercased()
        if name.contains("ultra") { return 800e9 }
        if name.contains("max") { return 546e9 }
        if name.contains("pro") { return 307e9 }
        return 120e9
    }

    var usedFraction: Double {
        guard physicalMemory > 0 else { return 0 }
        return 1 - Double(availableMemory) / Double(physicalMemory)
    }

    static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        return String(cString: buffer)
    }

    /// frei + inaktiv + löschbar + spekulativ (wie „verfügbar“ in der Aktivitätsanzeige)
    static func availableMemoryBytes() -> UInt64 {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &stats) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }
        let page = UInt64(sysconf(_SC_PAGESIZE))
        let pages = UInt64(stats.free_count) + UInt64(stats.inactive_count) + UInt64(stats.purgeable_count)
            + UInt64(stats.speculative_count)
        return pages * page
    }
}
