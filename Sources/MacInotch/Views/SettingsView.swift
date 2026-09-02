import SwiftUI
import AppKit

@MainActor
final class SettingsNav: ObservableObject {
    static let shared = SettingsNav()
    @Published var tab: SettingsView.Tab = .general
    @Published var boostPercent: Double = 1.0
    @Published var boostMinutes: Double = 5
    @Published var historySearch: String = ""
    @Published var historySource: NotchSource? = nil
    @Published var newAccountLabel: String = ""
    @Published var shortcutNames: [String] = []
    @Published var githubToken: String = ""
    @Published var connectingGitHub = false
    @Published var settingsSearch: String = ""
}

struct SettingsView: View {
    @ObservedObject private var prefs = Prefs.shared
    @ObservedObject private var nav = SettingsNav.shared
    @ObservedObject private var fanControl = FanControlClient.shared
    @ObservedObject private var state = NotchState.shared
    @ObservedObject private var history = HistoryStore.shared
    @ObservedObject private var shelf = ShelfStore.shared
    @ObservedObject private var focus = FocusWatcher.shared
    @ObservedObject private var calendar = CalendarService.shared
    @ObservedObject private var weather = WeatherService.shared
    @ObservedObject private var themes = ThemeManager.shared
    @ObservedObject private var github = GitHubService.shared
    @ObservedObject private var dictation = Dictation.shared
    @ObservedObject private var switcher = AccountService.shared

    enum Tab: String, CaseIterable, Identifiable {
        case general = "General"
        case widgets = "Widgets"
        case notch = "Notch"
        case fans = "Fans"
        case alerts = "Alerts"
        case history = "History"
        case integrations = "Connect"

        var id: String { rawValue }
        var symbol: String {
            switch self {
            case .general:      return "gearshape"
            case .widgets:      return "square.grid.2x2"
            case .notch:        return "rectangle.topthird.inset.filled"
            case .fans:         return "fan"
            case .alerts:       return "bell.badge"
            case .history:      return "clock.arrow.circlepath"
            case .integrations: return "link"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            tabBar
            Divider()
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 640, height: 620)
    }

    private var tabBar: some View {
        HStack(spacing: 2) {
            ForEach(Tab.allCases) { tab in
                Button {
                    nav.tab = tab
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: tab.symbol)
                            .font(.system(size: 16, weight: .regular))
                            .frame(height: 19)
                        Text(tab.rawValue)
                            .font(.system(size: 10.5))
                            .lineLimit(1)
                    }
                    .frame(width: 78, height: 48)
                    .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(nav.tab == tab ? Color.primary.opacity(0.10)
                                                 : Color.clear)
                    )
                    .foregroundStyle(nav.tab == tab ? Color.primary : Color.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity)
        .background(.bar)
    }

