import AppKit
import Combine

struct MusicSnapshot: Equatable {
    var app: String = ""
    var trackID: String = ""
    var title: String = ""
    var artist: String = ""
    var album: String = ""
    var isPlaying: Bool = false
    var position: Double = 0
    var duration: Double = 0
    var artworkURL: String = ""
    var artwork: NSImage? = nil
    var volume: Int = 50

    var isActive: Bool { !title.isEmpty }

    var isAppleMusic: Bool { app == "Music" }

    var appLabel: String { app == "Music" ? "Apple Music" : "Spotify" }

    var timeLeft: String {
        let left = max(0, duration - position)
        return String(format: "-%d:%02d", Int(left) / 60, Int(left) % 60)
    }

    var elapsed: String {
        String(format: "%d:%02d", Int(position) / 60, Int(position) % 60)
    }
    var fraction: Double {
        guard duration > 0 else { return 0 }
        return min(max(position / duration, 0), 1)
    }

    static func == (a: MusicSnapshot, b: MusicSnapshot) -> Bool {
        a.trackID == b.trackID && a.isPlaying == b.isPlaying &&
        abs(a.position - b.position) < 0.35 && a.artwork === b.artwork
    }
}

@MainActor
final class MusicService {
    private weak var state: NotchState?
    private var timer: Timer?
    private var lastTrackID: String = ""
    private var artCache: [String: NSImage] = [:]
    private var artTask: Task<Void, Never>?

    nonisolated private static let spotifyScript = """
    tell application id "com.spotify.client"
        if player state is stopped then return "stopped"
        set t to current track
        return "Spotify" & "\\n" & (id of t as text) & "\\n" & (name of t as text) & "\\n" ¬
            & (artist of t as text) & "\\n" & (album of t as text) & "\\n" ¬
            & ((player state as text)) & "\\n" & ((player position as text)) & "\\n" ¬
            & (((duration of t) / 1000) as text) & "\\n" & (artwork url of t as text)
    end tell
    """

    nonisolated private static let musicScript = """
    tell application id "com.apple.Music"
        if player state is stopped then return "stopped"
        set t to current track
        return "Music" & "\\n" & (persistent ID of t as text) & "\\n" & (name of t as text) & "\\n" ¬
            & (artist of t as text) & "\\n" & (album of t as text) & "\\n" ¬
            & ((player state as text)) & "\\n" & ((player position as text)) & "\\n" ¬
            & ((duration of t) as text) & "\\n" & ""
    end tell
    """

    init(state: NotchState) { self.state = state }

    func start() {
        tick()
        let t = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() { timer?.invalidate(); timer = nil }

    func playPause() { control("playpause") }
    func next()      { control("next track") }
    func previous()  { control("previous track") }

    func seek(to seconds: Double) {
        guard let bundle = activeBundle else { return }
        let clamped = max(0, seconds)
        state?.music.position = clamped
        Self.queue.async {
            _ = Self.run("tell application id \"\(bundle)\" to set player position to \(clamped)")
        }
    }

    func setVolume(_ percent: Double) {
        guard let bundle = activeBundle else { return }
        let value = Int(min(max(percent, 0), 1) * 100)
        Self.queue.async {
            _ = Self.run("tell application id \"\(bundle)\" to set sound volume to \(value)")
        }
    }

    private var activeBundle: String? {
        if running("com.spotify.client") { return "com.spotify.client" }
        if running("com.apple.Music") { return "com.apple.Music" }
        return nil
    }

    private func control(_ command: String) {
        guard let bundle = activeBundle else { return }
        Self.queue.async {
            _ = Self.run("tell application id \"\(bundle)\" to \(command)")
        }
    }

    private func running(_ bundleID: String) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    }

    nonisolated private static let queue = DispatchQueue(label: "io.macinotch.applescript")
    private var polling = false

