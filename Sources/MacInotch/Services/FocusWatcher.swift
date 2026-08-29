import Foundation

@MainActor
final class FocusWatcher: ObservableObject {
    static let shared = FocusWatcher()

    @Published private(set) var active = false
    @Published private(set) var available = false
    @Published private(set) var modeName: String?

    private var timer: Timer?

    private static var assertionsPath: String {
        NSHomeDirectory() + "/Library/DoNotDisturb/DB/Assertions.json"
    }
    private static var modesPath: String {
        NSHomeDirectory() + "/Library/DoNotDisturb/DB/ModeConfigurations.json"
    }

    private init() {}

    func start(interval: TimeInterval = 15) {
        tick()
        let t = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() { timer?.invalidate(); timer = nil }

    private func tick() {
        guard let data = FileManager.default.contents(atPath: Self.assertionsPath) else {

            if available { available = false; active = false; modeName = nil }
            return
        }
        available = true

        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let records = (root["data"] as? [[String: Any]])?.first?["storeAssertionRecords"]
                as? [[String: Any]] else {
            setActive(false, name: nil)
            return
        }

        let live = records.compactMap { record -> String? in
            let details = record["assertionDetails"] as? [String: Any]
            return details?["assertionDetailsModeIdentifier"] as? String
        }
        setActive(!live.isEmpty, name: live.first.map(Self.prettyMode))
    }

    private func setActive(_ on: Bool, name: String?) {
        if active != on { active = on }
        if modeName != name { modeName = name }
    }

    private static func prettyMode(_ identifier: String) -> String {
        let leaf = identifier.split(separator: ".").last.map(String.init) ?? identifier
        switch leaf {
        case "default": return "Do Not Disturb"
        default:        return leaf.capitalized
        }
    }
}
