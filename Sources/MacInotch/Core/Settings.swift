import SwiftUI

struct PrefsData: Codable, Equatable {

    var showGregorian   = true
    var showShamsi      = true
    var showHijri       = false
    var showClock       = true
    var clockSeconds    = false
    var showYearProgress = true
    var showWeekNumber  = true
    var showUptime      = true
    var showNowruz      = true

    var showRepo    = false
    var repoPath    = ""

    var showWeather        = true
    var weatherUseLocation = true
    var weatherLatitude    = 0.0
    var weatherLongitude   = 0.0
    var weatherFahrenheit  = false
    var idleShowWeather    = true

    var pomodoroFocusMinutes     = 25.0
    var pomodoroBreakMinutes     = 5.0
    var pomodoroLongBreakMinutes = 15.0
    var pomodoroRounds           = 4
    var pomodoroAutoContinue     = true

    var showCalendar          = true
    var calendarHorizonHours  = 12.0
    var calendarAllDay        = false

    var showCPU     = true
    var showRAM     = true
    var showSwap    = false
    var showBattery = true
    var showTemperature = true
    var fahrenheit      = false
    var showFans        = true
    var showPower       = true
    var showBluetooth   = true
    var showAudioSwitcher = true
    var batteryLimitNudge = true
    var batteryLimitPercent = 80.0
    var notesPath       = ""
    var meetingLocale   = "en-US"
    var meetingCapturesSystemAudio = true
    var meetingAutoRecord = false
    var stripEnabled     = true
    var stripDefault     = "volume"
    var ambientGlow      = false
    var ambientStyle     = "glow"
    var ambientWidth     = 1.6
    var ambientIntensity = 0.75
    var ambientSpeed     = 1.0
    var ambientOnFailure = true
    var ambientOnLimit   = true
    var ambientOnWaiting = true
    var ambientOnRecord  = true
    var ambientColorFailure = "#FF453A"
    var ambientColorLimit   = "#FF9F0A"
    var ambientColorWaiting = "#0A84FF"
    var ambientColorRecord  = "#FF375F"
    var showNotes       = true
    var menuBarHiding   = false
    var menuBarHidden   = false
    var menuBarAutoHideSeconds = 0.0
    var showSparklines  = true
    var showTopProcess  = true

    var showSessions         = true
    var sessionsShowClaude   = true
    var sessionsShowCodex    = true
    var sessionsActiveOnly   = false
    var showAccounts         = true
    var notifyOnUsageThreshold = true
    var alertDisk            = true
    var alertRunaway         = true
    var alertThermal         = true
    var alertBattery         = true
    var alertNetwork         = true
    var focusShortcut        = ""
    var showFocusRow         = true
    var suggestMeetingMode   = true
    var meetingMutesAudio    = true
    var meetingSilencesNotch = true
    var showReminders        = true
    var alertWorkflowFailure = true
    var showGitHub           = true
    var showQuickBar         = true
    var githubClientId       = ""
    var accountUsageSchema   = 0
    var claudePeakTokens     = 0
    var claudePeakMessages   = 0
    var rowsBeforeScrolling  = 7
    var calendarsExcluded: [String] = []
    var caffeineMinutes      = 60.0
    var caffeineKeepsDisplayOn = true
    var showMail             = true
    var notifyOnMail         = true
    var mailSummaries        = true
    var mailWindowHours      = 24.0
    var mailLimit            = 12
    var mailHasAccounts      = false
    var mailSortByImportance = true
    var mailNeedsReplyOnly   = false
    var showUsage            = true
    var usageWindowHours     = 5.0
    var notifyOnUsageReset   = true
    var usageShowClaude      = true
    var usageShowCodex       = true

    var showNowPlaying   = true
    var musicAutoPopup   = true
    var showVisualizer   = true
    var allowScrubbing   = true
    var haptics          = true