    private func tick() {
        guard !polling else { return }
        let wantSpotify = running("com.spotify.client")
        let wantMusic = running("com.apple.Music")
        guard wantSpotify || wantMusic else {
            if state?.music.isActive == true { state?.music = MusicSnapshot(); lastTrackID = "" }
            return
        }
        polling = true
        Self.queue.async { [weak self] in
            var raw: String?
            if wantSpotify { raw = Self.run(Self.spotifyScript) }
            if raw == nil || raw == "stopped", wantMusic {
                raw = Self.run(Self.musicScript) ?? raw
            }
            Task { @MainActor in
                self?.polling = false
                self?.apply(raw)
            }
        }
    }

    private func apply(_ raw: String?) {
        guard let state else { return }

        guard let raw, raw != "stopped" else {
            if state.music.isActive {
                state.music = MusicSnapshot()
                lastTrackID = ""
            }
            return
        }

        let f = raw.components(separatedBy: "\n")
        guard f.count >= 9 else { return }

        var snap = MusicSnapshot()
        snap.app = f[0]
        snap.trackID = f[1]
        snap.title = f[2]
        snap.artist = f[3]
        snap.album = f[4]
        snap.isPlaying = f[5].lowercased().contains("playing")
        snap.position = Double(f[6]) ?? 0
        snap.duration = Double(f[7]) ?? 0
        snap.artworkURL = f[8]
        snap.volume = f.count > 9 ? (Int(Double(f[9]) ?? 50)) : 50
        snap.artwork = artCache[snap.trackID]

        let changed = snap.trackID != lastTrackID && !snap.trackID.isEmpty
        state.music = snap

        if changed {
            lastTrackID = snap.trackID
            if snap.isPlaying { state.pushMusic(snap) }
            loadArtwork(for: snap)
        }
    }

    private func loadArtwork(for snap: MusicSnapshot) {
        guard artCache[snap.trackID] == nil else { return }

        if snap.app == "Music" {
            loadAppleMusicArtwork(trackID: snap.trackID)
            return
        }
        guard let url = URL(string: snap.artworkURL),
              url.scheme?.hasPrefix("http") == true else { return }
        artTask?.cancel()
        let id = snap.trackID
        artTask = Task { [weak self] in
            guard let (data, _) = try? await URLSession.shared.data(from: url),
                  let img = NSImage(data: data), !Task.isCancelled else { return }
            await MainActor.run {
                guard let self, let state = self.state else { return }
                self.artCache[id] = img
                if self.artCache.count > 40 { self.artCache.removeAll() }
                if state.music.trackID == id { state.music.artwork = img }
                if let i = state.items.firstIndex(where: { $0.key == "now-playing" }) {
                    state.items[i].artwork = img
                }
            }
        }
    }

    private func loadAppleMusicArtwork(trackID: String) {
        Self.queue.async { [weak self] in
            let script = """
            tell application id "com.apple.Music"
                if player state is stopped then return missing value
                try
                    return data of artwork 1 of current track
                on error
                    return missing value
                end try
            end tell
            """
            guard let data = Self.runForData(script),
                  let image = NSImage(data: data) else { return }
            Task { @MainActor in
                guard let self, let state = self.state else { return }
                self.artCache[trackID] = image
                if state.music.trackID == trackID { state.music.artwork = image }
                if let i = state.items.firstIndex(where: { $0.key == "now-playing" }) {
                    state.items[i].artwork = image
                }
            }
        }
    }

    nonisolated private static func runForData(_ source: String) -> Data? {
        var error: NSDictionary?
        guard let script = NSAppleScript(source: source) else { return nil }
        let result = script.executeAndReturnError(&error)
        guard error == nil, let data = result.data as Data?, data.count > 8 else { return nil }
        return data
    }

    nonisolated private static func run(_ source: String) -> String? {
        var error: NSDictionary?
        guard let script = NSAppleScript(source: source) else { return nil }
        let result = script.executeAndReturnError(&error)
        if error != nil { return nil }
        return result.stringValue
    }
}
