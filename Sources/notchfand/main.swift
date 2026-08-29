import Foundation
import SMCKit

let socketPath = "/var/run/macinotch-fand.sock"
let maxHoldSeconds: Double = 3600
let thermalCeiling: Double = 90

struct Fan {
    var index: Int
    var minRPM: Double
    var maxRPM: Double
}

func discoverFans() -> [Fan] {
    guard let count = SMC.shared.read("FNum"), count > 0 else { return [] }
    var fans: [Fan] = []
    for i in 0..<Int(min(count, 8)) {
        guard let mn = SMC.shared.read("F\(i)Mn"),
              let mx = SMC.shared.read("F\(i)Mx"), mx > mn else { continue }
        fans.append(Fan(index: i, minRPM: mn, maxRPM: mx))
    }
    return fans
}

final class Controller: @unchecked Sendable {
    private let lock = NSLock()
    private var fans: [Fan] = []

    private var deadlines: [Int: Date] = [:]
    private var targets: [Int: Double] = [:]
    private var originalMinimum: [Int: Double] = [:]
    private var strategy: [Int: String] = [:]

    init() { fans = discoverFans() }

    func fan(_ index: Int) -> Fan? { fans.first { $0.index == index } }

    struct Outcome {
        var ok: Bool
        var message: String
        var strategy: String
    }

    func set(index: Int, fraction: Double, seconds: Double) -> Outcome {
        guard let f = fan(index) else {
            return Outcome(ok: false, message: "no such fan", strategy: "none")
        }
        let clampedSeconds = min(max(seconds, 1), maxHoldSeconds)
        let frac = min(max(fraction, 0), 1)
        let rpm = f.minRPM + (f.maxRPM - f.minRPM) * frac

        lock.lock()
        defer { lock.unlock() }

        let modeOK = SMC.shared.writeUInt8("F\(index)Md", 1)
        let targetOK = SMC.shared.writeFloat("F\(index)Tg", Float(rpm))

        if modeOK && targetOK {
            deadlines[index] = Date().addingTimeInterval(clampedSeconds)
            targets[index] = rpm
            strategy[index] = "target"
            return Outcome(ok: true,
                           message: "fan \(index) -> \(Int(rpm)) rpm for \(Int(clampedSeconds))s",
                           strategy: "target")
        }

        _ = SMC.shared.writeUInt8("F\(index)Md", 0)

        if originalMinimum[index] == nil { originalMinimum[index] = f.minRPM }
        if SMC.shared.writeFloat("F\(index)Mn", Float(rpm)) {
            deadlines[index] = Date().addingTimeInterval(clampedSeconds)
            targets[index] = rpm
            strategy[index] = "minimum"
            return Outcome(ok: true,
                           message: "fan \(index) floor raised to \(Int(rpm)) rpm "
                                  + "for \(Int(clampedSeconds))s",
                           strategy: "minimum")
        }

        return Outcome(ok: false,
                       message: "SMC refused both target and minimum writes "
                              + "(mode \(modeOK ? "ok" : "refused"), "
                              + "target \(targetOK ? "ok" : "refused"))",
                       strategy: "none")
    }

    @discardableResult
    func auto(index: Int) -> Outcome {
        lock.lock(); defer { lock.unlock() }
        deadlines[index] = nil
        targets[index] = nil
        let used = strategy[index] ?? "target"
        strategy[index] = nil

        if used == "minimum", let original = originalMinimum[index] {
            _ = SMC.shared.writeFloat("F\(index)Mn", Float(original))
            originalMinimum[index] = nil
        }
        let ok = SMC.shared.writeUInt8("F\(index)Md", 0)
        return Outcome(ok: ok,
                       message: ok ? "fan \(index) -> automatic" : "SMC refused the write",
                       strategy: used)
    }

    func autoAll() {
        for f in fans { _ = auto(index: f.index) }
    }

    func sweep() {
        let hot = socTemperature().map { $0 >= thermalCeiling } ?? false
        let now = Date()

        lock.lock()
        let expired = deadlines.filter { hot || $0.value <= now }.map(\.key)
        let live = deadlines.filter { !hot && $0.value > now }
        let wanted = targets
        lock.unlock()

        for index in expired { auto(index: index) }

        lock.lock()
        let modes = strategy
        lock.unlock()

        for (index, _) in live {
            guard let rpm = wanted[index] else { continue }
            if modes[index] == "minimum" {
                _ = SMC.shared.writeFloat("F\(index)Mn", Float(rpm))
            } else {
                _ = SMC.shared.writeUInt8("F\(index)Md", 1)
                _ = SMC.shared.writeFloat("F\(index)Tg", Float(rpm))
            }
        }
    }

