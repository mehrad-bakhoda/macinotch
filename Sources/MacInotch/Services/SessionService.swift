import Foundation

struct CodeSession: Identifiable, Equatable {
    var id: String
    var provider: NotchSource
    var project: String
    var path: String
    var updatedAt: Date
    var messages: Int
    var tokens: Int
    var model: String
    var isLive: Bool
    var title: String = ""

    var projectName: String {
        if project.contains("/") {
            return (project as NSString).lastPathComponent
        }
        let trimmed = project.hasPrefix("-") ? String(project.dropFirst()) : project
        let parts = trimmed.split(separator: "-")
        return parts.last.map(String.init) ?? trimmed
    }

    var displayName: String { title.isEmpty ? projectName : title }

    var ago: String {
        let seconds = Int(Date().timeIntervalSince(updatedAt))
        if seconds < 90 { return "just now" }
        if seconds < 3600 { return "\(seconds / 60)m ago" }
        if seconds < 86400 { return "\(seconds / 3600)h ago" }
        return "\(seconds / 86400)d ago"
    }
}

final class SessionService: @unchecked Sendable {
    private let queue = DispatchQueue(label: "io.macinotch.sessions")
    private var timer: DispatchSourceTimer?
    private let onUpdate: @Sendable ([CodeSession]) -> Void
    private let sources: @Sendable () -> (enabled: Bool, claude: Bool, codex: Bool,
                                          activeOnly: Bool)

    init(sources: @escaping @Sendable () -> (enabled: Bool, claude: Bool, codex: Bool,
                                             activeOnly: Bool),
         onUpdate: @escaping @Sendable ([CodeSession]) -> Void) {
        self.sources = sources
        self.onUpdate = onUpdate
    }

