import Foundation

struct HistoryEntry: Codable, Identifiable, Equatable {
    var id = UUID()
    var date: Date
    var source: String
    var kind: String
    var title: String
    var body: String

    var sourceValue: NotchSource { NotchSource(rawValue: source) ?? .custom }
    var kindValue: NotchKind { NotchKind(rawValue: kind) ?? .info }
}

@MainActor
final class HistoryStore: ObservableObject {
    static let shared = HistoryStore()

    static let limit = 300

    @Published private(set) var entries: [HistoryEntry] = []

    private let url: URL
    private var saveTask: Task<Void, Never>?

    private init() {
        let dir = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MacInotch", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        url = dir.appendingPathComponent("history.json")
        load()
    }

    func filtered(search: String, source: NotchSource?) -> [HistoryEntry] {
        var out = entries
        if let source { out = out.filter { $0.sourceValue == source } }
        let term = search.trimmingCharacters(in: .whitespaces).lowercased()
        if !term.isEmpty {
            out = out.filter {
                $0.title.lowercased().contains(term) || $0.body.lowercased().contains(term)
            }
        }
        return out.reversed()
    }

    var sourcesPresent: [NotchSource] {
        var seen: [NotchSource] = []
        for e in entries where !seen.contains(e.sourceValue) { seen.append(e.sourceValue) }
        return seen
    }

    func record(_ item: NotchItem) {

        if item.kind == .progress,
           let i = entries.lastIndex(where: { $0.title == item.title
                                              && $0.source == item.source.rawValue }) {
            entries[i].body = item.body
            entries[i].date = .now
            scheduleSave()
            return
        }

        entries.append(HistoryEntry(date: item.createdAt,
                                    source: item.source.rawValue,
                                    kind: item.kind.rawValue,
                                    title: item.title,
                                    body: item.body))
        if entries.count > Self.limit { entries.removeFirst(entries.count - Self.limit) }
        scheduleSave()
    }

    func clear() {
        entries.removeAll()
        scheduleSave()
    }

    private func load() {
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([HistoryEntry].self, from: data)
        else { return }
        entries = decoded
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            await MainActor.run { self?.save() }
        }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
