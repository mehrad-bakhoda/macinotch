import AppKit
import CoreAudio
import IOKit

struct BluetoothDevice: Identifiable, Equatable {
    var id: String
    var name: String
    var percent: Int
    var isCharging: Bool
    var kind: String

    var symbol: String {
        let lower = kind.lowercased() + name.lowercased()
        if lower.contains("airpod") || lower.contains("headphone")
            || lower.contains("buds") { return "airpods" }
        if lower.contains("mouse") { return "magicmouse" }
        if lower.contains("keyboard") { return "keyboard" }
        if lower.contains("trackpad") { return "trackpad" }
        return "dot.radiowaves.right"
    }
}

@MainActor
final class BluetoothBatteryService: ObservableObject {
    static let shared = BluetoothBatteryService()

    @Published private(set) var devices: [BluetoothDevice] = []

    private var timer: Timer?

    private init() {}

    func start(interval: TimeInterval = 60) {
        tick()
        let t = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() { timer?.invalidate(); timer = nil }

    private func tick() {
        guard Prefs.shared.d.showBluetooth else {
            if !devices.isEmpty { devices = [] }
            return
        }
        let found = Self.read()
        if found != devices { devices = found }
    }

    static func read() -> [BluetoothDevice] {
        var results: [BluetoothDevice] = []
        var iterator: io_iterator_t = 0
        let matching = IOServiceMatching("AppleDeviceManagementHIDEventService")
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator)
                == KERN_SUCCESS else { return [] }
        defer { IOObjectRelease(iterator) }

        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }

            func property(_ key: String) -> Any? {
                IORegistryEntryCreateCFProperty(service, key as CFString,
                                                kCFAllocatorDefault, 0)?.takeRetainedValue()
            }

            guard let percent = property("BatteryPercent") as? Int, percent > 0 else { continue }
            let name = property("Product") as? String
                ?? property("DeviceName") as? String ?? "Bluetooth device"
            let serial = property("SerialNumber") as? String ?? name
            let charging = (property("BatteryStatusFlags") as? Int ?? 0) != 0

            results.append(BluetoothDevice(id: serial, name: name, percent: percent,
                                           isCharging: charging, kind: name))
        }
        return results.sorted { $0.percent < $1.percent }
    }
}

struct AudioDevice: Identifiable, Equatable {
    var id: AudioDeviceID
    var name: String
    var isDefault: Bool

    var symbol: String {
        let lower = name.lowercased()
        if lower.contains("airpod") || lower.contains("headphone") { return "airpods" }
        if lower.contains("display") || lower.contains("monitor") { return "display" }
        if lower.contains("macbook") || lower.contains("built-in") { return "laptopcomputer" }
        return "hifispeaker.fill"
    }
}

@MainActor
final class AudioService: ObservableObject {
    static let shared = AudioService()

    @Published private(set) var outputs: [AudioDevice] = []

    private var timer: Timer?

    private init() {}

    func start(interval: TimeInterval = 10) {
        tick()
        let t = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() { timer?.invalidate(); timer = nil }

    var current: AudioDevice? { outputs.first(where: \.isDefault) }

    private func tick() {
        guard Prefs.shared.d.showAudioSwitcher else {
            if !outputs.isEmpty { outputs = [] }
            return
        }
        let found = Self.readOutputs()
        if found != outputs { outputs = found }
    }

    func select(_ device: AudioDevice) {
        var deviceID = device.id
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        let status = AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil,
            UInt32(MemoryLayout<AudioDeviceID>.size), &deviceID)
        if status == noErr {
            SoundKit.tap()
            tick()
        }
    }

    static func readOutputs() -> [AudioDevice] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)

        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject),
                                             &address, 0, nil, &size) == noErr else { return [] }
        let count = Int(size) / MemoryLayout<AudioDeviceID>.size
        var ids = [AudioDeviceID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject),
                                         &address, 0, nil, &size, &ids) == noErr else { return [] }

        let defaultID = currentDefaultOutput()
        var results: [AudioDevice] = []

        for id in ids {
            guard hasOutputStreams(id), let name = deviceName(id) else { continue }
            results.append(AudioDevice(id: id, name: name, isDefault: id == defaultID))
        }
        return results
    }

    private static func currentDefaultOutput() -> AudioDeviceID {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject),
                                   &address, 0, nil, &size, &deviceID)
        return deviceID
    }

    private static func hasOutputStreams(_ id: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr,
              size > 0 else { return false }

        let buffer = UnsafeMutableRawPointer.allocate(byteCount: Int(size),
                                                      alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { buffer.deallocate() }
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, buffer) == noErr else {
            return false
        }
        let list = buffer.assumingMemoryBound(to: AudioBufferList.self)
        let buffers = UnsafeMutableAudioBufferListPointer(list)
        return buffers.contains { $0.mNumberChannels > 0 }
    }

    private static func deviceName(_ id: AudioDeviceID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var name: CFString = "" as CFString
        var size = UInt32(MemoryLayout<CFString>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &name) == noErr else {
            return nil
        }
        let value = name as String
        return value.isEmpty ? nil : value
    }
}

@MainActor
final class FrontmostAppWatcher {
    static let shared = FrontmostAppWatcher()

    private(set) var bundleID: String = ""

    private init() {}

    func start() {
        update(NSWorkspace.shared.frontmostApplication)
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil, queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            Task { @MainActor in self?.update(app) }
        }
    }

    private func update(_ app: NSRunningApplication?) {
        bundleID = app?.bundleIdentifier ?? ""
    }

    var shouldSuppress: Bool {
        let raw = Prefs.shared.d.quietApps
        guard !raw.isEmpty, !bundleID.isEmpty else { return false }
        return raw.split(whereSeparator: { ",; \n".contains($0) })
            .map(String.init)
            .filter { !$0.isEmpty }
            .contains { bundleID.localizedCaseInsensitiveContains($0) }
    }
}