    var liveStripEnabled = true
    var liveStripPlacement: StripPlacement = .ears
    var liveLeft: LiveSlot  = .clock
    var liveRight: LiveSlot = .auto

    var bridgeEnabled       = false
    var bridgeAIOnly        = true
    var bridgeCustomBundles = ""

    var hoverToExpand   = true
    var peekSeconds     = 4.6
    var playSounds      = true
    var serverEnabled   = true
    var pollSeconds     = 2.0

    var appearance: AppearanceMode = .system
    var openAnimation: OpenAnimation = .spring
    var accentFollowsSystem = true
    var glassEnabled    = true
    var cornerRadius: Double = 20
    var expandedWidth: Double = 660
    var accentHex: String = "#FF9F0A"
    var persianDigits   = true
    var reduceMotion    = false
    var clock24h        = true

    var idleShowStats     = true
    var idleShowCPU       = true
    var idleShowRAM       = true
    var idleShowTemp      = true
    var idleShowPresence  = true
    var watchClaude       = true
    var watchChatGPT      = true
    var watchSpotify      = false

    var showNetwork = false
    var showDisk    = false

    var soundSet: String = "chime"

    var soundPerSource: [String: String] = [:]

    var keepHistory = true

    var followActiveDisplay = false

    var mutedUntil: Double = 0
    var respectFocus = true
    var quietApps    = ""

    var idleClockEnabled = false
    var idleClockMinutes = 5.0

    var shelfEnabled = true
    var shelfPiles: [String] = ["General", "Send", "Read later"]
    var clipboardEnabled = true
    var screenshotCatch = true

    var hasOnboarded  = false
    var hotKeyEnabled = true
    var hotKeyLabel   = "⌥⌘N"

    enum SourceRule: String, Codable, CaseIterable, Identifiable {
        case normal
        case sticky
        case silent
        case quiet
        case muted

        var id: String { rawValue }
        var label: String {
            switch self {
            case .normal: return "Normal"
            case .sticky: return "Always sticky"
            case .silent: return "Silent (no sound)"
            case .quiet:  return "No banner"
            case .muted:  return "Ignore"
            }
        }
    }

    var sourceRules: [String: SourceRule] = [:]

    enum StripItem: String, Codable, CaseIterable, Identifiable {
        case cpu, ram, temp, weather, battery, disk, network
        case clock, shamsi, date, uptime
        case presence, music, timer

        var id: String { rawValue }

        var label: String {
            switch self {
            case .cpu: return "CPU"
            case .ram: return "Memory"
            case .temp: return "Temperature"
            case .weather: return "Weather"
            case .battery: return "Battery"
            case .disk: return "Disk free"
            case .network: return "Network"
            case .clock: return "Clock"
            case .shamsi: return "Shamsi date"
            case .date: return "Date"
            case .uptime: return "Uptime"
            case .presence: return "App presence"
            case .music: return "Now playing"
            case .timer: return "Timer"
            }
        }

        var width: CGFloat {
            switch self {
            case .cpu, .ram, .temp, .weather, .battery, .disk: return 42
            case .network: return 58
            case .clock: return 46
            case .uptime: return 52
            case .shamsi: return 74
            case .date: return 58
            case .presence: return 44
            case .music: return 116
            case .timer: return 62
            }
        }
    }

    var idleLeft: [String] = ["cpu", "ram", "weather", "temp"]
    var idleRight: [String] = ["music", "presence"]

    enum StripPlacement: String, Codable, CaseIterable, Identifiable {
        case chin
        case ears
        var id: String { rawValue }
        var label: String {
            switch self {
            case .chin: return "Below the menu bar"
            case .ears: return "Beside the notch"
            }
        }
    }

