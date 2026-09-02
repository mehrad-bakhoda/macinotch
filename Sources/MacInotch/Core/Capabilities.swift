import Foundation

@MainActor
final class Capabilities: ObservableObject {
    static let shared = Capabilities()

    @Published private(set) var fans = false
    @Published private(set) var temperature = false
    @Published private(set) var power = false
    @Published private(set) var battery = false

    private init() {
        let p = Prefs.shared.d
        fans = p.seenFans
        temperature = p.seenTemperature
        power = p.seenPower
        battery = p.seenBattery
    }

    var intelligence: Bool { Summarizer.onDeviceAvailable }
    var speech: Bool { MeetingRecorder.available }
    var dictation: Bool { Dictation.available }
    var notch: Bool { NotchState.shared.hasRealNotch }

    func observe(_ state: NotchState) {
        note(&fans, state.fans.available && !state.fans.fans.isEmpty,
             \.seenFans)
        note(&temperature, state.temps.available && state.temps.soc > 0,
             \.seenTemperature)
        note(&power, state.fans.systemWatts > 0, \.seenPower)
        note(&battery, state.battery.present, \.seenBattery)
    }

    private func note(_ flag: inout Bool, _ present: Bool,
                      _ key: WritableKeyPath<PrefsData, Bool>) {
        guard present, !flag else { return }
        flag = true
        Prefs.shared.d[keyPath: key] = true
    }

    var missing: [String] {
        var out: [String] = []
        if !fans { out.append("fan sensors") }
        if !temperature { out.append("temperature sensors") }
        if !power { out.append("a power sensor") }
        if !intelligence { out.append("Apple Intelligence") }
        return out
    }
}
