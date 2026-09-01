import SwiftUI
import UniformTypeIdentifiers

struct ExpandedPanel: View {
    static let dayLabel: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "d MMM"
        return f
    }()
    static let clock: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    @EnvironmentObject var state: NotchState
    @ObservedObject private var prefs = Prefs.shared
    @ObservedObject private var themes = ThemeManager.shared
    @ObservedObject private var shelfStore = ShelfStore.shared
    @ObservedObject private var calendar = CalendarService.shared
    @ObservedObject private var fanControl = FanControlClient.shared
    @ObservedObject private var nav = SettingsNav.shared
    @ObservedObject private var hover = HoverTracker.shared
    @ObservedObject private var clipboard = ClipboardService.shared
    @ObservedObject private var timer = TimerService.shared
    @ObservedObject private var weather = WeatherService.shared
    @ObservedObject private var audio = AudioService.shared
    @ObservedObject private var bluetooth = BluetoothBatteryService.shared
    @ObservedObject private var notes = NotesStore.shared
    @ObservedObject private var switcher = AccountService.shared
    @ObservedObject private var network = NetworkService.shared
    @ObservedObject private var capture = CaptureService.shared
    @ObservedObject private var focusState = FocusWatcher.shared
    @ObservedObject private var meeting = MeetingMode.shared
    @ObservedObject private var github = GitHubService.shared
    @ObservedObject private var caffeine = CaffeineService.shared
    @ObservedObject private var mail = MailService.shared

    private var p: PrefsData { prefs.d }
    private var t: Theme { themes.theme }
    private let gutter: CGFloat = 16

    var body: some View {
        VStack(spacing: 0) {
            chrome.frame(height: state.notchSize.height)

            VStack(alignment: .leading, spacing: 14) {
                if p.shelfEnabled { tabBar }
                if p.showQuickBar { quickBar }
                if nav.connectingGitHub { githubConnect }
                switch state.panelTab {
                case .home:
                    hero
                    if p.showWeather && weather.snapshot.available || timer.isRunning {
                        focusStrip
                    }
                    if p.showNowPlaying && state.music.isActive { mediaCard }
                    if showsVitals { vitalsCard }
                    if !rows.isEmpty { rowStack }
                    if !state.items.isEmpty { activity }
                case .dock:
                    dock
                case .sessions:
                    sessionList
                case .accounts:
                    accountsTab
                case .github:
                    githubTab
                case .mail:
                    mailTab
                case .notes:
                    notesTab
                }
            }
            .padding(.horizontal, gutter)
            .padding(.top, 12)
            .padding(.bottom, 16)
        }
    }

    private var showsVitals: Bool {
        p.showCPU || p.showRAM || p.showBattery || showsTemp || showsFans || p.showPower
    }
    private var showsTemp: Bool { p.showTemperature && state.temps.available }
    private var showsFans: Bool { p.showFans && !state.fans.fans.isEmpty }
    private struct QuickButton: View {
        var symbol: String
        var label: String
        var tint: Color
        var on: Bool
        var dim: Bool
        var theme: Theme
        var action: () -> Void

        var body: some View {
            Button {
                SoundKit.tap()
                action()
            } label: {
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(on ? (theme.isDark ? Color.black : Color.white)
                                        : (dim ? theme.tertiary : theme.secondary))
                    .frame(width: 28, height: 28)
                    .background(
                        Circle().fill(on ? tint : theme.control)
                            .opacity(on ? 1 : (dim ? 0.45 : 1))
                    )
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help(label)
        }
    }

    private var quickBar: some View {
        HStack(spacing: 7) {
            QuickButton(symbol: "video.fill", label: "Meeting mode",
                        tint: t.purple, on: meeting.active, dim: false, theme: t) {
                meeting.toggle()
            }

            QuickButton(symbol: state.isMuted ? "bell.slash.fill" : "bell.fill",
                        label: state.isMuted ? "Notifications held" : "Hold notifications",
                        tint: t.orange, on: state.isMuted, dim: false, theme: t) {
                state.isMuted ? state.unmute() : state.mute(minutes: 60)
            }

            if focusState.available {
                QuickButton(symbol: focusState.active ? "moon.fill" : "moon",
                            label: focusState.active
                                ? (focusState.modeName ?? "Focus on") : "Toggle Focus",
                            tint: t.purple, on: focusState.active,
                            dim: p.focusShortcut.isEmpty, theme: t) {
                    if p.focusShortcut.isEmpty {
                        SettingsNav.shared.tab = .general
                        SettingsWindow.shared.show()
                    } else {
                        FocusController.run(p.focusShortcut)
                    }
                }
            }

            Button {
                SoundKit.tap()
                caffeine.toggle()
            } label: {
                CoffeeCup(fill: caffeine.fill,
                          active: caffeine.active,
                          tint: t.orange,
                          shell: caffeine.active
                              ? (t.isDark ? Color.black : Color.white) : t.secondary)
                    .frame(width: 17, height: 17)
                    .padding(5.5)
                    .background(Circle().fill(caffeine.active ? t.orange : t.control))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help(caffeine.active ? "Keeping awake, \(caffeine.remainingText)"
                                  : "Keep this Mac awake")
            .animation(.spring(response: 0.55, dampingFraction: 0.7), value: caffeine.fill)
            .contextMenu {
                ForEach(CaffeineService.durations, id: \.label) { option in
                    Button(option.label) { caffeine.start(minutes: option.minutes) }
                }
                if caffeine.active {
                    Divider()
                    Button("Let it sleep again") { caffeine.stop() }
                }
            }

            QuickButton(symbol: capture.recording ? "stop.fill" : "record.circle",
                        label: capture.recording ? "Stop recording" : "Record screen",
                        tint: t.red, on: capture.recording, dim: false, theme: t) {
                capture.toggle()
            }

            Divider().frame(height: 16)

            QuickButton(symbol: "calendar", label: calendar.authorized
                        ? "Calendar connected"
                        : calendar.denied ? "Access declined, open Privacy Settings"
                        : "Connect calendar",
                        tint: t.teal, on: calendar.authorized,
                        dim: !calendar.authorized, theme: t) {
                if calendar.authorized {
                    if let url = URL(string: "x-apple-calendar://") {
                        NSWorkspace.shared.open(url)
                    }
                } else {
                    calendar.requestAccess()
                }
            }
            .contextMenu {
                Button("Add a Google or other account") {
                    if let url = URL(string:
                        "x-apple.systempreferences:com.apple.Internet-Accounts-Settings"
                        + ".extension") {
                        NSWorkspace.shared.open(url)
                    }
                }
                Button("Reminders access") { calendar.requestReminderAccess() }
            }

            QuickButton(symbol: "chevron.left.forwardslash.chevron.right",
                        label: github.snapshot.connected
                            ? "GitHub as \(github.snapshot.login)" : "Connect GitHub",
                        tint: t.teal, on: github.snapshot.connected,
                        dim: !github.snapshot.connected, theme: t) {
                if github.snapshot.connected {
                    if let url = URL(string: "https://github.com/\(github.snapshot.login)") {
                        NSWorkspace.shared.open(url)
                    }
                } else {
                    nav.connectingGitHub.toggle()
                    if nav.connectingGitHub {
                        state.pinned = true
                        NSApp.activate(ignoringOtherApps: true)
                    } else {
                        state.pinned = false
                    }
                }
            }

            Spacer(minLength: 0)
        }
    }

    private var githubConnect: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !github.userCode.isEmpty {
                Text("Enter this code on GitHub")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(t.primary)
                HStack(spacing: 8) {
                    Text(github.userCode)
                        .font(.system(size: 19, weight: .bold, design: .monospaced))
                        .foregroundStyle(t.accent)
                        .textSelection(.enabled)
                    Text("copied, waiting for you")
                        .font(.system(size: 10))
                        .foregroundStyle(t.tertiary)
                    Spacer()
                    Button("Cancel") { github.cancelSignIn() }
                        .buttonStyle(.plain)
                        .font(.system(size: 10))
                        .foregroundStyle(t.tertiary)
                }
                Button("Open the page again") {
                    if let url = URL(string: github.verificationURL) {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(.plain)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(t.accent)
            } else if github.canSignIn {
                HStack(spacing: 8) {
                    Button {
                        Task { await github.signIn() }
                    } label: {
                        Text(github.signingIn ? "Starting" : "Sign in with GitHub")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(t.isDark ? Color.black : Color.white)
                            .padding(.horizontal, 11)
                            .padding(.vertical, 6)
                            .background(Capsule().fill(t.accent))
                    }
                    .buttonStyle(.plain)
                    .disabled(github.signingIn)

                    Button("Cancel") {
                        nav.connectingGitHub = false
                        state.pinned = false
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 10))
                    .foregroundStyle(t.tertiary)
                }
                Text("Opens github.com and asks you to approve. Nothing is typed here.")
                    .font(.system(size: 9.5))
                    .foregroundStyle(t.tertiary)
            } else {
                Text("Paste a GitHub token")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(t.primary)

                HStack(spacing: 6) {
                    SecureField("github_pat_", text: $nav.githubToken)
                        .textFieldStyle(.plain)
                        .font(.system(size: 11, design: .monospaced))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(RoundedRectangle(cornerRadius: 7).fill(t.wellFill))

                    Button {
                        github.connect(token: nav.githubToken)
                        nav.githubToken = ""
                        nav.connectingGitHub = false
                        state.pinned = false
                    } label: {
                        Text("Connect")
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(t.isDark ? Color.black : Color.white)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(Capsule().fill(t.accent))
                    }
                    .buttonStyle(.plain)
                    .disabled(nav.githubToken.isEmpty)
                }

                HStack(spacing: 8) {
                    Button("Create a token") {
                        if let url = URL(string:
                            "https://github.com/settings/personal-access-tokens/new") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(t.accent)

                    Button("Cancel") {
                        nav.githubToken = ""
                        nav.connectingGitHub = false
                        state.pinned = false
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 10))
                    .foregroundStyle(t.tertiary)
                }

                Text("Read only Metadata, Actions, Contents and Pull requests. Kept "
                     + "in your keychain for this device only and sent nowhere except "
                     + "api.github.com.")
                    .font(.system(size: 9.5))
                    .foregroundStyle(t.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !github.lastError.isEmpty {
                Text(github.lastError)
                    .font(.system(size: 10))
                    .foregroundStyle(t.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 11).fill(t.wellFill))
    }

    private var tabBar: some View {
        HStack(spacing: 4) {
            ForEach(visibleTabs) { tab in
                Button {
                    SoundKit.tap()
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                        state.panelTab = tab
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: tab.symbol)
                            .font(.system(size: 10, weight: .semibold))
                        Text(tab.label)
                            .font(.system(size: 11, weight: .medium))
                        if tab == .sessions,
                           state.sessions.contains(where: \.isLive) {
                            Circle().fill(t.green).frame(width: 5, height: 5)
                        }
                        if tab == .dock && !shelfStore.items.isEmpty {
                            Text("\(shelfStore.items.count)")
                                .font(.system(size: 9, weight: .bold, design: .rounded))
                                .foregroundStyle(t.isDark ? Color.black : Color.white)
                                .padding(.horizontal, 4.5)
                                .padding(.vertical, 1)
                                .background(Capsule().fill(t.accent))
                        }
                    }
                    .foregroundStyle(state.panelTab == tab ? t.primary : t.tertiary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        Capsule().fill(state.panelTab == tab ? t.control : Color.clear)
                    )
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
    }

    private var visibleTabs: [PanelTab] {
        PanelTab.allCases.filter { tab in
            switch tab {
            case .sessions: return p.showSessions
            case .accounts: return p.showAccounts
            case .github:   return p.showGitHub && github.snapshot.connected
            case .mail:     return p.showMail
            case .notes:    return p.showNotes
            default:        return true
            }
        }
    }

    private var mailTab: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                sectionLabel("UNREAD TODAY", action: nil)
                Spacer()
                if mail.state == .ready {
                    let waiting = mail.messages.filter(\.wantsAnswer).count
                    Button {
                        prefs.d.mailNeedsReplyOnly.toggle()
                    } label: {
                        Text(p.mailNeedsReplyOnly
                             ? "Showing \(waiting) waiting" : "\(waiting) waiting")
                            .font(.system(size: 9.5, weight: .semibold))
                            .foregroundStyle(p.mailNeedsReplyOnly
                                             ? (t.isDark ? Color.black : Color.white)
                                             : t.accent)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2.5)
                            .background(Capsule().fill(p.mailNeedsReplyOnly
                                                       ? t.accent : t.control))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    Text("\(mail.messages.count)")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(t.tertiary)
                }
            }

            switch mail.state {
            case .notRunning:
                mailNotice("Mail is not open",
                           "MacInotch reads what Mail already has, so Mail needs to "
                           + "be running.",
                           action: ("Open Mail", { mail.openMail() }))
            case .noAccounts:
                mailNotice("No mail account",
                           "Add your Google or other account to Mail in Internet "
                           + "Accounts, the same place calendars come from.",
                           action: ("Add an account", { mail.openAccountSettings() }))
            case .denied:
                mailNotice("Mail would not answer",
                           "Allow MacInotch to control Mail under Privacy and "
                           + "Security, Automation.",
                           action: nil)
            case .ready:
                if mail.messages.isEmpty {
                    Text("Nothing unread today")
                        .font(.system(size: 11))
                        .foregroundStyle(t.tertiary)
                } else {
                    let shown = p.mailNeedsReplyOnly
                        ? mail.messages.filter(\.wantsAnswer) : mail.messages
                    if shown.isEmpty {
                        Text("Nothing is waiting on you")
                            .font(.system(size: 11))
                            .foregroundStyle(t.tertiary)
                    }
                    ScrollView(.vertical, showsIndicators: true) {
                        VStack(alignment: .leading, spacing: 9) {
                            ForEach(shown) { message in
                                mailRow(message)
                                if mail.replyingTo == message.id { replyBox(message) }
                            }
                        }
                        .padding(.trailing, 4)
                    }
                    .frame(maxHeight: 300)
                }
            }

            if !mail.lastError.isEmpty {
                Text(mail.lastError)
                    .font(.system(size: 10))
                    .foregroundStyle(t.red)
            }
        }
    }

    private func mailNotice(_ title: String, _ body: String,
                            action: (String, () -> Void)?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(t.secondary)
            Text(body)
                .font(.system(size: 10.5))
                .foregroundStyle(t.tertiary)
                .fixedSize(horizontal: false, vertical: true)
            if let action {
                Button(action.0) { action.1() }
                    .buttonStyle(.plain)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(t.accent)
            }
        }
        .padding(.vertical, 4)
    }

    private func mailRow(_ message: MailMessage) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            PanelRow(id: "mail-\(message.id)",
                     title: message.sender,
                     subtitle: message.subject,
                     theme: t,
                     onTap: { mail.openInMail(message.id) },
                     leading: {
                         ZStack(alignment: .topTrailing) {
                             ZStack {
                                 Circle()
                                     .fill(message.important
                                           ? t.red.opacity(0.20) : t.wellFill)
                                 Text(message.initials)
                                     .font(.system(size: 9.5, weight: .bold))
                                     .foregroundStyle(message.important ? t.red
                                                                        : t.secondary)
                             }
                             .frame(width: 26, height: 26)
                             if message.wantsAnswer {
                                 Circle()
                                     .fill(message.triage == .urgent ? t.red : t.accent)
                                     .frame(width: 7, height: 7)
                                     .offset(x: 1, y: -1)
                             }
                         }
                         .frame(width: 26, height: 26)
                     },
                     trailing: {
                         VStack(alignment: .trailing, spacing: 3) {
                             Text(message.ago)
                                 .font(.system(size: 9))
                                 .foregroundStyle(t.tertiary)
                             if let triage = message.triage {
                                 Text(triage.short)
                                     .font(.system(size: 8, weight: .bold))
                                     .foregroundStyle(triageTint(triage))
                                     .padding(.horizontal, 4.5)
                                     .padding(.vertical, 1.5)
                                     .background(Capsule()
                                         .fill(triageTint(triage).opacity(0.16)))
                             }
                         }
                     })
                .contextMenu {
                    Button("Mark as read") { mail.markRead(message.id) }
                    Button("Open in Mail") { mail.openInMail(message.id) }
                }

            if !message.summary.isEmpty {
                Text(message.summary)
                    .font(.system(size: 10))
                    .foregroundStyle(t.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 47)
            }

            if mail.replyingTo != message.id {
                HStack(spacing: 10) {
                    Button("Reply") {
                        mail.beginReply(to: message.id)
                        state.pinned = true
                        NSApp.activate(ignoringOtherApps: true)
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(t.accent)

                    Button("Mark read") { mail.markRead(message.id) }
                        .buttonStyle(.plain)
                        .font(.system(size: 10))
                        .foregroundStyle(t.tertiary)
                }
                .padding(.leading, 47)
            }
        }
    }

    private func triageTint(_ triage: MailTriage) -> Color {
        switch triage {
        case .urgent: return t.red
        case .reply: return t.accent
        case .notice: return t.tertiary
        case .bulk: return t.tertiary
        }
    }

    private func replyBox(_ message: MailMessage) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("Replying to \(message.sender)")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(t.secondary)

            TextEditor(text: $mail.draft)
                .font(.system(size: 11))
                .scrollContentBackground(.hidden)
                .frame(height: 62)
                .padding(6)
                .background(RoundedRectangle(cornerRadius: 8).fill(t.wellFill))

            HStack(spacing: 8) {
                Button {
                    mail.draftReply(for: message.id)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "wand.and.sparkles")
                            .font(.system(size: 9.5, weight: .semibold))
                        Text(mail.drafting ? "Writing" : "Draft one")
                            .font(.system(size: 10.5, weight: .medium))
                    }
                    .foregroundStyle(t.accent)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(t.control))
                }
                .buttonStyle(.plain)
                .disabled(mail.drafting)

                Button {
                    mail.sendReply()
                } label: {
                    Text(mail.sending ? "Sending" : "Send")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(t.isDark ? Color.black : Color.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(t.accent))
                }
                .buttonStyle(.plain)
                .disabled(mail.draft.trimmingCharacters(in: .whitespaces).isEmpty
                          || mail.sending)

                Button("Cancel") {
                    mail.cancelReply()
                    state.pinned = false
                }
                .buttonStyle(.plain)
                .font(.system(size: 10))
                .foregroundStyle(t.tertiary)

                Spacer()
                Text("Sends through Mail")
                    .font(.system(size: 9))
                    .foregroundStyle(t.tertiary)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 11).fill(t.control))
        .padding(.leading, 40)
    }

    private var githubTab: some View {
        let snap = github.snapshot
        return VStack(alignment: .leading, spacing: 11) {
            HStack {
                sectionLabel("GITHUB", action: nil)
                Spacer()
                Text(snap.login)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(t.tertiary)
            }

            HStack(spacing: 14) {
                statBlock("\(snap.pushes)", "pushes today")
                statBlock("\(snap.pullRequests)", "PRs opened")
                statBlock("\(snap.reviewRequests)", "to review")
                Spacer()
            }

            if !snap.contributions.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    Text("\(snap.contributionTotal) contributions in the last year")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(t.secondary)
                    contributionGrid(snap.contributions)
                }
            }

            if snap.failures.isEmpty {
                Text("No failing workflows")
                    .font(.system(size: 10.5))
                    .foregroundStyle(t.tertiary)
            } else {
                ForEach(snap.failures.prefix(4)) { failure in
                    PanelRow(id: "ghtab-\(failure.id)", title: failure.workflow,
                             subtitle: "\(failure.repo) · \(failure.ago)", theme: t,
                             onTap: {
                                 if let url = URL(string: failure.url) {
                                     NSWorkspace.shared.open(url)
                                 }
                             },
                             leading: {
                                 IconBadge(symbol: "xmark.octagon.fill",
                                           tint: t.red, theme: t)
                             },
                             trailing: { EmptyView() })
                }
            }

            HStack(spacing: 10) {
                Button("Refresh") { Task { await github.refresh() } }
                    .buttonStyle(.plain)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(t.accent)
                Button("Sign out") {
                    github.disconnect()
                    state.panelTab = .home
                }
                .buttonStyle(.plain)
                .font(.system(size: 10))
                .foregroundStyle(t.red)
                Spacer()
                if let at = snap.checkedAt {
                    Text("checked \(Self.clock.string(from: at))")
                        .font(.system(size: 9))
                        .foregroundStyle(t.tertiary)
                }
            }
        }
    }

    private func statBlock(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value)
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundStyle(t.primary)
                .monospacedDigit()
            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(t.tertiary)
        }
    }

    private func contributionGrid(_ days: [ContributionDay]) -> some View {
        let weeks = stride(from: 0, to: days.count, by: 7).map {
            Array(days[$0..<min($0 + 7, days.count)])
        }
        let recent = weeks.suffix(26)
        return HStack(alignment: .top, spacing: 2) {
            ForEach(Array(recent.enumerated()), id: \.offset) { _, week in
                VStack(spacing: 2) {
                    ForEach(Array(week.enumerated()), id: \.offset) { _, day in
                        RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                            .fill(contributionTint(day.level))
                            .frame(width: 7, height: 7)
                            .help("\(day.count) on \(Self.dayLabel.string(from: day.date))")
                    }
                }
            }
        }
    }

    private func contributionTint(_ level: Int) -> Color {
        switch level {
        case 1: return t.green.opacity(0.35)
        case 2: return t.green.opacity(0.55)
        case 3: return t.green.opacity(0.78)
        case 4: return t.green
        default: return t.wellFill
        }
    }

    private var accountsTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            if switcher.availableProviders.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Nothing to switch yet")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(t.secondary)
                    Text("Sign in with codex login or claude, then save the session here.")
                        .font(.system(size: 10.5))
                        .foregroundStyle(t.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            ForEach(switcher.availableProviders) { provider in
                providerBlock(provider)
            }

            if switcher.busy {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Closing, switching and reopening")
                        .font(.system(size: 10.5))
                        .foregroundStyle(t.secondary)
                }
            }

            if !switcher.lastError.isEmpty {
                Text(switcher.lastError)
                    .font(.system(size: 10))
                    .foregroundStyle(t.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func providerBlock(_ provider: AccountProvider) -> some View {
        let saved = switcher.accounts(for: provider)
        let active = switcher.activeId[provider]
        let signedIn = switcher.currentEmail[provider] ?? ""

        return VStack(alignment: .leading, spacing: 7) {
            HStack {
                sectionLabel(provider.title.uppercased(), action: nil)
                Spacer()
                if switcher.hasSession(provider) && active == nil {
                    Button("Save current") {
                        switcher.attemptCapture(provider, label: "")
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(t.accent)
                }
            }

            if saved.isEmpty {
                Text(switcher.hasSession(provider)
                     ? (signedIn.isEmpty
                        ? "Signed in. Save it, then sign in with another account."
                        : "Signed in as \(signedIn). Save it, then sign in with another.")
                     : "No session on disk. Run \(provider.loginHint) first.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(t.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ForEach(saved) { account in
                accountRow(account, isActive: active == account.id)
                if switcher.pendingSwitch == account.id {
                    switchPrompt(provider)
                }
            }
        }
    }

    private func switchPrompt(_ provider: AccountProvider) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(provider.title) is open and would write its old session back "
                 + "over the new one. It has to be closed for the switch to hold.")
                .font(.system(size: 10.5))
                .foregroundStyle(t.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 7) {
                Button {
                    SoundKit.tap()
                    switcher.confirmPending()
                } label: {
                    Text("Quit, switch and reopen")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(t.isDark ? Color.black : Color.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(t.accent))
                }
                .buttonStyle(.plain)

                Button {
                    switcher.cancelPending()
                } label: {
                    Text("Cancel")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(t.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(t.control))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 4)
    }

    private func accountRow(_ account: SavedAccount, isActive: Bool) -> some View {
        PanelRow(id: "account-\(account.id)",
                 title: account.label,
                 subtitle: {
                     var parts: [String] = []
                     if isActive { parts.append("Signed in now") }
                     let detail = account.subtitle(showEmail: account.label != account.email)
                     if !detail.isEmpty { parts.append(detail) }
                     if let usage = account.usageText { parts.append(usage) }
                     return parts.joined(separator: " · ")
                 }(),
                 theme: t,
                 onTap: isActive ? nil : { switcher.requestActivate(account.id) },
                 leading: {
                     ZStack(alignment: .bottomTrailing) {
                         SourceIcon(source: account.provider.source, kind: .info,
                                    theme: t, side: 26)
                         if isActive {
                             Circle().fill(t.green)
                                 .frame(width: 7, height: 7)
                                 .overlay(Circle().strokeBorder(
                                     Color.black.opacity(0.3), lineWidth: 0.5))
                                 .offset(x: 2, y: 2)
                         }
                     }
                 },
                 trailing: {
                     VStack(alignment: .trailing, spacing: 2) {
                         Text(isActive ? "in use" : "switch")
                             .font(.system(size: 10, weight: .semibold))
                             .foregroundStyle(isActive ? t.tertiary : t.accent)
                         if !isActive && account.isStale {
                             Text("may ask to sign in")
                                 .font(.system(size: 8.5))
                                 .foregroundStyle(t.orange)
                         }
                     }
                 })
            .contextMenu {
                Button("Clear the usage reading") { switcher.clearReading(account.id) }
                Button("Forget this account") { switcher.forget(account.id) }
                    .disabled(isActive)
            }
    }

    private var notesTab: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(notes.notes.isEmpty ? "No notes yet"
                     : "\(notes.notes.count) note\(notes.notes.count == 1 ? "" : "s")")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(t.primary)
                Spacer()
                PillButton(label: "Folder", tint: t.secondary, theme: t) {
                    notes.revealFolder()
                }
                PillButton(label: "New", tint: t.accent, theme: t, filled: true) {
                    _ = notes.create()
                }
            }

            if let error = notes.lastError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 10.5))
                    .foregroundStyle(t.orange)
            }

            if let path = notes.selected,
               let note = notes.notes.first(where: { $0.path == path }) {
                noteEditor(note)
            } else if notes.notes.isEmpty {
                emptyDock(symbol: "note.text",
                          title: "Notes live as files on disk",
                          detail: notes.directory.path)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 9),
                                             count: 3), spacing: 9) {
                        ForEach(notes.notes) { note in noteCard(note) }
                    }
                    .padding(.vertical, 2)
                }
                .frame(height: notes.notes.count > 3 ? 200 : 104)
            }
        }
    }

    private func noteCard(_ note: Note) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(note.title)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(Color.black.opacity(0.82))
                .lineLimit(1)
            Text(note.snippet)
                .font(.system(size: 10))
                .foregroundStyle(Color.black.opacity(0.55))
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)
            Spacer(minLength: 0)
            Text(note.ago)
                .font(.system(size: 8.5))
                .foregroundStyle(Color.black.opacity(0.4))
        }
        .padding(9)
        .frame(height: 92, alignment: .topLeading)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(notes.color(note))
                .shadow(color: .black.opacity(0.22), radius: 3, y: 2))
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .onTapGesture {
            SoundKit.tap()
            notes.selected = note.path
        }
        .contextMenu {
            Button("Edit") { notes.selected = note.path }
            Button("Reveal in Finder") { notes.reveal(note) }
            Divider()
            Button("Delete") { notes.delete(note) }
        }
    }

    private func noteEditor(_ note: Note) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Circle().fill(notes.color(note)).frame(width: 9, height: 9)
                Text(note.title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(t.primary)
                    .lineLimit(1)
                Spacer()
                PillButton(label: "Reveal", tint: t.secondary, theme: t) {
                    notes.reveal(note)
                }
                PillButton(label: "Delete", tint: t.red, theme: t) { notes.delete(note) }
                PillButton(label: "Done", tint: t.accent, theme: t, filled: true) {
                    notes.selected = nil
                }
            }

            TextEditor(text: Binding(
                get: { note.text },
                set: { notes.update(note, text: $0) }))
                .font(.system(size: 12))
                .scrollContentBackground(.hidden)
                .padding(8)
                .frame(height: 180)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(t.control))
        }
    }

    private var sessionList: some View {
        VStack(alignment: .leading, spacing: 8) {
            if state.sessions.isEmpty {
                emptyDock(symbol: "sparkles",
                          title: "No Claude Code sessions found",
                          detail: "Transcripts live in ~/.claude/projects")
            } else {
                HStack {
                    Text("\(state.sessions.count) recent")
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(t.primary)
                    Spacer()
                    Text("\(UsageSnapshot.short(state.sessions.reduce(0) { $0 + $1.tokens })) tokens")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(t.tertiary)
                        .monospacedDigit()
                }

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 2) {
                        ForEach(state.sessions) { session in sessionRow(session) }
                    }
                }
                .frame(height: min(CGFloat(state.sessions.count) * 46, 230))
                .padding(.horizontal, -10)
            }
        }
    }

    private func sessionRow(_ session: CodeSession) -> some View {
        PanelRow(id: "session-\(session.id)", title: session.displayName,
                 subtitle: "\(session.messages) msgs · \(session.ago)"
                         + (session.model.isEmpty ? "" : " · \(session.model)"),
                 theme: t,
                 onTap: {
                     if !SessionLauncher.resume(session) {
                         NSWorkspace.shared.activateFileViewerSelecting(
                             [URL(fileURLWithPath: session.path)])
                     }
                 },
                 leading: {
                     ZStack(alignment: .bottomTrailing) {
                         SourceIcon(source: session.provider, kind: .info, theme: t, side: 26)
                         if session.isLive {
                             Circle().fill(t.green)
                                 .frame(width: 7, height: 7)
                                 .overlay(Circle().strokeBorder(Color.black.opacity(0.3),
                                                                lineWidth: 0.5))
                                 .offset(x: 2, y: 2)
                         }
                     }
                 },
                 trailing: {
                     Text(UsageSnapshot.short(session.tokens))
                         .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                         .foregroundStyle(t.secondary)
                         .monospacedDigit()
                 })
        .contextMenu {
            if SessionLauncher.canResume(session) {
                Button("Resume this session") { SessionLauncher.resume(session) }
            }
            Button("Reveal transcript") {
                NSWorkspace.shared.activateFileViewerSelecting(
                    [URL(fileURLWithPath: session.path)])
            }
            Button("Copy session id") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(session.id, forType: .string)
            }
        }
    }

    private var dock: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 6) {
                ForEach(DockSection.allCases) { section in
                    Button {
                        SoundKit.tap()
                        state.dockSection = section
                    } label: {
                        Text(section.label)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(state.dockSection == section
                                             ? t.primary : t.tertiary)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4)
                            .background(
                                Capsule().fill(state.dockSection == section
                                               ? t.control : Color.clear))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
                Button {
                    SoundKit.tap()
                    capture.toggle()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: capture.recording
                              ? "stop.circle.fill" : "record.circle")
                            .font(.system(size: 11, weight: .semibold))
                        if capture.recording {
                            Text(capture.elapsed)
                                .font(.system(size: 10, weight: .semibold))
                                .monospacedDigit()
                        }
                    }
                    .foregroundStyle(capture.recording ? t.red : t.tertiary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(capture.recording
                                               ? t.red.opacity(0.16) : Color.clear))
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .help(capture.recording ? "Stop recording" : "Record the screen")
                dockToolbar
            }

            if state.dockSection == .clipboard {
                clipboardSection
            } else {
                filesSection
            }
        }
    }

    @ViewBuilder private var dockToolbar: some View {
        if state.dockSection == .files {
            if !shelfStore.items.isEmpty {
                HStack(spacing: 6) {
                    PillButton(label: "AirDrop", tint: t.blue, theme: t) {
                        shelfStore.airdrop(shelfStore.items)
                    }
                    PillButton(label: "Zip", tint: t.purple, theme: t) {
                        shelfStore.compress(shelfStore.items)
                    }
                    PillButton(label: "Clear", tint: t.secondary, theme: t) {
                        shelfStore.clear()
                    }
                }
            }
        } else if !clipboard.entries.isEmpty {
            PillButton(label: "Clear", tint: t.secondary, theme: t) {
                clipboard.clearUnpinned()
            }
        }
    }

    @ViewBuilder private var clipboardSection: some View {
        if !p.clipboardEnabled {
            emptyDock(symbol: "doc.on.clipboard",
                      title: "Clipboard history is off",
                      detail: "Turn it on in Settings → Notch")
        } else if clipboard.entries.isEmpty {
            emptyDock(symbol: "doc.on.clipboard",
                      title: "Nothing copied yet",
                      detail: "Anything you copy shows up here")
        } else {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 2) {
                    ForEach(clipboard.pinned) { clipRow($0) }
                    ForEach(clipboard.recent) { clipRow($0) }
                }
            }
            .frame(height: 200)
            .padding(.horizontal, -10)
        }
    }

    private func clipRow(_ entry: ClipEntry) -> some View {
        PanelRow(id: "clip-\(entry.id)", title: entry.preview,
                 subtitle: entry.detail, theme: t,
                 onTap: { clipboard.copy(entry) },
                 leading: {
                     if entry.kind == .image, let image = clipboard.image(for: entry) {
                         Image(nsImage: image)
                             .resizable()
                             .aspectRatio(contentMode: .fill)
                             .frame(width: 28, height: 28)
                             .clipShape(RoundedRectangle(cornerRadius: 6,
                                                         style: .continuous))
                     } else {
                         IconBadge(symbol: entry.symbol,
                                   tint: entry.pinned ? t.accent : t.secondary, theme: t)
                     }
                 },
                 trailing: {
                     HStack(spacing: 6) {
                         Button { clipboard.togglePin(entry) } label: {
                             Image(systemName: entry.pinned ? "pin.fill" : "pin")
                                 .font(.system(size: 10, weight: .semibold))
                                 .foregroundStyle(entry.pinned ? t.accent : t.tertiary)
                                 .frame(width: 20, height: 20)
                                 .contentShape(Rectangle())
                         }
                         .buttonStyle(.plain)
                         Button { clipboard.remove(entry) } label: {
                             Image(systemName: "xmark")
                                 .font(.system(size: 8, weight: .bold))
                                 .foregroundStyle(t.tertiary)
                                 .frame(width: 18, height: 18)
                                 .background(Circle().fill(t.control))
                                 .contentShape(Circle())
                         }
                         .buttonStyle(.plain)
                     }
                 })
        .contextMenu {
            Button("Copy") { clipboard.copy(entry) }
            Button(entry.pinned ? "Unpin" : "Pin") { clipboard.togglePin(entry) }
            Divider()
            Button("Delete") { clipboard.remove(entry) }
        }
    }

    private func emptyDock(symbol: String, title: String, detail: String) -> some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .strokeBorder(shelfStore.targeted ? t.accent : t.hairline,
                          style: StrokeStyle(lineWidth: shelfStore.targeted ? 2 : 1,
                                             dash: [6, 5]))
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(shelfStore.targeted ? t.accent.opacity(0.08) : Color.clear))
            .frame(height: 120)
            .overlay(
                VStack(spacing: 7) {
                    Image(systemName: symbol)
                        .font(.system(size: 24, weight: .light))
                        .foregroundStyle(shelfStore.targeted ? t.accent : t.tertiary)
                    Text(title)
                        .font(.system(size: 11.5))
                        .foregroundStyle(t.tertiary)
                    Text(detail)
                        .font(.system(size: 10))
                        .foregroundStyle(t.tertiary.opacity(0.7))
                })
            .animation(.easeOut(duration: 0.18), value: shelfStore.targeted)
    }

    private var pileBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(shelfStore.piles, id: \.self) { pile in
                    Button {
                        SoundKit.tap()
                        shelfStore.activePile = pile
                    } label: {
                        HStack(spacing: 5) {
                            Text(pile)
                                .font(.system(size: 10.5, weight: .medium))
                            let count = shelfStore.count(in: pile)
                            if count > 0 {
                                Text("\(count)")
                                    .font(.system(size: 9, weight: .bold, design: .rounded))
                                    .foregroundStyle(t.tertiary)
                            }
                        }
                        .foregroundStyle(shelfStore.activePile == pile ? t.primary : t.tertiary)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(
                            Capsule().fill(shelfStore.activePile == pile
                                           ? t.accent.opacity(0.18) : t.control))
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button("Delete pile") { shelfStore.removePile(pile) }
                    }
                }
                Menu {
                    ForEach(["Work", "Send", "Read later", "Screenshots", "Scratch"],
                            id: \.self) { name in
                        Button(name) { shelfStore.addPile(name) }
                    }
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(t.tertiary)
                        .frame(width: 22, height: 20)
                        .background(Capsule().fill(t.control))
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .frame(width: 26)
            }
        }
    }

    private var filesSection: some View {
        VStack(alignment: .leading, spacing: 11) {
            pileBar

            if shelfStore.items.isEmpty {
                emptyDock(symbol: "tray.and.arrow.down",
                          title: "Drag anything here to hold it",
                          detail: "then drag it straight back out")
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10),
                                             count: 5), spacing: 10) {
                        ForEach(shelfStore.items) { item in dockTile(item) }
                    }
                    .padding(.vertical, 2)
                }
                .frame(height: shelfStore.items.count > 5 ? 190 : 96)

                HStack(spacing: 5) {
                    Image(systemName: "hand.draw")
                        .font(.system(size: 9))
                    Text("Drag a tile out to move it · right-click for more")
                        .font(.system(size: 10))
                }
                .foregroundStyle(t.tertiary)
            }
        }
    }

    private func dockTile(_ item: ShelfItem) -> some View {
        VStack(spacing: 5) {
            Image(nsImage: shelfStore.icon(for: item))
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: 38, height: 38)
                .shadow(color: .black.opacity(0.25), radius: 3, y: 2)
            Text(item.name)
                .font(.system(size: 9.5))
                .foregroundStyle(t.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 9)
        .padding(.horizontal, 4)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(hover.hovered == item.id.uuidString ? t.controlHover : t.control)
        )
        .overlay(alignment: .topTrailing) {
            if hover.hovered == item.id.uuidString {
                Button { shelfStore.remove(item) } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(t.secondary)
                        .background(Circle().fill(t.isDark ? Color.black : Color.white))
                }
                .buttonStyle(.plain)
                .offset(x: 4, y: -4)
            }
        }
        .onHover { inside in
            if inside { hover.hovered = item.id.uuidString }
            else if hover.hovered == item.id.uuidString { hover.hovered = nil }
        }
        .onDrag { NSItemProvider(contentsOf: item.url) ?? NSItemProvider() }
        .contextMenu {
            Button("Open") { shelfStore.open(item) }
            Button("Reveal in Finder") { shelfStore.revealInFinder(item) }
            Divider()
            Button("AirDrop…") { shelfStore.airdrop([item]) }
            Button("Compress to zip") { shelfStore.compress([item]) }
            Button("Copy file") { shelfStore.copyFile(item) }
            Button("Copy path") { shelfStore.copyPath(item) }
            Divider()
            Menu("Move to") {
                ForEach(shelfStore.piles, id: \.self) { pile in
                    Button(pile) { shelfStore.move(item, to: pile) }
                }
            }
            Divider()
            Button("Remove from shelf") { shelfStore.remove(item) }
            Button("Move to Trash") { shelfStore.moveToTrash(item) }
        }
        .help(item.sizeText.isEmpty ? item.path : "\(item.path)\n\(item.sizeText)")
    }

    private var chrome: some View {
        HStack(spacing: 0) {
            HStack(spacing: 7) {
                if p.idleShowPresence {
                    if p.watchClaude {
                        PresenceChip(source: .claude, running: state.presence.claude,
                                     theme: t, side: 16)
                    }
                    if p.watchChatGPT {
                        PresenceChip(source: .chatgpt, running: state.presence.chatgpt,
                                     theme: t, side: 16)
                    }
                }
                if state.stats.thermalPressure > 0 {
                    Text(state.stats.thermalLabel.uppercased())
                        .font(.system(size: 8, weight: .bold))
                        .kerning(0.6)
                        .foregroundStyle(t.orange)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(t.orange.opacity(0.16)))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: state.notchSize.width - 6)

            HStack(spacing: 4) {
                chromeButton(state.pinned ? "pin.fill" : "pin",
                             active: state.pinned) { state.togglePin() }
                chromeButton("slider.horizontal.3", active: false) {
                    SettingsWindow.shared.show()
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, gutter - 2)
    }

    private func chromeButton(_ symbol: String, active: Bool,
                              action: @escaping () -> Void) -> some View {
        Button {
            SoundKit.tap()
            action()
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(active ? t.accent : t.tertiary)
                .frame(width: 22, height: 20)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(active ? t.accent.opacity(0.16) : Color.clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var hero: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 1) {
                Text(clockText)
                    .font(.system(size: 38, weight: .medium, design: .rounded))
                    .foregroundStyle(t.primary)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .animation(.easeInOut(duration: 0.3), value: clockText)
                if p.showShamsi {
                    Text(shamsi)
                        .font(.system(size: 12))
                        .foregroundStyle(t.accent)
                        .environment(\.layoutDirection, .rightToLeft)
                }
            }

            Spacer(minLength: 12)

            VStack(alignment: .trailing, spacing: 3) {
                if p.showGregorian {
                    Text(DateKit.gregLong.string(from: state.now))
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(t.secondary)
                }
                HStack(spacing: 7) {
                    if p.showWeekNumber { metaChip("W\(DateKit.weekNumber(state.now))") }
                    if p.showNowruz, let days = DateKit.daysUntilNowruz() {
                        metaChip(days == 0 ? "نوروز" : "نوروز \(faNumber(days))")
                    }
                    if p.showUptime { metaChip("up \(DateKit.uptime())") }
                }
                if p.showHijri {
                    Text(hijri)
                        .font(.system(size: 10.5))
                        .foregroundStyle(t.tertiary)
                        .environment(\.layoutDirection, .rightToLeft)
                }
            }
        }
    }

    private func metaChip(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 9.5, weight: .medium))
            .foregroundStyle(t.tertiary)
            .padding(.horizontal, 7)
            .padding(.vertical, 2.5)
            .background(Capsule().fill(t.wellFill.opacity(0.55)))
    }

    private var clockText: String {
        let f: DateFormatter = p.clock24h
            ? (p.clockSeconds ? DateKit.clockSeconds : DateKit.clock)
            : (p.clockSeconds ? DateKit.clock12Seconds : DateKit.clock12)
        return f.string(from: state.now)
    }

    private var shamsi: String {
        let s = "\(DateKit.shamsiWeekday.string(from: state.now))، "
              + DateKit.shamsiLong.string(from: state.now)
        return p.persianDigits ? s : DateKit.enDigits(s)
    }

    private var hijri: String {
        let s = DateKit.hijriLong.string(from: state.now)
        return p.persianDigits ? s : DateKit.enDigits(s)
    }

    private func faNumber(_ n: Int) -> String {
        p.persianDigits ? DateKit.faDigits("\(n)") : "\(n)"
    }

    private var focusStrip: some View {
        HStack(spacing: 10) {
            if p.showWeather && weather.snapshot.available {
                let w = weather.snapshot
                HStack(spacing: 8) {
                    Image(systemName: w.symbol)
                        .font(.system(size: 17))
                        .foregroundStyle(t.blue)
                        .frame(width: 22)
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(alignment: .firstTextBaseline, spacing: 5) {
                            Text(w.formatted(w.temperature, fahrenheit: p.weatherFahrenheit))
                                .font(.system(size: 15, weight: .medium, design: .rounded))
                                .foregroundStyle(t.primary)
                                .monospacedDigit()
                            Text(w.summary)
                                .font(.system(size: 11))
                                .foregroundStyle(t.secondary)
                        }
                        Text("\(w.place.isEmpty ? "" : w.place + " · ")"
                             + "H \(w.formatted(w.high, fahrenheit: p.weatherFahrenheit))"
                             + "  L \(w.formatted(w.low, fahrenheit: p.weatherFahrenheit))")
                            .font(.system(size: 9.5))
                            .foregroundStyle(t.tertiary)
                    }
                }
                .padding(.horizontal, 11)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 11, style: .continuous).fill(t.control))
            }

            timerCard
        }
    }

    private var timerCard: some View {
        HStack(spacing: 9) {
            if timer.isRunning {
                ZStack {
                    Circle().stroke(t.wellFill, lineWidth: 3)
                    Circle()
                        .trim(from: 0, to: max(0.02, 1 - timer.fraction))
                        .stroke(timer.tint, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.linear(duration: 0.3), value: timer.fraction)
                }
                .frame(width: 26, height: 26)

                VStack(alignment: .leading, spacing: 1) {
                    Text(timer.readout)
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundStyle(t.primary)
                        .monospacedDigit()
                    Text(timer.paused ? "paused" : timer.phase.label)
                        .font(.system(size: 9.5))
                        .foregroundStyle(t.tertiary)
                }

                Spacer(minLength: 4)

                HStack(spacing: 5) {
                    PillButton(label: timer.paused ? "Resume" : "Pause",
                               tint: t.secondary, theme: t) { timer.togglePause() }
                    PillButton(label: "+5", tint: t.secondary, theme: t) {
                        timer.extend(minutes: 5)
                    }
                    PillButton(label: "Stop", tint: t.red, theme: t) { timer.cancel() }
                }
            } else {
                Image(systemName: "timer")
                    .font(.system(size: 15))
                    .foregroundStyle(t.tertiary)
                    .frame(width: 22)
                Text("Timer")
                    .font(.system(size: 12))
                    .foregroundStyle(t.secondary)
                Spacer(minLength: 4)
                HStack(spacing: 5) {
                    PillButton(label: "5m", tint: t.secondary, theme: t) {
                        timer.start(minutes: 5, phase: .focus)
                    }
                    PillButton(label: "15m", tint: t.secondary, theme: t) {
                        timer.start(minutes: 15, phase: .focus)
                    }
                    PillButton(label: "Pomodoro", tint: t.accent, theme: t, filled: true) {
                        timer.startPomodoro()
                    }
                }
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous).fill(t.control))
    }

    private var vitalsCard: some View {
        SurfaceCard(theme: t, padding: 13) {
            VStack(spacing: 0) {
                HStack(alignment: .top, spacing: 0) {
                    ForEach(Array(vitals.enumerated()), id: \.offset) { index, column in
                        if index > 0 {
                            Rectangle()
                                .fill(t.hairline)
                                .frame(width: 0.75, height: 46)
                                .padding(.horizontal, 10)
                        }
                        column
                    }
                }
                if showsFans && state.showFanControls {
                    Rectangle().fill(t.hairline).frame(height: 0.75).padding(.top, 12)
                    fanControls.padding(.top, 11)
                }
            }
        }
        .onTapGesture {
            guard showsFans else { return }
            SoundKit.tap()
            withAnimation(.spring(response: 0.32, dampingFraction: 0.84)) {
                state.showFanControls.toggle()
            }
        }
    }

    private var vitals: [AnyView] {
        var out: [AnyView] = []
        if p.showCPU {
            out.append(AnyView(VitalColumn(
                label: "CPU", value: "\(Int((state.stats.cpuTotal * 100).rounded()))",
                unit: "%", detail: cpuDetail, fraction: state.stats.cpuTotal,
                tint: t.load(state.stats.cpuTotal), theme: t,
                history: p.showSparklines ? state.cpuHistory : [])))
        }
        if p.showRAM {
            out.append(AnyView(VitalColumn(
                label: "Memory", value: String(format: "%.1f", state.stats.memUsedGB),
                unit: "GB", detail: ramDetail, fraction: state.stats.memPressure,
                tint: t.load(state.stats.memPressure), theme: t,
                history: p.showSparklines ? state.ramHistory : [])))
        }
        if showsTemp {
            out.append(AnyView(VitalColumn(
                label: "Temp",
                value: Temperatures.format(state.temps.soc, fahrenheit: p.fahrenheit)
                    .replacingOccurrences(of: "°", with: ""),
                unit: p.fahrenheit ? "°F" : "°C",
                detail: "peak " + Temperatures.format(state.temps.socMax,
                                                      fahrenheit: p.fahrenheit),
                fraction: state.temps.socLoad, tint: t.load(state.temps.socLoad), theme: t,
                history: p.showSparklines ? state.tempHistory : [])))
        }
        if showsFans, let fan = hottestFan {
            out.append(AnyView(VitalColumn(
                label: state.showFanControls ? "Fans ▾" : "Fans",
                value: fan.isStopped ? "-" : String(format: "%.1f", fan.rpm / 1000),
                unit: fan.isStopped ? "" : "k",
                detail: fanDetail, fraction: fan.fraction,
                tint: t.load(fan.fraction), theme: t)))
        }
        if p.showPower && state.fans.systemWatts > 0 {
            out.append(AnyView(VitalColumn(
                label: "Power", value: String(format: "%.0f", state.fans.systemWatts),
                unit: "W", detail: state.battery.isCharging ? "charging" : "system",
                fraction: min(1, state.fans.systemWatts / 90), tint: t.purple, theme: t)))
        }
        if p.showBattery && state.battery.present {
            out.append(AnyView(VitalColumn(
                label: state.battery.isCharging ? "Charging" : "Battery",
                value: "\(state.battery.percent)", unit: "%", detail: batteryDetail,
                fraction: Double(state.battery.percent) / 100,
                tint: batteryTint, theme: t)))
        }
        if p.showDisk {
            out.append(AnyView(VitalColumn(
                label: "Disk", value: String(format: "%.0f", state.stats.diskFreeGB),
                unit: "GB", detail: "free", fraction: state.stats.diskUsedFraction,
                tint: t.teal, theme: t)))
        }
        return out
    }

    private var cpuDetail: String {
        if p.showTopProcess, let top = state.topCPU { return "\(top.name) \(Int(top.cpu))%" }
        return "\(state.stats.coreCount) cores"
    }

    private var ramDetail: String {
        if p.showTopProcess, let top = state.topMemory {
            return "\(top.name) \(String(format: "%.1f", top.memoryGB))G"
        }
        return String(format: "of %.0f GB", state.stats.memTotalGB)
    }

    private var batteryDetail: String {
        if let time = state.battery.timeText { return time }
        if state.battery.healthPercent > 0 {
            return "\(state.battery.healthPercent)% health"
        }
        return ""
    }

    private var fanDetail: String {
        if let seconds = fanControl.holds.values.max(), seconds > 0 {
            return "\(seconds / 60)m \(seconds % 60)s hold"
        }
        if state.fans.fans.allSatisfy(\.isStopped) { return "stopped" }
        return "\(state.fans.fans.count) fans"
    }

    private var hottestFan: FanReading? { state.fans.fans.max { $0.rpm < $1.rpm } }

    private var batteryTint: Color {
        if state.battery.isCharging { return t.green }
        return state.battery.percent <= 20 ? t.red : t.green
    }

    @ViewBuilder private var fanControls: some View {
        if fanControl.reachable {
            HStack(spacing: 7) {
                PillButton(label: "50%", tint: t.blue, theme: t) {
                    fanControl.setAll(percent: 0.5, minutes: nav.boostMinutes)
                }
                PillButton(label: "75%", tint: t.orange, theme: t) {
                    fanControl.setAll(percent: 0.75, minutes: nav.boostMinutes)
                }
                PillButton(label: "Blast", tint: t.red, theme: t, filled: true) {
                    fanControl.setAll(percent: 1.0, minutes: nav.boostMinutes)
                }
                Picker("", selection: $nav.boostMinutes) {
                    Text("2m").tag(2.0)
                    Text("5m").tag(5.0)
                    Text("15m").tag(15.0)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 140)
                Spacer(minLength: 4)
                PillButton(label: "Auto", tint: t.secondary, theme: t) {
                    fanControl.autoAll()
                }
            }
        } else {
            HStack(spacing: 8) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(t.tertiary)
                Text(fanControl.lastError ?? "Fan control needs a one-time helper install")
                    .font(.system(size: 11))
                    .foregroundStyle(t.tertiary)
                    .lineLimit(1)
                Spacer(minLength: 4)
                PillButton(label: "Install…", tint: t.accent, theme: t) {
                    SettingsNav.shared.tab = .fans
                    SettingsWindow.shared.show()
                }
            }
        }
    }

    private struct RowSpec: Identifiable {
        var id: String
        var view: AnyView
    }

    private var rows: [RowSpec] {
        var out: [RowSpec] = []

        if p.showCalendar, let event = calendar.next {
            out.append(RowSpec(id: "calendar", view: AnyView(
                PanelRow(id: "calendar", title: event.title,
                         subtitle: eventSubtitle(event), theme: t,
                         onTap: { if let url = event.joinURL { NSWorkspace.shared.open(url) } },
                         leading: {
                             IconBadge(symbol: "calendar",
                                       tint: event.calendarColor.map { Color(nsColor: $0) }
                                           ?? t.blue, theme: t)
                         },
                         trailing: {
                             if let join = event.joinURL {
                                 PillButton(label: "Join", tint: t.green, theme: t,
                                            filled: true) { NSWorkspace.shared.open(join) }
                             } else {
                                 Text(event.countdown)
                                     .font(.system(size: 11, weight: .medium,
                                                   design: .rounded))
                                     .foregroundStyle(event.isRunning ? t.green : t.secondary)
                                     .monospacedDigit()
                             }
                         })
            )))
        }

        if p.showUsage {
            if p.usageShowClaude, let tally = state.usage.claude {
                out.append(RowSpec(id: "usage-claude",
                                   view: AnyView(tallyRow(.claude, tally))))
            }
            if p.usageShowCodex {
                if let limits = state.usage.codexLimits {
                    out.append(RowSpec(id: "usage-codex",
                                       view: AnyView(limitRow(limits))))
                } else if let tally = state.usage.codexTally {
                    out.append(RowSpec(id: "usage-codex",
                                       view: AnyView(tallyRow(.chatgpt, tally))))
                }
            }
        }

        if p.showGitHub && github.snapshot.connected {
            let snap = github.snapshot
            out.append(RowSpec(id: "github", view: AnyView(
                PanelRow(id: "github", title: "GitHub today",
                         subtitle: snap.summary, theme: t,
                         onTap: {
                             if let url = URL(string: "https://github.com/\(snap.login)") {
                                 NSWorkspace.shared.open(url)
                             }
                         },
                         leading: {
                             IconBadge(symbol: "chevron.left.forwardslash.chevron.right",
                                       tint: snap.failures.isEmpty ? t.teal : t.red,
                                       theme: t)
                         },
                         trailing: {
                             if !snap.failures.isEmpty {
                                 Text("\(snap.failures.count) failing")
                                     .font(.system(size: 9, weight: .bold))
                                     .foregroundStyle(t.isDark ? Color.black : Color.white)
                                     .padding(.horizontal, 5)
                                     .padding(.vertical, 1.5)
                                     .background(Capsule().fill(t.red))
                             }
                         })
            )))

            for failure in snap.failures.prefix(3) {
                out.append(RowSpec(id: "gh-\(failure.id)", view: AnyView(
                    PanelRow(id: "gh-\(failure.id)", title: failure.workflow,
                             subtitle: "\(failure.repo) · \(failure.ago)", theme: t,
                             onTap: {
                                 if let url = URL(string: failure.url) {
                                     NSWorkspace.shared.open(url)
                                 }
                             },
                             leading: {
                                 IconBadge(symbol: "xmark.octagon.fill",
                                           tint: t.red, theme: t)
                             },
                             trailing: { EmptyView() })
                )))
            }
        }

        if meeting.active {
            out.append(RowSpec(id: "meeting-mode", view: AnyView(
                PanelRow(id: "meeting-mode", title: "Meeting mode",
                         subtitle: meeting.endsAt.map {
                             "Quiet until \(Self.clock.string(from: $0))"
                         } ?? "Audio muted, notifications held",
                         theme: t,
                         onTap: { meeting.disable() },
                         leading: {
                             IconBadge(symbol: "video.fill", tint: t.purple, theme: t)
                         },
                         trailing: {
                             Text("End")
                                 .font(.system(size: 10, weight: .semibold))
                                 .foregroundStyle(t.accent)
                         })
            )))
        }

        if p.showReminders {
            for reminder in calendar.reminders.prefix(4) {
                out.append(RowSpec(id: "reminder-\(reminder.id)", view: AnyView(
                    PanelRow(id: "reminder-\(reminder.id)", title: reminder.title,
                             subtitle: reminder.detail, theme: t,
                             onTap: {
                                 if let url = URL(string: "x-apple-reminderkit://") {
                                     NSWorkspace.shared.open(url)
                                 }
                             },
                             leading: {
                                 IconBadge(symbol: reminder.overdue
                                           ? "exclamationmark.circle" : "checklist",
                                           tint: reminder.overdue ? t.red : t.orange,
                                           theme: t)
                             },
                             trailing: { EmptyView() })
                )))
            }
        }

        if caffeine.active {
            out.append(RowSpec(id: "caffeine", view: AnyView(
                PanelRow(id: "caffeine", title: "Keeping this Mac awake",
                         subtitle: caffeine.detail, theme: t,
                         onTap: { caffeine.stop() },
                         leading: {
                             CoffeeCup(fill: caffeine.fill, active: true,
                                       tint: t.orange, shell: t.orange)
                                 .frame(width: 26, height: 26)
                         },
                         trailing: {
                             Text("Stop")
                                 .font(.system(size: 10, weight: .semibold))
                                 .foregroundStyle(t.accent)
                         })
            )))
        }

        if p.showFocusRow && focusState.available {
            out.append(RowSpec(id: "focus", view: AnyView(
                PanelRow(id: "focus",
                         title: focusState.active
                             ? (focusState.modeName ?? "Focus") : "Focus off",
                         subtitle: focusState.active
                             ? "Notifications are being held"
                             : (p.focusShortcut.isEmpty
                                ? "Pick a shortcut in Settings to toggle"
                                : "Tap to run \(p.focusShortcut)"),
                         theme: t,
                         onTap: p.focusShortcut.isEmpty ? nil : {
                             FocusController.run(p.focusShortcut)
                         },
                         leading: {
                             IconBadge(symbol: focusState.active
                                       ? "moon.fill" : "moon",
                                       tint: focusState.active ? t.purple : t.secondary,
                                       theme: t)
                         },
                         trailing: {
                             if focusState.active {
                                 Circle().fill(t.purple).frame(width: 7, height: 7)
                             }
                         })
            )))
        }

        if p.alertNetwork {
            let net = network.snapshot
            if net.onVPN || net.expensive || net.constrained || !net.connected {
                out.append(RowSpec(id: "network", view: AnyView(
                    PanelRow(id: "network", title: net.label,
                             subtitle: net.detail.isEmpty ? "Connected" : net.detail,
                             theme: t, onTap: nil,
                             leading: {
                                 IconBadge(symbol: net.symbol,
                                           tint: net.connected
                                               ? (net.expensive ? t.orange : t.teal)
                                               : t.red,
                                           theme: t)
                             },
                             trailing: {
                                 if net.onVPN {
                                     Text("VPN")
                                         .font(.system(size: 9, weight: .bold))
                                         .foregroundStyle(t.isDark ? Color.black
                                                                   : Color.white)
                                         .padding(.horizontal, 5)
                                         .padding(.vertical, 1.5)
                                         .background(Capsule().fill(t.green))
                                 }
                             })
                )))
            }
        }

        if p.showAudioSwitcher, let device = audio.current {
            out.append(RowSpec(id: "audio", view: AnyView(
                PanelRow(id: "audio", title: device.name, subtitle: "Output", theme: t,
                         onTap: nil,
                         leading: { IconBadge(symbol: device.symbol, tint: t.teal, theme: t) },
                         trailing: {
                             Menu {
                                 ForEach(audio.outputs) { option in
                                     Button {
                                         audio.select(option)
                                     } label: {
                                         if option.isDefault {
                                             Label(option.name, systemImage: "checkmark")
                                         } else {
                                             Text(option.name)
                                         }
                                     }
                                 }
                             } label: {
                                 Image(systemName: "chevron.up.chevron.down")
                                     .font(.system(size: 10, weight: .semibold))
                                     .foregroundStyle(t.tertiary)
                             }
                             .menuStyle(.borderlessButton)
                             .menuIndicator(.hidden)
                             .frame(width: 26)
                         })
            )))
        }

        if p.showBluetooth, !bluetooth.devices.isEmpty {
            out.append(RowSpec(id: "bluetooth", view: AnyView(
                PanelRow(id: "bluetooth", title: "Devices",
                         subtitle: bluetooth.devices.map(\.name).joined(separator: ", "),
                         theme: t, onTap: nil,
                         leading: {
                             IconBadge(symbol: "dot.radiowaves.right",
                                       tint: t.blue, theme: t)
                         },
                         trailing: {
                             HStack(spacing: 9) {
                                 ForEach(bluetooth.devices) { device in
                                     HStack(spacing: 3) {
                                         Image(systemName: device.symbol)
                                             .font(.system(size: 10))
                                         Text("\(device.percent)%")
                                             .font(.system(size: 10.5, weight: .semibold,
                                                           design: .rounded))
                                             .monospacedDigit()
                                     }
                                     .foregroundStyle(device.percent <= 20
                                                      ? t.red : t.secondary)
                                 }
                             }
                         })
            )))
        }

        if p.showRepo && state.repo.available {
            out.append(RowSpec(id: "repo", view: AnyView(
                PanelRow(id: "repo", title: state.repo.name,
                         subtitle: "\(state.repo.branch) · \(state.repo.summary)", theme: t,
                         onTap: nil,
                         leading: {
                             IconBadge(symbol: "arrow.triangle.branch",
                                       tint: state.repo.isClean ? t.secondary : t.orange,
                                       theme: t)
                         },
                         trailing: {
                             if !state.repo.isClean {
                                 Text("\(state.repo.dirty)")
                                     .font(.system(size: 11, weight: .semibold,
                                                   design: .rounded))
                                     .foregroundStyle(t.orange)
                                     .monospacedDigit()
                             }
                         })
            )))
        }

        return out
    }

    private var rowStack: some View {
        VStack(spacing: 2) {
            ForEach(rows) { $0.view }
        }
        .padding(.horizontal, -10)
    }

    private func eventSubtitle(_ event: AgendaEvent) -> String {
        var parts: [String] = []
        parts.append(event.isAllDay ? "All day" : DateKit.clock.string(from: event.start))
        parts.append(event.countdown)
        if let location = event.location, !location.isEmpty { parts.append(location) }
        return parts.joined(separator: " · ")
    }

    private var mediaCard: some View {
        let music = state.music
        let tint = music.isAppleMusic ? t.red : NotchSource.spotify.tint(t)

        return SurfaceCard(theme: t, padding: 12) {
            HStack(spacing: 13) {
                ZStack(alignment: .bottomTrailing) {
                    Artwork(image: music.artwork, tint: tint, side: 62, radius: 10)
                        .shadow(color: .black.opacity(0.32), radius: 7, y: 4)
                    if let icon = AppIcons.player(music.app) {
                        Image(nsImage: icon)
                            .resizable()
                            .frame(width: 16, height: 16)
                            .offset(x: 5, y: 5)
                    }
                }

                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 6) {
                        Text(music.title)
                            .font(.system(size: 13.5, weight: .semibold))
                            .foregroundStyle(t.primary)
                            .lineLimit(1)
                        if music.isPlaying && p.showVisualizer {
                            Visualizer(tint: tint, active: true, bars: 3, maxHeight: 10)
                        }
                        Spacer(minLength: 0)
                        Text(music.appLabel.uppercased())
                            .font(.system(size: 7.5, weight: .bold))
                            .kerning(0.6)
                            .foregroundStyle(tint)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1.5)
                            .background(Capsule().fill(tint.opacity(0.15)))
                    }

                    Text(music.artist + (music.album.isEmpty ? "" : " · " + music.album))
                        .font(.system(size: 11))
                        .foregroundStyle(t.secondary)
                        .lineLimit(1)

                    scrubber.padding(.top, 1)

                    HStack(spacing: 6) {
                        Text(music.elapsed)
                        Spacer(minLength: 0)
                        Text(music.timeLeft)
                    }
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundStyle(t.tertiary)
                    .monospacedDigit()
                }

                VStack(spacing: 7) {
                    HStack(spacing: 10) {
                        transport("backward.fill") { state.musicControl?.previous() }
                        Button {
                            SoundKit.tap()
                            state.musicControl?.playPause()
                        } label: {
                            Image(systemName: music.isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(t.isDark ? Color.black : Color.white)
                                .frame(width: 30, height: 30)
                                .background(Circle().fill(tint))
                                .contentShape(Circle())
                        }
                        .buttonStyle(.plain)
                        transport("forward.fill") { state.musicControl?.next() }
                    }

                    HStack(spacing: 5) {
                        Image(systemName: "speaker.fill")
                            .font(.system(size: 8))
                            .foregroundStyle(t.tertiary)
                        Slider(value: Binding(
                            get: { Double(music.volume) / 100 },
                            set: { state.musicControl?.setVolume($0) }), in: 0...1)
                            .controlSize(.mini)
                            .frame(width: 74)
                        Image(systemName: "speaker.wave.2.fill")
                            .font(.system(size: 8))
                            .foregroundStyle(t.tertiary)
                    }
                }
            }
        }
    }

    private var scrubber: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(t.wellFill)
                Capsule()
                    .fill(NotchSource.spotify.tint(t))
                    .frame(width: max(2, geo.size.width * state.music.fraction))
            }
            .contentShape(Rectangle().inset(by: -7))
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard p.allowScrubbing, state.music.duration > 0 else { return }
                        let ratio = min(max(value.location.x / geo.size.width, 0), 1)
                        state.music.position = ratio * state.music.duration
                    }
                    .onEnded { value in
                        guard p.allowScrubbing, state.music.duration > 0 else { return }
                        let ratio = min(max(value.location.x / geo.size.width, 0), 1)
                        state.musicControl?.seek(to: ratio * state.music.duration)
                        SoundKit.tap(.alignment)
                    }
            )
        }
        .frame(height: 3.5)
    }

    private func transport(_ symbol: String, size: CGFloat = 11,
                           action: @escaping () -> Void) -> some View {
        Button {
            SoundKit.tap()
            action()
        } label: {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(t.secondary)
                .frame(width: 18, height: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func tallyRow(_ provider: NotchSource, _ tally: LocalTally) -> some View {
        PanelRow(id: "usage-\(provider.rawValue)",
                 title: provider == .claude ? "Claude Code" : "Codex",
                 subtitle: "\(tally.messages) messages in the last \(tally.sinceText)",
                 theme: t, onTap: nil,
                 leading: {
                     SourceIcon(source: provider, kind: .info, theme: t, side: 28)
                 },
                 trailing: {
                     VStack(alignment: .trailing, spacing: 2) {
                         Text(UsageSnapshot.short(tally.tokens))
                             .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                             .foregroundStyle(t.primary)
                             .monospacedDigit()
                         Text("tokens")
                             .font(.system(size: 8.5, weight: .medium))
                             .foregroundStyle(t.tertiary)
                     }
                 })
    }

    private func limitRow(_ limits: CodexLimits) -> some View {
        let primary = limits.primary
        let fraction = min(1, max(0, primary.usedPercent / 100))
        let tint = primary.usedPercent >= 90 ? t.red
            : primary.usedPercent >= 70 ? t.orange : NotchSource.chatgpt.tint(t)

        return PanelRow(id: "usage-codex",
                        title: limits.plan.isEmpty ? "Codex"
                            : "Codex \(limits.plan.capitalized)",
                        subtitle: {
                            var parts = ["\(primary.label) limit",
                                         "resets in \(primary.remainingText)"]
                            if let text = limits.projection?.text { parts.append(text) }
                            return parts.joined(separator: ", ")
                        }(),
                        theme: t, onTap: nil,
                        leading: {
                            SourceIcon(source: .chatgpt, kind: .info, theme: t, side: 28)
                        },
                        trailing: {
                            VStack(alignment: .trailing, spacing: 3) {
                                HStack(spacing: 4) {
                                    if let weekly = limits.secondary {
                                        Text("\(Int(weekly.usedPercent))% wk")
                                            .font(.system(size: 8.5, weight: .medium))
                                            .foregroundStyle(t.tertiary)
                                            .monospacedDigit()
                                    }
                                    Text("\(Int(primary.usedPercent))%")
                                        .font(.system(size: 12.5, weight: .semibold,
                                                      design: .rounded))
                                        .foregroundStyle(t.primary)
                                        .monospacedDigit()
                                }
                                Capsule()
                                    .fill(t.wellFill)
                                    .frame(width: 54, height: 2.5)
                                    .overlay(alignment: .leading) {
                                        Capsule()
                                            .fill(tint)
                                            .frame(width: max(2, 54 * fraction), height: 2.5)
                                    }
                            }
                        })
    }

    private var activity: some View {
        VStack(alignment: .leading, spacing: 3) {
            sectionLabel("ACTIVITY", action: ("Clear", { state.clearAll() }))
                .padding(.bottom, 3)

            ForEach(state.items.reversed().prefix(4)) { item in
                PanelRow(id: "item-\(item.id)", title: item.title,
                         subtitle: item.body, theme: t, onTap: nil,
                         leading: {
                             SourceIcon(source: item.source, kind: item.kind,
                                        theme: t, side: 26)
                         },
                         trailing: {
                             HStack(spacing: 8) {
                                 ForEach(item.actions) { action in
                                     PillButton(label: action.label,
                                                tint: item.accent(t), theme: t) {
                                         state.run(action, on: item)
                                     }
                                 }
                                 Button { state.dismiss(item) } label: {
                                     Image(systemName: "xmark")
                                         .font(.system(size: 8, weight: .bold))
                                         .foregroundStyle(t.tertiary)
                                         .frame(width: 18, height: 18)
                                         .background(Circle().fill(t.control))
                                         .contentShape(Circle())
                                 }
                                 .buttonStyle(.plain)
                             }
                         })
                .overlay(alignment: .bottom) {
                    if item.kind == .progress {
                        ProgressBar(value: item.progress, tint: item.accent(t),
                                    theme: t, height: 2.5)
                            .padding(.horizontal, 10)
                    }
                }
            }
        }
        .padding(.horizontal, -10)
    }

    private func sectionLabel(_ text: String,
                              action: (String, () -> Void)? = nil) -> some View {
        HStack {
            Text(text)
                .font(.system(size: 9, weight: .bold))
                .kerning(0.9)
                .foregroundStyle(t.tertiary)
            Spacer()
            if let action {
                Button(action.0, action: action.1)
                    .buttonStyle(.plain)
                    .font(.system(size: 10.5))
                    .foregroundStyle(t.secondary)
            }
        }
        .padding(.horizontal, 10)
    }
}
