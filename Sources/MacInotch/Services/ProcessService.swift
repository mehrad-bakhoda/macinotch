import Foundation

struct ProcessUsage: Equatable {
    var pid: Int
    var name: String
    var cpu: Double
    var memoryGB: Double
}

final class ProcessService: @unchecked Sendable {
    private let queue = DispatchQueue(label: "io.macinotch.processes")
    private var timer: DispatchSourceTimer?
    private let onUpdate: @Sendable (ProcessUsage?, ProcessUsage?) -> Void

    private let shouldSample: @Sendable () -> Bool

    init(shouldSample: @escaping @Sendable () -> Bool,
         onUpdate: @escaping @Sendable (ProcessUsage?, ProcessUsage?) -> Void) {
        self.shouldSample = shouldSample
        self.onUpdate = onUpdate
    }

    func start(interval: TimeInterval = 4) {
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + 1, repeating: interval)
        t.setEventHandler { [weak self] in self?.tick() }
        t.resume()
        timer = t
    }

    func stop() { timer?.cancel(); timer = nil }

    private func tick() {
        guard shouldSample() else { return }
        let rows = Self.sample()
        let topCPU = rows.max { $0.cpu < $1.cpu }
        let topMemory = rows.max { $0.memoryGB < $1.memoryGB }
        onUpdate(topCPU, topMemory)
    }

    private static func sample() -> [ProcessUsage] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")

        process.arguments = ["-Aceo", "pid,pcpu,rss,comm", "-r"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return [] }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        var out: [ProcessUsage] = []
        let lines = String(decoding: data, as: UTF8.self)
            .split(separator: "\n").dropFirst().prefix(40)

        for line in lines {
            let parts = line.split(separator: " ", omittingEmptySubsequences: true)
            guard parts.count >= 4,
                  let pid = Int(parts[0]),
                  let cpu = Double(parts[1]),
                  let rssKB = Double(parts[2]) else { continue }
            let name = parts[3...].joined(separator: " ")

            guard name != "ps" else { continue }
            out.append(ProcessUsage(pid: pid, name: name,
                                    cpu: cpu, memoryGB: rssKB / 1_048_576))
        }
        return out
    }
}
