import Foundation
import AppKit

final class ScreenshotWatcher: @unchecked Sendable {
    private let queue = DispatchQueue(label: "io.macinotch.screenshots")
    private var timer: DispatchSourceTimer?
    private var seen: Set<String> = []
    private var startedAt = Date()
    private var primed = false
    private let onCatch: @Sendable (String) -> Void
    private let enabled: @Sendable () -> Bool

    init(enabled: @escaping @Sendable () -> Bool,
         onCatch: @escaping @Sendable (String) -> Void) {
        self.enabled = enabled
        self.onCatch = onCatch
    }

    static var captureDirectory: String {
        let defaults = UserDefaults(suiteName: "com.apple.screencapture")
        if let location = defaults?.string(forKey: "location"), !location.isEmpty {
            return (location as NSString).expandingTildeInPath
        }
        return NSHomeDirectory() + "/Desktop"
    }

    func start(interval: TimeInterval = 2) {
        startedAt = Date()

        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + interval, repeating: interval)
        t.setEventHandler { [weak self] in self?.tick() }
        t.resume()
        timer = t

        queue.async { [weak self] in
            guard let self else { return }
            self.seen = Set(Self.candidates(in: Self.captureDirectory).map(\.path))
            self.primed = true
        }
    }

    func stop() { timer?.cancel(); timer = nil }

    private func tick() {
        guard enabled(), primed else { return }
        for url in Self.candidates(in: Self.captureDirectory) {
            guard !seen.contains(url.path) else { continue }
            seen.insert(url.path)

            let created = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate ?? .distantPast
            guard created > startedAt else { continue }
            guard Self.isSettled(url) else {
                seen.remove(url.path)
                continue
            }
            onCatch(url.path)
        }
    }

    private static func isSettled(_ url: URL) -> Bool {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? Int64, size > 0 else { return false }
        Thread.sleep(forTimeInterval: 0.25)
        guard let again = try? FileManager.default.attributesOfItem(atPath: url.path),
              let secondSize = again[.size] as? Int64 else { return false }
        return size == secondSize
    }

    private static func candidates(in directory: String) -> [URL] {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: URL(fileURLWithPath: directory),
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]) else { return [] }

        return entries.filter { url in
            let ext = url.pathExtension.lowercased()
            guard ["png", "jpg", "jpeg", "mov", "heic"].contains(ext) else { return false }
            let name = url.lastPathComponent
            return name.hasPrefix("Screenshot") || name.hasPrefix("Screen Shot")
                || name.hasPrefix("Screen Recording") || name.hasPrefix("CleanShot")
        }
    }
}
