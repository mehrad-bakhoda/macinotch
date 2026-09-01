import AppKit
import Foundation

@MainActor
final class MeetingMode: ObservableObject {
    static let shared = MeetingMode()

    @Published private(set) var active = false
    @Published private(set) var endsAt: Date?

    private var wasMuted = false
    private var offered: Set<String> = []
    private var timer: Timer?

    private init() {}

    func start() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { _ in
            Task { @MainActor in MeetingMode.shared.tick() }
        }
    }

    func stop() { timer?.invalidate(); timer = nil }

    private func tick() {
        if let endsAt, Date() >= endsAt { disable() }

        guard Prefs.shared.d.suggestMeetingMode,
              let event = CalendarService.shared.next,
              event.joinURL != nil, event.isRunning else { return }

        let key = "\(event.title)-\(event.start.timeIntervalSince1970)"
        guard !offered.contains(key), !active else { return }
        offered.insert(key)

        var p = NotchPayload()
        p.source = NotchSource.system.rawValue
        p.kind = "attention"
        p.key = "meeting-\(key)"
        p.title = event.title
        p.body = "Started \(event.countdown). Join, or go quiet until it ends."
        p.timeout = 60
        p.sound = true

        var actions: [NotchAction] = []
        if let url = event.joinURL {
            actions.append(NotchAction(label: "Join now", url: url.absoluteString))
        }
        actions.append(NotchAction(label: "Meeting mode",
                                   url: "macinotch://meeting?on=1"))
        p.actions = actions
        NotchState.shared.handle(p)
    }

    func enable(until end: Date?) {
        guard !active else { return }
        active = true
        endsAt = end ?? CalendarService.shared.next?.end

        if Prefs.shared.d.meetingMutesAudio {
            wasMuted = Self.muted()
            if !wasMuted { Self.setMuted(true) }
        }
        if Prefs.shared.d.meetingSilencesNotch {
            let minutes = (endsAt?.timeIntervalSinceNow ?? 3600) / 60
            NotchState.shared.mute(minutes: max(5, minutes))
        }
    }

    func disable() {
        guard active else { return }
        active = false
        endsAt = nil

        if Prefs.shared.d.meetingMutesAudio && !wasMuted { Self.setMuted(false) }
        wasMuted = false
        if Prefs.shared.d.meetingSilencesNotch { NotchState.shared.unmute() }
    }

    func toggle() { active ? disable() : enable(until: nil) }

    static func muted() -> Bool {
        run("output muted of (get volume settings)")?.contains("true") ?? false
    }

    static func setMuted(_ on: Bool) {
        _ = run("set volume \(on ? "with" : "without") output muted")
    }

    @discardableResult
    private static func run(_ source: String) -> String? {
        var error: NSDictionary?
        let value = NSAppleScript(source: source)?
            .executeAndReturnError(&error).stringValue
        return error == nil ? (value ?? "") : nil
    }
}
