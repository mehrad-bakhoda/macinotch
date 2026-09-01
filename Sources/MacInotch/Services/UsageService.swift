import Foundation

struct RateWindow: Equatable {
    var usedPercent: Double
    var windowMinutes: Int
    var resetsAt: Date

    var remaining: TimeInterval { max(0, resetsAt.timeIntervalSinceNow) }

    var remainingText: String {
        let s = Int(remaining)
        if s <= 0 { return "resetting" }
        let h = s / 3600, m = (s % 3600) / 60
        if h >= 24 { return "\(h / 24)d \(h % 24)h" }
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }

    var label: String {
        switch windowMinutes {
        case ..<90: return "\(windowMinutes)m"
        case ..<1440: return "\(windowMinutes / 60)h"
        default: return "\(windowMinutes / 1440)d"
        }
    }
}

struct RateProjection: Equatable {
    var percentPerHour: Double
    var exhaustionAt: Date?

    var text: String? {
        guard let exhaustionAt else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return "at this pace, full around \(formatter.string(from: exhaustionAt))"
    }
}

struct CodexLimits: Equatable {
    var primary: RateWindow
    var secondary: RateWindow?
    var plan: String
    var measuredAt: Date
    var projection: RateProjection?
}

struct LocalTally: Equatable {
    var tokens: Int
    var messages: Int
    var since: Date

    var sinceText: String {
        let s = Int(Date().timeIntervalSince(since))
        if s < 3600 { return "\(max(1, s / 60))m" }
        if s < 86400 { return "\(s / 3600)h" }
        return "\(s / 86400)d"
    }
}

struct UsageSnapshot: Equatable {
    var claude: LocalTally?
    var codexTally: LocalTally?
    var codexLimits: CodexLimits?

    var available: Bool { claude != nil || codexTally != nil || codexLimits != nil }

    static func short(_ n: Int) -> String {
        switch n {
        case ..<1_000: return "\(n)"
        case ..<1_000_000: return String(format: "%.1fK", Double(n) / 1_000)
        default: return String(format: "%.2fM", Double(n) / 1_000_000)
        }
    }
}

final class UsageService: @unchecked Sendable {
    private let queue = DispatchQueue(label: "io.macinotch.usage")
    private var timer: DispatchSourceTimer?

    private let onUpdate: @Sendable (UsageSnapshot) -> Void
    private let onReset: @Sendable (NotchSource, RateWindow) -> Void
    private let onThreshold: @Sendable (RateWindow, Int, RateProjection?) -> Void

    private let lock = NSLock()
    private var windowHours: Double
    private var lastCodexReset: Date?
    private var announced: [Date: Set<Int>] = [:]

    init(windowHours: Double,
         onUpdate: @escaping @Sendable (UsageSnapshot) -> Void,
         onReset: @escaping @Sendable (NotchSource, RateWindow) -> Void,
         onThreshold: @escaping @Sendable (RateWindow, Int, RateProjection?) -> Void) {
        self.windowHours = windowHours
        self.onUpdate = onUpdate
        self.onReset = onReset
        self.onThreshold = onThreshold
    }

    func update(windowHours value: Double) {
        lock.lock(); windowHours = value; lock.unlock()
    }

    private var hours: Double {
        lock.lock(); defer { lock.unlock() }
        return windowHours
    }

