import Foundation

final class SnapshotStore: @unchecked Sendable {
    static let shared = SnapshotStore()

    private let lock = NSLock()
    private var json = "{}"
    private var prefs = "{}"

    func set(_ value: String) {
        lock.lock(); json = value; lock.unlock()
    }

    func get() -> String {
        lock.lock(); defer { lock.unlock() }
        return json
    }

    func setPrefs(_ value: String) {
        lock.lock(); prefs = value; lock.unlock()
    }

    func getPrefs() -> String {
        lock.lock(); defer { lock.unlock() }
        return prefs
    }

    private var fans = #"{"ok":true}"#

    func setFans(_ value: String) {
        lock.lock(); fans = value; lock.unlock()
    }

    func getFans() -> String {
        lock.lock(); defer { lock.unlock() }
        return fans
    }
}

final class Flag: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Bool

    init(_ initial: Bool = false) { value = initial }

    func set(_ new: Bool) {
        lock.lock(); value = new; lock.unlock()
    }

    func get() -> Bool {
        lock.lock(); defer { lock.unlock() }
        return value
    }
}

final class PathBox: @unchecked Sendable {
    private let lock = NSLock()
    private var value = ""

    func set(_ new: String) {
        lock.lock(); value = new; lock.unlock()
    }

    func get() -> String {
        lock.lock(); defer { lock.unlock() }
        return value
    }
}
