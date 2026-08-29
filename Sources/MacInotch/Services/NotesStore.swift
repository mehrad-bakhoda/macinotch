import Foundation
import AppKit
import SwiftUI

struct Note: Identifiable, Equatable {
    var id: String
    var path: String
    var text: String
    var modified: Date
    var colorIndex: Int

    var title: String {
        let first = text.split(separator: "\n").first.map(String.init) ?? ""
        let trimmed = first.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? "Untitled" : trimmed
    }

    var snippet: String {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        guard lines.count > 1 else { return "" }
        return lines.dropFirst()
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var ago: String {
        let seconds = Int(Date().timeIntervalSince(modified))
        if seconds < 90 { return "just now" }
        if seconds < 3600 { return "\(seconds / 60)m ago" }
        if seconds < 86400 { return "\(seconds / 3600)h ago" }
        return "\(seconds / 86400)d ago"
    }
}

@MainActor
final class NotesStore: ObservableObject {
    static let shared = NotesStore()

    static let palette: [Color] = [
        Color(hex: "#F5C451")!,
        Color(hex: "#7FC8F8")!,
        Color(hex: "#8FD9A8")!,
        Color(hex: "#F2A0A0")!,
        Color(hex: "#C3A6F0")!,
    ]

    @Published private(set) var notes: [Note] = []
    @Published var selected: String?
    @Published private(set) var lastError: String?

    private var watcher: DispatchSourceFileSystemObject?
    private var saveTasks: [String: Task<Void, Never>] = [:]

    private init() { reload() }

    var directory: URL {
        let configured = Prefs.shared.d.notesPath
        if !configured.isEmpty {
            return URL(fileURLWithPath: (configured as NSString).expandingTildeInPath)
        }
        return FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MacInotch Notes", isDirectory: true)
    }

    func reload() {
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            lastError = "Cannot use \(directory.path)"
            notes = []
            return
        }
        lastError = nil

        guard let entries = try? fm.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]) else { notes = []; return }

        var found: [Note] = []
        for url in entries where ["md", "txt"].contains(url.pathExtension.lowercased()) {
            let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
            let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate ?? .distantPast
            let name = url.deletingPathExtension().lastPathComponent
            found.append(Note(id: url.path, path: url.path, text: text,
                              modified: modified,
                              colorIndex: abs(name.hashValue) % Self.palette.count))
        }
        notes = found.sorted { $0.modified > $1.modified }
    }

    func color(_ note: Note) -> Color { Self.palette[note.colorIndex % Self.palette.count] }

    @discardableResult
    func create() -> Note? {
        let stamp = ISO8601DateFormatter().string(from: .now)
            .replacingOccurrences(of: ":", with: "-")
        let url = directory.appendingPathComponent("Note \(stamp).md")
        guard (try? "".write(to: url, atomically: true, encoding: .utf8)) != nil else {
            lastError = "Could not create a note in \(directory.path)"
            return nil
        }
        reload()
        selected = url.path
        return notes.first { $0.path == url.path }
    }

    func update(_ note: Note, text: String) {
        guard let index = notes.firstIndex(where: { $0.id == note.id }) else { return }
        notes[index].text = text
        notes[index].modified = .now
        scheduleSave(path: note.path, text: text)
    }

    func delete(_ note: Note) {
        try? FileManager.default.trashItem(at: URL(fileURLWithPath: note.path),
                                           resultingItemURL: nil)
        if selected == note.path { selected = nil }
        reload()
    }

    func reveal(_ note: Note) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: note.path)])
    }

    func revealFolder() {
        NSWorkspace.shared.activateFileViewerSelecting([directory])
    }

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = directory
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Prefs.shared.d.notesPath = url.path
        reload()
    }

    private func scheduleSave(path: String, text: String) {
        saveTasks[path]?.cancel()
        saveTasks[path] = Task { [weak self] in
            try? await Task.sleep(for: .seconds(0.8))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                do {
                    try text.write(to: URL(fileURLWithPath: path),
                                   atomically: true, encoding: .utf8)
                    self?.lastError = nil
                } catch {
                    self?.lastError = "Could not save \((path as NSString).lastPathComponent)"
                }
            }
        }
    }
}
