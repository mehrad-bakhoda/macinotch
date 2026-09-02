import AppKit
import CoreGraphics
import Foundation

enum StripTarget: String, CaseIterable, Identifiable {
    case volume
    case brightness
    case scrub

    var id: String { rawValue }

    var label: String {
        switch self {
        case .volume: return "Volume"
        case .brightness: return "Brightness"
        case .scrub: return "Track position"
        }
    }

    var symbol: String {
        switch self {
        case .volume: return "speaker.wave.2.fill"
        case .brightness: return "sun.max.fill"
        case .scrub: return "waveform"
        }
    }
}

private typealias GetBrightness = @convention(c) (UInt32, UnsafeMutablePointer<Float>) -> Int32
private typealias SetBrightness = @convention(c) (UInt32, Float) -> Int32

@MainActor
final class ControlStrip: ObservableObject {
    static let shared = ControlStrip()

    @Published private(set) var active: StripTarget?
    @Published private(set) var value: Double = 0
    @Published private(set) var showing = false
    @Published private(set) var lastTarget: StripTarget?

    private var hideTask: Task<Void, Never>?
    private var origin: Double = 0
    private var handle: UnsafeMutableRawPointer?
    private var getter: GetBrightness?
    private var setter: SetBrightness?

    private init() {
        handle = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework"
                        + "/DisplayServices", RTLD_NOW)
        if let handle {
            if let sym = dlsym(handle, "DisplayServicesGetBrightness") {
                getter = unsafeBitCast(sym, to: GetBrightness.self)
            }
            if let sym = dlsym(handle, "DisplayServicesSetBrightness") {
                setter = unsafeBitCast(sym, to: SetBrightness.self)
            }
        }
    }

    var brightnessAvailable: Bool { getter != nil && setter != nil }

    func target(for modifiers: NSEvent.ModifierFlags) -> StripTarget {
        if modifiers.contains(.option), brightnessAvailable { return .brightness }
        if modifiers.contains(.shift), NotchState.shared.music.isActive { return .scrub }
        return StripTarget(rawValue: Prefs.shared.d.stripDefault) ?? .volume
    }

    func begin(_ target: StripTarget) {
        active = target
        lastTarget = target
        origin = current(target)
        value = origin
        showing = true
        hideTask?.cancel()
    }

    func drag(_ delta: Double, width: Double) {
        guard let active, width > 0 else { return }
        let span = max(120, width)
        let next = min(1, max(0, origin + delta / span))
        guard abs(next - value) > 0.002 else { return }
        value = next
        apply(active, next)
    }

    func end() {
        active = nil
        hideTask?.cancel()
        hideTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 900_000_000)
            showing = false
        }
    }

    private func current(_ target: StripTarget) -> Double {
        switch target {
        case .volume: return Self.systemVolume()
        case .brightness: return Double(brightness())
        case .scrub:
            let music = NotchState.shared.music
            guard music.duration > 0 else { return 0 }
            return min(1, max(0, music.position / music.duration))
        }
    }

    private func apply(_ target: StripTarget, _ level: Double) {
        switch target {
        case .volume:
            Self.setSystemVolume(level)
        case .brightness:
            setBrightness(Float(level))
        case .scrub:
            let music = NotchState.shared.music
            guard music.duration > 0 else { return }
            NotchState.shared.musicControl?.seek(to: level * music.duration)
        }
    }

    private func brightness() -> Float {
        guard let getter else { return 0 }
        var level: Float = 0
        return getter(CGMainDisplayID(), &level) == 0 ? level : 0
    }

    private func setBrightness(_ level: Float) {
        guard let setter else { return }
        _ = setter(CGMainDisplayID(), min(1, max(0.01, level)))
    }

    static func systemVolume() -> Double {
        guard let value = run("output volume of (get volume settings)"),
              let number = Double(value) else { return 0.5 }
        return number / 100
    }

    static func setSystemVolume(_ level: Double) {
        _ = run("set volume output volume \(Int((level * 100).rounded()))")
    }

    @discardableResult
    private static func run(_ source: String) -> String? {
        var error: NSDictionary?
        let value = NSAppleScript(source: source)?.executeAndReturnError(&error)
        return error == nil ? (value?.stringValue ?? "") : nil
    }
}
