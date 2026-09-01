import AppKit
import Foundation

@MainActor
final class AlertService: ObservableObject {
    static let shared = AlertService()

    private var timer: Timer?
    private var fired: Set<String> = []
    private var hotSince: Date?
    private var busySince: Date?
    private var busyName: String = ""
    private var lastNetwork: NetworkSnapshot?

    private init() {}

    func start(interval: TimeInterval = 15) {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { _ in
            Task { @MainActor in AlertService.shared.tick() }
        }
    }

    func stop() { timer?.invalidate(); timer = nil }

    private func send(_ key: String, title: String, body: String,
                      kind: String, source: NotchSource = .system,
                      actions: [NotchAction] = []) {
        var p = NotchPayload()
        p.source = source.rawValue
        p.kind = kind
        p.key = key
        p.title = title
        p.body = body
        p.timeout = 12
        p.sound = true
        if !actions.isEmpty { p.actions = actions }
        NotchState.shared.handle(p)
    }

    private func once(_ key: String, _ body: () -> Void) {
        guard !fired.contains(key) else { return }
        fired.insert(key)
        body()
    }

    private func clear(_ key: String) { fired.remove(key) }

    private func tick() {
        let prefs = Prefs.shared.d
        let state = NotchState.shared

        if prefs.alertDisk { checkDisk(state) }
        if prefs.alertRunaway { checkRunaway(state) }
        if prefs.alertThermal { checkThermal(state) }
        if prefs.alertBattery { checkBattery(state) }
        if prefs.alertNetwork { checkNetwork() }
    }

    private func checkDisk(_ state: NotchState) {
        let used = state.stats.diskUsedFraction
        guard state.stats.diskTotal > 1 else { return }
        let free = String(format: "%.0f GB free", state.stats.diskFreeGB)

        if used >= 0.95 {
            once("disk-95") {
                send("disk", title: "Disk is \(Int(used * 100))% full",
                     body: "\(free). Things will start failing soon.", kind: "error")
            }
        } else if used >= 0.85 {
            once("disk-85") {
                send("disk", title: "Disk is \(Int(used * 100))% full",
                     body: free, kind: "warning")
            }
        }
        if used < 0.93 { clear("disk-95") }
        if used < 0.82 { clear("disk-85") }
    }

    private func checkRunaway(_ state: NotchState) {
        guard let top = state.topCPU, top.cpu >= 85 else {
            busySince = nil
            busyName = ""
            clear("runaway-\(busyName)")
            return
        }

        if busyName != top.name {
            busyName = top.name
            busySince = Date()
            return
        }
        guard let since = busySince,
              Date().timeIntervalSince(since) >= 120 else { return }

        once("runaway-\(top.name)") {
            send("runaway", title: "\(top.name) is pinning the CPU",
                 body: String(format: "%.0f%% for two minutes", top.cpu),
                 kind: "warning",
                 actions: [NotchAction(label: "Show Activity Monitor",
                                       url: "file:///System/Applications/Utilities/"
                                          + "Activity%20Monitor.app")])
        }
    }

    private func checkThermal(_ state: NotchState) {
        let pressure = state.stats.thermalPressure
        let hot = state.temps.available && state.temps.soc >= 95

        if pressure >= 2 || hot {
            if hotSince == nil { hotSince = Date() }
            guard let since = hotSince,
                  Date().timeIntervalSince(since) >= 60 else { return }
            once("thermal") {
                let detail = state.temps.available
                    ? String(format: "%.0f C on the SoC", state.temps.soc)
                    : state.stats.thermalLabel
                send("thermal", title: "The machine is throttling",
                     body: detail, kind: "warning")
            }
        } else {
            hotSince = nil
            clear("thermal")
        }
    }

    private func checkBattery(_ state: NotchState) {
        let battery = state.battery
        guard battery.present, battery.healthPercent > 0 else { return }

        if battery.healthPercent <= 80 {
            once("battery-health") {
                send("battery", title: "Battery health is \(battery.healthPercent)%",
                     body: "\(battery.cycleCount) cycles. Apple treats 80% as the "
                         + "end of the warranty window.", kind: "info")
            }
        }
        if !battery.isPlugged && battery.percent <= 10 {
            once("battery-low") {
                send("battery", title: "Battery at \(battery.percent)%",
                     body: battery.minutesRemaining.map { "About \($0) minutes left" }
                         ?? "Plug in soon", kind: "warning")
            }
        }
        if battery.isPlugged || battery.percent > 15 { clear("battery-low") }
    }

    private func checkNetwork() {
        let now = NetworkService.shared.snapshot
        defer { lastNetwork = now }
        guard let previous = lastNetwork else { return }

        if now.expensive && !previous.expensive {
            send("network", title: "You are on a metered connection",
                 body: "\(now.label). Large downloads will use your allowance.",
                 kind: "warning")
        }
        if now.connected && previous.connected && now.ssid != previous.ssid
            && !now.ssid.isEmpty {
            send("network", title: "Joined \(now.ssid)",
                 body: now.detail.isEmpty ? "Wi-Fi network changed" : now.detail,
                 kind: "info")
        }
        if now.onVPN != previous.onVPN {
            send("network", title: now.onVPN ? "VPN connected" : "VPN disconnected",
                 body: now.onVPN ? now.vpnName : "Traffic is no longer tunnelled",
                 kind: now.onVPN ? "success" : "warning")
        }
        if !now.connected && previous.connected {
            send("network", title: "Offline", body: "No network route",
                 kind: "error")
        }
    }
}
