import SwiftUI
import AppKit

enum OpenAnimation: String, Codable, CaseIterable, Identifiable {
    case spring
    case snappy
    case smooth
    case bounce
    case fade
    case instant

    var id: String { rawValue }

    var label: String {
        switch self {
        case .spring:  return "Spring"
        case .snappy:  return "Snappy"
        case .smooth:  return "Smooth"
        case .bounce:  return "Playful"
        case .fade:    return "Fade"
        case .instant: return "Instant"
        }
    }

    var opening: Animation {
        switch self {
        case .spring:  return .spring(duration: 0.46, bounce: 0.32)
        case .snappy:  return .spring(duration: 0.30, bounce: 0.16)
        case .smooth:  return .spring(duration: 0.44, bounce: 0)
        case .bounce:  return .spring(duration: 0.58, bounce: 0.52)
        case .fade:    return .easeOut(duration: 0.26)
        case .instant: return .linear(duration: 0.01)
        }
    }

    var closing: Animation {
        switch self {
        case .spring:  return .spring(duration: 0.28, bounce: 0.04)
        case .snappy:  return .spring(duration: 0.20, bounce: 0)
        case .smooth:  return .spring(duration: 0.30, bounce: 0)
        case .bounce:  return .spring(duration: 0.34, bounce: 0.14)
        case .fade:    return .easeIn(duration: 0.18)
        case .instant: return .linear(duration: 0.01)
        }
    }

    var openDelay: Double {
        switch self {
        case .spring:  return 0.09
        case .snappy:  return 0.05
        case .smooth:  return 0.10
        case .bounce:  return 0.15
        case .fade:    return 0.02
        case .instant: return 0
        }
    }

    var contentRise: CGFloat {
        switch self {
        case .bounce:  return 12
        case .fade:    return 0
        case .instant: return 0
        default:       return 7
        }
    }

    var contentScale: CGFloat {
        switch self {
        case .bounce:  return 0.94
        case .fade, .instant: return 1
        default:       return 0.975
        }
    }
}

enum AppearanceMode: String, Codable, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
}

struct Theme {
    var isDark: Bool

    var panelTint: Color
    var raised: Color
    var raisedStroke: Color
    var separator: Color
    var wellFill: Color

    var primary: Color
    var secondary: Color
    var tertiary: Color

    var blue: Color
    var green: Color
    var orange: Color
    var red: Color
    var purple: Color
    var yellow: Color
    var teal: Color

    var accent: Color

    static func make(dark: Bool, accent: Color) -> Theme {
        dark
        ? Theme(
            isDark: true,
            panelTint: Color(white: 0.06).opacity(0.72),
            raised: Color.white.opacity(0.07),
            raisedStroke: Color.white.opacity(0.09),
            separator: Color.white.opacity(0.12),
            wellFill: Color.white.opacity(0.12),
            primary: Color.white.opacity(0.96),
            secondary: Color.white.opacity(0.60),
            tertiary: Color.white.opacity(0.38),
            blue:   Color(hex: "#0A84FF")!,
            green:  Color(hex: "#30D158")!,
            orange: Color(hex: "#FF9F0A")!,
            red:    Color(hex: "#FF453A")!,
            purple: Color(hex: "#BF5AF2")!,
            yellow: Color(hex: "#FFD60A")!,
            teal:   Color(hex: "#40C8E0")!,
            accent: accent)
        : Theme(
            isDark: false,
            panelTint: Color(white: 0.99).opacity(0.62),
            raised: Color.black.opacity(0.045),
            raisedStroke: Color.black.opacity(0.07),
            separator: Color.black.opacity(0.10),
            wellFill: Color.black.opacity(0.10),
            primary: Color.black.opacity(0.92),
            secondary: Color.black.opacity(0.56),
            tertiary: Color.black.opacity(0.36),
            blue:   Color(hex: "#007AFF")!,
            green:  Color(hex: "#34C759")!,
            orange: Color(hex: "#FF9500")!,
            red:    Color(hex: "#FF3B30")!,
            purple: Color(hex: "#AF52DE")!,
            yellow: Color(hex: "#FFCC00")!,
            teal:   Color(hex: "#30B0C7")!,
            accent: accent)
    }

    var cardGradient: LinearGradient {
        LinearGradient(
            colors: isDark
                ? [Color.white.opacity(0.085), Color.white.opacity(0.035)]
                : [Color.white.opacity(0.75), Color.white.opacity(0.45)],
            startPoint: .top, endPoint: .bottom)
    }

    var cardStroke: LinearGradient {
        LinearGradient(
            colors: isDark
                ? [Color.white.opacity(0.16), Color.white.opacity(0.05)]
                : [Color.white.opacity(0.95), Color.black.opacity(0.05)],
            startPoint: .top, endPoint: .bottom)
    }

    var control: Color { isDark ? Color.white.opacity(0.12) : Color.black.opacity(0.06) }
    var controlHover: Color { isDark ? Color.white.opacity(0.18) : Color.black.opacity(0.10) }
    var hairline: Color { isDark ? Color.white.opacity(0.08) : Color.black.opacity(0.07) }

    func load(_ v: Double) -> Color {
        switch v {
        case ..<0.60: return green
        case ..<0.85: return orange
        default:      return red
        }
    }
}

@MainActor
final class ThemeManager: ObservableObject {
    static let shared = ThemeManager()
    static let appearanceChanged = Notification.Name("io.macinotch.appearanceChanged")

    @Published private(set) var theme: Theme = .make(dark: true, accent: .orange)

    private init() {
        refresh()
        DistributedNotificationCenter.default.addObserver(
            forName: Notification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeOcclusionStateNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func refresh() {
        let p = Prefs.shared.d

        switch p.appearance {
        case .system: NSApp?.appearance = nil
        case .light:  NSApp?.appearance = NSAppearance(named: .aqua)
        case .dark:   NSApp?.appearance = NSAppearance(named: .darkAqua)
        }

        let dark: Bool
        switch p.appearance {
        case .light: dark = false
        case .dark:  dark = true
        case .system:
            let match = NSApp?.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua])
            dark = match == .darkAqua
        }

        let accent: Color = p.accentFollowsSystem
            ? Color(nsColor: .controlAccentColor)
            : (Color(hex: p.accentHex) ?? Color(hex: "#FF9F0A")!)

        let next = Theme.make(dark: dark, accent: accent)
        theme = next
        SettingsWindow.shared.applyAppearance()
        NotificationCenter.default.post(name: Self.appearanceChanged, object: nil)
    }
}