    func statusJSON() -> String {
        lock.lock()
        let snapshot = deadlines
        lock.unlock()
        let items: [[String: Any]] = fans.map { f in
            [
                "index": f.index,
                "rpm": Int(SMC.shared.read("F\(f.index)Ac") ?? 0),
                "min": Int(f.minRPM),
                "max": Int(f.maxRPM),
                "target": Int(SMC.shared.read("F\(f.index)Tg") ?? 0),
                "forced": (SMC.shared.read("F\(f.index)Md") ?? 0) >= 1,
                "holdsFor": snapshot[f.index].map { Int(max(0, $0.timeIntervalSinceNow)) } ?? 0,
            ]
        }
        let obj: [String: Any] = ["ok": true, "fans": items,
                                  "soc": socTemperature() ?? 0]
        guard let d = try? JSONSerialization.data(withJSONObject: obj) else { return "{}" }
        return String(decoding: d, as: UTF8.self)
    }
}

func socTemperature() -> Double? {
    for key in ["Tp0C", "Tp01", "TC0P", "Ts0P"] {
        if let v = SMC.shared.read(key), v > 1, v < 130 { return v }
    }
    return nil
}

guard getuid() == 0 else {
    FileHandle.standardError.write(Data("notchfand must run as root\n".utf8))
    exit(1)
}
guard SMC.shared.open() else {
    FileHandle.standardError.write(Data("cannot open AppleSMC\n".utf8))
    exit(1)
}

let controller = Controller()

func shutdown(_ code: Int32) -> Never {
    controller.autoAll()
    unlink(socketPath)
    exit(code)
}
for sig in [SIGTERM, SIGINT, SIGHUP] {
    signal(sig, SIG_IGN)
    let src = DispatchSource.makeSignalSource(signal: sig, queue: .main)
    src.setEventHandler { shutdown(0) }
    src.resume()

    _ = Unmanaged.passRetained(src as AnyObject)
}
atexit { controller.autoAll() }

unlink(socketPath)
let fd = socket(AF_UNIX, SOCK_STREAM, 0)
guard fd >= 0 else { exit(1) }

var addr = sockaddr_un()
addr.sun_family = sa_family_t(AF_UNIX)
let pathCapacity = MemoryLayout.size(ofValue: addr.sun_path)
_ = withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
    socketPath.withCString { src in
        strncpy(UnsafeMutableRawPointer(ptr).assumingMemoryBound(to: CChar.self),
                src, pathCapacity - 1)
    }
}
let addrLen = socklen_t(MemoryLayout<sockaddr_un>.size)
let bound = withUnsafePointer(to: &addr) {
    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, addrLen) }
}
guard bound == 0, listen(fd, 8) == 0 else { exit(1) }

chmod(socketPath, 0o660)
if let admin = getgrnam("admin") { _ = chown(socketPath, 0, admin.pointee.gr_gid) }

let sweeper = DispatchSource.makeTimerSource(queue: .global())
sweeper.schedule(deadline: .now() + 1, repeating: 2)
sweeper.setEventHandler { controller.sweep() }
sweeper.resume()

func encode(_ outcome: Controller.Outcome) -> String {
    let obj: [String: Any] = ["ok": outcome.ok,
                              "message": outcome.message,
                              "strategy": outcome.strategy]
    guard let data = try? JSONSerialization.data(withJSONObject: obj) else {
        return #"{"ok":false}"#
    }
    return String(decoding: data, as: UTF8.self)
}

func handle(_ line: String) -> String {
    guard let data = line.data(using: .utf8),
          let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let cmd = obj["cmd"] as? String else { return #"{"ok":false,"error":"bad command"}"# }

    switch cmd {
    case "status":
        return controller.statusJSON()
    case "auto":
        guard let fan = obj["fan"] as? Int else { controller.autoAll(); return #"{"ok":true}"# }
        let outcome = controller.auto(index: fan)
        return encode(outcome)
    case "set":
        guard let fan = obj["fan"] as? Int,
              let percent = obj["percent"] as? Double else {
            return #"{"ok":false,"error":"set needs fan and percent"}"#
        }
        let seconds = obj["seconds"] as? Double ?? 300
        return encode(controller.set(index: fan, fraction: percent, seconds: seconds))
    default:
        return #"{"ok":false,"error":"unknown command"}"#
    }
}

DispatchQueue.global().async {
    while true {
        let client = accept(fd, nil, nil)
        guard client >= 0 else { continue }
        DispatchQueue.global().async {
            defer { close(client) }
            var buffer = [UInt8](repeating: 0, count: 4096)
            let n = recv(client, &buffer, buffer.count, 0)
            guard n > 0 else { return }
            let request = String(decoding: buffer[0..<n], as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            var response = handle(request)
            response += "\n"
            _ = response.withCString { send(client, $0, strlen($0), 0) }
        }
    }
}

dispatchMain()