    func start(interval: TimeInterval = 20) {
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + 3, repeating: interval)
        t.setEventHandler { [weak self] in self?.tick() }
        t.resume()
        timer = t
    }

    func stop() { timer?.cancel(); timer = nil }

    private func tick() {
        let wanted = sources()
        guard wanted.enabled else { return }
        var all: [CodeSession] = []
        if wanted.claude { all += Self.scanClaude() }
        if wanted.codex { all += Self.scanCodex() }
        if wanted.activeOnly { all = all.filter(\.isLive) }
        onUpdate(Array(all.sorted { $0.updatedAt > $1.updatedAt }.prefix(16)))
    }

    static func scan(limit: Int = 12) -> [CodeSession] {
        Array((scanClaude(limit: limit) + scanCodex(limit: limit))
            .sorted { $0.updatedAt > $1.updatedAt }.prefix(limit))
    }

    private static func recentFiles(root: String, limit: Int) -> [(URL, Date)] {
        let fm = FileManager.default
        guard let walker = fm.enumerator(
            at: URL(fileURLWithPath: root),
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]) else { return [] }

        var files: [(URL, Date)] = []
        for case let url as URL in walker where url.pathExtension == "jsonl" {
            let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate ?? .distantPast
            files.append((url, modified))
        }
        return Array(files.sorted { $0.1 > $1.1 }.prefix(limit))
    }

    private static func head(_ url: URL, bytes: Int) -> String {
        guard let handle = FileHandle(forReadingAtPath: url.path) else { return "" }
        defer { try? handle.close() }
        let data = (try? handle.read(upToCount: bytes)) ?? Data()
        return String(decoding: data, as: UTF8.self)
    }

    private static func tail(_ url: URL, bytes: UInt64) -> String {
        guard let handle = FileHandle(forReadingAtPath: url.path) else { return "" }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        try? handle.seek(toOffset: size > bytes ? size - bytes : 0)
        let data = (try? handle.readToEnd()) ?? Data()
        return String(decoding: data, as: UTF8.self)
    }

    struct LiveClaude {
        var name: String
        var cwd: String
    }

    static func liveClaudeSessions() -> [String: LiveClaude] {
        let root = NSHomeDirectory() + "/.claude/sessions"
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: root) else {
            return [:]
        }

        var live: [String: LiveClaude] = [:]
        for name in names where name.hasSuffix(".json") {
            guard let data = FileManager.default.contents(atPath: root + "/" + name),
                  let object = try? JSONSerialization.jsonObject(with: data)
                      as? [String: Any],
                  let pid = object["pid"] as? Int32,
                  kill(pid, 0) == 0 else { continue }

            let id = object["sessionId"] as? String ?? String(name.dropLast(5))
            live[id] = LiveClaude(name: object["name"] as? String ?? "",
                                  cwd: object["cwd"] as? String ?? "")
        }
        return live
    }

    static func scanClaude(limit: Int = 10) -> [CodeSession] {
        let root = NSHomeDirectory() + "/.claude/projects"
        guard FileManager.default.fileExists(atPath: root) else { return [] }
        let live = liveClaudeSessions()

        return recentFiles(root: root, limit: limit).map { url, modified in
            var messages = 0
            var tokens = 0
            var model = ""

            for line in tail(url, bytes: 400_000).split(separator: "\n") {
                guard line.contains("\"usage\""),
                      let raw = line.data(using: .utf8),
                      let object = try? JSONSerialization.jsonObject(with: raw)
                          as? [String: Any],
                      let message = object["message"] as? [String: Any],
                      let usage = message["usage"] as? [String: Any] else { continue }
                messages += 1
                tokens += (usage["input_tokens"] as? Int ?? 0)
                    + (usage["output_tokens"] as? Int ?? 0)
                    + (usage["cache_creation_input_tokens"] as? Int ?? 0)
                if model.isEmpty { model = message["model"] as? String ?? "" }
            }

            let id = url.deletingPathExtension().lastPathComponent
            let session = live[id]

            return CodeSession(
                id: id,
                provider: .claude,
                project: session?.cwd
                    ?? url.deletingLastPathComponent().lastPathComponent,
                path: url.path,
                updatedAt: modified,
                messages: messages,
                tokens: tokens,
                model: model.replacingOccurrences(of: "claude-", with: ""),
                isLive: session != nil,
                title: session?.name ?? "")
        }
    }

    static func codexThreadNames() -> [String: String] {
        let path = NSHomeDirectory() + "/.codex/session_index.jsonl"
        guard let handle = FileHandle(forReadingAtPath: path) else { return [:] }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        try? handle.seek(toOffset: size > 400_000 ? size - 400_000 : 0)
        let text = String(decoding: (try? handle.readToEnd()) ?? Data(), as: UTF8.self)

        var names: [String: String] = [:]
        for line in text.split(separator: "\n") {
            guard let raw = line.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: raw)
                      as? [String: Any],
                  let id = object["id"] as? String,
                  let name = object["thread_name"] as? String,
                  !name.isEmpty else { continue }
            names[id] = name
        }
        return names
    }

    private static func codexIdentifier(_ url: URL) -> String {
        let stem = url.deletingPathExtension().lastPathComponent
        return stem.count > 36 ? String(stem.suffix(36)) : stem
    }

    static func scanCodex(limit: Int = 10) -> [CodeSession] {
        let root = NSHomeDirectory() + "/.codex/sessions"
        guard FileManager.default.fileExists(atPath: root) else { return [] }

        let names = codexThreadNames()
        let running = PresenceService.processExists(named: "codex")

        return recentFiles(root: root, limit: limit).map { url, modified in
            var project = ""
            var model = ""

            for line in head(url, bytes: 400_000).split(separator: "\n") {
                guard line.contains("session_meta") || line.contains("turn_context"),
                      let raw = line.data(using: .utf8),
                      let object = try? JSONSerialization.jsonObject(with: raw)
                          as? [String: Any],
                      let payload = object["payload"] as? [String: Any] else { continue }
                if project.isEmpty, let cwd = payload["cwd"] as? String { project = cwd }
                if model.isEmpty, let name = payload["model"] as? String { model = name }
                if !project.isEmpty && !model.isEmpty { break }
            }

            var messages = 0
            var tokens = 0

            for line in tail(url, bytes: 300_000).split(separator: "\n") {
                guard line.contains("token_count"),
                      let raw = line.data(using: .utf8),
                      let object = try? JSONSerialization.jsonObject(with: raw)
                          as? [String: Any],
                      let payload = object["payload"] as? [String: Any],
                      payload["type"] as? String == "token_count",
                      let info = payload["info"] as? [String: Any] else { continue }
                messages += 1
                if let total = info["total_token_usage"] as? [String: Any],
                   let value = total["total_tokens"] as? Int {
                    tokens = max(tokens, value)
                }
            }

            let id = codexIdentifier(url)

            return CodeSession(
                id: id,
                provider: .chatgpt,
                project: project,
                path: url.path,
                updatedAt: modified,
                messages: messages,
                tokens: tokens,
                model: model,
                isLive: running && Date().timeIntervalSince(modified) < 180,
                title: names[id] ?? "")
        }
    }
}
