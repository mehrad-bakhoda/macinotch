import AppKit

@MainActor
enum SoundKit {
    private static var cache: [String: NSSound] = [:]

    static func play(for kind: NotchKind, source: NotchSource = .custom) {
        guard Prefs.shared.d.playSounds else { return }

        if let override = Prefs.shared.d.soundPerSource[source.rawValue],
           override != "default" {
            if override == "none" { return }
            sound(named: override)?.play()
            return
        }

        if Prefs.shared.d.soundSet == "system" {
            NSSound(named: systemName(for: kind))?.play()
            return
        }
        sound(named: bundledName(for: kind))?.play()
    }

    static let bundledNames = ["notify", "success", "attention", "error", "tick"]

    static func tap(_ pattern: NSHapticFeedbackManager.FeedbackPattern = .generic) {
        guard Prefs.shared.d.haptics else { return }
        NSHapticFeedbackManager.defaultPerformer.perform(pattern, performanceTime: .now)
    }

    static func preview(_ name: String) { sound(named: name)?.play() }

    private static func bundledName(for kind: NotchKind) -> String {
        switch kind {
        case .success:            return "success"
        case .error:              return "error"
        case .warning, .attention: return "attention"
        case .progress, .music:   return "tick"
        case .info:               return "notify"
        }
    }

    private static func systemName(for kind: NotchKind) -> String {
        switch kind {
        case .error:   return "Basso"
        case .success: return "Glass"
        case .attention, .warning: return "Funk"
        default:       return "Tink"
        }
    }

    private static func sound(named name: String) -> NSSound? {
        if let s = cache[name] { s.stop(); s.currentTime = 0; return s }
        guard let url = Bundle.main.url(forResource: name, withExtension: "wav",
                                        subdirectory: "Sounds")
                ?? Bundle.main.url(forResource: name, withExtension: "wav"),
              let s = NSSound(contentsOf: url, byReference: false) else { return nil }
        cache[name] = s
        return s
    }
}
