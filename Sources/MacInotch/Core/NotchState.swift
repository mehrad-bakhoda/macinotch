import SwiftUI
import Combine
import CoreGraphics

enum DockSection: String, CaseIterable, Identifiable {
    case files
    case clipboard

    var id: String { rawValue }
    var label: String {
        switch self {
        case .files: return "Files"
        case .clipboard: return "Clipboard"
        }
    }
}

enum PanelTab: String, CaseIterable, Identifiable {
    case home
    case dock
    case sessions
    case notes

    var id: String { rawValue }
    var label: String {
        switch self {
        case .home: return "Home"
        case .dock: return "Dock"
        case .sessions: return "Sessions"
        case .notes: return "Notes"
        }
    }
    var symbol: String {
        switch self {
        case .home: return "square.grid.2x2"
        case .dock: return "tray.full"
        case .sessions: return "sparkles"
        case .notes: return "note.text"
        }
    }
}

enum NotchMode: Equatable {
    case collapsed
    case peek
    case expanded
}

@MainActor
final class NotchState: ObservableObject {
    static let shared = NotchState()

    @Published var mode: NotchMode = .collapsed
    @Published var items: [NotchItem] = []
    @Published var now: Date = .now
    @Published var hovering: Bool = false

    @Published var pinned: Bool = false

    @Published var music = MusicSnapshot()
    @Published var battery = BatterySnapshot()
    @Published var stats = SystemStats() {
        didSet { recordSamples() }
    }

    @Published private(set) var cpuHistory: [Double] = []
    @Published private(set) var ramHistory: [Double] = []
    @Published private(set) var tempHistory: [Double] = []

    static let historyLength = 60

    private func recordSamples() {
        func push(_ list: inout [Double], _ value: Double) {
            list.append(min(max(value, 0), 1))
            if list.count > Self.historyLength { list.removeFirst(list.count - Self.historyLength) }
        }
        push(&cpuHistory, stats.cpuTotal)
        push(&ramHistory, stats.memPressure)
        push(&tempHistory, temps.socLoad)
    }
    @Published var presence = Presence()
    @Published var temps = Temperatures()
    @Published var fans = FanSnapshot()
    @Published var usage = UsageSnapshot()
    @Published var topCPU: ProcessUsage?
    @Published var topMemory: ProcessUsage?
    @Published var repo = RepoStatus()
    @Published var showFanControls = false
    @Published var panelTab: PanelTab = .home
    @Published var dockSection: DockSection = .files
    @Published var sessions: [CodeSession] = []

    @Published var notchSize: CGSize = CGSize(width: 200, height: 32)

    @Published var measuredExpandedHeight: CGFloat = 240

    var musicControl: MusicService?

    private var timer: AnyCancellable?
    private var peekTask: Task<Void, Never>?

    private var prefs: PrefsData { Prefs.shared.d }

    var isLive: Bool {
        if isIdle { return true }
        guard prefs.liveStripEnabled else { return false }

        if prefs.idleShowStats || prefs.idleShowPresence { return true }
        if hasAttention || activeProgress != nil { return true }
        if TimerService.shared.isRunning { return true }
        if prefs.showNowPlaying && music.isActive && music.isPlaying { return true }
        return false
    }

    var usesChin: Bool { prefs.liveStripPlacement == .chin }

    static let chinHeight: CGFloat = 24

    var collapsedSize: CGSize {
        guard isLive else { return notchSize }
        if usesChin {
            let content = liveLeftWidth + liveRightWidth + 46
            return CGSize(width: max(notchSize.width + 130, content),
                          height: notchSize.height + Self.chinHeight)
        }
        return CGSize(width: notchSize.width + liveSlotWidth * 2 + 24,
                      height: notchSize.height + 6)
    }

    var leftItems: [PrefsData.StripItem] {
        resolve(prefs.idleLeft)
    }

    var rightItems: [PrefsData.StripItem] {
        resolve(prefs.idleRight)
    }

    private func resolve(_ raw: [String]) -> [PrefsData.StripItem] {
        raw.compactMap { PrefsData.StripItem(rawValue: $0) }.filter { available($0) }
    }

    private func available(_ item: PrefsData.StripItem) -> Bool {
        switch item {
        case .temp:     return temps.available
        case .weather:  return prefs.showWeather && WeatherService.shared.snapshot.available
        case .battery:  return battery.present
        case .music:    return prefs.showNowPlaying && music.isActive && music.isPlaying
        case .timer:    return TimerService.shared.isRunning
        case .presence: return prefs.watchClaude || prefs.watchChatGPT || prefs.watchSpotify
        default:        return true
        }
    }

    private func width(_ items: [PrefsData.StripItem]) -> CGFloat {
        guard !items.isEmpty else { return 0 }
        let content = items.reduce(0) { $0 + $1.width }
        return content + CGFloat(items.count - 1) * 8
    }

