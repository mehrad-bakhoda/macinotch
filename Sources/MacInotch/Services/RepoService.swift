import Foundation

struct RepoStatus: Equatable {
    var name: String = ""
    var branch: String = ""
    var dirty: Int = 0
    var ahead: Int = 0
    var behind: Int = 0
    var available: Bool = false

    var isClean: Bool { dirty == 0 }

    var summary: String {
        var parts: [String] = []
        if dirty > 0 { parts.append("\(dirty) changed") }
        if ahead > 0 { parts.append("↑\(ahead)") }
        if behind > 0 { parts.append("↓\(behind)") }
        return parts.isEmpty ? "clean" : parts.joined(separator: " · ")
    }
}

final class RepoService: @unchecked Sendable {
    private let queue = DispatchQueue(label: "io.macinotch.repo")
    private var timer: DispatchSourceTimer?
    private let onUpdate: @Sendable (RepoStatus) -> Void
    private let path: @Sendable () -> String

    init(path: @escaping @Sendable () -> String,
         onUpdate: @escaping @Sendable (RepoStatus) -> Void) {
        self.path = path
        self.onUpdate = onUpdate
    }

    func start(interval: TimeInterval = 20) {
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + 2, repeating: interval)
        t.setEventHandler { [weak self] in self?.tick() }
        t.resume()
        timer = t
    }

    func stop() { timer?.cancel(); timer = nil }

    private func tick() {
        let root = path()
        guard !root.isEmpty,
              FileManager.default.fileExists(atPath: root + "/.git") else {
            onUpdate(RepoStatus())
            return
        }

        var status = RepoStatus()
        status.available = true
        status.name = (root as NSString).lastPathComponent
        status.branch = Self.git(["rev-parse", "--abbrev-ref", "HEAD"], in: root) ?? ""

        if let porcelain = Self.git(["status", "--porcelain"], in: root) {
            status.dirty = porcelain.isEmpty ? 0
                : porcelain.split(separator: "\n").count
        }

        if let counts = Self.git(["rev-list", "--left-right", "--count", "@{upstream}...HEAD"],
                                 in: root) {
            let parts = counts.split(whereSeparator: { $0 == "\t" || $0 == " " })
            if parts.count == 2 {
                status.behind = Int(parts[0]) ?? 0
                status.ahead = Int(parts[1]) ?? 0
            }
        }

        onUpdate(status)
    }

    private static func git(_ arguments: [String], in directory: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        process.currentDirectoryURL = URL(fileURLWithPath: directory)
        process.environment = ["GIT_OPTIONAL_LOCKS": "0", "PATH": "/usr/bin:/bin"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return nil }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return String(decoding: data, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
