import Foundation
import AppKit

@MainActor
final class FanControlClient: ObservableObject {
    static let shared = FanControlClient()

    static let socketPath = "/var/run/macinotch-fand.sock"
    static let helperPath = "/usr/local/libexec/notchfand"
    static let plistPath = "/Library/LaunchDaemons/io.macinotch.fand.plist"
    static let label = "io.macinotch.fand"

    @Published private(set) var installed = false
    @Published private(set) var reachable = false
    @Published private(set) var busy = false
    @Published private(set) var lastError: String?

    @Published private(set) var holds: [Int: Int] = [:]

    private var pollTimer: Timer?

    private init() {
        refresh()
        let t = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        RunLoop.main.add(t, forMode: .common)
        pollTimer = t
    }

    var hasActiveOverride: Bool { !holds.isEmpty }

    func refresh() {
        installed = FileManager.default.fileExists(atPath: Self.helperPath)
        guard let reply = send(["cmd": "status"]) else {
            reachable = false
            holds = [:]
            return
        }
        reachable = true
        var next: [Int: Int] = [:]
        for f in (reply["fans"] as? [[String: Any]] ?? []) {
            if let i = f["index"] as? Int, let h = f["holdsFor"] as? Int, h > 0 { next[i] = h }
        }
        if next != holds { holds = next }
    }

    @discardableResult
    func set(fan: Int, percent: Double, minutes: Double) -> Bool {
        let reply = send(["cmd": "set", "fan": fan, "percent": percent,
                          "seconds": minutes * 60])
        let ok = (reply?["ok"] as? Bool) ?? false
        if ok {
            lastError = nil
        } else {
            lastError = (reply?["message"] as? String)
                ?? (reply?["error"] as? String)
                ?? "helper not reachable"
        }
        refresh()
        return ok
    }

    @discardableResult
    func setAll(percent: Double, minutes: Double) -> Bool {
        var anySucceeded = false
        for fan in NotchState.shared.fans.fans {
            if set(fan: fan.index, percent: percent, minutes: minutes) { anySucceeded = true }
        }
        if !anySucceeded, let reason = lastError {
            var p = NotchPayload()
            p.source = "system"
            p.kind = "error"
            p.key = "fan-failed"
            p.title = "Fan control refused"
            p.body = reason
            p.timeout = 8
            NotchState.shared.handle(p)
        }
        return anySucceeded
    }

    @discardableResult
    func auto(fan: Int) -> Bool {
        let reply = send(["cmd": "auto", "fan": fan])
        let ok = (reply?["ok"] as? Bool) ?? false
        lastError = ok ? nil : (reply?["error"] as? String ?? "helper not reachable")
        refresh()
        return ok
    }

    func autoAll() {
        _ = send(["cmd": "auto"])
        lastError = nil
        refresh()
    }

    private func send(_ payload: [String: Any]) -> [String: Any]? {
        guard let data = try? JSONSerialization.data(withJSONObject: payload) else { return nil }

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        defer { close(fd) }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)

        let pathCapacity = MemoryLayout.size(ofValue: addr.sun_path)
        _ = withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
            Self.socketPath.withCString { src in
                strncpy(UnsafeMutableRawPointer(ptr).assumingMemoryBound(to: CChar.self),
                        src, pathCapacity - 1)
            }
        }

        var tv = timeval(tv_sec: 1, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

        let len = socklen_t(MemoryLayout<sockaddr_un>.size)
        let connected = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, len) }
        }
        guard connected == 0 else { return nil }

        var out = data
        out.append(0x0A)
        let sent = out.withUnsafeBytes { Darwin.send(fd, $0.baseAddress, out.count, 0) }
        guard sent > 0 else { return nil }

        var buffer = [UInt8](repeating: 0, count: 8192)
        let n = recv(fd, &buffer, buffer.count, 0)
        guard n > 0 else { return nil }
        return try? JSONSerialization.jsonObject(with: Data(buffer[0..<n])) as? [String: Any]
    }

    func install() {
        guard let source = helperInBundle() else {
            lastError = "helper binary missing from the app bundle"
            return
        }

        let plist = [
            "<?xml version=\"1.0\" encoding=\"UTF-8\"?>",
            "<plist version=\"1.0\"><dict>",
            "<key>Label</key><string>\(Self.label)</string>",
            "<key>ProgramArguments</key><array>"
                + "<string>\(Self.helperPath)</string></array>",
            "<key>RunAtLoad</key><true/>",
            "<key>KeepAlive</key><true/>",
            "</dict></plist>",
        ].joined(separator: "")

        let steps = [
            "/bin/mkdir -p /usr/local/libexec",
            "/bin/cp '\(source.path)' '\(Self.helperPath)'",
            "/usr/sbin/chown root:wheel '\(Self.helperPath)'",
            "/bin/chmod 755 '\(Self.helperPath)'",
            "/bin/echo '\(plist.replacingOccurrences(of: "'", with: "'\\''"))' > '\(Self.plistPath)'",
            "/usr/sbin/chown root:wheel '\(Self.plistPath)'",
            "/bin/chmod 644 '\(Self.plistPath)'",
            "/bin/launchctl bootout system/\(Self.label) 2>/dev/null || true",
            "/bin/launchctl bootstrap system '\(Self.plistPath)'",
        ]
        runPrivileged(steps.joined(separator: " && "), purpose: "install the fan helper")
    }

    func uninstall() {
        let steps = [
            "/bin/launchctl bootout system/\(Self.label) 2>/dev/null || true",
            "/bin/rm -f '\(Self.plistPath)' '\(Self.helperPath)' '\(Self.socketPath)'",
        ]
        runPrivileged(steps.joined(separator: "; "), purpose: "remove the fan helper")
    }

    private func helperInBundle() -> URL? {
        let candidates = [
            Bundle.main.executableURL?.deletingLastPathComponent()
                .appendingPathComponent("notchfand"),
            Bundle.main.url(forAuxiliaryExecutable: "notchfand"),
        ].compactMap { $0 }
        return candidates.first { FileManager.default.fileExists(atPath: $0.path) }
    }

    private func runPrivileged(_ command: String, purpose: String) {
        busy = true
        let escaped = command
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let source = "do shell script \"\(escaped)\" with administrator privileges"

        var error: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&error)
        if let error {

            let code = error[NSAppleScript.errorNumber] as? Int ?? 0
            lastError = code == -128 ? nil : "Could not \(purpose)."
        } else {
            lastError = nil
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            self.busy = false
            self.refresh()
        }
    }
}
