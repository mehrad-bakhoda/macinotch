import Foundation
import SMCKit

struct FanReading: Equatable, Identifiable {
    var index: Int
    var rpm: Double = 0
    var minRPM: Double = 0
    var maxRPM: Double = 0
    var targetRPM: Double = 0
    var forced: Bool = false

    var id: Int { index }
    var label: String { "Fan \(index + 1)" }

    var fraction: Double {
        let span = maxRPM - minRPM
        guard span > 0 else { return 0 }
        return min(1, max(0, (rpm - minRPM) / span))
    }

    var isStopped: Bool { rpm < 1 }

    var isAtFloor: Bool { !isStopped && rpm <= minRPM * 1.05 }
}

struct FanSnapshot: Equatable {
    var fans: [FanReading] = []
    var systemWatts: Double = 0
    var available: Bool = false

    var controllable: Bool = false
}

final class FanService: @unchecked Sendable {
    private let queue = DispatchQueue(label: "io.macinotch.fans")
    private var timer: DispatchSourceTimer?
    private let onUpdate: @Sendable (FanSnapshot) -> Void

    init(onUpdate: @escaping @Sendable (FanSnapshot) -> Void) {
        self.onUpdate = onUpdate
    }

    private var emptyPolls = 0
    private var interval: TimeInterval = 3

    func start(interval: TimeInterval = 3) {
        self.interval = interval
        schedule(interval)
    }

    private func schedule(_ every: TimeInterval) {
        timer?.cancel()
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now(), repeating: every)
        t.setEventHandler { [weak self] in self?.tick() }
        t.resume()
        timer = t
    }

    private func backOffIfIdle(_ snapshot: FanSnapshot) {
        guard snapshot.fans.isEmpty else {
            if emptyPolls > 0 { emptyPolls = 0; schedule(interval) }
            return
        }
        emptyPolls += 1
        guard emptyPolls == 6 else { return }
        if snapshot.systemWatts > 0 {
            schedule(30)
        } else {
            timer?.cancel()
            timer = nil
        }
    }

    func stop() { timer?.cancel(); timer = nil }

    private func tick() {
        var snap = FanSnapshot()
        guard let count = SMC.shared.read("FNum"), count > 0 else {
            snap.systemWatts = SMC.shared.read("PSTR") ?? 0
            backOffIfIdle(snap)
            onUpdate(snap)
            return
        }
        snap.available = true

        for i in 0..<Int(min(count, 8)) {
            var fan = FanReading(index: i)
            fan.rpm = SMC.shared.read("F\(i)Ac") ?? 0
            fan.minRPM = SMC.shared.read("F\(i)Mn") ?? 0
            fan.maxRPM = SMC.shared.read("F\(i)Mx") ?? 0
            fan.targetRPM = SMC.shared.read("F\(i)Tg") ?? 0
            fan.forced = (SMC.shared.read("F\(i)Md") ?? 0) >= 1

            guard fan.maxRPM > 0 else { continue }
            snap.fans.append(fan)
        }
        snap.systemWatts = SMC.shared.read("PSTR")
            ?? SMC.shared.read("PPBR") ?? 0

        backOffIfIdle(snap)
        onUpdate(snap)
    }
}

enum FanControl {

    static func clampedTarget(_ requested: Double, for fan: FanReading) -> Double {
        min(max(requested, fan.minRPM), fan.maxRPM)
    }

    static func probeWritable(fan: FanReading) -> Bool {
        guard getuid() == 0 else { return false }
        return SMC.shared.writeUInt8("F\(fan.index)Md", fan.forced ? 1 : 0)
    }
}
