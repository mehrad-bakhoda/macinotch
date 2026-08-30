import Foundation
import SwiftUI

@MainActor
final class TimerService: ObservableObject {
    static let shared = TimerService()

    enum Phase: String {
        case idle
        case focus
        case shortBreak
        case longBreak

        var label: String {
            switch self {
            case .idle:       return "Timer"
            case .focus:      return "Focus"
            case .shortBreak: return "Break"
            case .longBreak:  return "Long break"
            }
        }

        var symbol: String {
            switch self {
            case .idle:       return "timer"
            case .focus:      return "brain.head.profile"
            case .shortBreak: return "cup.and.saucer.fill"
            case .longBreak:  return "figure.walk"
            }
        }
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var endsAt: Date?
    @Published private(set) var total: TimeInterval = 0
    @Published private(set) var paused = false
    @Published private(set) var remainingWhenPaused: TimeInterval = 0
    @Published private(set) var completedFocusRounds = 0

    private var ticker: Timer?

    var isRunning: Bool { phase != .idle }

    var remaining: TimeInterval {
        if paused { return remainingWhenPaused }
        guard let endsAt else { return 0 }
        return max(0, endsAt.timeIntervalSinceNow)
    }

    var fraction: Double {
        guard total > 0 else { return 0 }
        return min(1, max(0, 1 - remaining / total))
    }

    var readout: String {
        let seconds = Int(remaining.rounded())
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    var tint: Color {
        switch phase {
        case .focus: return ThemeManager.shared.theme.accent
        case .shortBreak, .longBreak: return ThemeManager.shared.theme.green
        case .idle: return ThemeManager.shared.theme.secondary
        }
    }

    private init() {}

    func start(minutes: Double, phase: Phase = .focus) {
        self.phase = phase
        total = minutes * 60
        endsAt = Date().addingTimeInterval(total)
        paused = false
        ensureTicker()
        SoundKit.tap(.levelChange)
    }

    func startPomodoro() {
        start(minutes: Prefs.shared.d.pomodoroFocusMinutes, phase: .focus)
    }

    func pause() {
        guard isRunning, !paused else { return }
        remainingWhenPaused = remaining
        paused = true
    }

    func resume() {
        guard isRunning, paused else { return }
        endsAt = Date().addingTimeInterval(remainingWhenPaused)
        paused = false
    }

    func togglePause() { paused ? resume() : pause() }

    func extend(minutes: Double) {
        guard isRunning else { return }
        total += minutes * 60
        if paused {
            remainingWhenPaused += minutes * 60
        } else {
            endsAt = (endsAt ?? Date()).addingTimeInterval(minutes * 60)
        }
    }

    func cancel() {
        phase = .idle
        endsAt = nil
        total = 0
        paused = false
        ticker?.invalidate()
        ticker = nil
    }

    private func ensureTicker() {
        guard ticker == nil else { return }
        let t = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(t, forMode: .common)
        ticker = t
    }

    private func tick() {
        guard isRunning, !paused else { return }
        guard remaining <= 0 else { return }
        complete()
    }

    private func complete() {
        let finished = phase
        var payload = NotchPayload()
        payload.source = "system"
        payload.key = "timer"
        payload.sound = true
        payload.timeout = 0

        switch finished {
        case .focus:
            completedFocusRounds += 1
            payload.kind = "attention"
            payload.title = "Focus done"
            payload.body = "Round \(completedFocusRounds) complete, take a break"
        case .shortBreak, .longBreak:
            payload.kind = "success"
            payload.title = "Break over"
            payload.body = "Back to it"
        case .idle:
            break
        }

        cancel()
        NotchState.shared.handle(payload)

        guard Prefs.shared.d.pomodoroAutoContinue else { return }
        switch finished {
        case .focus:
            let long = completedFocusRounds % Prefs.shared.d.pomodoroRounds == 0
            start(minutes: long ? Prefs.shared.d.pomodoroLongBreakMinutes
                                : Prefs.shared.d.pomodoroBreakMinutes,
                  phase: long ? .longBreak : .shortBreak)
        case .shortBreak, .longBreak:
            start(minutes: Prefs.shared.d.pomodoroFocusMinutes, phase: .focus)
        case .idle:
            break
        }
    }
}
