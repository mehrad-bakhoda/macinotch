import Foundation

struct ProjectSpan: Identifiable, Equatable {
    var id: String { name }
    var name: String
    var seconds: Double
    var messages: Int
    var providers: Set<String>

    var text: String {
        let minutes = Int(seconds / 60)
        if minutes < 60 { return "\(max(1, minutes))m" }
        return "\(minutes / 60)h \(minutes % 60)m"
    }
}

struct WorkDay: Equatable {
    var date: Date
    var seconds: Double

    var level: Int {
        switch seconds {
        case ..<1: return 0
        case ..<3600: return 1
        case ..<10800: return 2
        case ..<21600: return 3
        default: return 4
        }
    }
}

struct WorkHistory: Equatable {
    var days: [WorkDay] = []
    var streak = 0
    var bestStreak = 0
    var todaySeconds: Double = 0

    var weekSeconds: Double {
        let since = Date().addingTimeInterval(-7 * 86400)
        return days.filter { $0.date >= since }.reduce(0) { $0 + $1.seconds }
    }

    static func span(_ seconds: Double) -> String {
        let minutes = Int(seconds / 60)
        if minutes < 60 { return "\(minutes)m" }
        return "\(minutes / 60)h \(minutes % 60)m"
    }
}

final class ProjectTime: @unchecked Sendable {
    private let queue = DispatchQueue(label: "io.macinotch.projecttime")
    private var timer: DispatchSourceTimer?
    private let onUpdate: @Sendable ([ProjectSpan]) -> Void
    private let onHistory: @Sendable (WorkHistory) -> Void

    init(onUpdate: @escaping @Sendable ([ProjectSpan]) -> Void,
         onHistory: @escaping @Sendable (WorkHistory) -> Void = { _ in }) {
        self.onUpdate = onUpdate
        self.onHistory = onHistory
    }

    func start(interval: TimeInterval = 180) {
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + 6, repeating: interval)
        t.setEventHandler { [weak self] in
            guard let self else { return }
            self.onUpdate(Self.today())
            self.onHistory(Self.history())
        }
        t.resume()
        timer = t
    }

    func stop() { timer?.cancel(); timer = nil }

    private static let idleGap: Double = 600

    static func today() -> [ProjectSpan] {
        let since = Calendar.current.startOfDay(for: Date())
        var stamps: [String: (dates: [Date], providers: Set<String>)] = [:]

        collect(root: NSHomeDirectory() + "/.claude/projects",
                provider: "claude", since: since, into: &stamps)
        collect(root: NSHomeDirectory() + "/.codex/sessions",
                provider: "codex", since: since, into: &stamps)

        return stamps.compactMap { name, entry -> ProjectSpan? in
            let sorted = entry.dates.sorted()
            guard sorted.count > 1 else { return nil }

            var total: Double = 0
            for index in 1..<sorted.count {
                let gap = sorted[index].timeIntervalSince(sorted[index - 1])
                if gap > 0 && gap <= idleGap { total += gap }
            }
            guard total >= 60 else { return nil }
            return ProjectSpan(name: name, seconds: total,
                               messages: sorted.count, providers: entry.providers)
        }
        .sorted { $0.seconds > $1.seconds }
    }

    static func history(weeks: Int = 12) -> WorkHistory {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: Date())
            .addingTimeInterval(-Double(weeks * 7) * 86400)

        var perDay: [Date: [Date]] = [:]
        var stamps: [String: (dates: [Date], providers: Set<String>)] = [:]
        collect(root: NSHomeDirectory() + "/.claude/projects",
                provider: "claude", since: start, into: &stamps)
        collect(root: NSHomeDirectory() + "/.codex/sessions",
                provider: "codex", since: start, into: &stamps)

        for entry in stamps.values {
            for date in entry.dates {
                let day = calendar.startOfDay(for: date)
                perDay[day, default: []].append(date)
            }
        }

        var history = WorkHistory()
        var days: [WorkDay] = []
        for offset in 0...(weeks * 7) {
            let day = calendar.startOfDay(for: Date())
                .addingTimeInterval(-Double(offset) * 86400)
            let sorted = (perDay[day] ?? []).sorted()
            var total: Double = 0
            if sorted.count > 1 {
                for index in 1..<sorted.count {
                    let gap = sorted[index].timeIntervalSince(sorted[index - 1])
                    if gap > 0 && gap <= idleGap { total += gap }
                }
            }
            days.append(WorkDay(date: day, seconds: total))
        }

        history.days = days.reversed()
        history.todaySeconds = days.first?.seconds ?? 0

        var run = 0
        for day in days {
            if day.seconds >= 600 { run += 1 } else { break }
        }
        history.streak = run

        var best = 0, current = 0
        for day in history.days {
            if day.seconds >= 600 { current += 1; best = max(best, current) }
            else { current = 0 }
        }
        history.bestStreak = best
        return history
    }

    private static func collect(root: String, provider: String, since: Date,
                                into stamps: inout [String: (dates: [Date],
                                                             providers: Set<String>)]) {
        let fm = FileManager.default
        guard fm.fileExists(atPath: root),
              let walker = fm.enumerator(
                at: URL(fileURLWithPath: root),
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]) else { return }

        for case let url as URL in walker where url.pathExtension == "jsonl" {
            let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate ?? .distantPast
            guard modified >= since else { continue }

            guard let handle = FileHandle(forReadingAtPath: url.path) else { continue }
            defer { try? handle.close() }
            let size = (try? handle.seekToEnd()) ?? 0
            try? handle.seek(toOffset: size > 4_000_000 ? size - 4_000_000 : 0)
            let text = String(decoding: (try? handle.readToEnd()) ?? Data(), as: UTF8.self)

            var name = provider == "claude"
                ? url.deletingLastPathComponent().lastPathComponent : ""
            var dates: [Date] = []

            for line in text.split(separator: "\n") {
                guard let raw = line.data(using: .utf8),
                      let object = try? JSONSerialization.jsonObject(with: raw)
                          as? [String: Any] else { continue }

                if name.isEmpty || provider == "claude",
                   let cwd = (object["payload"] as? [String: Any])?["cwd"] as? String
                       ?? object["cwd"] as? String {
                    name = (cwd as NSString).lastPathComponent
                }
                guard let stamp = object["timestamp"] as? String,
                      let date = UsageService.parseDate(stamp), date >= since else {
                    continue
                }
                dates.append(date)
            }

            let key = Self.pretty(name)
            guard !key.isEmpty, !dates.isEmpty else { continue }
            var entry = stamps[key] ?? ([], [])
            entry.0.append(contentsOf: dates)
            entry.1.insert(provider)
            stamps[key] = entry
        }
    }

    private static func pretty(_ raw: String) -> String {
        if raw.contains("/") { return (raw as NSString).lastPathComponent }
        let trimmed = raw.hasPrefix("-") ? String(raw.dropFirst()) : raw
        return trimmed.split(separator: "-").last.map(String.init) ?? trimmed
    }
}