    var liveLeftWidth: CGFloat {
        if activeProgress != nil { return max(76, width(leftItems)) }
        return width(leftItems)
    }

    var liveSlotWidth: CGFloat { max(liveLeftWidth, liveRightWidth) }

    var liveRightWidth: CGFloat { width(rightItems) }

    var peekSize: CGSize {
        CGSize(width: max(470, notchSize.width + 250),
               height: max(notchSize.height + 30, 62))
    }

    var expandedSize: CGSize {
        CGSize(width: prefs.expandedWidth,
               height: min(max(measuredExpandedHeight, 150), 780))
    }

    var currentSize: CGSize {
        switch mode {
        case .collapsed: return collapsedSize
        case .peek:      return peekSize
        case .expanded:  return expandedSize
        }
    }

    var featured: NotchItem? {
        items.first(where: { $0.kind == .attention })
            ?? items.max(by: { $0.createdAt < $1.createdAt })
    }

    var hasAttention: Bool { items.contains { $0.kind == .attention && !$0.acknowledged } }

    var activeProgress: NotchItem? {
        items.filter { $0.kind == .progress }.max(by: { $0.createdAt < $1.createdAt })
    }

    private init() {
        timer = Timer.publish(every: 0.5, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] date in
                guard let self else { return }
                self.now = date
                self.reap()
                self.sampleIdle()
                self.publishSnapshot()
            }
    }

    func handle(_ p: NotchPayload) {
        if let dismissKey = p.dismiss {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                items.removeAll { $0.key == dismissKey }
            }
            settle()
            return
        }

        var kind = NotchKind(rawValue: (p.kind ?? "info").lowercased()) ?? .info
        let source = NotchSource(rawValue: (p.source ?? "custom").lowercased()) ?? .custom
        let key = p.key ?? UUID().uuidString

        let rule = prefs.sourceRules[source.rawValue] ?? .normal
        if rule == .muted { return }
        if rule == .sticky { kind = .attention }

        let quietHours = isMuted
            || (prefs.respectFocus && FocusWatcher.shared.active)
            || FrontmostAppWatcher.shared.shouldSuppress

        let defaultTimeout: Double = kind.isSticky ? .infinity : (kind == .progress ? 90 : 6)
        let timeout = p.timeout ?? defaultTimeout
        let expires: Date? = timeout.isFinite ? Date().addingTimeInterval(timeout) : nil

        let existingIndex = items.firstIndex(where: { $0.key == key })
        let isNew = existingIndex == nil
        let kindChanged = existingIndex.map { items[$0].kind != kind } ?? true

        if let idx = existingIndex {

            var it = items[idx]
            if let t = p.title { it.title = t }
            if let b = p.body { it.body = b }
            it.kind = kind
            it.source = source
            it.progress = p.progress ?? it.progress
            it.expiresAt = expires
            if let actions = p.actions { it.actions = actions }
            if kind != .attention { it.acknowledged = false }
            withAnimation(.easeInOut(duration: 0.25)) { items[idx] = it }
        } else {
            var it = NotchItem(
                key: key,
                source: source,
                title: p.title ?? source.displayName,
                body: p.body ?? "",
                kind: kind,
                progress: p.progress,
                expiresAt: expires
            )
            it.actions = p.actions ?? []
            withAnimation(.spring(response: 0.45, dampingFraction: 0.78)) {
                items.append(it)
                if items.count > 12 { items.removeFirst(items.count - 12) }
            }
        }

        let chatter = (kind == .progress || kind == .music)
        let wantsSound = p.sound ?? ((isNew || kindChanged) && !chatter)
        if wantsSound && rule != .silent && rule != .quiet && !quietHours {
            SoundKit.play(for: kind, source: source)
        }

        if prefs.keepHistory, isNew || kindChanged,
           let item = items.first(where: { $0.key == key }) {
            HistoryStore.shared.record(item)
        }

        if rule != .quiet && !quietHours { showPeek() }
    }

    func pushMusic(_ snap: MusicSnapshot) {
        guard prefs.musicAutoPopup else { return }
        var p = NotchPayload()
        p.source = "spotify"
        p.kind = "music"
        p.key = "now-playing"
        p.title = snap.title
        p.body = snap.artist
        p.timeout = 4.5
        p.sound = false
        handle(p)
        if let idx = items.firstIndex(where: { $0.key == "now-playing" }) {
            items[idx].artwork = snap.artwork
        }
    }

    func run(_ action: NotchAction, on item: NotchItem) {
        if let raw = action.url, let url = URL(string: raw) {
            NSWorkspace.shared.open(url)
        }
        if let command = action.command {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/sh")
            process.arguments = ["-c", command]
            try? process.run()
        }
        SoundKit.tap()
        dismiss(item)
    }

    func dismiss(_ item: NotchItem) {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
            items.removeAll { $0.id == item.id }
        }
        settle()
    }

    func clearAll() {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { items.removeAll() }
        settle()
    }

    func showPeek() {
        guard mode != .expanded else { return }
        withAnimation(.spring(response: 0.5, dampingFraction: 0.74)) { mode = .peek }
        peekTask?.cancel()
        peekTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(max(1.0, self?.prefs.peekSeconds ?? 4.6)))
            guard !Task.isCancelled else { return }
            await MainActor.run { self?.settle() }
        }
    }

    func settle() {
        guard !hovering, !pinned else { return }
        peekTask?.cancel()
        let next: NotchMode = hasAttention ? .peek : .collapsed
        withAnimation(.spring(response: 0.5, dampingFraction: 0.82)) { mode = next }
    }

    func noteShelfDrop() {
        panelTab = .dock
        dockSection = .files
        peekTask?.cancel()
        withAnimation(.spring(response: 0.45, dampingFraction: 0.78)) { mode = .expanded }
        peekTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2.5))
            guard !Task.isCancelled else { return }
            await MainActor.run { self?.settle() }
        }
    }

    @Published private(set) var idleSeconds: Double = 0

    var isIdle: Bool {
        guard prefs.idleClockEnabled, mode == .collapsed, !pinned else { return false }
        return idleSeconds >= prefs.idleClockMinutes * 60
    }

    private func sampleIdle() {
        guard prefs.idleClockEnabled else {
            if idleSeconds != 0 { idleSeconds = 0 }
            return
        }
        let anyInput = CGEventType(rawValue: ~0)!
        let seconds = CGEventSource.secondsSinceLastEventType(.combinedSessionState,
                                                             eventType: anyInput)

        if abs(seconds - idleSeconds) > 0.4 { idleSeconds = seconds }
    }

    var isMuted: Bool { Date().timeIntervalSince1970 < prefs.mutedUntil }

    var muteRemaining: String? {
        guard isMuted else { return nil }
        let s = Int(prefs.mutedUntil - Date().timeIntervalSince1970)
        return s >= 3600 ? "\(s / 3600)h \(s % 3600 / 60)m" : "\(max(1, s / 60))m"
    }

    func mute(minutes: Double) {
        Prefs.shared.d.mutedUntil = Date().addingTimeInterval(minutes * 60).timeIntervalSince1970
        clearAll()
    }

    func unmute() { Prefs.shared.d.mutedUntil = 0 }

    func previewAnimation() {
        peekTask?.cancel()
        pinned = false
        withAnimation(.easeInOut(duration: 0.12)) { mode = .collapsed }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(260))
            self.pinned = true
            withAnimation(Prefs.shared.d.openAnimation.opening) { self.mode = .expanded }
            try? await Task.sleep(for: .milliseconds(1500))
            self.pinned = false
            withAnimation(Prefs.shared.d.openAnimation.closing) { self.mode = .collapsed }
        }
    }

    func forceExpand() {
        peekTask?.cancel()
        withAnimation(.spring(duration: 0.3, bounce: 0.1)) { mode = .expanded }
    }

    func togglePin() {
        pinned.toggle()
        if pinned {
            peekTask?.cancel()
            withAnimation(.spring(response: 0.46, dampingFraction: 0.8)) { mode = .expanded }
        } else if !hovering {
            settle()
        }
    }

    func unpin() {
        guard pinned else { return }
        pinned = false
        if !hovering { settle() }
    }

    func setHover(_ on: Bool) {
        guard hovering != on else { return }
        hovering = on

        if pinned { return }
        if on && !prefs.hoverToExpand { return }
        if on {
            peekTask?.cancel()
            if mode != .expanded { SoundKit.tap(.levelChange) }
            withAnimation(.spring(response: 0.46, dampingFraction: 0.8)) { mode = .expanded }
        } else {

            for i in items.indices where items[i].kind == .attention { items[i].acknowledged = true }
            settle()
        }
    }

    private var lastSnapshot: Date = .distantPast
    private func publishSnapshot() {
        guard Date().timeIntervalSince(lastSnapshot) > 1 else { return }
        lastSnapshot = Date()
        SnapshotStore.shared.set(AppDelegate.snapshotJSON())
        SnapshotStore.shared.setFans(AppDelegate.fansJSON())
    }

    private func reap() {
        let n = Date()
        let expired = items.filter { ($0.expiresAt ?? .distantFuture) < n }
        guard !expired.isEmpty else { return }
        withAnimation(.easeOut(duration: 0.3)) {
            items.removeAll { ($0.expiresAt ?? .distantFuture) < n }
        }
        if mode == .peek && featured == nil { settle() }
    }
}
