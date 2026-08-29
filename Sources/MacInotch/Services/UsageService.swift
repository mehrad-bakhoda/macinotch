import Foundation

struct UsageWindow: Equatable {
    var provider: NotchSource
    var windowStart: Date
    var windowLength: TimeInterval
    var input = 0
    var output = 0
    var cacheRead = 0
    var cacheWrite = 0
    var messages = 0
    var lastActivity: Date = .distantPast

    var windowEnd: Date { windowStart.addingTimeInterval(windowLength) }
    var total: Int { input + output + cacheRead + cacheWrite }

    var billable: Int { input + output + cacheWrite }

    var elapsedFraction: Double {
        let e = Date().timeIntervalSince(windowStart)
        return min(1, max(0, e / windowLength))
    }

    var timeRemaining: TimeInterval { max(0, windowEnd.timeIntervalSinceNow) }

    var remainingText: String {
        let s = Int(timeRemaining)
        if s <= 0 { return "resetting" }
        let h = s / 3600, m = (s % 3600) / 60
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }

    static func short(_ n: Int) -> String {
        switch n {
        case ..<1_000: return "\(n)"
        case ..<1_000_000: return String(format: "%.1fK", Double(n) / 1_000)
        default: return String(format: "%.2fM", Double(n) / 1_000_000)
        }
    }
}

struct UsageSnapshot: Equatable {
    var claude: UsageWindow?
    var codex: UsageWindow?
    var available: Bool { claude != nil || codex != nil }
}

final class UsageService: @unchecked Sendable {
    private let queue = DispatchQueue(label: "io.macinotch.usage")
    private var timer: DispatchSourceTimer?

    private let onUpdate: @Sendable (UsageSnapshot) -> Void

    private let onReset: @Sendable (NotchSource, UsageWindow) -> Void

    private var offsets: [String: UInt64] = [:]
    private var events: [NotchSource: [(Date, Int, Int, Int, Int)]] = [:]
    private var lastWindowStart: [NotchSource: Date] = [:]
    private var primed = false

    private var windowLength: TimeInterval

    init(windowHours: Double = 5,
         onUpdate: @escaping @Sendable (UsageSnapshot) -> Void,
         onReset: @escaping @Sendable (NotchSource, UsageWindow) -> Void) {
        self.windowLength = windowHours * 3600
        self.onUpdate = onUpdate
        self.onReset = onReset
    }

    func setWindowHours(_ h: Double) { queue.async { self.windowLength = h * 3600 } }

