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

    var projectName: String {
        if project.contains("/") {
            return (project as NSString).lastPathComponent
        }
        let trimmed = project.hasPrefix("-") ? String(project.dropFirst()) : project
        let parts = trimmed.split(separator: "-")
        return parts.last.map(String.init) ?? trimmed
    }

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
    private let sources: @Sendable () -> (enabled: Bool, claude: Bool, codex: Bool)

    init(sources: @escaping @Sendable () -> (enabled: Bool, claude: Bool, codex: Bool),
         onUpdate: @escaping @Sendable ([CodeSession]) -> Void) {
        self.sources = sources
        self.onUpdate = onUpdate
    }

    func start(interval: TimeInterval = 45) {
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

    static func scanClaude(limit: Int = 10) -> [CodeSession] {
        let root = NSHomeDirectory() + "/.claude/projects"
        guard FileManager.default.fileExists(atPath: root) else { return [] }

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

            return CodeSession(
                id: url.deletingPathExtension().lastPathComponent,
                provider: .claude,
                project: url.deletingLastPathComponent().lastPathComponent,
                path: url.path,
                updatedAt: modified,
                messages: messages,
                tokens: tokens,
                model: model.replacingOccurrences(of: "claude-", with: ""),
                isLive: Date().timeIntervalSince(modified) < 300)
        }
    }

    static func scanCodex(limit: Int = 10) -> [CodeSession] {
        let root = NSHomeDirectory() + "/.codex/sessions"
        guard FileManager.default.fileExists(atPath: root) else { return [] }

        return recentFiles(root: root, limit: limit).map { url, modified in
            var project = ""
            var model = ""

            for line in head(url, bytes: 16_000).split(separator: "\n") {
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

            return CodeSession(
                id: url.deletingPathExtension().lastPathComponent,
                provider: .chatgpt,
                project: project.isEmpty ? "Codex" : project,
                path: url.path,
                updatedAt: modified,
                messages: messages,
                tokens: tokens,
                model: model,
                isLive: Date().timeIntervalSince(modified) < 300)
        }
    }
}
