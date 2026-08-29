import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ShelfItem: Identifiable, Codable, Equatable {
    var id = UUID()
    var path: String
    var addedAt: Date = .now
    var pile: String = "General"

    var url: URL { URL(fileURLWithPath: path) }
    var name: String { url.lastPathComponent }
    var exists: Bool { FileManager.default.fileExists(atPath: path) }

    var isDirectory: Bool {
        var isDir: ObjCBool = false
        FileManager.default.fileExists(atPath: path, isDirectory: &isDir)
        return isDir.boolValue
    }

    var sizeText: String {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
              let bytes = attrs[.size] as? Int64, !isDirectory else { return "" }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

@MainActor
final class ShelfStore: ObservableObject {
    static let shared = ShelfStore()
    static let limit = 24

    @Published private(set) var allItems: [ShelfItem] = []
    @Published var targeted = false
    @Published var activePile: String = "General"

    var piles: [String] {
        var names = Prefs.shared.d.shelfPiles
        if names.isEmpty { names = ["General"] }
        for item in allItems where !names.contains(item.pile) { names.append(item.pile) }
        return names
    }

    var items: [ShelfItem] { allItems.filter { $0.pile == activePile } }

    func count(in pile: String) -> Int { allItems.filter { $0.pile == pile }.count }

    func move(_ item: ShelfItem, to pile: String) {
        guard let index = allItems.firstIndex(where: { $0.id == item.id }) else { return }
        allItems[index].pile = pile
        save()
    }

    func addPile(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !Prefs.shared.d.shelfPiles.contains(trimmed) else { return }
        Prefs.shared.d.shelfPiles.append(trimmed)
        activePile = trimmed
    }

    func removePile(_ name: String) {
        guard piles.count > 1 else { return }
        allItems.removeAll { $0.pile == name }
        Prefs.shared.d.shelfPiles.removeAll { $0 == name }
        if activePile == name { activePile = piles.first ?? "General" }
        save()
    }

    private let url: URL

    private init() {
        let dir = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MacInotch", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        url = dir.appendingPathComponent("shelf.json")
        load()
        prune()
    }

    @discardableResult
    func add(paths: [String]) -> Int {
        var added = 0
        for path in paths {
            guard FileManager.default.fileExists(atPath: path) else { continue }

            if let existing = allItems.firstIndex(where: { $0.path == path
                                                            && $0.pile == activePile }) {
                allItems[existing].addedAt = .now
                continue
            }
            allItems.append(ShelfItem(path: path, pile: activePile))
            added += 1
        }
        if allItems.count > Self.limit {
            allItems.removeFirst(allItems.count - Self.limit)
        }
        save()
        return added
    }

    func remove(_ item: ShelfItem) {
        allItems.removeAll { $0.id == item.id }
        save()
    }

    func clear() {
        allItems.removeAll { $0.pile == activePile }
        save()
    }

    func prune() {
        let before = allItems.count
        allItems.removeAll { !$0.exists }
        if allItems.count != before { save() }
    }

    func revealInFinder(_ item: ShelfItem) {
        NSWorkspace.shared.activateFileViewerSelecting([item.url])
    }

    func open(_ item: ShelfItem) {
        NSWorkspace.shared.open(item.url)
    }

    func copyPath(_ item: ShelfItem) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(item.path, forType: .string)
    }

    func copyFile(_ item: ShelfItem) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([item.url as NSURL])
    }

    func share(_ item: ShelfItem, from view: NSView?) {
        let picker = NSSharingServicePicker(items: [item.url])
        guard let view, view.window != nil else { return }
        picker.show(relativeTo: view.bounds, of: view, preferredEdge: .minY)
    }

    func airdrop(_ items: [ShelfItem]) {
        let urls = items.map(\.url)
        guard !urls.isEmpty,
              let service = NSSharingService(named: .sendViaAirDrop) else { return }
        service.perform(withItems: urls)
    }

    func compress(_ items: [ShelfItem]) {
        let urls = items.map(\.url)
        guard let first = urls.first else { return }
        let parent = first.deletingLastPathComponent()
        let base = urls.count == 1
            ? first.deletingPathExtension().lastPathComponent
            : "Archive"
        var destination = parent.appendingPathComponent(base + ".zip")
        var counter = 2
        while FileManager.default.fileExists(atPath: destination.path) {
            destination = parent.appendingPathComponent("\(base) \(counter).zip")
            counter += 1
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-c", "-k", "--sequesterRsrc", "--keepParent"]
            + urls.map(\.path) + [destination.path]
        process.terminationHandler = { proc in
            Task { @MainActor in
                var payload = NotchPayload()
                payload.source = "system"
                payload.key = "zip"
                payload.timeout = 6
                if proc.terminationStatus == 0 {
                    payload.kind = "success"
                    payload.title = "Compressed"
                    payload.body = destination.lastPathComponent
                    ShelfStore.shared.add(paths: [destination.path])
                } else {
                    payload.kind = "error"
                    payload.title = "Compression failed"
                    payload.body = destination.lastPathComponent
                }
                NotchState.shared.handle(payload)
            }
        }
        try? process.run()
    }

    func moveToTrash(_ item: ShelfItem) {
        try? FileManager.default.trashItem(at: item.url, resultingItemURL: nil)
        remove(item)
    }

    func icon(for item: ShelfItem) -> NSImage {
        let icon = NSWorkspace.shared.icon(forFile: item.path)
        icon.size = NSSize(width: 64, height: 64)
        return icon
    }

    private func load() {
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([ShelfItem].self, from: data)
        else { return }
        allItems = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(allItems) else { return }
        try? data.write(to: url, options: .atomic)
    }

    func accept(_ providers: [NSItemProvider]) -> Bool {
        let relevant = providers.filter { $0.hasItemConformingToTypeIdentifier(
            UTType.fileURL.identifier) }
        guard !relevant.isEmpty else { return false }

        for provider in relevant {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { item, _ in
                var resolved: URL?
                if let data = item as? Data {
                    resolved = URL(dataRepresentation: data, relativeTo: nil)
                } else if let url = item as? URL {
                    resolved = url
                }
                guard let resolved else { return }
                Task { @MainActor in
                    self.add(paths: [resolved.path])
                    NotchState.shared.noteShelfDrop()
                }
            }
        }
        return true
    }
}
