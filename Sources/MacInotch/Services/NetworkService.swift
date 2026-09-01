import CoreWLAN
import Foundation
import Network

struct NetworkSnapshot: Equatable {
    var ssid: String = ""
    var interface: String = ""
    var connected: Bool = false
    var expensive: Bool = false
    var constrained: Bool = false
    var vpnName: String = ""

    var onVPN: Bool { !vpnName.isEmpty }

    var symbol: String {
        if !connected { return "wifi.slash" }
        if expensive { return "personalhotspot" }
        switch interface {
        case "wired": return "cable.connector"
        case "wifi": return "wifi"
        default: return "network"
        }
    }

    var label: String {
        if !connected { return "Offline" }
        if !ssid.isEmpty { return ssid }
        switch interface {
        case "wired": return "Ethernet"
        case "wifi": return "Wi-Fi"
        default: return "Online"
        }
    }

    var detail: String {
        var parts: [String] = []
        if expensive { parts.append("hotspot") }
        if constrained { parts.append("low data") }
        if onVPN { parts.append(vpnName) }
        return parts.joined(separator: ", ")
    }
}

@MainActor
final class NetworkService: ObservableObject {
    static let shared = NetworkService()

    @Published private(set) var snapshot = NetworkSnapshot()

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "io.macinotch.network")
    private var timer: Timer?
    private var started = false

    private init() {}

    func start() {
        guard !started else { return }
        started = true

        monitor.pathUpdateHandler = { path in
            let connected = path.status == .satisfied
            let expensive = path.isExpensive
            let constrained = path.isConstrained
            let interface: String
            if path.usesInterfaceType(.wiredEthernet) { interface = "wired" }
            else if path.usesInterfaceType(.wifi) { interface = "wifi" }
            else if path.usesInterfaceType(.cellular) { interface = "cellular" }
            else { interface = "other" }

            Task { @MainActor in
                NetworkService.shared.applyPath(connected: connected,
                                                expensive: expensive,
                                                constrained: constrained,
                                                interface: interface)
            }
        }
        monitor.start(queue: queue)

        timer = Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { _ in
            Task { @MainActor in NetworkService.shared.refreshSlowFields() }
        }
        refreshSlowFields()
    }

    func stop() {
        monitor.cancel()
        timer?.invalidate()
        timer = nil
        started = false
    }

    private func applyPath(connected: Bool, expensive: Bool,
                           constrained: Bool, interface: String) {
        var next = snapshot
        next.connected = connected
        next.expensive = expensive
        next.constrained = constrained
        next.interface = interface
        if next != snapshot { snapshot = next }
        refreshSlowFields()
    }

    private func refreshSlowFields() {
        var next = snapshot
        next.ssid = CWWiFiClient.shared().interface()?.ssid() ?? ""
        next.vpnName = Self.activeVPN()
        if next != snapshot { snapshot = next }
    }

    static func activeVPN() -> String {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/scutil")
        task.arguments = ["--nc", "list"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        guard (try? task.run()) != nil else { return "" }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()

        for line in String(decoding: data, as: UTF8.self).split(separator: "\n") {
            guard line.contains("(Connected)") else { continue }
            guard let open = line.range(of: "\"", options: .backwards,
                                        range: line.startIndex..<line.endIndex) else {
                continue
            }
            let head = line[line.startIndex..<open.lowerBound]
            guard let start = head.range(of: "\"", options: .backwards) else { continue }
            return String(head[start.upperBound...])
        }
        return ""
    }
}
