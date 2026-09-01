import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let state = NotchState.shared
    private var windowController: NotchWindowController!
    private var server: NotchServer?
    private var music: MusicService!
    private var battery: BatteryService!
    private var stats: SystemStatsService!
    private var bridge: NotificationBridge!
    private var presence: PresenceService!
    private var thermal: ThermalService!
    private var fans: FanService!
    private var usage: UsageService!
    private var processes: ProcessService!
    private var repo: RepoService!
    private var screenshots: ScreenshotWatcher!
    private var sessionService: SessionService!
    private let sessionGate = Flag(true)
    private let sessionClaudeGate = Flag(true)
    private let sessionCodexGate = Flag(true)
    private let sessionActiveGate = Flag(false)
    private let screenshotGate = Flag(true)
    private let repoPath = PathBox()

    private let sampleGate = Flag(false)
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ note: Notification) {
        NSApp.setActivationPolicy(.accessory)
        ThemeManager.shared.refresh()
        Prefs.shared.publish()

        windowController = NotchWindowController(state: state)
        windowController.install()

        music = MusicService(state: state)
        state.musicControl = music
        music.start()

        battery = BatteryService(state: state)
        battery.start()

        stats = SystemStatsService(state: state)
        stats.start(interval: Prefs.shared.d.pollSeconds)

        if Prefs.shared.d.serverEnabled {
            let s = NotchServer(
                onPayload: { payload in
                    Task { @MainActor in NotchState.shared.handle(payload) }
                },
                stateJSON: { SnapshotStore.shared.get() },
                onPrefsPatch: { patch in
                    Task { @MainActor in
                        Prefs.shared.apply(patch: patch)
                        AppServices.bridge?.restart()
                    }
                },
                onFanCommand: { command in
                    Task { @MainActor in
                        let client = FanControlClient.shared
                        if command["auto"] != nil {
                            client.autoAll()
                        } else if let percent = command["percent"] as? Double {
                            client.setAll(percent: percent,
                                          minutes: command["minutes"] as? Double ?? 5)
                        }
                    }
                    return SnapshotStore.shared.getFans()
                }
            )
            s.start()
            server = s
        }

        presence = PresenceService(state: state)
        presence.start()

        thermal = ThermalService { temps in
            Task { @MainActor in
                if temps != NotchState.shared.temps { NotchState.shared.temps = temps }
            }
        }
        thermal.start()

        fans = FanService { snap in
            Task { @MainActor in
                if snap != NotchState.shared.fans { NotchState.shared.fans = snap }
            }
        }
        fans.start()

        usage = UsageService(
            windowHours: Prefs.shared.d.usageWindowHours,
            onUpdate: { snap in
                Task { @MainActor in
                    if snap != NotchState.shared.usage { NotchState.shared.usage = snap }
                    if let limits = snap.codexLimits {
                        AccountService.shared.recordUsage(
                            .codex,
                            percent: limits.primary.usedPercent,
                            resetsAt: limits.primary.resetsAt)
                    }
                }
            },
            onReset: { provider, window in
                Task { @MainActor in Self.announceUsageReset(provider, window) }
            },
            onThreshold: { window, mark, projection in
                Task { @MainActor in Self.announceThreshold(window, mark, projection) }
            })
        usage.start()

        processes = ProcessService(

            shouldSample: { [gate = sampleGate] in gate.get() },
            onUpdate: { cpu, memory in
                Task { @MainActor in
                    NotchState.shared.topCPU = cpu
                    NotchState.shared.topMemory = memory
                }
            })
        processes.start()

        repo = RepoService(path: { [box = repoPath] in box.get() },
                           onUpdate: { status in
            Task { @MainActor in
                if status != NotchState.shared.repo { NotchState.shared.repo = status }
            }
        })
        repo.start()

        screenshots = ScreenshotWatcher(
            enabled: { [gate = screenshotGate] in gate.get() },
            onCatch: { path in
                Task { @MainActor in
                    ShelfStore.shared.add(paths: [path])
                    var payload = NotchPayload()
                    payload.source = "system"
                    payload.kind = "success"
                    payload.title = "Screenshot caught"
                    payload.body = (path as NSString).lastPathComponent
                    payload.timeout = 4
                    payload.sound = false
                    NotchState.shared.handle(payload)
                }
            })
        screenshots.start()

        sessionService = SessionService(
            sources: { [gate = sessionGate, claude = sessionClaudeGate,
                        codex = sessionCodexGate, active = sessionActiveGate] in
                (gate.get(), claude.get(), codex.get(), active.get())
            },
            onUpdate: { list in
                Task { @MainActor in
                    if list != NotchState.shared.sessions {
                        NotchState.shared.sessions = list
                    }
                }
            })
        sessionService.start()
        AccountService.shared.start()
        NetworkService.shared.start()
        AlertService.shared.start()
        MeetingMode.shared.start()

        let gateTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) {
            [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.sampleGate.set(Prefs.shared.d.showTopProcess
                    && (self.state.mode == .expanded || self.state.pinned))
                self.repoPath.set(Prefs.shared.d.showRepo ? Prefs.shared.d.repoPath : "")
                self.sessionGate.set(Prefs.shared.d.showSessions)
                self.sessionClaudeGate.set(Prefs.shared.d.sessionsShowClaude)
                self.sessionCodexGate.set(Prefs.shared.d.sessionsShowCodex)
                self.sessionActiveGate.set(Prefs.shared.d.sessionsActiveOnly)
                self.usage?.update(windowHours: Prefs.shared.d.usageWindowHours)
                self.screenshotGate.set(Prefs.shared.d.screenshotCatch
                                        && Prefs.shared.d.shelfEnabled)
            }
        }
        RunLoop.main.add(gateTimer, forMode: .common)

        bridge = NotificationBridge(state: state)
        AppServices.bridge = bridge
        bridge.start()
        reportBridgeStatus()

        NSAppleEventManager.shared().setEventHandler(
            self, andSelector: #selector(handleURL(_:reply:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL))

        FocusWatcher.shared.start()
        CalendarService.shared.start()
        ClipboardService.shared.start()
        WeatherService.shared.start()
        BluetoothBatteryService.shared.start()
        AudioService.shared.start()
        FrontmostAppWatcher.shared.start()
        applyHotKey()
        if Prefs.shared.d.menuBarHiding {
            MenuBarHider.shared.install()
            MenuBarHider.shared.setHidden(Prefs.shared.d.menuBarHidden)
        }
        installStatusItem()
        greet()

        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.2))
            OnboardingWindow.shared.showIfNeeded()
        }
    }

    func applicationWillTerminate(_ note: Notification) {
        bridge?.stop()
        presence?.stop()
        thermal?.stop()
        fans?.stop()
        usage?.stop()
        processes?.stop()
        repo?.stop()
        screenshots?.stop()
        sessionService?.stop()
        server?.stop()
        music?.stop()
        battery?.stop()
        stats?.stop()
    }

    private func reportBridgeStatus() {
        guard case .needsFullDiskAccess = bridge.status else { return }
        var p = NotchPayload()
        p.source = "system"
        p.kind = "warning"
        p.key = "bridge-fda"
        p.title = "Full Disk Access needed"
        p.body = "To mirror Notification Center, allow MacInotch in Privacy settings"
        p.timeout = 10
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            state.handle(p)
        }
    }

    static func fansJSON() -> String {
        let client = FanControlClient.shared
        let obj: [String: Any] = [
            "ok": true,
            "helper": client.reachable ? "running" : (client.installed ? "installed" : "absent"),
            "fans": NotchState.shared.fans.fans.map {
                ["index": $0.index, "rpm": Int($0.rpm),
                 "min": Int($0.minRPM), "max": Int($0.maxRPM),
                 "holdsFor": client.holds[$0.index] ?? 0]
            },
            "watts": (NotchState.shared.fans.systemWatts * 10).rounded() / 10,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys])
        else { return #"{"ok":true}"# }
        return String(decoding: data, as: UTF8.self)
    }

    static func snapshotJSON() -> String {
        let s = NotchState.shared
        let t = ThemeManager.shared.theme
        var obj: [String: Any] = [
            "mode": String(describing: s.mode),
            "theme": t.isDark ? "dark" : "light",
            "cpu": (s.stats.cpuTotal * 100).rounded() / 100,
            "cpuPercent": Int((s.stats.cpuTotal * 100).rounded()),
            "cores": s.stats.coreCount,
            "ramUsedGB": (s.stats.memUsedGB * 10).rounded() / 10,
            "ramTotalGB": s.stats.memTotalGB.rounded(),
            "ramPercent": Int((s.stats.memPressure * 100).rounded()),
            "swapGB": (s.stats.swapUsedGB * 100).rounded() / 100,
            "diskFreeGB": s.stats.diskFreeGB.rounded(),
            "netDown": Int(s.stats.netDown),
            "netUp": Int(s.stats.netUp),
            "fans": s.fans.fans.map { ["index": $0.index, "rpm": Int($0.rpm),
                                       "min": Int($0.minRPM), "max": Int($0.maxRPM),
                                       "target": Int($0.targetRPM), "forced": $0.forced] },
            "fansControllable": s.fans.controllable,
            "systemWatts": (s.fans.systemWatts * 10).rounded() / 10,
            "repo": ["branch": s.repo.branch, "summary": s.repo.summary,
                     "available": s.repo.available],
            "usage": [
                "claude": s.usage.claude.map { ["tokens": $0.tokens, "messages": $0.messages,
                                                "since": $0.sinceText,
                                                "source": "local tally"] } as Any,
                "codex": s.usage.codexTally.map { ["tokens": $0.tokens, "messages": $0.messages,
                                                   "since": $0.sinceText,
                                                   "source": "local tally"] } as Any,
                "codexLimits": s.usage.codexLimits.map {
                    ["plan": $0.plan,
                     "usedPercent": $0.primary.usedPercent,
                     "windowMinutes": $0.primary.windowMinutes,
                     "resetsIn": $0.primary.remainingText,
                     "weeklyPercent": $0.secondary?.usedPercent as Any,
                     "weeklyResetsIn": $0.secondary?.remainingText as Any,
                     "burnPercentPerHour": $0.projection.map {
                         ($0.percentPerHour * 10).rounded() / 10 } as Any,
                     "projection": $0.projection?.text as Any,
                     "source": "reported by codex"] } as Any,
            ],
            "sessions": s.sessions.map {
                ["provider": $0.provider.rawValue, "name": $0.displayName,
                 "project": $0.project, "live": $0.isLive,
                 "messages": $0.messages, "tokens": $0.tokens,
                 "model": $0.model, "ago": $0.ago]
            },
            "network": {
                let n = NetworkService.shared.snapshot
                return ["label": n.label, "ssid": n.ssid, "interface": n.interface,
                        "connected": n.connected, "expensive": n.expensive,
                        "constrained": n.constrained, "vpn": n.vpnName]
            }(),
            "tempSoC": (s.temps.soc * 10).rounded() / 10,
            "tempSoCMax": (s.temps.socMax * 10).rounded() / 10,
            "tempBattery": (s.temps.battery * 10).rounded() / 10,
            "tempSSD": (s.temps.ssd * 10).rounded() / 10,
            "battery": s.battery.percent,
            "batteryHealth": s.battery.healthPercent,
            "batteryCycles": s.battery.cycleCount,
            "thermalPressure": s.stats.thermalLabel,
            "pinned": s.pinned,
            "hotKey": HotKey.shared.descriptor,
            "historyCount": HistoryStore.shared.entries.count,
            "shelfCount": ShelfStore.shared.items.count,
            "clipCount": ClipboardService.shared.entries.count,
            "menuBar": ["installed": MenuBarHider.shared.installed,
                        "hidden": MenuBarHider.shared.hidden,
                        "diag": MenuBarHider.shared.diagnostics],
            "weather": ["available": WeatherService.shared.snapshot.available,
                        "status": WeatherService.shared.status,
                        "temp": WeatherService.shared.snapshot.temperature,
                        "summary": WeatherService.shared.snapshot.summary,
                        "place": WeatherService.shared.snapshot.place],
            "timer": ["running": TimerService.shared.isRunning,
                      "phase": TimerService.shared.phase.rawValue,
                      "remaining": TimerService.shared.readout],
            "daysToNowruz": DateKit.daysUntilNowruz() ?? -1,
            "muted": s.isMuted,
            "focusAvailable": FocusWatcher.shared.available,
            "charging": s.battery.isCharging,
            "presence": [
                "claudeApp": s.presence.claudeApp,
                "claudeCode": s.presence.claudeCode,
                "chatgpt": s.presence.chatgpt,
                "spotify": s.presence.spotify,
            ],
            "items": s.items.map { ["key": $0.key, "kind": $0.kind.rawValue,
                                    "source": $0.source.rawValue, "title": $0.title] },
            "mirror": AppServices.bridgeStatusText,
            "panelHeight": Int(s.measuredExpandedHeight),
            "collapsedWidth": Int(s.collapsedSize.width),
            "liveSlotWidth": Int(s.liveSlotWidth),
            "notchWidth": Int(s.notchSize.width),
            "panelHeightUsed": Int(s.expandedSize.height),
            "gregorian": DateKit.gregLong.string(from: .now),
            "shamsi": DateKit.shamsiLong.string(from: .now),
            "shamsiLatin": DateKit.shamsiLatin(.now),
            "hijri": DateKit.hijriLong.string(from: .now),
        ]
        if s.music.isActive {
            obj["music"] = ["title": s.music.title, "artist": s.music.artist,
                            "playing": s.music.isPlaying, "app": s.music.app]
        }
        guard let data = try? JSONSerialization.data(withJSONObject: obj,
                                                     options: [.sortedKeys]) else {
            return "{}"
        }
        return String(decoding: data, as: UTF8.self)
    }

    static func announceUsageReset(_ provider: NotchSource, _ window: RateWindow) {
        guard Prefs.shared.d.notifyOnUsageReset else { return }
        var p = NotchPayload()
        p.source = provider.rawValue
        p.kind = "success"
        p.key = "usage-reset-\(provider.rawValue)"
        p.title = "Codex \(window.label) limit reset"
        p.body = "Back to \(Int(window.usedPercent))% used, next reset in \(window.remainingText)"
        p.timeout = 8
        p.sound = true
        NotchState.shared.handle(p)
    }

    static func announceThreshold(_ window: RateWindow, _ mark: Int,
                                  _ projection: RateProjection?) {
        guard Prefs.shared.d.notifyOnUsageThreshold else { return }

        var p = NotchPayload()
        p.source = NotchSource.chatgpt.rawValue
        p.kind = mark >= 95 ? "warning" : "info"
        p.key = "usage-threshold-codex"
        p.title = "Codex \(Int(window.usedPercent))% of the \(window.label) limit"

        var lines = ["resets in \(window.remainingText)"]
        if let text = projection?.text { lines.append(text) }
        p.body = lines.joined(separator: ", ")

        if let spare = AccountService.shared.alternative(to: .codex),
           let usage = spare.usageText {
            p.body = (p.body ?? "") + ". \(spare.label) is \(usage)"
            p.actions = [NotchAction(label: "Switch to \(spare.label)",
                                     url: "macinotch://switch?account=\(spare.id)")]
        }

        p.timeout = mark >= 95 ? 14 : 10
        p.sound = true
        NotchState.shared.handle(p)
    }

    static func applyHotKey() {
        let p = Prefs.shared.d
        guard p.hotKeyEnabled, let choice = HotKey.choice(named: p.hotKeyLabel) else {
            HotKey.shared.unregister()
            return
        }
        HotKey.shared.register(keyCode: choice.keyCode, modifiers: choice.modifiers) {
            NotchState.shared.togglePin()
        }
    }

    func applyHotKey() { Self.applyHotKey() }

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = MenuBarIcon.make()
        item.button?.toolTip = "MacInotch"
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item

    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let recent = HistoryStore.shared.entries.suffix(6).reversed()
        if recent.isEmpty {
            let empty = NSMenuItem(title: "No recent notifications", action: nil,
                                   keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        } else {
            let header = NSMenuItem(title: "Recent", action: nil, keyEquivalent: "")
            header.isEnabled = false
            menu.addItem(header)
            for entry in recent {
                let title = entry.body.isEmpty ? entry.title : "\(entry.title) · \(entry.body)"
                let row = NSMenuItem(title: String(title.prefix(60)), action: nil,
                                     keyEquivalent: "")
                row.image = AppIcons.icon(for: entry.sourceValue).map { icon in
                    let copy = icon.copy() as! NSImage
                    copy.size = NSSize(width: 14, height: 14)
                    return copy
                }
                row.isEnabled = false
                menu.addItem(row)
            }
        }
        menu.addItem(.separator())

        if let remaining = state.muteRemaining {
            menu.addItem(withTitle: "Muted for \(remaining), unmute",
                         action: #selector(unmute), keyEquivalent: "").target = self
        } else {
            let mute = NSMenu()
            for minutes in [15.0, 60.0, 240.0] {
                let label = minutes < 60 ? "\(Int(minutes)) minutes"
                                         : "\(Int(minutes / 60)) hour\(minutes > 60 ? "s" : "")"
                let entry = NSMenuItem(title: label, action: #selector(muteFor(_:)),
                                       keyEquivalent: "")
                entry.target = self
                entry.representedObject = minutes
                mute.addItem(entry)
            }
            let muteItem = NSMenuItem(title: "Mute notifications", action: nil,
                                      keyEquivalent: "")
            menu.addItem(muteItem)
            menu.setSubmenu(mute, for: muteItem)
        }

        menu.addItem(.separator())
        addFanMenu(to: menu)
        menu.addItem(.separator())

        menu.addItem(withTitle: state.pinned ? "Unpin panel" : "Pin panel open",
                     action: #selector(togglePin), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Send Test Notification",
                     action: #selector(sendTest), keyEquivalent: "t").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Settings…", action: #selector(openSettings),
                     keyEquivalent: ",").target = self
        menu.addItem(withTitle: "Setup Guide…", action: #selector(openOnboarding),
                     keyEquivalent: "").target = self
        menu.addItem(withTitle: "Quit MacInotch",
                     action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    }

    @objc private func handleURL(_ event: NSAppleEventDescriptor,
                                 reply: NSAppleEventDescriptor) {
        guard let raw = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
              let components = URLComponents(string: raw) else { return }

        switch components.host ?? components.path {
        case "notify":
            var payload = NotchPayload()
            for item in components.queryItems ?? [] {
                switch item.name {
                case "source":   payload.source = item.value
                case "title":    payload.title = item.value
                case "body":     payload.body = item.value
                case "kind":     payload.kind = item.value
                case "key":      payload.key = item.value
                case "dismiss":  payload.dismiss = item.value
                case "progress": payload.progress = item.value.flatMap(Double.init)
                case "timeout":  payload.timeout = item.value.flatMap(Double.init)
                case "sound":    payload.sound = item.value == "1" || item.value == "true"
                default: break
                }
            }
            state.handle(payload)
        case "fan":
            let query = components.queryItems ?? []
            func value(_ name: String) -> Double? {
                query.first { $0.name == name }?.value.flatMap(Double.init)
            }
            if query.contains(where: { $0.name == "auto" }) {
                FanControlClient.shared.autoAll()
            } else if let percent = value("percent") {
                FanControlClient.shared.setAll(percent: percent,
                                               minutes: value("minutes") ?? 5)
            }
        case "timer":
            let query = components.queryItems ?? []
            let minutes = query.first { $0.name == "minutes" }?.value
                .flatMap(Double.init) ?? 25
            if query.contains(where: { $0.name == "stop" }) {
                TimerService.shared.cancel()
            } else if query.contains(where: { $0.name == "pomodoro" }) {
                TimerService.shared.startPomodoro()
            } else {
                TimerService.shared.start(minutes: minutes)
            }
        case "menubar":
            MenuBarHider.shared.setHidden(
                !(components.queryItems?.contains { $0.name == "show" } ?? false))
        case "tab":
            let name = components.queryItems?.first { $0.name == "name" }?.value ?? "home"
            if let tab = PanelTab(rawValue: name) {
                state.panelTab = tab
                state.pinned = true
                state.forceExpand()
            }
            if let section = components.queryItems?
                .first(where: { $0.name == "section" })?.value,
               let value = DockSection(rawValue: section) {
                state.dockSection = value
            }
        case "switch":
            if let id = components.queryItems?
                .first(where: { $0.name == "account" })?.value {
                state.panelTab = .accounts
                state.pinned = true
                state.forceExpand()
                AccountService.shared.requestActivate(id)
            }
        case "meeting":
            let on = components.queryItems?.first { $0.name == "on" }?.value
            if on == "0" { MeetingMode.shared.disable() }
            else { MeetingMode.shared.enable(until: nil) }
        case "pin":      state.togglePin()
        case "settings": SettingsWindow.shared.show()
        case "mute":
            let minutes = components.queryItems?
                .first { $0.name == "minutes" }?.value.flatMap(Double.init) ?? 60
            state.mute(minutes: minutes)
        case "unmute":   state.unmute()
        default: break
        }
    }

    private func addFanMenu(to menu: NSMenu) {
        let fans = state.fans.fans
        guard !fans.isEmpty else { return }

        let rpm = fans.map { Int($0.rpm) }.max() ?? 0
        let hold = FanControlClient.shared.holds.values.max() ?? 0
        let title = hold > 0
            ? "Fans · \(rpm) rpm · \(hold / 60)m \(hold % 60)s left"
            : (rpm == 0 ? "Fans · stopped" : "Fans · \(rpm) rpm")

        let parent = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        parent.image = NSImage(systemSymbolName: "fan", accessibilityDescription: nil)
        menu.addItem(parent)

        let submenu = NSMenu()

        guard FanControlClient.shared.reachable else {
            let install = NSMenuItem(title: "Install fan helper…",
                                     action: #selector(openFanSettings), keyEquivalent: "")
            install.target = self
            submenu.addItem(install)
            menu.setSubmenu(submenu, for: parent)
            return
        }

        for preset in [(label: "50%", percent: 0.5), (label: "75%", percent: 0.75),
                       (label: "Blast", percent: 1.0)] {
            for minutes in [5.0, 15.0] {
                let entry = NSMenuItem(
                    title: "\(preset.label) for \(Int(minutes)) min",
                    action: #selector(boostFans(_:)), keyEquivalent: "")
                entry.target = self
                entry.representedObject = [preset.percent, minutes]
                submenu.addItem(entry)
            }
            submenu.addItem(.separator())
        }

        let auto = NSMenuItem(title: "Back to automatic",
                              action: #selector(autoFans), keyEquivalent: "")
        auto.target = self
        auto.isEnabled = FanControlClient.shared.hasActiveOverride
        submenu.addItem(auto)

        let settings = NSMenuItem(title: "Fan settings…",
                                  action: #selector(openFanSettings), keyEquivalent: "")
        settings.target = self
        submenu.addItem(settings)

        menu.setSubmenu(submenu, for: parent)
    }

    @objc private func boostFans(_ sender: NSMenuItem) {
        guard let values = sender.representedObject as? [Double], values.count == 2 else { return }
        FanControlClient.shared.setAll(percent: values[0], minutes: values[1])
    }

    @objc private func autoFans() { FanControlClient.shared.autoAll() }

    @objc private func openFanSettings() {
        SettingsNav.shared.tab = .fans
        SettingsWindow.shared.show()
    }

    @objc private func muteFor(_ sender: NSMenuItem) {
        state.mute(minutes: sender.representedObject as? Double ?? 60)
    }

    @objc private func unmute() { state.unmute() }

    @objc private func togglePin() { state.togglePin() }

    @objc private func openSettings() { SettingsWindow.shared.show() }

    @objc private func openOnboarding() { OnboardingWindow.shared.show() }

    @objc private func sendTest() {
        var p = NotchPayload()
        p.source = "claude"
        p.title = "MacInotch is listening"
        p.body = "curl localhost:\(NotchServer.port)/notify"
        p.kind = "success"
        state.handle(p)
    }

    private func greet() {
        var p = NotchPayload()
        p.source = "system"
        p.title = "MacInotch ready"
        p.body = DateKit.shamsiLatin(.now)
        p.kind = "info"
        p.timeout = 3.5
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(700))
            state.handle(p)
        }
    }
}

let app = NSApplication.shared
let delegate = MainActor.assumeIsolated { AppDelegate() }
app.delegate = delegate
app.run()
