import AppKit
import SwiftUI

struct ClipEntry: Identifiable, Codable, Equatable {
    enum Kind: String, Codable { case text, image, files }

    var id = UUID()
    var kind: Kind
    var text: String
    var imageFile: String?
    var paths: [String] = []
    var createdAt: Date = .now
    var pinned = false

    var preview: String {
        switch kind {
        case .text:
            let flat = text
                .replacingOccurrences(of: "\n", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return flat.isEmpty ? "empty" : flat
        case .image:
            return "Image"
        case .files:
            return paths.map { ($0 as NSString).lastPathComponent }
                .joined(separator: ", ")
        }
    }

    var detail: String {
        switch kind {
        case .text:  return "\(text.count) characters"
        case .image: return "Image"
        case .files: return "\(paths.count) file\(paths.count == 1 ? "" : "s")"
        }
    }

    var symbol: String {
        switch kind {
        case .text:  return "textformat"
        case .image: return "photo"
        case .files: return "doc.on.doc"
        }
    }
}

@MainActor
final class ClipboardService: ObservableObject {
    static let shared = ClipboardService()
    static let limit = 120

    @Published private(set) var entries: [ClipEntry] = []

    private var timer: Timer?
    private var lastChangeCount = NSPasteboard.general.changeCount
    private var suppressUntil: Date = .distantPast

    private let directory: URL
    private let indexURL: URL

    private init() {
        directory = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MacInotch/Clipboard", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory,
                                                 withIntermediateDirectories: true)
        indexURL = directory.appendingPathComponent("index.json")
        load()
    }

    func start() {
        guard Prefs.shared.d.clipboardEnabled else { return }
        let t = Timer.scheduledTimer(withTimeInterval: 0.6, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.poll() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() { timer?.invalidate(); timer = nil }

    func restart() {
        stop()
        start()
    }

    var pinned: [ClipEntry] { entries.filter(\.pinned).reversed() }
    var recent: [ClipEntry] { entries.filter { !$0.pinned }.reversed() }

    func image(for entry: ClipEntry) -> NSImage? {
        guard let name = entry.imageFile else { return nil }
        return NSImage(contentsOf: directory.appendingPathComponent(name))
    }

    private func poll() {
        let board = NSPasteboard.general
        guard board.changeCount != lastChangeCount else { return }
        lastChangeCount = board.changeCount
        guard Date() > suppressUntil, Prefs.shared.d.clipboardEnabled else { return }

        if board.types?.contains(.fileURL) == true,
           let urls = board.readObjects(forClasses: [NSURL.self]) as? [URL], !urls.isEmpty {
            add(ClipEntry(kind: .files, text: "", paths: urls.map(\.path)))
            return
        }

        if let string = board.string(forType: .string),
           !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            add(ClipEntry(kind: .text, text: String(string.prefix(20_000))))
            return
        }

        if let data = board.data(forType: .tiff) ?? board.data(forType: .png),
           let image = NSImage(data: data) {
            guard let name = writeThumbnail(image) else { return }
            add(ClipEntry(kind: .image, text: "", imageFile: name))
        }
    }

    private func add(_ entry: ClipEntry) {
        if let index = entries.firstIndex(where: { $0.kind == entry.kind
                                                   && $0.text == entry.text
                                                   && $0.paths == entry.paths
                                                   && entry.kind != .image }) {
            entries[index].createdAt = .now
            save()
            return
        }
        entries.append(entry)
        prune()
        save()
    }

    private func prune() {
        let unpinned = entries.filter { !$0.pinned }
        guard unpinned.count > Self.limit else { return }
        let excess = unpinned.count - Self.limit
        var removed = 0
        entries.removeAll { candidate in
            guard removed < excess, !candidate.pinned else { return false }
            removed += 1
            if let file = candidate.imageFile {
                try? FileManager.default.removeItem(
                    at: directory.appendingPathComponent(file))
            }
            return true
        }
    }

    private func writeThumbnail(_ image: NSImage) -> String? {
        let maxSide: CGFloat = 320
        let size = image.size
        guard size.width > 0, size.height > 0 else { return nil }
        let scale = min(1, maxSide / max(size.width, size.height))
        let target = NSSize(width: size.width * scale, height: size.height * scale)

        let thumb = NSImage(size: target)
        thumb.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: target))
        thumb.unlockFocus()

        guard let tiff = thumb.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return nil }

        let name = UUID().uuidString + ".png"
        try? png.write(to: directory.appendingPathComponent(name))
        return name
    }

    func copy(_ entry: ClipEntry) {
        suppressUntil = Date().addingTimeInterval(1.2)
        let board = NSPasteboard.general
        board.clearContents()

        switch entry.kind {
        case .text:
            board.setString(entry.text, forType: .string)
        case .files:
            board.writeObjects(entry.paths.map { URL(fileURLWithPath: $0) as NSURL })
        case .image:
            if let image = image(for: entry) { board.writeObjects([image]) }
        }
        lastChangeCount = board.changeCount
        SoundKit.tap()
    }

    func togglePin(_ entry: ClipEntry) {
        guard let index = entries.firstIndex(where: { $0.id == entry.id }) else { return }
        entries[index].pinned.toggle()
        save()
    }

    func remove(_ entry: ClipEntry) {
        if let file = entry.imageFile {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(file))
        }
        entries.removeAll { $0.id == entry.id }
        save()
    }

    func clearUnpinned() {
        for entry in entries where !entry.pinned {
            if let file = entry.imageFile {
                try? FileManager.default.removeItem(
                    at: directory.appendingPathComponent(file))
            }
        }
        entries.removeAll { !$0.pinned }
        save()
    }

    private func load() {
        guard let data = try? Data(contentsOf: indexURL),
              let decoded = try? JSONDecoder().decode([ClipEntry].self, from: data)
        else { return }
        entries = decoded
    }

    private var saveTask: Task<Void, Never>?

    private func save() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self, let data = try? JSONEncoder().encode(self.entries) else { return }
                try? data.write(to: self.indexURL, options: .atomic)
            }
        }
    }
}