    func start(interval: TimeInterval = 30) {
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + 2, repeating: interval)
        t.setEventHandler { [weak self] in self?.tick() }
        t.resume()
        timer = t
    }

    func stop() { timer?.cancel(); timer = nil }

    private func tick() {
        scanClaude()
        scanCodex()
        prune()
        publish()
        primed = true
    }

    private var home: String { NSHomeDirectory() }

    private func recentFiles(in root: String, maxAge: TimeInterval) -> [String] {
        let fm = FileManager.default
        guard let e = fm.enumerator(at: URL(fileURLWithPath: root),
                                    includingPropertiesForKeys: [.contentModificationDateKey],
                                    options: [.skipsHiddenFiles]) else { return [] }
        var out: [String] = []
        let cutoff = Date().addingTimeInterval(-maxAge)
        for case let url as URL in e {
            guard url.pathExtension == "jsonl" else { continue }
            let mod = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate ?? .distantPast

            guard mod > cutoff else { continue }
            out.append(url.path)
        }
        return out
    }

    private func newLines(_ path: String) -> [String] {
        guard let handle = FileHandle(forReadingAtPath: path) else { return [] }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        let start = offsets[path] ?? 0

        let from = start <= size ? start : 0
        guard size > from else { offsets[path] = size; return [] }
        try? handle.seek(toOffset: from)
        let data = (try? handle.readToEnd()) ?? Data()
        offsets[path] = size
        return String(decoding: data, as: UTF8.self)
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map(String.init)
    }

    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let isoPlain = ISO8601DateFormatter()

    private static func parseDate(_ s: String) -> Date? {
        iso.date(from: s) ?? isoPlain.date(from: s)
    }

    private func record(_ source: NotchSource, _ date: Date,
                        _ input: Int, _ output: Int, _ cacheRead: Int, _ cacheWrite: Int) {
        events[source, default: []].append((date, input, output, cacheRead, cacheWrite))
    }

    private func scanClaude() {
        let root = home + "/.claude/projects"
        guard FileManager.default.fileExists(atPath: root) else { return }

        for path in recentFiles(in: root, maxAge: windowLength * 2 + 3600) {
            for line in newLines(path) {
                guard line.contains("\"usage\""),
                      let data = line.data(using: .utf8),
                      let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let message = obj["message"] as? [String: Any],
                      let usage = message["usage"] as? [String: Any],
                      let ts = obj["timestamp"] as? String,
                      let date = Self.parseDate(ts) else { continue }

                record(.claude, date,
                       usage["input_tokens"] as? Int ?? 0,
                       usage["output_tokens"] as? Int ?? 0,
                       usage["cache_read_input_tokens"] as? Int ?? 0,
                       usage["cache_creation_input_tokens"] as? Int ?? 0)
            }
        }
    }

    private func scanCodex() {
        let root = home + "/.codex/sessions"
        guard FileManager.default.fileExists(atPath: root) else { return }

        for path in recentFiles(in: root, maxAge: windowLength * 2 + 3600) {
            for line in newLines(path) {
                guard line.contains("token_count"),
                      let data = line.data(using: .utf8),
                      let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let payload = obj["payload"] as? [String: Any],
                      payload["type"] as? String == "token_count",
                      let info = payload["info"] as? [String: Any],

                      let last = info["last_token_usage"] as? [String: Any],
                      let ts = obj["timestamp"] as? String,
                      let date = Self.parseDate(ts) else { continue }

                let cached = last["cached_input_tokens"] as? Int ?? 0
                let input = max(0, (last["input_tokens"] as? Int ?? 0) - cached)
                record(.chatgpt, date, input,
                       last["output_tokens"] as? Int ?? 0, cached, 0)
            }
        }
    }

    private func prune() {
        let cutoff = Date().addingTimeInterval(-(windowLength * 2 + 3600))
        for (k, v) in events { events[k] = v.filter { $0.0 > cutoff } }
    }

    private func window(for source: NotchSource) -> UsageWindow? {
        guard let list = events[source], !list.isEmpty else { return nil }
        let sorted = list.sorted { $0.0 < $1.0 }

        var start = Self.floorToHour(sorted[0].0)

        let now = Date()
        while start.addingTimeInterval(windowLength) < now,
              let next = sorted.first(where: { $0.0 >= start.addingTimeInterval(windowLength) })?.0 {
            start = Self.floorToHour(next)
        }
        guard start.addingTimeInterval(windowLength) >= now else { return nil }

        var w = UsageWindow(provider: source, windowStart: start, windowLength: windowLength)
        for (date, input, output, cacheRead, cacheWrite) in sorted where date >= start {
            w.input += input; w.output += output
            w.cacheRead += cacheRead; w.cacheWrite += cacheWrite
            w.messages += 1
            w.lastActivity = max(w.lastActivity, date)
        }
        return w
    }

    private static func floorToHour(_ date: Date) -> Date {
        let t = date.timeIntervalSinceReferenceDate
        return Date(timeIntervalSinceReferenceDate: (t / 3600).rounded(.down) * 3600)
    }

    private func publish() {
        var snap = UsageSnapshot()
        snap.claude = window(for: .claude)
        snap.codex = window(for: .chatgpt)

        for w in [snap.claude, snap.codex].compactMap({ $0 }) {
            let previous = lastWindowStart[w.provider]
            lastWindowStart[w.provider] = w.windowStart

            if primed, let previous, previous != w.windowStart {
                onReset(w.provider, w)
            }
        }
        onUpdate(snap)
    }
}
