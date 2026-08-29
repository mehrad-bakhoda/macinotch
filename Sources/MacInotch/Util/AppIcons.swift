import AppKit
import SwiftUI

@MainActor
enum AppIcons {
    private static var cache: [NotchSource: NSImage?] = [:]
    private static var missedAt: [NotchSource: Date] = [:]

    private static func bundleIDs(_ source: NotchSource) -> [String] {
        switch source {
        case .claude:  return ["com.anthropic.claudefordesktop", "com.anthropic.claude"]

        case .chatgpt: return ["com.openai.chat", "com.openai.codex", "com.openai.chatgpt"]
        case .spotify: return ["com.spotify.client"]
        case .system, .custom: return []
        }
    }

    static func icon(for source: NotchSource) -> NSImage? {
        if let cached = cache[source], let img = cached { return img }

        if let missed = missedAt[source], Date().timeIntervalSince(missed) < 60 { return nil }

        let found = bundleIDs(source).lazy
            .compactMap { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }
            .first
            .map { url -> NSImage in
                let icon = NSWorkspace.shared.icon(forFile: url.path)

                icon.size = NSSize(width: 128, height: 128)
                return icon
            }

        if found == nil { missedAt[source] = Date() } else { missedAt[source] = nil }
        cache[source] = found
        return found
    }

    static func invalidate() { cache.removeAll(); missedAt.removeAll() }

    private static var playerCache: [String: NSImage?] = [:]

    static func player(_ app: String) -> NSImage? {
        if let cached = playerCache[app], let image = cached { return image }
        let bundle = app == "Music" ? "com.apple.Music" : "com.spotify.client"
        let found = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle)
            .map { url -> NSImage in
                let icon = NSWorkspace.shared.icon(forFile: url.path)
                icon.size = NSSize(width: 128, height: 128)
                return icon
            }
        playerCache[app] = found
        return found
    }
}

struct SourceIcon: View {
    var source: NotchSource
    var kind: NotchKind
    var theme: Theme
    var side: CGFloat = 26

    var muted: Bool = false

    var body: some View {
        Group {
            if let icon = AppIcons.icon(for: source) {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .saturation(muted ? 0 : 1)
                    .opacity(muted ? 0.45 : 1)
            } else {
                SourceGlyph(source: source, kind: kind, theme: theme, side: side)
            }
        }
        .frame(width: side, height: side)
    }
}
