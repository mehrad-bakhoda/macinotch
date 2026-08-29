import Foundation
import AppKit
import SQLite3

@MainActor
final class NotificationBridge {
    enum Status: Equatable {
        case off
        case running
        case needsFullDiskAccess
        case unavailable(String)
    }

    static let dbPath = NSHomeDirectory()
        + "/Library/Group Containers/group.com.apple.usernoted/db2/db"

    private weak var state: NotchState?
    private var db: OpaquePointer?
    private var timer: Timer?
    private var lastRecID: Int64 = 0
    private(set) var status: Status = .off

    init(state: NotchState) { self.state = state }

    func start() {
        guard Prefs.shared.d.bridgeEnabled else { status = .off; return }
        guard FileManager.default.fileExists(atPath: Self.dbPath) else {
            status = .unavailable("Notification database not found")
            return
        }
        guard open() else { return }

        lastRecID = maxRecID()
        status = .running

        let t = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.poll() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() {
        timer?.invalidate(); timer = nil
        if let db { sqlite3_close(db) }
        db = nil
        status = .off
    }

    func restart() { stop(); start() }

    private func open() -> Bool {
        var handle: OpaquePointer?

        let uri = "file:\(Self.dbPath)?mode=ro"
        let rc = sqlite3_open_v2(uri, &handle,
                                 SQLITE_OPEN_READONLY | SQLITE_OPEN_URI, nil)
        guard rc == SQLITE_OK, let handle else {

            status = (rc == SQLITE_CANTOPEN || rc == SQLITE_PERM || rc == SQLITE_AUTH)
                ? .needsFullDiskAccess
                : .unavailable("sqlite error \(rc)")
            if handle != nil { sqlite3_close(handle) }
            return false
        }
        db = handle
        return true
    }

    private func maxRecID() -> Int64 {
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, "SELECT IFNULL(MAX(rec_id), 0) FROM record",
                                 -1, &stmt, nil) == SQLITE_OK else {
            status = .needsFullDiskAccess
            return 0
        }
        return sqlite3_step(stmt) == SQLITE_ROW ? sqlite3_column_int64(stmt, 0) : 0
    }

    private func poll() {
        guard db != nil else { return }
        let sql = """
        SELECT r.rec_id, a.identifier, r.data
        FROM record r JOIN app a ON a.app_id = r.app_id
        WHERE r.rec_id > ?
        ORDER BY r.rec_id ASC LIMIT 12
        """
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        sqlite3_bind_int64(stmt, 1, lastRecID)

        while sqlite3_step(stmt) == SQLITE_ROW {
            lastRecID = max(lastRecID, sqlite3_column_int64(stmt, 0))

            guard let idPtr = sqlite3_column_text(stmt, 1) else { continue }
            let bundle = String(cString: idPtr)

            guard let blob = sqlite3_column_blob(stmt, 2) else { continue }
            let len = Int(sqlite3_column_bytes(stmt, 2))
            let data = Data(bytes: blob, count: len)

            guard allowed(bundle), let parsed = Self.parse(data) else { continue }
            forward(bundle: bundle, title: parsed.title, body: parsed.body)
        }
    }

    private func allowed(_ bundle: String) -> Bool {
        let p = Prefs.shared.d

        if bundle == "io.macinotch.app" { return false }

        let custom = p.bridgeCustomBundles
            .split(whereSeparator: { ",; \n".contains($0) })
            .map(String.init)
            .filter { !$0.isEmpty }

        if !custom.isEmpty && custom.contains(where: { bundle.localizedCaseInsensitiveContains($0) }) {
            return true
        }
        if p.bridgeAIOnly { return Self.source(for: bundle) != .custom }
        return custom.isEmpty
    }

    static func source(for bundle: String) -> NotchSource {
        let b = bundle.lowercased()
        if b.contains("openai") || b.contains("chatgpt") { return .chatgpt }
        if b.contains("anthropic") || b.contains("claude") { return .claude }
        if b.contains("spotify") { return .spotify }
        return .custom
    }

    private func forward(bundle: String, title: String, body: String) {
        guard let state, !(title.isEmpty && body.isEmpty) else { return }
        var p = NotchPayload()
        let src = Self.source(for: bundle)
        p.source = src.rawValue
        p.title = title.isEmpty ? Self.appName(bundle) : title
        p.body = body
        p.kind = "info"
        state.handle(p)
    }

    private static var nameCache: [String: String] = [:]

    static func appName(_ bundle: String) -> String {
        if let cached = nameCache[bundle] { return cached }
        let name = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle)
            .map { FileManager.default.displayName(atPath: $0.path) }
            ?? bundle
        nameCache[bundle] = name
        return name
    }

    static func parse(_ data: Data) -> (title: String, body: String)? {
        guard let plist = try? PropertyListSerialization.propertyList(
            from: data, options: [], format: nil) as? [String: Any] else { return nil }

        let req = plist["req"] as? [String: Any] ?? plist

        let title = (req["titl"] as? String) ?? (req["title"] as? String) ?? ""
        let subtitle = (req["subt"] as? String) ?? ""
        let bodyText = (req["body"] as? String) ?? ""

        let body = [subtitle, bodyText]
            .filter { !$0.isEmpty }
            .joined(separator: " — ")
        return (title, body)
    }
}
