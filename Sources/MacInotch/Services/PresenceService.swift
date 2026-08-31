import AppKit
import Darwin

struct Presence: Equatable {
    var claudeApp = false
    var claudeCode = false
    var chatgpt = false
    var spotify = false

    var claude: Bool { claudeApp || claudeCode }

    var claudeDetail: String {
        switch (claudeApp, claudeCode) {
        case (true, true):  return "app + code"
        case (true, false): return "app"
        case (false, true): return "code"
        default:            return "off"
        }
    }
}

@MainActor
final class PresenceService {
    private weak var state: NotchState?
    private var timer: Timer?

    init(state: NotchState) { self.state = state }

    func start(interval: TimeInterval = 4) {
        tick()
        let t = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() { timer?.invalidate(); timer = nil }

    private func tick() {
        var p = Presence()
        let apps = NSWorkspace.shared.runningApplications
        for a in apps {
            guard let id = a.bundleIdentifier?.lowercased() else { continue }
            if id.contains("anthropic") || id.contains("claude") { p.claudeApp = true }
            if id.contains("openai") || id.contains("chatgpt") { p.chatgpt = true }
            if id == "com.spotify.client" { p.spotify = true }
        }
        p.claudeCode = Self.processExists(named: "claude")

        if p != state?.presence { state?.presence = p }
    }

    nonisolated static func processExists(named name: String) -> Bool {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0]
        var size = 0
        guard sysctl(&mib, 4, nil, &size, nil, 0) == 0, size > 0 else { return false }

        let count = size / MemoryLayout<kinfo_proc>.stride
        var procs = [kinfo_proc](repeating: kinfo_proc(), count: count + 16)
        size = procs.count * MemoryLayout<kinfo_proc>.stride
        guard sysctl(&mib, 4, &procs, &size, nil, 0) == 0 else { return false }

        let actual = size / MemoryLayout<kinfo_proc>.stride
        for i in 0..<min(actual, procs.count) {
            var comm = procs[i].kp_proc.p_comm
            let found = withUnsafeBytes(of: &comm) { raw -> Bool in
                guard let base = raw.baseAddress else { return false }
                return String(cString: base.assumingMemoryBound(to: CChar.self)) == name
            }
            if found { return true }
        }
        return false
    }
}
