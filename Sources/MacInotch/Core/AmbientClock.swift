import Foundation

@MainActor
final class AmbientClock {
    static let shared = AmbientClock()

    private var token = ""
    private var since = Date.distantPast

    private init() {}

    func note(_ identity: String) {
        guard identity != token else { return }
        token = identity
        since = Date()
    }

    func stillFresh(_ timeout: Double) -> Bool {
        guard timeout > 0 else { return true }
        return Date().timeIntervalSince(since) < timeout
    }
}