    enum LiveSlot: String, Codable, CaseIterable, Identifiable {
        case off, clock, shamsi, cpu, ram, battery, music, auto
        var id: String { rawValue }
        var label: String {
            switch self {
            case .off:     return "Off"
            case .clock:   return "Clock"
            case .shamsi:  return "Shamsi date"
            case .cpu:     return "CPU"
            case .ram:     return "RAM"
            case .battery: return "Battery"
            case .music:   return "Music"
            case .auto:    return "Auto (music → activity)"
            }
        }
    }
}

@MainActor
final class Prefs: ObservableObject {
    static let shared = Prefs()
    private static let key = "io.macinotch.prefs.v1"

    @Published var d: PrefsData { didSet { if d != oldValue { save() } } }

    @discardableResult
    func apply(patch: Data) -> Bool {
        guard let incoming = try? JSONSerialization.jsonObject(with: patch) as? [String: Any],
              let currentData = try? JSONEncoder().encode(d),
              var merged = try? JSONSerialization.jsonObject(with: currentData)
                  as? [String: Any] else { return false }

        for (k, v) in incoming where merged[k] != nil { merged[k] = v }

        guard let mergedData = try? JSONSerialization.data(withJSONObject: merged),
              let decoded = try? JSONDecoder().decode(PrefsData.self, from: mergedData)
        else { return false }
        d = decoded
        return true
    }

    func publish() {
        guard let raw = try? JSONEncoder().encode(d) else { return }
        SnapshotStore.shared.setPrefs(String(decoding: raw, as: UTF8.self))
    }

    static var configURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/macinotch/config.json")
    }

    func loadConfigFile() -> Bool {
        guard let data = try? Data(contentsOf: Self.configURL) else { return false }
        return apply(patch: data)
    }

    func writeConfigFile() {
        let dir = Self.configURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(d) else { return }
        try? data.write(to: Self.configURL, options: .atomic)
    }

    private init() {

        var initial = Self.decodeLeniently(UserDefaults.standard.data(forKey: Self.key))
        if let data = try? Data(contentsOf: Self.configURL) {
            initial = Self.merge(data, onto: initial)
        }
        d = initial
    }

    static func merge(_ patch: Data, onto base: PrefsData) -> PrefsData {
        guard let incoming = try? JSONSerialization.jsonObject(with: patch) as? [String: Any],
              let baseData = try? JSONEncoder().encode(base),
              var merged = try? JSONSerialization.jsonObject(with: baseData) as? [String: Any]
        else { return base }
        for (key, value) in incoming where merged[key] != nil { merged[key] = value }
        guard let mergedData = try? JSONSerialization.data(withJSONObject: merged),
              let decoded = try? JSONDecoder().decode(PrefsData.self, from: mergedData)
        else { return base }
        return decoded
    }

    static func decodeLeniently(_ raw: Data?) -> PrefsData {
        let defaults = PrefsData()
        guard let raw,
              let stored = try? JSONSerialization.jsonObject(with: raw) as? [String: Any],
              let defaultData = try? JSONEncoder().encode(defaults),
              var merged = try? JSONSerialization.jsonObject(with: defaultData)
                  as? [String: Any]
        else { return defaults }

        for (key, value) in stored where merged[key] != nil { merged[key] = value }

        guard let mergedData = try? JSONSerialization.data(withJSONObject: merged),
              let decoded = try? JSONDecoder().decode(PrefsData.self, from: mergedData)
        else { return defaults }
        return decoded
    }

    private func save() {
        guard let raw = try? JSONEncoder().encode(d) else { return }
        UserDefaults.standard.set(raw, forKey: Self.key)

        ThemeManager.shared.refresh()
        AppDelegate.applyHotKey()
        publish()
    }

    func reset() { d = PrefsData() }

    var accent: Color { Color(hex: d.accentHex) ?? Color(red: 1.0, green: 0.48, blue: 0.18) }
}

extension Color {
    init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        self.init(red: Double((v >> 16) & 0xFF) / 255,
                  green: Double((v >> 8) & 0xFF) / 255,
                  blue: Double(v & 0xFF) / 255)
    }
}
