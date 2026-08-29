import SwiftUI
import AppKit

struct OnboardingView: View {
    @ObservedObject private var prefs = Prefs.shared
    @ObservedObject private var calendar = CalendarService.shared
    @ObservedObject private var fanControl = FanControlClient.shared
    @ObservedObject private var focus = FocusWatcher.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(steps) { step in row(step) }
                }
                .padding(18)
            }

            Divider()
            HStack {
                Text("Everything here is optional. MacInotch works without any of it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Done") {
                    prefs.d.hasOnboarded = true
                    OnboardingWindow.shared.close()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(14)
        }
        .frame(width: 540, height: 520)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(nsImage: NSApp.applicationIconImage ?? NSImage())
                .resizable()
                .frame(width: 46, height: 46)
            VStack(alignment: .leading, spacing: 2) {
                Text("MacInotch").font(.system(size: 18, weight: .semibold))
                Text("Grant only what you want. Each one unlocks one feature.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(18)
    }

    private struct Step: Identifiable {
        var id: String
        var title: String
        var detail: String
        var symbol: String
        var granted: Bool
        var actionLabel: String
        var action: () -> Void
    }

    private var steps: [Step] {
        [
            Step(id: "music",
                 title: "Now playing",
                 detail: "Reads the current track from Spotify or Music. macOS asks the "
                       + "first time MacInotch talks to a player.",
                 symbol: "music.note",
                 granted: NotchState.shared.music.isActive,
                 actionLabel: "Open Automation settings",
                 action: {
                     open("x-apple.systempreferences:com.apple.preference.security"
                          + "?Privacy_Automation")
                 }),
            Step(id: "calendar",
                 title: "Next event",
                 detail: "Shows your next meeting with a countdown and a join button.",
                 symbol: "calendar",
                 granted: calendar.authorized,
                 actionLabel: calendar.denied ? "Open Privacy settings" : "Request access",
                 action: {
                     if calendar.denied {
                         open("x-apple.systempreferences:com.apple.preference.security"
                              + "?Privacy_Calendars")
                     } else {
                         calendar.requestAccess()
                     }
                 }),
            Step(id: "fda",
                 title: "Mirror notifications and Focus",
                 detail: "Puts real macOS notifications into the notch and stays quiet "
                       + "during a Focus. Needs Full Disk Access.",
                 symbol: "bell.badge",
                 granted: focus.available,
                 actionLabel: "Open Privacy settings",
                 action: {
                     open("x-apple.systempreferences:com.apple.preference.security"
                          + "?Privacy_AllFiles")
                 }),
            Step(id: "fans",
                 title: "Fan control",
                 detail: "Timed boost presets. Installs a small root helper, which asks "
                       + "for your administrator password once.",
                 symbol: "fan",
                 granted: fanControl.reachable,
                 actionLabel: "Install helper",
                 action: { fanControl.install() }),
            Step(id: "login",
                 title: "Launch at login",
                 detail: "Starts MacInotch when you log in.",
                 symbol: "power",
                 granted: LoginItem.isEnabled,
                 actionLabel: "Enable",
                 action: { LoginItem.set(true) }),
        ]
    }

    private func row(_ step: Step) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: step.granted ? "checkmark.circle.fill" : step.symbol)
                .font(.system(size: 17))
                .foregroundStyle(step.granted ? Color.green : Color.secondary)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 3) {
                Text(step.title).font(.system(size: 13, weight: .medium))
                Text(step.detail)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            if step.granted {
                Text("On").font(.caption).foregroundStyle(.secondary)
            } else {
                Button(step.actionLabel, action: step.action)
                    .controlSize(.small)
            }
        }
    }

    private func open(_ string: String) {
        guard let url = URL(string: string) else { return }
        NSWorkspace.shared.open(url)
    }
}

@MainActor
final class OnboardingWindow {
    static let shared = OnboardingWindow()
    private var window: NSWindow?

    func showIfNeeded() {
        guard !Prefs.shared.d.hasOnboarded else { return }
        show()
    }

    func show() {
        if let w = window {
            NSApp.activate(ignoringOtherApps: true)
            w.makeKeyAndOrderFront(nil)
            return
        }
        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 540, height: 520),
            styleMask: [.titled, .closable],
            backing: .buffered, defer: false)
        w.title = "Welcome to MacInotch"
        w.isReleasedWhenClosed = false
        w.center()
        w.contentView = NSHostingView(rootView: OnboardingView())
        window = w
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
    }

    func close() {
        window?.close()
        NSApp.setActivationPolicy(.accessory)
    }
}
