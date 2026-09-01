import AppKit
import Foundation

@MainActor
final class CaptureService: ObservableObject {
    static let shared = CaptureService()

    @Published private(set) var recording = false
    @Published private(set) var startedAt: Date?

    private var task: Process?
    private var output: URL?

    private init() {}

    var elapsed: String {
        guard let startedAt else { return "0:00" }
        let seconds = Int(Date().timeIntervalSince(startedAt))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    static var saveDirectory: URL {
        if let custom = UserDefaults(suiteName: "com.apple.screencapture")?
            .string(forKey: "location") {
            return URL(fileURLWithPath: (custom as NSString).expandingTildeInPath)
        }
        return FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)[0]
    }

    func toggle() { recording ? stop() : start() }

    func start() {
        guard !recording else { return }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        let name = "Screen Recording \(formatter.string(from: Date())).mov"
        let destination = Self.saveDirectory.appendingPathComponent(name)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-v", destination.path]
        process.standardError = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice

        guard (try? process.run()) != nil else { return }

        task = process
        output = destination
        startedAt = Date()
        recording = true

        process.terminationHandler = { _ in
            Task { @MainActor in CaptureService.shared.finish() }
        }
    }

    func stop() {
        guard let task, task.isRunning else { finish(); return }
        kill(task.processIdentifier, SIGINT)
    }

    private func finish() {
        recording = false
        startedAt = nil
        task = nil

        guard let url = output else { return }
        output = nil
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 900_000_000)
            guard FileManager.default.fileExists(atPath: url.path) else { return }
            _ = ShelfStore.shared.add(paths: [url.path])
        }
    }
}

@MainActor
enum FocusController {
    static func shortcuts() -> [String] {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
        task.arguments = ["list"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        guard (try? task.run()) != nil else { return [] }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    @discardableResult
    static func run(_ name: String) -> Bool {
        guard !name.isEmpty else { return false }
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
        task.arguments = ["run", name]
        task.standardError = FileHandle.nullDevice
        task.standardOutput = FileHandle.nullDevice
        guard (try? task.run()) != nil else { return false }
        task.waitUntilExit()
        return task.terminationStatus == 0
    }
}
