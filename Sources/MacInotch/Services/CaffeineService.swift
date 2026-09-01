import Foundation
import IOKit.pwr_mgt

@MainActor
final class CaffeineService: ObservableObject {
    static let shared = CaffeineService()

    @Published private(set) var active = false
    @Published private(set) var endsAt: Date?
    @Published private(set) var startedAt: Date?
    @Published private(set) var fill: Double = 0

    private var assertion: IOPMAssertionID = IOPMAssertionID(0)
    private var ticker: Timer?

    private init() {}

    static let durations: [(label: String, minutes: Double)] = [
        ("15 minutes", 15),
        ("30 minutes", 30),
        ("1 hour", 60),
        ("2 hours", 120),
        ("4 hours", 240),
        ("Until I turn it off", 0),
    ]

    var remainingText: String {
        guard let endsAt else { return "on" }
        let seconds = Int(max(0, endsAt.timeIntervalSinceNow))
        let h = seconds / 3600, m = (seconds % 3600) / 60
        if h > 0 { return "\(h)h \(m)m left" }
        if m > 0 { return "\(m)m left" }
        return "\(seconds)s left"
    }

    var detail: String {
        guard active else { return "Sleep as usual" }
        return endsAt == nil ? "Awake until you stop it" : "Awake, \(remainingText)"
    }

    func toggle() { active ? stop() : start(minutes: Prefs.shared.d.caffeineMinutes) }

    func start(minutes: Double) {
        stopAssertion()

        let type = Prefs.shared.d.caffeineKeepsDisplayOn
            ? kIOPMAssertionTypeNoDisplaySleep
            : kIOPMAssertionTypePreventUserIdleSystemSleep

        var identifier = IOPMAssertionID(0)
        let created = IOPMAssertionCreateWithName(
            type as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            "MacInotch is keeping this Mac awake" as CFString,
            &identifier)

        guard created == kIOReturnSuccess else { return }

        assertion = identifier
        active = true
        startedAt = Date()
        endsAt = minutes > 0 ? Date().addingTimeInterval(minutes * 60) : nil
        fill = 0

        withAnimationIfPossible { self.fill = 1 }
        beginTicking()
    }

    func extend(minutes: Double) {
        guard active else { start(minutes: minutes); return }
        guard minutes > 0 else { endsAt = nil; fill = 1; return }
        endsAt = (endsAt ?? Date()).addingTimeInterval(minutes * 60)
    }

    func stop() {
        stopAssertion()
        ticker?.invalidate()
        ticker = nil
        active = false
        endsAt = nil
        startedAt = nil
        withAnimationIfPossible { self.fill = 0 }
    }

    private func stopAssertion() {
        guard assertion != IOPMAssertionID(0) else { return }
        IOPMAssertionRelease(assertion)
        assertion = IOPMAssertionID(0)
    }

    private func beginTicking() {
        ticker?.invalidate()
        ticker = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { _ in
            Task { @MainActor in CaffeineService.shared.tick() }
        }
    }

    private func tick() {
        guard active else { return }
        guard let endsAt, let startedAt else { fill = 1; return }

        if Date() >= endsAt {
            stop()
            var p = NotchPayload()
            p.source = NotchSource.system.rawValue
            p.kind = "info"
            p.key = "caffeine"
            p.title = "Back to normal sleep"
            p.body = "The Mac can sleep again"
            p.timeout = 6
            p.sound = true
            NotchState.shared.handle(p)
            return
        }

        let total = endsAt.timeIntervalSince(startedAt)
        guard total > 0 else { return }
        let left = endsAt.timeIntervalSinceNow / total
        fill = min(1, max(0.06, left))
    }

    private func withAnimationIfPossible(_ body: @escaping () -> Void) {
        body()
    }
}
