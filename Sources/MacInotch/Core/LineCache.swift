import Foundation

final class LineCache<Item>: @unchecked Sendable {
    private struct Entry {
        var size: UInt64
        var offset: UInt64
        var items: [Item]
    }

    private let lock = NSLock()
    private var store: [String: Entry] = [:]
    private let cap: Int
    private let filter: String?

    init(cap: Int = 6000, containing filter: String? = nil) {
        self.cap = cap
        self.filter = filter
    }

    func items(at url: URL, parse: (Substring) -> Item?) -> [Item] {
        let path = url.path
        let attributes = try? FileManager.default.attributesOfItem(atPath: path)
        let size = (attributes?[.size] as? NSNumber)?.uint64Value ?? 0
        guard size > 0 else { return [] }

        lock.lock()
        var entry = store[path] ?? Entry(size: 0, offset: 0, items: [])
        lock.unlock()

        if size < entry.size {
            entry = Entry(size: 0, offset: 0, items: [])
        }
        guard size > entry.offset else { return entry.items }

        guard let handle = FileHandle(forReadingAtPath: path) else { return entry.items }
        defer { try? handle.close() }

        var from = entry.offset
        if entry.offset == 0, size > Self.firstReadLimit {
            from = size - Self.firstReadLimit
        }
        try? handle.seek(toOffset: from)
        guard let data = try? handle.readToEnd(), !data.isEmpty else {
            return entry.items
        }

        let text = String(decoding: data, as: UTF8.self)
        guard let lastBreak = text.lastIndex(of: "\n") else { return entry.items }

        let complete = text[text.startIndex..<lastBreak]
        let consumed = complete.utf8.count + 1

        for line in complete.split(separator: "\n") {
            if let filter, !line.contains(filter) { continue }
            if let item = parse(line) { entry.items.append(item) }
        }
        if entry.items.count > cap {
            entry.items.removeFirst(entry.items.count - cap)
        }

        entry.offset = from + UInt64(consumed)
        entry.size = size

        lock.lock()
        store[path] = entry
        if store.count > 400 { store.removeAll() }
        lock.unlock()

        return entry.items
    }

    func forget() {
        lock.lock(); store.removeAll(); lock.unlock()
    }

    private static var firstReadLimit: UInt64 { 3_000_000 }
}