    @ViewBuilder private var content: some View {
        if !nav.settingsSearch.isEmpty {
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Text("Results")
                        .font(.system(size: 13, weight: .semibold))
                    Spacer(minLength: 12)
                    searchField
                }
                .padding(.horizontal, 18)
                .padding(.top, 12)
                .padding(.bottom, 4)
                searchResults
            }
        } else {
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Image(systemName: nav.tab.symbol)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.tint)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(nav.tab.rawValue)
                            .font(.system(size: 13, weight: .semibold))
                        Text(tabBlurb)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 12)
                    searchField
                }
                .padding(.horizontal, 18)
                .padding(.top, 12)
                .padding(.bottom, 4)

                tabContent
            }
        }
    }

    private var searchResults: some View {
        let query = nav.settingsSearch
            .lowercased().trimmingCharacters(in: .whitespaces)
        let hits = SettingsIndex.entries.filter { entry in
            entry.title.lowercased().contains(query)
                || entry.keywords.contains { $0.contains(query) }
        }

        return Form {
            if hits.isEmpty {
                Text("Nothing matches \"\(nav.settingsSearch)\".")
                    .foregroundStyle(.secondary)
            }
            ForEach(hits) { entry in
                Button {
                    nav.tab = entry.tab
                    nav.settingsSearch = ""
                } label: {
                    HStack(spacing: 9) {
                        Image(systemName: entry.tab.symbol)
                            .foregroundStyle(.secondary)
                            .frame(width: 18)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(entry.title)
                            Text(entry.tab.rawValue)
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .formStyle(.grouped)
    }

    private var searchField: some View {
        HStack(spacing: 5) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            TextField("Search", text: $nav.settingsSearch)
                .textFieldStyle(.plain)
                .font(.system(size: 11.5))
                .frame(width: 118)
            if !nav.settingsSearch.isEmpty {
                Button {
                    nav.settingsSearch = ""
                } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.borderless)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 7).fill(.quaternary))
    }

    private var tabBlurb: String {
        switch nav.tab {
        case .general:
            return "How it looks and sounds, and the keys that reach it."
        case .widgets:
            return "What the panel shows about you and the machine."
        case .notch:
            return "The shape itself: its size, what it does when you drag it, "
                + "and what it can say with a colour."
        case .fans:
            return "Live fan speeds, and timed boosts through the helper."
        case .alerts:
            return "What is worth interrupting you for."
        case .history:
            return "Everything the notch has shown, searchable."
        case .integrations:
            return "Accounts, mail, calendars, GitHub, dictation and permissions."
        }
    }

    @ViewBuilder private var tabContent: some View {
        switch nav.tab {
        case .general:      general
        case .widgets:      widgets
        case .notch:        notch
        case .fans:         fansTab
        case .alerts:       alerts
        case .history:      historyTab
        case .integrations: integrations
        }
    }

    private var general: some View {
        Form {
            Section("Appearance") {
                Picker("Theme", selection: $prefs.d.appearance) {
                    ForEach(AppearanceMode.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)

                Toggle("Liquid Glass background", isOn: $prefs.d.glassEnabled)
                Toggle("Use the system accent colour", isOn: $prefs.d.accentFollowsSystem)
                ColorPicker("Custom accent", selection: Binding(
                    get: { Color(hex: prefs.d.accentHex) ?? .orange },
                    set: { prefs.d.accentHex = $0.hexString }
                ))
                .disabled(prefs.d.accentFollowsSystem)
                Picker("Opening animation", selection: $prefs.d.openAnimation) {
                    ForEach(OpenAnimation.allCases) { Text($0.label).tag($0) }
                }
                .disabled(prefs.d.reduceMotion)
                .onChange(of: prefs.d.openAnimation) { _, _ in
                    NotchState.shared.previewAnimation()
                }
                HStack {
                    Text("Opening springs open, closing snaps shut, they are tuned "
                         + "separately so an overshoot on the way out does not become "
                         + "a wobble on the way back.")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Preview") { NotchState.shared.previewAnimation() }
                        .disabled(prefs.d.reduceMotion)
                }
                Toggle("Reduce motion", isOn: $prefs.d.reduceMotion)
                Toggle("Trackpad haptics", isOn: $prefs.d.haptics)
            }

            Section("Clock") {
                Toggle("Show the clock", isOn: $prefs.d.showClock)
                Toggle("24-hour time", isOn: $prefs.d.clock24h)
                Toggle("Show seconds", isOn: $prefs.d.clockSeconds)
                    .disabled(!prefs.d.showClock)
            }

            Section("Keyboard") {
                Toggle("Global shortcut", isOn: $prefs.d.hotKeyEnabled)
                Picker("Shortcut", selection: $prefs.d.hotKeyLabel) {
                    ForEach(HotKey.choices) { Text($0.label).tag($0.label) }
                }
                .disabled(!prefs.d.hotKeyEnabled)
                Text("Pins the panel open from anywhere. Uses Carbon hotkey "
                     + "registration, so it needs no Accessibility permission.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Startup") {
                Toggle("Launch at login", isOn: Binding(
                    get: { LoginItem.isEnabled },
                    set: { LoginItem.set($0) }
                ))
                HStack {
                    Button("Reset to defaults") { prefs.reset() }
                    Spacer()
                    Button("Quit MacInotch") { NSApp.terminate(nil) }
                }
            }
        }
        .formStyle(.grouped)
    }

    private var widgets: some View {
        Form {
            Section("Calendars") {
                Toggle("Gregorian", isOn: $prefs.d.showGregorian)
                Toggle("Shamsi (Jalali)", isOn: $prefs.d.showShamsi)
                Toggle("Hijri", isOn: $prefs.d.showHijri)
                Toggle("Persian digits (۱۲۳)", isOn: $prefs.d.persianDigits)
            }
            Section("System vitals") {
                Toggle("CPU", isOn: $prefs.d.showCPU)
                Toggle("Memory", isOn: $prefs.d.showRAM)
                Toggle("Swap", isOn: $prefs.d.showSwap)
                Toggle("Battery", isOn: $prefs.d.showBattery)
                Toggle("Temperature", isOn: $prefs.d.showTemperature)
                Toggle("Use Fahrenheit", isOn: $prefs.d.fahrenheit)
                    .disabled(!prefs.d.showTemperature)
                Toggle("Fan speeds", isOn: $prefs.d.showFans)
                Toggle("Power draw", isOn: $prefs.d.showPower)
                Toggle("Bluetooth device battery", isOn: $prefs.d.showBluetooth)
                Toggle("Audio output switcher", isOn: $prefs.d.showAudioSwitcher)
                Toggle("Notes", isOn: $prefs.d.showNotes)
                Toggle("Sparkline history", isOn: $prefs.d.showSparklines)
                Toggle("Name the top process", isOn: $prefs.d.showTopProcess)
                Toggle("Disk space", isOn: $prefs.d.showDisk)
                Toggle("Network throughput", isOn: $prefs.d.showNetwork)
                LabeledContent("Sample every") {
                    Slider(value: $prefs.d.pollSeconds, in: 0.5...10, step: 0.5)
                        .frame(width: 170)
                }
                Text("\(prefs.d.pollSeconds, specifier: "%.1f") seconds, restart to apply")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Sessions") {
                Toggle("Session browser", isOn: $prefs.d.showSessions)
                Toggle("Claude Code", isOn: $prefs.d.sessionsShowClaude)
                    .disabled(!prefs.d.showSessions)
                Toggle("Codex", isOn: $prefs.d.sessionsShowCodex)
                    .disabled(!prefs.d.showSessions)
                Toggle("Only sessions that are still running",
                       isOn: $prefs.d.sessionsActiveOnly)
                    .disabled(!prefs.d.showSessions)
                Text("A session counts as running when its process is alive, "
                     + "not merely when its transcript was written to recently.")
                    .font(.caption).foregroundStyle(.secondary)
            }


            Section("AI usage") {
                Toggle("Show token usage", isOn: $prefs.d.showUsage)
                Toggle("Claude Code", isOn: $prefs.d.usageShowClaude)
                    .disabled(!prefs.d.showUsage)
                Toggle("Codex", isOn: $prefs.d.usageShowCodex)
                    .disabled(!prefs.d.showUsage)
                Toggle("Notify when the window resets", isOn: $prefs.d.notifyOnUsageReset)
                    .disabled(!prefs.d.showUsage)
                Toggle("Warn at 80% and 95% of the limit",
                       isOn: $prefs.d.notifyOnUsageThreshold)
                    .disabled(!prefs.d.showUsage)
                Text("The warning offers to switch to another saved account when one "
                     + "has room left.")
                    .font(.caption).foregroundStyle(.secondary)
                LabeledContent("Window length") {
                    Slider(value: $prefs.d.usageWindowHours, in: 1...24, step: 1)
                        .frame(width: 170)
                }
                Text("Codex reports its own limits, so its figures are the real ones. "
                     + "Claude Code publishes no quota anywhere on disk, so its figure "
                     + "is a local token tally over the window length above.")
                    .font(.caption).foregroundStyle(.secondary)
            }




            Section("Keep awake") {
                Picker("Coffee cup lasts", selection: $prefs.d.caffeineMinutes) {
                    ForEach(CaffeineService.durations, id: \.minutes) { option in
                        Text(option.label).tag(option.minutes)
                    }
                }
                Toggle("Keep the display on too", isOn: $prefs.d.caffeineKeepsDisplayOn)
                Text("Clicking the cup fills it and holds a power assertion for that "
                     + "long, draining as the time runs down. Right click it to pick a "
                     + "different length for one go. With the display off the machine "
                     + "stays running while the screen is free to sleep.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Notch as a control") {
                Toggle("Drag across the notch to adjust", isOn: $prefs.d.stripEnabled)
                Picker("Dragging changes", selection: $prefs.d.stripDefault) {
                    Text("Volume").tag("volume")
                    Text("Brightness").tag("brightness")
                    Text("Track position").tag("scrub")
                }
                .disabled(!prefs.d.stripEnabled)
                Text("Hold option while dragging for brightness, shift for the track "
                     + "position. Brightness goes through a private display interface, "
                     + "so it may stop working after a system update, and does nothing "
                     + "rather than failing loudly.")
                    .font(.caption).foregroundStyle(.secondary)

                Toggle("Trace the notch with a status colour", isOn: $prefs.d.ambientGlow)
                if prefs.d.ambientGlow { ambientControls }
            }

            Section("Sound cues") {
                Text("A different sound per event, so what happened is audible "
                     + "without looking.")
                    .font(.caption).foregroundStyle(.secondary)
                ForEach(SoundCue.allCases) { cue in
                    HStack {
                        Picker(cue.label, selection: cueBinding(cue)) {
                            Text("Silent").tag("none")
                            ForEach(SoundKit.bundledNames, id: \.self) { name in
                                Text(name.capitalized).tag(name)
                            }
                        }
                        Button {
                            SoundKit.play(cue: cue)
                        } label: { Image(systemName: "play.circle") }
                            .buttonStyle(.borderless)
                    }
                }
            }

            Section("Panel behaviour") {
                Toggle("Collapse when the pointer leaves", isOn: $prefs.d.autoCollapse)
                LabeledContent("Wait before collapsing") {
                    HStack {
                        Slider(value: $prefs.d.collapseDelay, in: 0...5, step: 0.25)
                            .frame(width: 140)
                        Text(prefs.d.collapseDelay == 0 ? "at once"
                             : String(format: "%.2gs", prefs.d.collapseDelay))
                            .font(.caption).monospacedDigit()
                            .frame(width: 44, alignment: .trailing)
                    }
                }
                .disabled(!prefs.d.autoCollapse)
                Text("Turning it off keeps the panel open until you click away, "
                     + "which helps if reaching a control before it closes is a "
                     + "fight.")
                    .font(.caption).foregroundStyle(.secondary)
            }



            Section("Focus") {
                Toggle("Focus row in the panel", isOn: $prefs.d.showFocusRow)
                Picker("Toggle with shortcut", selection: $prefs.d.focusShortcut) {
                    Text("None").tag("")
                    ForEach(nav.shortcutNames, id: \.self) { name in
                        Text(name).tag(name)
                    }
                }
                Text("macOS offers no way to set a Focus directly, so toggling runs a "
                     + "Shortcut you have made. Build one with the Set Focus action, "
                     + "then pick it here. The state shown in the notch is read from "
                     + "the system and is accurate either way.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Reload shortcuts") { nav.shortcutNames = FocusController.shortcuts() }
                    .controlSize(.small)
                    .onAppear {
                        if nav.shortcutNames.isEmpty {
                            nav.shortcutNames = FocusController.shortcuts()
                        }
                    }
            }

            Section("Panel") {
                Stepper("Scroll the list past \(prefs.d.rowsBeforeScrolling) rows",
                        value: $prefs.d.rowsBeforeScrolling, in: 3...20)
                Text("Rows below that point scroll instead of growing the panel "
                     + "past the bottom of the screen.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Alerts") {
                Toggle("Disk filling up", isOn: $prefs.d.alertDisk)
                Toggle("A process pinning the CPU", isOn: $prefs.d.alertRunaway)
                Toggle("Thermal throttling", isOn: $prefs.d.alertThermal)
                Toggle("Battery health and low battery", isOn: $prefs.d.alertBattery)
                Toggle("Network, VPN and hotspot changes", isOn: $prefs.d.alertNetwork)
                Text("Each warning fires once and rearms only after the condition "
                     + "clears, so a full disk does not chime every minute.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Facts") {
                Toggle("Year progress", isOn: $prefs.d.showYearProgress)
                Toggle("Week number", isOn: $prefs.d.showWeekNumber)
                Toggle("Uptime", isOn: $prefs.d.showUptime)
                Toggle("Nowruz countdown", isOn: $prefs.d.showNowruz)
            }
            Section("Repository") {
                Toggle("Show git status", isOn: $prefs.d.showRepo)
                HStack {
                    TextField("path to a repo", text: $prefs.d.repoPath)
                        .textFieldStyle(.roundedBorder)
                    Button("Choose…") {
                        let panel = NSOpenPanel()
                        panel.canChooseDirectories = true
                        panel.canChooseFiles = false
                        panel.allowsMultipleSelection = false
                        if panel.runModal() == .OK, let url = panel.url {
                            prefs.d.repoPath = url.path
                        }
                    }
                }
                .disabled(!prefs.d.showRepo)
                Text(state.repo.available
                     ? "\(state.repo.name): \(state.repo.branch) · \(state.repo.summary)"
                     : "Branch, uncommitted changes, and ahead/behind counts.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Weather") {
                Toggle("Show weather", isOn: $prefs.d.showWeather)
                Toggle("Use my location", isOn: $prefs.d.weatherUseLocation)
                    .disabled(!prefs.d.showWeather)
                Toggle("Fahrenheit", isOn: $prefs.d.weatherFahrenheit)
                    .disabled(!prefs.d.showWeather)
                Toggle("Show in the collapsed notch", isOn: $prefs.d.idleShowWeather)
                    .disabled(!prefs.d.showWeather)
                HStack {
                    Text("Manual coordinates")
                    Spacer()
                    TextField("lat", value: $prefs.d.weatherLatitude,
                              format: .number.precision(.fractionLength(3)))
                        .frame(width: 70)
                    TextField("lon", value: $prefs.d.weatherLongitude,
                              format: .number.precision(.fractionLength(3)))
                        .frame(width: 70)
                }
                .disabled(prefs.d.weatherUseLocation)
                HStack {
                    Text(weather.status).font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Request location") { weather.requestLocation() }
                    Button("Refresh") { weather.fetch() }
                }
            }

            Section("Timer") {
                LabeledContent("Focus") {
                    Stepper("\(Int(prefs.d.pomodoroFocusMinutes)) min",
                            value: $prefs.d.pomodoroFocusMinutes, in: 5...90, step: 5)
                }
                LabeledContent("Break") {
                    Stepper("\(Int(prefs.d.pomodoroBreakMinutes)) min",
                            value: $prefs.d.pomodoroBreakMinutes, in: 1...30, step: 1)
                }
                LabeledContent("Long break") {
                    Stepper("\(Int(prefs.d.pomodoroLongBreakMinutes)) min",
                            value: $prefs.d.pomodoroLongBreakMinutes, in: 5...60, step: 5)
                }
                LabeledContent("Rounds before a long break") {
                    Stepper("\(prefs.d.pomodoroRounds)",
                            value: $prefs.d.pomodoroRounds, in: 2...8)
                }
                Toggle("Chain rounds automatically", isOn: $prefs.d.pomodoroAutoContinue)
            }

            Section("Menu bar") {
                Toggle("Hide menu bar items", isOn: $prefs.d.menuBarHiding)
                    .onChange(of: prefs.d.menuBarHiding) { _, on in
                        if on { MenuBarHider.shared.install() }
                        else { MenuBarHider.shared.uninstall() }
                    }
                LabeledContent("Re-hide after") {
                    Slider(value: $prefs.d.menuBarAutoHideSeconds, in: 0...60, step: 5)
                        .frame(width: 150)
                }
                .disabled(!prefs.d.menuBarHiding)
                Text(prefs.d.menuBarAutoHideSeconds == 0
                     ? "Stays open until you click again"
                     : "\(Int(prefs.d.menuBarAutoHideSeconds)) seconds")
                    .font(.caption).foregroundStyle(.secondary)
                Text("Adds a divider and a chevron to the menu bar. Command-drag any "
                     + "status icon to the left of the divider to put it in the hidden "
                     + "group, then click the chevron to collapse it. This needs no "
                     + "Accessibility permission because it only resizes MacInotch's own "
                     + "status item, which pushes the icons left of it off-screen.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Notes") {
                HStack {
                    Text(NotesStore.shared.directory.path)
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.head)
                    Spacer()
                    Button("Choose…") { NotesStore.shared.chooseFolder() }
                    Button("Reveal") { NotesStore.shared.revealFolder() }
                }
                Text("Notes are plain .md files in that folder, so they sync with "
                     + "whatever you already use.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Calendar") {
                Toggle("Next event", isOn: $prefs.d.showCalendar)
                Toggle("Include all-day events", isOn: $prefs.d.calendarAllDay)
                    .disabled(!prefs.d.showCalendar)
                LabeledContent("Look ahead") {
                    Slider(value: $prefs.d.calendarHorizonHours, in: 1...48, step: 1)
                        .frame(width: 170)
                }
                .disabled(!prefs.d.showCalendar)
                Text("\(Int(prefs.d.calendarHorizonHours)) hours")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Label(calendar.authorized ? "Calendar access granted"
                          : calendar.denied ? "Calendar access denied"
                                            : "Calendar access not requested",
                          systemImage: calendar.authorized ? "checkmark.circle.fill"
                                                           : "lock.fill")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    if !calendar.authorized {
                        Button("Request access") { calendar.requestAccess() }
                    }
                }
            }

            Section("Media") {
                Toggle("Now playing", isOn: $prefs.d.showNowPlaying)
                Toggle("Pop up on track change", isOn: $prefs.d.musicAutoPopup)
                    .disabled(!prefs.d.showNowPlaying)
                Toggle("Audio visualizer", isOn: $prefs.d.showVisualizer)
                    .disabled(!prefs.d.showNowPlaying)
                Toggle("Drag the progress bar to seek", isOn: $prefs.d.allowScrubbing)
                    .disabled(!prefs.d.showNowPlaying)
            }
        }
        .formStyle(.grouped)
    }

    private var notch: some View {
        Form {
            Section("Collapsed readout") {
                Toggle("Show live info beside the notch", isOn: $prefs.d.liveStripEnabled)
                Text("Pick what sits either side of the notch. Anything with no data "
                     + "right now stays hidden until it has some.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Left of the notch") {
                stripPicker(isLeft: true)
            }

            Section("Right of the notch") {
                stripPicker(isLeft: false)
                Toggle("App presence dots", isOn: $prefs.d.idleShowPresence)
                    .disabled(!prefs.d.liveStripEnabled)
            }
            Section("Watch these apps") {
                Toggle("Claude (desktop + Claude Code)", isOn: $prefs.d.watchClaude)
                Toggle("ChatGPT", isOn: $prefs.d.watchChatGPT)
                Toggle("Spotify", isOn: $prefs.d.watchSpotify)
            }
            Section("Shelf") {
                Toggle("Accept files dropped on the notch", isOn: $prefs.d.shelfEnabled)
                Toggle("Catch new screenshots", isOn: $prefs.d.screenshotCatch)
                    .disabled(!prefs.d.shelfEnabled)
                Toggle("Clipboard history", isOn: $prefs.d.clipboardEnabled)
                    .onChange(of: prefs.d.clipboardEnabled) { _, _ in
                        ClipboardService.shared.restart()
                    }
                HStack {
                    Text("\(shelf.items.count) of \(ShelfStore.limit) parked")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Empty shelf") { shelf.clear() }
                        .disabled(shelf.items.isEmpty)
                }
                Text("Files are referenced, never copied, removing one from the shelf "
                     + "leaves the original alone, and entries whose file has moved are "
                     + "dropped automatically.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Size") {
                LabeledContent("Panel width") {
                    Slider(value: $prefs.d.expandedWidth, in: 460...780, step: 10)
                        .frame(width: 170)
                }
                Text("\(Int(prefs.d.expandedWidth)) pt")
                    .font(.caption).foregroundStyle(.secondary)
                LabeledContent("Corner radius") {
                    Slider(value: $prefs.d.cornerRadius, in: 8...28, step: 1)
                        .frame(width: 170)
                }
                Text("\(Int(prefs.d.cornerRadius)) pt")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Displays") {
                Toggle("Follow the display the pointer is on",
                       isOn: $prefs.d.followActiveDisplay)
                Text("Only moves while the notch is collapsed, an open panel "
                     + "stays where you are reading it.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Idle") {
                Toggle("Show a clock when idle", isOn: $prefs.d.idleClockEnabled)
                LabeledContent("After") {
                    Slider(value: $prefs.d.idleClockMinutes, in: 1...60, step: 1)
                        .frame(width: 170)
                }
                .disabled(!prefs.d.idleClockEnabled)
                Text("\(Int(prefs.d.idleClockMinutes)) minutes without input")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Interaction") {
                Toggle("Expand on hover", isOn: $prefs.d.hoverToExpand)
                LabeledContent("Banner duration") {
                    Slider(value: $prefs.d.peekSeconds, in: 1.5...15, step: 0.5)
                        .frame(width: 170)
                }
                Text("\(prefs.d.peekSeconds, specifier: "%.1f") seconds")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var fansTab: some View {
        Form {
            Section("Fans") {
                if state.fans.fans.isEmpty {
                    Text("No fans detected on this Mac.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(state.fans.fans) { fan in
                        LabeledContent(fan.label) {
                            HStack(spacing: 6) {
                                Text("\(Int(fan.rpm)) rpm")
                                    .monospacedDigit()
                                if let hold = fanControl.holds[fan.index], hold > 0 {
                                    Text("· held \(hold / 60)m \(hold % 60)s")
                                        .foregroundStyle(.orange)
                                        .monospacedDigit()
                                }
                            }
                            .font(.callout)
                        }
                    }
                    Text("Commandable range \(Int(state.fans.fans[0].minRPM)) to "
                         + "\(Int(state.fans.fans[0].maxRPM)) rpm. The firmware stops the "
                         + "fans entirely when the Mac is cool, but 2317 rpm is the "
                         + "slowest speed the SMC will accept, so there is no "
                         + "\u{201C}off\u{201D} to set, only automatic, which may mean "
                         + "stopped.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            Section("Boost") {
                Picker("Speed", selection: $nav.boostPercent) {
                    Text("50%").tag(0.5)
                    Text("75%").tag(0.75)
                    Text("Blast (100%)").tag(1.0)
                }
                .pickerStyle(.segmented)

                Picker("For", selection: $nav.boostMinutes) {
                    Text("2 min").tag(2.0)
                    Text("5 min").tag(5.0)
                    Text("10 min").tag(10.0)
                    Text("30 min").tag(30.0)
                }
                .pickerStyle(.segmented)

                HStack {
                    Button {
                        fanControl.setAll(percent: nav.boostPercent,
                                          minutes: nav.boostMinutes)
                    } label: {
                        Label("Start", systemImage: "wind")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!fanControl.reachable)

                    Button("Back to automatic") { fanControl.autoAll() }
                        .disabled(!fanControl.reachable || !fanControl.hasActiveOverride)

                    Spacer()
                    if fanControl.hasActiveOverride {
                        Label("holding", systemImage: "clock")
                            .font(.caption).foregroundStyle(.orange)
                    }
                }

                Text("Reverts to automatic when the timer ends, if the SoC passes 90 °C, "
                     + "or if the helper stops for any reason.")
                    .font(.caption).foregroundStyle(.secondary)
                if let error = fanControl.lastError {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            Section("Helper") {
                HStack {
                    Label(helperStatusText, systemImage: helperStatusIcon)
                        .font(.callout)
                        .foregroundStyle(fanControl.reachable ? .primary : .secondary)
                    Spacer()
                    if fanControl.busy {
                        ProgressView().controlSize(.small)
                    } else if fanControl.reachable {
                        Button("Remove") { fanControl.uninstall() }
                    } else {
                        Button("Install…") { fanControl.install() }
                            .buttonStyle(.borderedProminent)
                    }
                }
                if let error = fanControl.lastError {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(.red)
                }
                Text("Changing fan speed needs a root helper, because macOS refuses SMC "
                     + "writes from ordinary apps. Installing asks for your administrator "
                     + "password once and adds a LaunchDaemon; Remove takes it back out.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var helperStatusText: String {
        if fanControl.reachable { return "Helper running" }
        if fanControl.installed { return "Helper installed but not responding" }
        return "Helper not installed, fan control unavailable"
    }

    private var helperStatusIcon: String {
        if fanControl.reachable { return "checkmark.circle.fill" }
        return fanControl.installed ? "exclamationmark.circle" : "lock.fill"
    }

    private var alerts: some View {
        Form {
            Section("Sound") {
                Toggle("Play a sound with notifications", isOn: $prefs.d.playSounds)
                Picker("Sound set", selection: $prefs.d.soundSet) {
                    Text("MacInotch chimes").tag("chime")
                    Text("macOS system alerts").tag("system")
                }
                .disabled(!prefs.d.playSounds)

                HStack(spacing: 8) {
                    ForEach(["notify", "success", "attention", "error", "tick"], id: \.self) { n in
                        Button(n.capitalized) { SoundKit.preview(n) }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }
                }
                Text("The chimes are synthesised mallet tones, short soft attack, no clipping.")
                    .font(.caption).foregroundStyle(.secondary)

                ForEach(ruleSources, id: \.rawValue) { src in
                    Picker("\(src.displayName) sound", selection: soundBinding(src)) {
                        Text("Default").tag("default")
                        Text("Silent").tag("none")
                        ForEach(SoundKit.bundledNames, id: \.self) {
                            Text($0.capitalized).tag($0)
                        }
                    }
                }
            }

            Section("Quiet") {
                if let remaining = state.muteRemaining {
                    HStack {
                        Label("Muted for \(remaining)", systemImage: "bell.slash.fill")
                            .foregroundStyle(.orange)
                        Spacer()
                        Button("Unmute") { state.unmute() }
                    }
                } else {
                    HStack {
                        Text("Mute notifications")
                        Spacer()
                        ForEach([15.0, 60.0, 240.0], id: \.self) { minutes in
                            Button(minutes < 60 ? "\(Int(minutes))m" : "\(Int(minutes / 60))h") {
                                state.mute(minutes: minutes)
                            }
                            .controlSize(.small)
                        }
                    }
                }
                Toggle("Stay quiet during a Focus", isOn: $prefs.d.respectFocus)
                LabeledContent("Also quiet in these apps") {
                    TextField("bundle ids, comma separated", text: $prefs.d.quietApps)
                        .frame(width: 220)
                }
                Toggle("Nudge when charged past a limit", isOn: $prefs.d.batteryLimitNudge)
                LabeledContent("Limit") {
                    Slider(value: $prefs.d.batteryLimitPercent, in: 50...100, step: 5)
                        .frame(width: 150)
                }
                .disabled(!prefs.d.batteryLimitNudge)
                Text("\(Int(prefs.d.batteryLimitPercent))%")
                    .font(.caption).foregroundStyle(.secondary)
                Label(focus.available
                      ? (focus.active ? "Focus on: \(focus.modeName ?? "unknown")"
                                      : "No Focus active")
                      : "Focus state needs Full Disk Access",
                      systemImage: focus.available ? "moon.circle" : "lock.fill")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Per-source rules") {
                ForEach(ruleSources, id: \.rawValue) { src in
                    Picker(src.displayName, selection: ruleBinding(src)) {
                        ForEach(PrefsData.SourceRule.allCases) { Text($0.label).tag($0) }
                    }
                }
                Text("Rules are applied before anything else: \u{201C}Ignore\u{201D} drops "
                     + "the notification, \u{201C}No banner\u{201D} sends it straight to the "
                     + "panel and history.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Try it") {
                HStack {
                    Button("Test banner") {
                        var p = NotchPayload()
                        p.source = "claude"; p.title = "Hello from settings"
                        p.body = "This is a test notification"; p.kind = "success"
                        NotchState.shared.handle(p)
                    }
                    Button("Test attention") {
                        var p = NotchPayload()
                        p.source = "chatgpt"; p.title = "Needs your attention"
                        p.body = "Hover the notch to acknowledge"; p.kind = "attention"
                        p.key = "test-attention"
                        NotchState.shared.handle(p)
                    }
                    Button("Test progress") {
                        Task { @MainActor in
                            for i in stride(from: 0.0, through: 1.0, by: 0.1) {
                                var p = NotchPayload()
                                p.key = "test-progress"; p.source = "custom"
                                p.kind = "progress"; p.title = "Working"
                                p.body = "step \(Int(i * 10))/10"; p.progress = i
                                NotchState.shared.handle(p)
                                try? await Task.sleep(for: .milliseconds(400))
                            }
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private var historyTab: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search notifications", text: $nav.historySearch)
                    .textFieldStyle(.plain)

                Picker("", selection: $nav.historySource) {
                    Text("All sources").tag(nil as NotchSource?)
                    ForEach(history.sourcesPresent, id: \.rawValue) { src in
                        Text(src.displayName).tag(src as NotchSource?)
                    }
                }
                .labelsHidden()
                .frame(width: 130)

                Button("Clear") { history.clear() }
                    .disabled(history.entries.isEmpty)
            }
            .padding(12)

            Divider()

            if visibleHistory.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "tray")
                        .font(.system(size: 26))
                        .foregroundStyle(.tertiary)
                    Text(history.entries.isEmpty
                         ? "Nothing here yet, notifications are archived as they arrive."
                         : "No matches.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(visibleHistory) { entry in
                    HStack(alignment: .top, spacing: 10) {
                        SourceIcon(source: entry.sourceValue, kind: entry.kindValue,
                                   theme: themes.theme, side: 22)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.title).font(.system(size: 12, weight: .medium))
                            if !entry.body.isEmpty {
                                Text(entry.body)
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer(minLength: 8)
                        Text(entry.date, format: .dateTime.month().day().hour().minute())
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                            .monospacedDigit()
                    }
                    .padding(.vertical, 3)
                }
                .listStyle(.inset)
            }

            Divider()
            HStack {
                Toggle("Keep a history", isOn: $prefs.d.keepHistory)
                Spacer()
                Text("\(history.entries.count) of \(HistoryStore.limit) kept")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(12)
        }
    }

    private var visibleHistory: [HistoryEntry] {
        history.filtered(search: nav.historySearch, source: nav.historySource)
    }

    private var integrations: some View {
        Form {
            Section("GitHub") {
                Toggle("Quick actions row in the panel", isOn: $prefs.d.showQuickBar)
                Toggle("GitHub row in the panel", isOn: $prefs.d.showGitHub)
                Toggle("Alert when a workflow fails", isOn: $prefs.d.alertWorkflowFailure)

                if github.snapshot.connected {
                    LabeledContent("Signed in as", value: github.snapshot.login)
                    Text(github.snapshot.summary)
                        .font(.caption).foregroundStyle(.secondary)
                    HStack {
                        Button("Refresh now") { Task { await github.refresh() } }
                            .controlSize(.small)
                        Button("Disconnect") { github.disconnect() }
                            .controlSize(.small)
                    }
                } else {
                    if github.canSignIn {
                        if github.userCode.isEmpty {
                            Button(github.signingIn ? "Starting" : "Sign in with GitHub") {
                                Task { await github.signIn() }
                            }
                            .disabled(github.signingIn)
                        } else {
                            LabeledContent("Enter this code") {
                                Text(github.userCode)
                                    .font(.system(.title3, design: .monospaced).bold())
                                    .textSelection(.enabled)
                            }
                            Text("Copied to the clipboard. The page is open in your "
                                 + "browser and this window is waiting for it.")
                                .font(.caption).foregroundStyle(.secondary)
                            Button("Cancel") { github.cancelSignIn() }
                                .controlSize(.small)
                        }
                    }

                    DisclosureGroup("Token, or one click sign in setup") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Paste a fine grained token with read only access to "
                                 + "Metadata, Actions, Contents and Pull requests. "
                                 + "Select every repository you want workflow alerts "
                                 + "for.")
                                .font(.caption).foregroundStyle(.secondary)
                            HStack {
                                SecureField("Personal access token",
                                            text: $nav.githubToken)
                                    .textFieldStyle(.roundedBorder)
                                Button("Connect") {
                                    github.connect(token: nav.githubToken)
                                    nav.githubToken = ""
                                }
                                .controlSize(.small)
                            }
                            Button("Create a token") {
                                if let url = URL(string:
                                    "https://github.com/settings/personal-access-tokens/new") {
                                    NSWorkspace.shared.open(url)
                                }
                            }
                            .controlSize(.small)
                            Divider()
                            Text("For one click sign in, register an OAuth app on "
                                 + "GitHub with device flow enabled and paste its "
                                 + "client id here. It is a public identifier, not a "
                                 + "secret, and no client secret is needed.")
                                .font(.caption).foregroundStyle(.secondary)
                            HStack {
                                TextField("Client id", text: $prefs.d.githubClientId)
                                    .textFieldStyle(.roundedBorder)
                                Button("Register an app") {
                                    if let url = URL(string:
                                        "https://github.com/settings/applications/new") {
                                        NSWorkspace.shared.open(url)
                                    }
                                }
                                .controlSize(.small)
                            }
                        }
                        .padding(.top, 4)
                    }
                }
                if !github.lastError.isEmpty {
                    Text(github.lastError).font(.caption).foregroundStyle(.red)
                }
            }
            Section("Mail") {
                Toggle("Mail tab in the panel", isOn: $prefs.d.showMail)
                Toggle("Notify when new mail arrives", isOn: $prefs.d.notifyOnMail)
                    .disabled(!prefs.d.showMail)
                Toggle("Summarise each message", isOn: $prefs.d.mailSummaries)
                    .disabled(!prefs.d.showMail)
                Stepper("Show at most \(prefs.d.mailLimit)",
                        value: $prefs.d.mailLimit, in: 3...30)
                    .disabled(!prefs.d.showMail)
                Toggle("Sort by what needs you first", isOn: $prefs.d.mailSortByImportance)
                    .disabled(!prefs.d.showMail)
                Text("Each message is sorted into needs you now, wants a reply, for "
                     + "information, or marketing, by the same on device model. The "
                     + "count in the tab header filters to the ones waiting on you.")
                    .font(.caption).foregroundStyle(.secondary)
                Text(Summarizer.onDeviceAvailable
                     ? "Summaries are written by the model built into macOS. Nothing "
                       + "leaves the machine and no account or key is needed."
                     : "Apple Intelligence is not available here, so summaries fall "
                       + "back to the opening lines of the message.")
                    .font(.caption).foregroundStyle(.secondary)
                Text("Mail is read through Mail itself, so it needs your account added "
                     + "in Internet Accounts and Mail running. MacInotch never sees a "
                     + "password and holds no mail credentials of its own.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Meetings") {
                Toggle("Reminders in the panel", isOn: $prefs.d.showReminders)
                Toggle("Offer meeting mode when a call starts",
                       isOn: $prefs.d.suggestMeetingMode)
                Toggle("Meeting mode mutes audio", isOn: $prefs.d.meetingMutesAudio)
                    .disabled(!prefs.d.suggestMeetingMode)
                Toggle("Meeting mode holds notifications",
                       isOn: $prefs.d.meetingSilencesNotch)
                    .disabled(!prefs.d.suggestMeetingMode)
                HStack {
                    Button(calendar.authorized ? "Refresh calendars"
                           : calendar.denied ? "Open Privacy Settings"
                           : "Connect calendar and reminders") {
                        calendar.authorized ? calendar.refreshSources()
                                            : calendar.requestAccess()
                    }
                    .controlSize(.small)
                    Text(calendar.authorized ? "Connected"
                         : calendar.denied ? "Access was declined" : "Not connected")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Add a Google account") {
                        if let url = URL(string:
                            "x-apple.systempreferences:com.apple.Internet-Accounts-Settings"
                            + ".extension") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .controlSize(.small)
                }

                if calendar.denied {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("macOS asks only once, so declining is final and the "
                             + "button above can no longer produce a prompt. Turn "
                             + "MacInotch on under Privacy and Security, Calendars.")
                            .font(.caption).foregroundStyle(.secondary)
                        Text("To be asked again instead, run this in Terminal and "
                             + "reopen MacInotch:")
                            .font(.caption).foregroundStyle(.secondary)
                        HStack {
                            Text("tccutil reset Calendar io.macinotch.app")
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                            Button("Copy") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(
                                    "tccutil reset Calendar io.macinotch.app",
                                    forType: .string)
                            }
                            .controlSize(.small)
                        }
                    }
                }

                if calendar.authorized && !calendar.sources.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Which calendars to read")
                            .font(.caption).foregroundStyle(.secondary)
                        ForEach(calendar.sources) { choice in
                            Toggle(isOn: Binding(
                                get: { calendar.isEnabled(choice.id) },
                                set: { calendar.setEnabled(choice.id, $0) })) {
                                HStack(spacing: 6) {
                                    Circle()
                                        .fill(Color(choice.color ?? .systemGray))
                                        .frame(width: 8, height: 8)
                                    Text(choice.title)
                                    if !choice.account.isEmpty {
                                        Text(choice.account)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }

                    Button("Sign out of calendars") {
                        calendar.signOut()
                        if let url = URL(string:
                            "x-apple.systempreferences:com.apple.preference.security"
                            + "?Privacy_Calendars") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .controlSize(.small)
                    Text("Turns every calendar off here and opens the privacy pane, "
                         + "where access itself can be revoked. macOS does not let an "
                         + "application withdraw its own permission.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Text("Meeting mode is offered when an event with a join link starts. "
                     + "It mutes system audio and holds notifications until the event "
                     + "ends, then puts both back the way it found them.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Accounts") {
                Toggle("Accounts tab in the panel", isOn: $prefs.d.showAccounts)
                accountList
            }
            Section("Meeting notes") {
                Toggle("Start recording when a call begins",
                       isOn: $prefs.d.meetingAutoRecord)
                Toggle("Capture the other side as well",
                       isOn: $prefs.d.meetingCapturesSystemAudio)
                Picker("Spoken language", selection: $prefs.d.meetingLocale) {
                    Text("English").tag("en-US")
                    Text("British English").tag("en-GB")
                    Text("Persian").tag("fa-IR")
                    Text("German").tag("de-DE")
                    Text("French").tag("fr-FR")
                    Text("Spanish").tag("es-ES")
                    Text("Arabic").tag("ar-SA")
                }
                Text(MeetingRecorder.available
                     ? "Recording is transcribed by the speech model built into macOS "
                       + "and written up by the on device language model, then saved "
                       + "with your notes. Nothing is uploaded and no account is used."
                     : "This needs macOS 26 or later.")
                    .font(.caption).foregroundStyle(.secondary)
                Text("Your microphone is always captured. Capturing the other side "
                     + "records the audio your Mac is playing, which needs Screen "
                     + "Recording permission. Recording a call may need everyone's "
                     + "agreement where you are.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Dictation") {
                Toggle("Hold a key to dictate a note", isOn: $prefs.d.dictationEnabled)
                Picker("Hold", selection: $prefs.d.dictationHotKey) {
                    ForEach(HotKey.choices) { choice in
                        Text(choice.label).tag(choice.label)
                    }
                }
                .disabled(!prefs.d.dictationEnabled)
                Picker("Spoken language", selection: $prefs.d.dictationLocale) {
                    Text("English").tag("en-US")
                    Text("British English").tag("en-GB")
                    Text("Persian").tag("fa-IR")
                    Text("German").tag("de-DE")
                    Text("French").tag("fr-FR")
                    Text("Arabic").tag("ar-SA")
                }
                .disabled(!prefs.d.dictationEnabled)
                HStack {
                    Button("Apply hotkey") { Dictation.shared.installHotKey() }
                        .controlSize(.small)
                    Button(Dictation.shared.listening ? "Stop and save" : "Try it now") {
                        Dictation.shared.toggle()
                    }
                    .controlSize(.small)
                    if Dictation.shared.listening {
                        Text("Listening, speak now")
                            .font(.caption).foregroundStyle(.red)
                    }
                }
                Text("Hold the key, speak, let go. There is also a microphone button "
                     + "in the panel's quick actions row, which starts and stops on a "
                     + "click if you would rather not hold anything. The notch draws "
                     + "what it hears, and the note lands in your notes folder, "
                     + "transcribed on this Mac.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Mirror Notification Center") {
                Toggle("Mirror macOS notifications into the notch",
                       isOn: $prefs.d.bridgeEnabled)
                    .onChange(of: prefs.d.bridgeEnabled) { _, _ in
                        AppServices.bridge?.restart()
                    }
                Toggle("Claude & ChatGPT only", isOn: $prefs.d.bridgeAIOnly)
                    .disabled(!prefs.d.bridgeEnabled)
                LabeledContent("Also mirror") {
                    TextField("bundle ids, comma separated",
                              text: $prefs.d.bridgeCustomBundles)
                        .frame(width: 200)
                }
                .disabled(!prefs.d.bridgeEnabled)
                HStack {
                    Label(bridgeStatusText, systemImage: bridgeStatusIcon)
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Open Privacy settings") {
                        NSWorkspace.shared.open(URL(string:
                            "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!)
                    }
                    .font(.caption)
                }
                Text("Reading Notification Center needs Full Disk Access for MacInotch.app.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Config file") {
                HStack {
                    Text("~/.config/macinotch/config.json")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Export") { prefs.writeConfigFile() }
                    Button("Reload") { _ = prefs.loadConfigFile() }
                }
                Text("Read at launch and merged over your saved settings, so a dotfile "
                     + "can pin whichever keys it names and leave the rest alone.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Local endpoint") {
                Toggle("Listen on 127.0.0.1:\(NotchServer.port)", isOn: $prefs.d.serverEnabled)
                Text("Restart MacInotch after changing this.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Send notifications") {
                snippet("""
                notchctl "Build finished" "42 tests passed" -s claude -k success
                """)
                snippet("""
                curl -s localhost:\(NotchServer.port)/notify \\
                  -d '{"source":"chatgpt","title":"Reply ready","kind":"info"}'
                """)
                snippet("""
                notchctl --key deploy --progress 0.4 --title "Deploying"
                notchctl --key deploy --kind attention --title "Approve release?"
                notchctl --dismiss deploy
                """)
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private func stripPicker(isLeft: Bool) -> some View {
        ForEach(PrefsData.StripItem.allCases) { item in
            Toggle(item.label, isOn: Binding(
                get: {
                    (isLeft ? prefs.d.idleLeft : prefs.d.idleRight).contains(item.rawValue)
                },
                set: { on in
                    var list = isLeft ? prefs.d.idleLeft : prefs.d.idleRight
                    if on {
                        if !list.contains(item.rawValue) { list.append(item.rawValue) }
                    } else {
                        list.removeAll { $0 == item.rawValue }
                    }
                    if isLeft { prefs.d.idleLeft = list } else { prefs.d.idleRight = list }
                }))
        }
        .disabled(!prefs.d.liveStripEnabled)
    }

    private var ruleSources: [NotchSource] { [.claude, .chatgpt, .spotify, .system, .custom] }

    private func soundBinding(_ src: NotchSource) -> Binding<String> {
        Binding(
            get: { prefs.d.soundPerSource[src.rawValue] ?? "default" },
            set: { prefs.d.soundPerSource[src.rawValue] = $0 }
        )
    }

    private func ruleBinding(_ src: NotchSource) -> Binding<PrefsData.SourceRule> {
        Binding(
            get: { prefs.d.sourceRules[src.rawValue] ?? .normal },
            set: { prefs.d.sourceRules[src.rawValue] = $0 }
        )
    }

    private var bridgeStatusText: String {
        switch AppServices.bridge?.status ?? .off {
        case .off:                 return "Mirror off"
        case .running:             return "Mirror running"
        case .needsFullDiskAccess: return "Waiting on Full Disk Access"
        case .unavailable(let m):  return m
        }
    }

    private var bridgeStatusIcon: String {
        switch AppServices.bridge?.status ?? .off {
        case .running:             return "checkmark.circle.fill"
        case .needsFullDiskAccess: return "lock.fill"
        default:                   return "circle.dashed"
        }
    }

    private func snippet(_ text: String) -> some View {
        HStack(alignment: .top) {
            Text(text)
                .font(.system(size: 10.5, design: .monospaced))
                .textSelection(.enabled)
                .foregroundStyle(.secondary)
            Spacer()
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
            } label: { Image(systemName: "doc.on.doc") }
                .buttonStyle(.borderless)
        }
    }

    private func ambientColor(_ key: WritableKeyPath<PrefsData, String>,
                              _ fallback: String) -> Binding<Color> {
        Binding(
            get: { Color(hex: prefs.d[keyPath: key]) ?? Color(hex: fallback)! },
            set: { prefs.d[keyPath: key] = $0.hexString })
    }

    private var ambientControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Style", selection: $prefs.d.ambientStyle) {
                Text("Soft glow").tag("glow")
                Text("Hairline").tag("hairline")
                Text("Sweep").tag("sweep")
            }

            LabeledContent("Thickness") {
                Slider(value: $prefs.d.ambientWidth, in: 0.8...3.5).frame(width: 150)
            }
            LabeledContent("Brightness") {
                Slider(value: $prefs.d.ambientIntensity, in: 0.2...1).frame(width: 150)
            }
            LabeledContent("Pulse speed") {
                Slider(value: $prefs.d.ambientSpeed, in: 0.3...2.5).frame(width: 150)
            }
            LabeledContent("Fade after") {
                HStack {
                    Slider(value: $prefs.d.ambientTimeout, in: 0...300, step: 15)
                        .frame(width: 110)
                    Text(prefs.d.ambientTimeout == 0 ? "never"
                         : "\(Int(prefs.d.ambientTimeout))s")
                        .font(.caption).monospacedDigit()
                        .frame(width: 44, alignment: .trailing)
                }
            }

            Divider()

            Text("What it reacts to")
                .font(.caption).foregroundStyle(.secondary)

            HStack {
                Toggle("A workflow failed", isOn: $prefs.d.ambientOnFailure)
                Spacer()
                ColorPicker("", selection: ambientColor(\.ambientColorFailure, "#FF453A"))
                    .labelsHidden()
            }
            HStack {
                Toggle("A usage limit is close", isOn: $prefs.d.ambientOnLimit)
                Spacer()
                ColorPicker("", selection: ambientColor(\.ambientColorLimit, "#FF9F0A"))
                    .labelsHidden()
            }
            HStack {
                Toggle("Something is waiting on you", isOn: $prefs.d.ambientOnWaiting)
                Spacer()
                ColorPicker("", selection: ambientColor(\.ambientColorWaiting, "#0A84FF"))
                    .labelsHidden()
            }
            HStack {
                Toggle("Recording a meeting", isOn: $prefs.d.ambientOnRecord)
                Spacer()
                ColorPicker("", selection: ambientColor(\.ambientColorRecord, "#FF375F"))
                    .labelsHidden()
            }

            Text("Only one shows at a time, in the order listed. Off by default, "
                 + "because a permanent outline is a change to a machine you look at "
                 + "all day.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(.leading, 6)
    }

    private func cueBinding(_ cue: SoundCue) -> Binding<String> {
        switch cue {
        case .mail: return $prefs.d.cueMail
        case .buildFailure: return $prefs.d.cueBuildFailure
        case .limitWarning: return $prefs.d.cueLimitWarning
        case .availableAgain: return $prefs.d.cueAvailableAgain
        case .attention: return $prefs.d.cueAttention
        case .systemAlert: return $prefs.d.cueSystemAlert
        case .dictation: return $prefs.d.cueDictation
        }
    }

    private var accountList: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(AccountProvider.allCases) { provider in
                providerSection(provider)
            }
            if switcher.pendingSwitch != nil {
                HStack(spacing: 8) {
                    Text("The tool is open and would write its old session back. "
                         + "Close it for the switch to hold.")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("Quit and switch") { switcher.confirmPending() }
                        .controlSize(.small)
                    Button("Cancel") { switcher.cancelPending() }
                        .controlSize(.small)
                }
            }
            if switcher.orphanCount > 0 {
                HStack {
                    Text("\(switcher.orphanCount) saved sign in(s) in the keychain "
                         + "are not listed above.")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("Recover") { switcher.recoverFromKeychain() }
                        .controlSize(.small)
                }
            }
            if !switcher.lastError.isEmpty {
                Text(switcher.lastError).font(.caption).foregroundStyle(.red)
            }
            Text("Saved sessions are held in your login keychain, marked for this "
                 + "device only, so they are never synced and never written to disk "
                 + "in the clear. MacInotch never sees your password and never exposes "
                 + "accounts over its local endpoint.")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    private func providerSection(_ provider: AccountProvider) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(provider.title).font(.system(size: 12, weight: .semibold))

            ForEach(switcher.accounts(for: provider)) { account in
                accountRow(account, provider: provider)
            }

            if switcher.hasSession(provider) {
                saveRow(provider)
            } else {
                Text("No session file yet. Sign in with \(provider.loginHint) first.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Text(provider.restartHint).font(.caption2).foregroundStyle(.secondary)
        }
    }

    private func accountRow(_ account: SavedAccount,
                            provider: AccountProvider) -> some View {
        let active = switcher.activeId[provider] == account.id
        return HStack(spacing: 9) {
            Image(systemName: active ? "checkmark.circle.fill" : "person.crop.circle")
                .foregroundStyle(active ? Color.green : Color.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(account.label).font(.system(size: 12, weight: .medium))
                Text(account.subtitle(showEmail: account.label != account.email))
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            if active {
                Text("in use").font(.caption2).foregroundStyle(.secondary)
            } else {
                Button(switcher.busy ? "Working" : "Use") { switcher.requestActivate(account.id) }
                    .buttonStyle(.bordered).controlSize(.small)
            }
            Button { switcher.forget(account.id) } label: { Image(systemName: "trash") }
                .buttonStyle(.borderless)
                .disabled(active)
        }
    }

    private func saveRow(_ provider: AccountProvider) -> some View {
        let signedIn = switcher.currentEmail[provider] ?? ""
        let unsaved = switcher.activeId[provider] == nil
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                TextField("Name for the current session", text: $nav.newAccountLabel)
                    .textFieldStyle(.roundedBorder)
                Button("Save current") {
                    act { try switcher.capture(provider, label: nav.newAccountLabel) }
                    nav.newAccountLabel = ""
                }
            }
            if !signedIn.isEmpty && unsaved {
                Text("Signed in as \(signedIn), not saved yet.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func act(_ body: () throws -> Void) {
        do {
            try body()
            switcher.lastError = ""
        } catch {
            switcher.lastError = error.localizedDescription
        }
    }
}

extension Color {
    var hexString: String {
        let ns = NSColor(self).usingColorSpace(.sRGB) ?? .white
        return String(format: "#%02X%02X%02X",
                      Int(round(ns.redComponent * 255)),
                      Int(round(ns.greenComponent * 255)),
                      Int(round(ns.blueComponent * 255)))
    }
}

@MainActor
final class SettingsWindow: NSObject, NSWindowDelegate {
    static let shared = SettingsWindow()
    private var window: NSWindow?

    func show() {
        let w = window ?? make()
        window = w
        applyAppearance(to: w)

        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
        w.orderFrontRegardless()
    }

    func applyAppearance(to w: NSWindow? = nil) {
        guard let w = w ?? window else { return }
        switch Prefs.shared.d.appearance {
        case .system: w.appearance = nil
        case .light:  w.appearance = NSAppearance(named: .aqua)
        case .dark:   w.appearance = NSAppearance(named: .darkAqua)
        }
    }

    private func make() -> NSWindow {
        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 620),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered, defer: false
        )
        w.title = "MacInotch Settings"
        w.isReleasedWhenClosed = false
        w.delegate = self
        w.center()
        w.contentView = NSHostingView(rootView: SettingsView())
        return w
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}

enum SettingsIndex {
    struct Entry: Identifiable {
        var id: String { title }
        var title: String
        var tab: SettingsView.Tab
        var keywords: [String]
    }

    static let entries: [Entry] = [
        Entry(title: "Theme, light and dark", tab: .general,
              keywords: ["appearance", "dark", "light", "colour", "color", "glass"]),
        Entry(title: "Opening animation", tab: .general,
              keywords: ["animation", "spring", "motion", "open"]),
        Entry(title: "Hotkey", tab: .general, keywords: ["hotkey", "shortcut", "key"]),
        Entry(title: "Start at login", tab: .general,
              keywords: ["login", "startup", "launch"]),
        Entry(title: "Dictation", tab: .integrations,
              keywords: ["dictate", "dictation", "voice", "speak", "microphone",
                         "note", "transcribe", "hold"]),
        Entry(title: "Sound cues", tab: .general,
              keywords: ["sound", "cue", "audio", "chime", "tone", "silent",
                         "mail sound", "alert sound"]),
        Entry(title: "Meeting notes", tab: .integrations,
              keywords: ["meeting", "record", "transcript", "summary", "captions"]),
        Entry(title: "Notch as a control", tab: .notch,
              keywords: ["drag", "volume", "brightness", "scrub", "strip", "control"]),
        Entry(title: "Status outline", tab: .notch,
              keywords: ["glow", "outline", "ambient", "ring", "colour", "border"]),
        Entry(title: "Collapsed readout", tab: .widgets,
              keywords: ["collapsed", "idle", "left", "right", "readout", "slot"]),
        Entry(title: "System vitals", tab: .widgets,
              keywords: ["cpu", "memory", "ram", "temperature", "disk", "battery"]),
        Entry(title: "AI usage and limits", tab: .widgets,
              keywords: ["usage", "limit", "token", "codex", "claude", "quota",
                         "window", "reset"]),
        Entry(title: "Sessions", tab: .widgets,
              keywords: ["session", "project", "live", "active", "transcript"]),
        Entry(title: "Accounts", tab: .integrations,
              keywords: ["account", "switch", "sign in", "keychain", "codex",
                         "claude", "login"]),
        Entry(title: "GitHub", tab: .integrations,
              keywords: ["github", "token", "workflow", "pull request", "ci",
                         "contributions", "push"]),
        Entry(title: "Mail", tab: .integrations,
              keywords: ["mail", "email", "inbox", "unread", "reply", "triage",
                         "summary"]),
        Entry(title: "Meetings and reminders", tab: .integrations,
              keywords: ["calendar", "meeting", "reminder", "event", "join",
                         "google", "mute"]),
        Entry(title: "Keep awake", tab: .widgets,
              keywords: ["awake", "sleep", "caffeine", "coffee", "display"]),
        Entry(title: "Panel rows and scrolling", tab: .widgets,
              keywords: ["scroll", "rows", "panel", "height"]),
        Entry(title: "Alerts and warnings", tab: .alerts,
              keywords: ["alert", "disk", "thermal", "runaway", "network", "vpn",
                         "battery", "warning"]),
        Entry(title: "Fans", tab: .fans,
              keywords: ["fan", "rpm", "boost", "cooling", "blast", "speed"]),
        Entry(title: "Notification history", tab: .history,
              keywords: ["history", "notification", "search", "past"]),
        Entry(title: "Connect and permissions", tab: .integrations,
              keywords: ["permission", "connect", "full disk", "calendar access",
                         "hooks", "config", "mirror"]),
        Entry(title: "Menu bar hiding", tab: .notch,
              keywords: ["menu bar", "hide", "icons"]),
        Entry(title: "Notes folder", tab: .widgets,
              keywords: ["notes", "markdown", "folder", "sticky"]),
        Entry(title: "Timers and pomodoro", tab: .widgets,
              keywords: ["timer", "pomodoro", "ring", "countdown"]),
        Entry(title: "Weather", tab: .widgets,
              keywords: ["weather", "temperature", "location", "forecast"]),
    ]
}