    func start(interval: TimeInterval = 45) {
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + 2, repeating: interval)
        t.setEventHandler { [weak self] in self?.tick() }
        t.resume()
        timer = t
    }

    func stop() { timer?.cancel(); timer = nil }

    private func tick() {
        var snap = UsageSnapshot()
        let window = hours * 3600
        snap.claude = Self.claudeTally(window: window)
        snap.codexTally = Self.codexTally(window: window)
        snap.codexLimits = Self.codexLimits()

        if let limits = snap.codexLimits {
            let window = limits.primary
            let previous = lastCodexReset
            lastCodexReset = window.resetsAt
            if let previous, window.resetsAt > previous, window.usedPercent < 50 {
                onReset(.chatgpt, window)
                announced[previous] = nil
            }

            var seen = announced[window.resetsAt] ?? []
            for mark in [80, 95] where window.usedPercent >= Double(mark)
                && !seen.contains(mark) {
                seen.insert(mark)
                onThreshold(window, mark, limits.projection)
            }
            announced[window.resetsAt] = seen
            announced = announced.filter { $0.key > Date().addingTimeInterval(-86_400) }
        }
        onUpdate(snap)
    }

    private static func recentFiles(_ root: String, within seconds: TimeInterval,
                                    limit: Int) -> [URL] {
        let fm = FileManager.default
        guard let walker = fm.enumerator(
            at: URL(fileURLWithPath: root),
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]) else { return [] }

        let cutoff = Date().addingTimeInterval(-seconds)
        var found: [(URL, Date)] = []
        for case let url as URL in walker where url.pathExtension == "jsonl" {
            let m = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate ?? .distantPast
            if m > cutoff { found.append((url, m)) }
        }
        return found.sorted { $0.1 > $1.1 }.prefix(limit).map(\.0)
    }

    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let isoPlain = ISO8601DateFormatter()

    static func parseDate(_ s: String) -> Date? {
        iso.date(from: s) ?? isoPlain.date(from: s)
    }

    static func claudeTally(window: TimeInterval) -> LocalTally? {
        let root = NSHomeDirectory() + "/.claude/projects"
        guard FileManager.default.fileExists(atPath: root) else { return nil }
        let cutoff = Date().addingTimeInterval(-window)

        var tokens = 0
        var messages = 0
        var earliest = Date()

        for url in recentFiles(root, within: window + 3600, limit: 24) {
            guard let handle = FileHandle(forReadingAtPath: url.path) else { continue }
            defer { try? handle.close() }
            let size = (try? handle.seekToEnd()) ?? 0
            try? handle.seek(toOffset: size > 3_000_000 ? size - 3_000_000 : 0)
            let text = String(decoding: (try? handle.readToEnd()) ?? Data(), as: UTF8.self)

            for line in text.split(separator: "\n") {
                guard line.contains("\"usage\""),
                      let raw = line.data(using: .utf8),
                      let obj = try? JSONSerialization.jsonObject(with: raw) as? [String: Any],
                      let stamp = obj["timestamp"] as? String,
                      let date = parseDate(stamp), date >= cutoff,
                      let message = obj["message"] as? [String: Any],
                      let usage = message["usage"] as? [String: Any] else { continue }

                messages += 1
                tokens += (usage["input_tokens"] as? Int ?? 0)
                    + (usage["output_tokens"] as? Int ?? 0)
                    + (usage["cache_creation_input_tokens"] as? Int ?? 0)
                earliest = min(earliest, date)
            }
        }
        guard messages > 0 else { return nil }
        return LocalTally(tokens: tokens, messages: messages, since: earliest)
    }

    static func codexTally(window: TimeInterval) -> LocalTally? {
        let root = NSHomeDirectory() + "/.codex/sessions"
        guard FileManager.default.fileExists(atPath: root) else { return nil }
        let cutoff = Date().addingTimeInterval(-window)

        var tokens = 0
        var messages = 0
        var earliest = Date()

        for url in recentFiles(root, within: window + 3600, limit: 24) {
            guard let handle = FileHandle(forReadingAtPath: url.path) else { continue }
            defer { try? handle.close() }
            let size = (try? handle.seekToEnd()) ?? 0
            try? handle.seek(toOffset: size > 3_000_000 ? size - 3_000_000 : 0)
            let text = String(decoding: (try? handle.readToEnd()) ?? Data(), as: UTF8.self)

            for line in text.split(separator: "\n") {
                guard line.contains("token_count"),
                      let raw = line.data(using: .utf8),
                      let obj = try? JSONSerialization.jsonObject(with: raw) as? [String: Any],
                      let stamp = obj["timestamp"] as? String,
                      let date = parseDate(stamp), date >= cutoff,
                      let payload = obj["payload"] as? [String: Any],
                      payload["type"] as? String == "token_count",
                      let info = payload["info"] as? [String: Any],
                      let last = info["last_token_usage"] as? [String: Any] else { continue }

                messages += 1
                let cached = last["cached_input_tokens"] as? Int ?? 0
                tokens += max(0, (last["input_tokens"] as? Int ?? 0) - cached)
                    + (last["output_tokens"] as? Int ?? 0)
                earliest = min(earliest, date)
            }
        }
        guard messages > 0 else { return nil }
        return LocalTally(tokens: tokens, messages: messages, since: earliest)
    }

    static func codexLimits() -> CodexLimits? {
        let root = NSHomeDirectory() + "/.codex/sessions"
        guard FileManager.default.fileExists(atPath: root) else { return nil }

        var newest: (Date, [String: Any])?
        var samples: [(Date, Double)] = []

        for url in recentFiles(root, within: 86_400 * 3, limit: 8) {
            guard let handle = FileHandle(forReadingAtPath: url.path) else { continue }
            defer { try? handle.close() }
            let size = (try? handle.seekToEnd()) ?? 0
            try? handle.seek(toOffset: size > 2_000_000 ? size - 2_000_000 : 0)
            let text = String(decoding: (try? handle.readToEnd()) ?? Data(), as: UTF8.self)

            for line in text.split(separator: "\n") {
                guard line.contains("rate_limits"),
                      let raw = line.data(using: .utf8),
                      let obj = try? JSONSerialization.jsonObject(with: raw) as? [String: Any],
                      let payload = obj["payload"] as? [String: Any],
                      let limits = (payload["rate_limits"]
                                    ?? (payload["info"] as? [String: Any])?["rate_limits"])
                          as? [String: Any] else { continue }

                let stamp = (obj["timestamp"] as? String).flatMap(parseDate) ?? .distantPast
                if newest == nil || stamp > newest!.0 { newest = (stamp, limits) }
                if let primary = limits["primary"] as? [String: Any],
                   let used = primary["used_percent"] as? Double {
                    samples.append((stamp, used))
                }
            }
        }

        guard let (measured, limits) = newest,
              let primary = window(from: limits["primary"]) else { return nil }

        return CodexLimits(primary: primary,
                           secondary: window(from: limits["secondary"]),
                           plan: limits["plan_type"] as? String ?? "",
                           measuredAt: measured,
                           projection: project(primary, samples: samples))
    }

    private static func project(_ window: RateWindow,
                                samples: [(Date, Double)]) -> RateProjection? {
        let start = window.resetsAt
            .addingTimeInterval(-Double(window.windowMinutes) * 60)
        let inWindow = samples
            .filter { $0.0 >= start && $0.0 <= Date() }
            .sorted { $0.0 < $1.0 }

        guard let first = inWindow.first, let last = inWindow.last,
              inWindow.count >= 3 else { return nil }

        let hours = last.0.timeIntervalSince(first.0) / 3600
        guard hours >= 0.15 else { return nil }

        let rate = (last.1 - first.1) / hours
        guard rate > 0.5 else { return RateProjection(percentPerHour: max(0, rate),
                                                      exhaustionAt: nil) }

        let remaining = 100 - window.usedPercent
        guard remaining > 0 else {
            return RateProjection(percentPerHour: rate, exhaustionAt: nil)
        }

        let seconds = (remaining / rate) * 3600
        let hit = Date().addingTimeInterval(seconds)
        return RateProjection(percentPerHour: rate,
                              exhaustionAt: hit < window.resetsAt ? hit : nil)
    }

    private static func window(from value: Any?) -> RateWindow? {
        guard let d = value as? [String: Any],
              let used = d["used_percent"] as? Double,
              let minutes = d["window_minutes"] as? Int,
              let resets = d["resets_at"] as? Double else { return nil }
        return RateWindow(usedPercent: used,
                          windowMinutes: minutes,
                          resetsAt: Date(timeIntervalSince1970: resets))
    }
}
