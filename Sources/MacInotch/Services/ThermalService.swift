import Foundation

struct Temperatures: Equatable {
    var soc: Double = 0
    var socMax: Double = 0
    var gpu: Double = 0
    var battery: Double = 0
    var ssd: Double = 0
    var available: Bool = false

    var socLoad: Double { max(0, min(1, (soc - 30) / 65)) }

    static func format(_ celsius: Double, fahrenheit: Bool) -> String {
        guard celsius > 0 else { return "—" }
        let v = fahrenheit ? celsius * 9 / 5 + 32 : celsius
        return "\(Int(v.rounded()))°"
    }
}

final class ThermalService: @unchecked Sendable {

    private typealias CreateFn   = @convention(c) (CFAllocator?) -> Unmanaged<AnyObject>?
    private typealias MatchFn    = @convention(c) (AnyObject, CFDictionary) -> Int32
    private typealias ServicesFn = @convention(c) (AnyObject) -> Unmanaged<CFArray>?
    private typealias PropFn     = @convention(c) (AnyObject, CFString) -> Unmanaged<AnyObject>?
    private typealias EventFn    = @convention(c) (AnyObject, Int64, Int32, Int64) -> Unmanaged<AnyObject>?
    private typealias FloatFn    = @convention(c) (AnyObject, Int32) -> Double

    private static let temperatureType: Int64 = 15
    private static let usagePage = 0xff00
    private static let usage = 0x0005

    private struct Symbols {
        let create: CreateFn
        let setMatching: MatchFn
        let copyServices: ServicesFn
        let copyProperty: PropFn
        let copyEvent: EventFn
        let floatValue: FloatFn
    }

    private static let symbols: Symbols? = {
        guard let lib = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit",
                               RTLD_LAZY) else { return nil }
        func load<T>(_ name: String, _ type: T.Type) -> T? {
            guard let p = dlsym(lib, name) else { return nil }
            return unsafeBitCast(p, to: type)
        }
        guard let c = load("IOHIDEventSystemClientCreate", CreateFn.self),
              let m = load("IOHIDEventSystemClientSetMatching", MatchFn.self),
              let s = load("IOHIDEventSystemClientCopyServices", ServicesFn.self),
              let p = load("IOHIDServiceClientCopyProperty", PropFn.self),
              let e = load("IOHIDServiceClientCopyEvent", EventFn.self),
              let f = load("IOHIDEventGetFloatValue", FloatFn.self) else { return nil }
        return Symbols(create: c, setMatching: m, copyServices: s,
                       copyProperty: p, copyEvent: e, floatValue: f)
    }()

    private enum Group { case soc, gpu, battery, ssd }

    private let queue = DispatchQueue(label: "io.macinotch.thermal")
    private var client: AnyObject?
    private var sensors: [(service: AnyObject, group: Group)] = []
    private var resolvedAt: Date = .distantPast
    private var timer: DispatchSourceTimer?

    private let onUpdate: @Sendable (Temperatures) -> Void

    init(onUpdate: @escaping @Sendable (Temperatures) -> Void) {
        self.onUpdate = onUpdate
    }

    var isSupported: Bool { Self.symbols != nil }

    func start(interval: TimeInterval = 5) {
        guard isSupported else {
            onUpdate(Temperatures())
            return
        }
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now(), repeating: interval)
        t.setEventHandler { [weak self] in self?.tick() }
        t.resume()
        timer = t
    }

    func stop() { timer?.cancel(); timer = nil }

    private func tick() {
        guard let sym = Self.symbols else { return }
        resolveSensorsIfNeeded(sym)

        var socValues: [Double] = []
        var gpuValues: [Double] = []
        var batteryValues: [Double] = []
        var ssdValues: [Double] = []

        for entry in sensors {
            guard let event = sym.copyEvent(entry.service, Self.temperatureType, 0, 0)?
                .takeRetainedValue() else { continue }
            let v = sym.floatValue(event, Int32(Self.temperatureType << 16))

            guard v > 1, v < 130 else { continue }
            switch entry.group {
            case .soc:     socValues.append(v)
            case .gpu:     gpuValues.append(v)
            case .battery: batteryValues.append(v)
            case .ssd:     ssdValues.append(v)
            }
        }

        var t = Temperatures()
        t.available = !socValues.isEmpty
        if !socValues.isEmpty {
            t.soc = socValues.reduce(0, +) / Double(socValues.count)
            t.socMax = socValues.max() ?? 0
        }
        if !gpuValues.isEmpty { t.gpu = gpuValues.reduce(0, +) / Double(gpuValues.count) }
        if !batteryValues.isEmpty { t.battery = batteryValues.max() ?? 0 }
        if !ssdValues.isEmpty { t.ssd = ssdValues.max() ?? 0 }

        onUpdate(t)
    }

    private func resolveSensorsIfNeeded(_ sym: Symbols) {
        guard sensors.isEmpty || Date().timeIntervalSince(resolvedAt) > 120 else { return }
        resolvedAt = Date()

        if client == nil {
            client = sym.create(kCFAllocatorDefault)?.takeRetainedValue()
            guard let client else { return }
            let match: [String: Any] = ["PrimaryUsagePage": Self.usagePage,
                                        "PrimaryUsage": Self.usage]
            _ = sym.setMatching(client, match as CFDictionary)
        }
        guard let client,
              let services = sym.copyServices(client)?.takeRetainedValue() as? [AnyObject]
        else { return }

        sensors = services.compactMap { service in
            let name = sym.copyProperty(service, "Product" as CFString)?
                .takeRetainedValue() as? String ?? ""
            guard let group = Self.classify(name) else { return nil }
            return (service, group)
        }
    }

    private static func classify(_ name: String) -> Group? {

        if name.contains("tcal") { return nil }
        if name.contains("tdie") || name.contains("pACC") || name.contains("eACC")
            || name.contains("SOC MTR") { return .soc }
        if name.contains("GPU") { return .gpu }
        if name.lowercased().contains("gas gauge battery") { return .battery }
        if name.contains("NAND") { return .ssd }
        return nil
    }
}
