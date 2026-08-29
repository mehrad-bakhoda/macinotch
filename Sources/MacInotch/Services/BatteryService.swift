import Foundation
import IOKit
import IOKit.ps

struct BatterySnapshot: Equatable {
    var percent: Int = 100
    var isCharging: Bool = false
    var isPlugged: Bool = false
    var minutesRemaining: Int? = nil
    var present: Bool = false
    var cycleCount: Int = 0
    var healthPercent: Int = 0

    var symbol: String {
        if isCharging || (isPlugged && percent >= 100) { return "battery.100percent.bolt" }
        switch percent {
        case 90...:  return "battery.100percent"
        case 60..<90: return "battery.75percent"
        case 35..<60: return "battery.50percent"
        case 12..<35: return "battery.25percent"
        default:      return "battery.0percent"
        }
    }

    var timeText: String? {
        guard let m = minutesRemaining, m > 0 else { return nil }
        return m >= 60 ? "\(m / 60)h \(m % 60)m" : "\(m)m"
    }
}

@MainActor
final class BatteryService {
    private weak var state: NotchState?
    private var timer: Timer?

    init(state: NotchState) { self.state = state }

    func start() {
        tick()
        let t = Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() { timer?.invalidate(); timer = nil }

    private var nudgedAt: Date = .distantPast

    private func tick() {
        guard let snap = Self.read() else { return }
        checkChargeLimit(snap)
        guard snap != state?.battery else { return }
        state?.battery = snap
    }

    private func checkChargeLimit(_ snap: BatterySnapshot) {
        let prefs = Prefs.shared.d
        guard prefs.batteryLimitNudge, snap.present, snap.isCharging,
              Double(snap.percent) >= prefs.batteryLimitPercent,
              Date().timeIntervalSince(nudgedAt) > 3600 else { return }
        nudgedAt = Date()

        var payload = NotchPayload()
        payload.source = "system"
        payload.kind = "warning"
        payload.key = "charge-limit"
        payload.title = "Battery at \(snap.percent)%"
        payload.body = "Unplug to keep the cells healthy"
        payload.timeout = 20
        NotchState.shared.handle(payload)
    }

    static func readHealth(into snap: inout BatterySnapshot) {
        let service = IOServiceGetMatchingService(kIOMainPortDefault,
                                                  IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return }
        defer { IOObjectRelease(service) }

        func property(_ key: String) -> Any? {
            IORegistryEntryCreateCFProperty(service, key as CFString,
                                            kCFAllocatorDefault, 0)?.takeRetainedValue()
        }
        snap.cycleCount = property("CycleCount") as? Int ?? 0

        let nested = property("BatteryData") as? [String: Any] ?? [:]
        func capacity(_ key: String) -> Int? {
            nested[key] as? Int ?? property(key) as? Int
        }

        let design = capacity("DesignCapacity") ?? 0
        let full = capacity("NominalChargeCapacity")
            ?? capacity("FullChargeCapacity")
            ?? capacity("AppleRawMaxCapacity") ?? 0

        if design > 0, full > 0 {
            snap.healthPercent = min(100, Int((Double(full) / Double(design) * 100).rounded()))
        }
    }

    static func read() -> BatterySnapshot? {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef]
        else { return nil }

        for ps in list {
            guard let d = IOPSGetPowerSourceDescription(blob, ps)?.takeUnretainedValue()
                    as? [String: Any] else { continue }
            guard let cap = d[kIOPSCurrentCapacityKey] as? Int,
                  let max = d[kIOPSMaxCapacityKey] as? Int, max > 0 else { continue }

            var s = BatterySnapshot()
            s.present = true
            s.percent = Int((Double(cap) / Double(max) * 100).rounded())
            s.isCharging = (d[kIOPSIsChargingKey] as? Bool) ?? false
            s.isPlugged = (d[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue
            let mins = s.isCharging
                ? (d[kIOPSTimeToFullChargeKey] as? Int ?? -1)
                : (d[kIOPSTimeToEmptyKey] as? Int ?? -1)
            s.minutesRemaining = mins > 0 ? mins : nil
            readHealth(into: &s)
            return s
        }
        return nil
    }
}
