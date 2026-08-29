import SwiftUI

enum NotchKind: String, Codable, CaseIterable {
    case info
    case success
    case warning
    case error
    case progress
    case attention
    case music

    func tint(_ t: Theme) -> Color {
        switch self {
        case .info:      return t.blue
        case .success:   return t.green
        case .warning:   return t.yellow
        case .error:     return t.red
        case .progress:  return t.purple
        case .attention: return t.orange
        case .music:     return t.green
        }
    }

    var symbol: String {
        switch self {
        case .info:      return "info.circle.fill"
        case .success:   return "checkmark.circle.fill"
        case .warning:   return "exclamationmark.triangle.fill"
        case .error:     return "xmark.octagon.fill"
        case .progress:  return "arrow.triangle.2.circlepath"
        case .attention: return "hand.raised.fill"
        case .music:     return "music.note"
        }
    }

    var isSticky: Bool { self == .attention }
}

enum NotchSource: String, Codable {
    case claude
    case chatgpt
    case spotify
    case system
    case custom

    func tint(_ t: Theme) -> Color {
        switch self {
        case .claude:  return Color(hex: t.isDark ? "#E08A63" : "#C4643C")!
        case .chatgpt: return Color(hex: t.isDark ? "#19C39C" : "#0E9E7B")!
        case .spotify: return Color(hex: t.isDark ? "#1ED760" : "#12A54A")!
        case .system:  return t.secondary
        case .custom:  return t.purple
        }
    }

    var symbol: String {
        switch self {
        case .claude:  return "sparkle"
        case .chatgpt: return "bubble.left.and.bubble.right.fill"
        case .spotify: return "music.note"
        case .system:  return "gearshape.fill"
        case .custom:  return "bell.fill"
        }
    }

    var displayName: String {
        switch self {
        case .claude:  return "Claude"
        case .chatgpt: return "ChatGPT"
        case .spotify: return "Spotify"
        case .system:  return "System"
        case .custom:  return "Notch"
        }
    }
}

struct NotchAction: Codable, Identifiable, Equatable {
    var id = UUID()
    var label: String
    var url: String?
    var command: String?

    enum CodingKeys: String, CodingKey { case label, url, command }
}

struct NotchPayload: Codable {
    var source: String?
    var title: String?
    var body: String?
    var kind: String?
    var progress: Double?
    var timeout: Double?
    var key: String?
    var sound: Bool?
    var dismiss: String?
    var actions: [NotchAction]?
}

struct NotchItem: Identifiable, Equatable {
    let id = UUID()
    var key: String
    var source: NotchSource
    var title: String
    var body: String
    var kind: NotchKind
    var progress: Double?
    var createdAt: Date = .now
    var expiresAt: Date?
    var acknowledged: Bool = false

    var artwork: NSImage?
    var actions: [NotchAction] = []

    static func == (a: NotchItem, b: NotchItem) -> Bool { a.id == b.id }

    func accent(_ t: Theme) -> Color {
        (kind == .attention || kind == .error) ? kind.tint(t) : source.tint(t)
    }
}
