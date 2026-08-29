import Foundation
import Darwin

struct SystemStats: Equatable {
    var cpuUser: Double = 0
    var cpuSystem: Double = 0
    var cpuTotal: Double = 0
    var memUsed: UInt64 = 0
    var memTotal: UInt64 = 1
    var memPressure: Double = 0
    var swapUsed: UInt64 = 0
    var coreCount: Int = 1
    var netDown: Double = 0
    var netUp: Double = 0
    var diskFree: UInt64 = 0
    var diskTotal: UInt64 = 1
    var thermalPressure: Int = 0

    var memUsedGB: Double { Double(memUsed) / 1_073_741_824 }
    var memTotalGB: Double { Double(memTotal) / 1_073_741_824 }
    var swapUsedGB: Double { Double(swapUsed) / 1_073_741_824 }
    var diskFreeGB: Double { Double(diskFree) / 1_073_741_824 }
    var diskTotalGB: Double { Double(diskTotal) / 1_073_741_824 }
    var diskUsedFraction: Double {
        diskTotal > 0 ? 1 - Double(diskFree) / Double(diskTotal) : 0
    }

    var thermalLabel: String {
        switch thermalPressure {
        case 1: return "Fair"
        case 2: return "Serious"
        case 3: return "Critical"
        default: return "Nominal"
        }
    }

    static func rate(_ bytesPerSecond: Double) -> String {
        switch bytesPerSecond {
        case ..<1024:            return String(format: "%.0f B/s", bytesPerSecond)
        case ..<1_048_576:       return String(format: "%.0f KB/s", bytesPerSecond / 1024)
        default:                 return String(format: "%.1f MB/s", bytesPerSecond / 1_048_576)
        }
    }
}

@MainActor
final class SystemStatsService {
    private weak var state: NotchState?
    private var timer: Timer?
    private var previous: [UInt32] = []
    private var lastNet: (down: UInt64, up: UInt64, at: Date)?
    private var diskCheckedAt: Date = .distantPast

    init(state: NotchState) { self.state = state }

    func start(interval: TimeInterval = 2.0) {
        tick()
        let t = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() { timer?.invalidate(); timer = nil }

    private func tick() {
        var s = state?.stats ?? SystemStats()
        readCPU(into: &s)
        readMemory(into: &s)
        readNetwork(into: &s)
        readDisk(into: &s)

        switch ProcessInfo.processInfo.thermalState {
        case .nominal:  s.thermalPressure = 0
        case .fair:     s.thermalPressure = 1
        case .serious:  s.thermalPressure = 2
        case .critical: s.thermalPressure = 3
        @unknown default: s.thermalPressure = 0
        }
        if s != state?.stats { state?.stats = s }
    }

    private func readCPU(into s: inout SystemStats) {
        var count: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0

        let result = host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO,
                                         &count, &info, &infoCount)
        guard result == KERN_SUCCESS, let info else { return }
        defer {
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info),
                          vm_size_t(Int(infoCount) * MemoryLayout<integer_t>.stride))
        }

        s.coreCount = Int(count)
        let ticks = (0..<Int(infoCount)).map { UInt32(bitPattern: info[$0]) }

        guard previous.count == ticks.count else { previous = ticks; return }

        var user = 0.0, sys = 0.0, idle = 0.0, nice = 0.0
        let states = Int(CPU_STATE_MAX)
        for core in 0..<Int(count) {
            let base = core * states
            func delta(_ i: Int) -> Double {
                Double(ticks[base + i] &- previous[base + i])
            }
            user += delta(Int(CPU_STATE_USER))
            sys  += delta(Int(CPU_STATE_SYSTEM))
            idle += delta(Int(CPU_STATE_IDLE))
            nice += delta(Int(CPU_STATE_NICE))
        }
        previous = ticks

        let total = user + sys + idle + nice
        guard total > 0 else { return }
        s.cpuUser = (user + nice) / total
        s.cpuSystem = sys / total
        s.cpuTotal = min(1, (user + nice + sys) / total)
    }

    private func readNetwork(into s: inout SystemStats) {
        var down: UInt64 = 0, up: UInt64 = 0
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return }
        defer { freeifaddrs(head) }

        for ptr in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let ifa = ptr.pointee
            guard ifa.ifa_addr?.pointee.sa_family == UInt8(AF_LINK) else { continue }
            let name = String(cString: ifa.ifa_name)

            if name.hasPrefix("lo") || name.hasPrefix("bridge") || name.hasPrefix("utun") {
                continue
            }
            guard let data = ifa.ifa_data?.assumingMemoryBound(to: if_data.self) else { continue }
            down += UInt64(data.pointee.ifi_ibytes)
            up += UInt64(data.pointee.ifi_obytes)
        }

        let now = Date()
        if let last = lastNet {
            let dt = now.timeIntervalSince(last.at)
            if dt > 0.2 {

                s.netDown = down >= last.down ? Double(down - last.down) / dt : 0
                s.netUp = up >= last.up ? Double(up - last.up) / dt : 0
                lastNet = (down, up, now)
            }
        } else {
            lastNet = (down, up, now)
        }
    }

    private func readDisk(into s: inout SystemStats) {

        if Date().timeIntervalSince(diskCheckedAt) < 60, s.diskTotal > 1 { return }
        diskCheckedAt = Date()
        let url = URL(fileURLWithPath: "/")
        guard let vals = try? url.resourceValues(forKeys: [
            .volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey
        ]) else { return }
        if let free = vals.volumeAvailableCapacityForImportantUsage { s.diskFree = UInt64(free) }
        if let total = vals.volumeTotalCapacity { s.diskTotal = UInt64(total) }
    }

    private func readMemory(into s: inout SystemStats) {
        s.memTotal = ProcessInfo.processInfo.physicalMemory

        var stats = vm_statistics64()
        var size = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64>.stride / MemoryLayout<integer_t>.stride)
        let kr = withUnsafeMutablePointer(to: &stats) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(size)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &size)
            }
        }
        if kr == KERN_SUCCESS {
            let page = UInt64(vm_kernel_page_size)

            let used = (UInt64(stats.active_count)
                        + UInt64(stats.wire_count)
                        + UInt64(stats.compressor_page_count)) * page
            s.memUsed = used
            s.memPressure = s.memTotal > 0 ? min(1, Double(used) / Double(s.memTotal)) : 0
        }

        var xsw = xsw_usage()
        var xswSize = MemoryLayout<xsw_usage>.size
        if sysctlbyname("vm.swapusage", &xsw, &xswSize, nil, 0) == 0 {
            s.swapUsed = xsw.xsu_used
        }
    }
}
