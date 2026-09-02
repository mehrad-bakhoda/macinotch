import AppKit

enum SoundCue: String, CaseIterable, Identifiable {
    case mail
    case buildFailure
    case limitWarning
    case availableAgain
    case attention
    case systemAlert
    case dictation

    var id: String { rawValue }

    var label: String {
        switch self {
        case .mail: return "Mail arrives"
        case .buildFailure: return "A workflow fails"
        case .limitWarning: return "A limit is close"
        case .availableAgain: return "Something is usable again"
        case .attention: return "Claude Code wants you"
        case .systemAlert: return "The machine needs attention"
        case .dictation: return "A dictated note is saved"
        }
    }

    @MainActor var chosen: String {
        let p = Prefs.shared.d
        switch self {
        case .mail: return p.cueMail
        case .buildFailure: return p.cueBuildFailure
        case .limitWarning: return p.cueLimitWarning
        case .availableAgain: return p.cueAvailableAgain
        case .attention: return p.cueAttention
        case .systemAlert: return p.cueSystemAlert
        case .dictation: return p.cueDictation
        }
    }
}

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

    static let bundledNames = ["notify", "success", "attention", "error",
                               "tick", "mail", "failure", "ready"]

    static func play(cue: SoundCue) {
        guard Prefs.shared.d.soundSet != "silent" else { return }
        let name = cue.chosen
        guard name != "none" else { return }
        sound(named: name)?.play()
    }

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
