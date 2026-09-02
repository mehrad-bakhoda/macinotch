import AVFoundation
import Carbon.HIToolbox
import Foundation
#if compiler(>=6.2)
import Speech
#endif

@MainActor
final class Dictation: ObservableObject {
    static let shared = Dictation()

    @Published private(set) var listening = false
    @Published private(set) var text = ""
    @Published private(set) var levels: [Double] = Array(repeating: 0, count: 28)
    @Published private(set) var status = ""
    @Published var lastError = ""
    @Published private(set) var registered = false
    @Published private(set) var registerStatus: OSStatus = 0

    private var engine: AVAudioEngine?
    private var analyzer: Any?
    private var transcriber: Any?
    private var continuation: AsyncStream<AVAudioPCMBuffer>.Continuation?
    private var converter: AVAudioConverter?
    private var target: AVAudioFormat?
    private var collector: Task<Void, Never>?
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?

    private init() {}

    static var available: Bool {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) { return true }
        #endif
        return false
    }

    func installHotKey() {
        unregister()
        guard Prefs.shared.d.dictationEnabled,
              let choice = HotKey.choice(named: Prefs.shared.d.dictationHotKey)
        else { return }

        var specs = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                          eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                          eventKind: UInt32(kEventHotKeyReleased)),
        ]

        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ -> OSStatus in
            var id = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject),
                              EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &id)
            guard id.signature == Dictation.signature else {
                return OSStatus(eventNotHandledErr)
            }

            let kind = GetEventKind(event)
            Task { @MainActor in
                if kind == UInt32(kEventHotKeyPressed) {
                    await Dictation.shared.begin()
                } else {
                    await Dictation.shared.finish()
                }
            }
            return noErr
        }, 2, &specs, nil, &handler)

        let id = EventHotKeyID(signature: Self.signature, id: 2)
        registerStatus = RegisterEventHotKey(choice.keyCode, choice.modifiers, id,
                                             GetApplicationEventTarget(), 0, &hotKey)
        registered = registerStatus == noErr && hotKey != nil
    }

    private static let signature: OSType = 0x4D4E4443

    private func unregister() {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        hotKey = nil
        if let handler { RemoveEventHandler(handler) }
        handler = nil
    }

    func toggle() {
        Task { listening ? await finish() : await begin() }
    }

    func begin() async {
        guard !listening, Self.available else { return }
        listening = true
        text = ""
        lastError = ""
        status = "Listening"
        levels = Array(repeating: 0, count: levels.count)

        #if compiler(>=6.2)
        guard #available(macOS 26.0, *) else { listening = false; return }

        let speech = SpeechTranscriber(
            locale: Locale(identifier: Prefs.shared.d.dictationLocale),
            transcriptionOptions: [],
            reportingOptions: [.volatileResults],
            attributeOptions: [])
        let engineAnalyzer = SpeechAnalyzer(modules: [speech])
        transcriber = speech
        analyzer = engineAnalyzer

        do {
            if let request = try await AssetInventory
                .assetInstallationRequest(supporting: [speech]) {
                status = "Preparing"
                try await request.downloadAndInstall()
            }
            target = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [speech])
        } catch {
            lastError = "Speech model unavailable."
            listening = false
            return
        }

        let (stream, feed) = AsyncStream<AVAudioPCMBuffer>.makeStream()
        continuation = feed

        do {
            try await engineAnalyzer.start(inputSequence: stream.map {
                AnalyzerInput(buffer: $0)
            })
        } catch {
            lastError = "Could not start dictation."
            listening = false
            return
        }

        collector = Task { [weak self] in
            guard let self else { return }
            var settled = ""
            do {
                for try await result in speech.results {
                    let piece = String(result.text.characters)
                    if result.isFinal { settled += piece }
                    let combined = settled + (result.isFinal ? "" : piece)
                    await MainActor.run { self.text = combined }
                }
            } catch {}
        }

        startMicrophone()
        status = "Listening"
        #endif
    }

    private func startMicrophone() {
        let audio = AVAudioEngine()
        let input = audio.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0 else {
            lastError = "No microphone input."
            listening = false
            return
        }

        input.installTap(onBus: 0, bufferSize: 2048, format: format) { [weak self] buf, _ in
            let level = Self.loudness(buf)
            Task { @MainActor in
                self?.push(level)
                self?.submit(buf)
            }
        }
        do {
            try audio.start()
            engine = audio
        } catch {
            lastError = "Microphone unavailable."
            listening = false
        }
    }

    private nonisolated static func loudness(_ buffer: AVAudioPCMBuffer) -> Double {
        guard let data = buffer.floatChannelData?[0] else { return 0 }
        let count = Int(buffer.frameLength)
        guard count > 0 else { return 0 }

        var sum: Float = 0
        for index in stride(from: 0, to: count, by: 8) {
            sum += data[index] * data[index]
        }
        let rms = sqrt(sum / Float(max(1, count / 8)))
        let shaped = min(1, Double(rms) * 9)
        return pow(shaped, 0.65)
    }

    private func push(_ level: Double) {
        levels.removeFirst()
        levels.append(level)
    }

    private func submit(_ buffer: AVAudioPCMBuffer) {
        guard let target, let continuation else { return }
        if converter == nil || converter?.outputFormat != target {
            converter = AVAudioConverter(from: buffer.format, to: target)
        }
        guard let converter else { return }

        let ratio = target.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1024
        guard let out = AVAudioPCMBuffer(pcmFormat: target,
                                         frameCapacity: capacity) else { return }

        var supplied = false
        var error: NSError?
        converter.convert(to: out, error: &error) { _, status in
            if supplied { status.pointee = .noDataNow; return nil }
            supplied = true
            status.pointee = .haveData
            return buffer
        }
        guard error == nil, out.frameLength > 0 else { return }
        continuation.yield(out)
    }

    func finish() async {
        guard listening else { return }
        listening = false
        status = ""

        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil

        continuation?.finish()
        continuation = nil

        #if compiler(>=6.2)
        if #available(macOS 26.0, *), let analyzer = analyzer as? SpeechAnalyzer {
            try? await analyzer.finalizeAndFinishThroughEndOfInput()
        }
        #endif
        collector?.cancel()
        collector = nil

        let spoken = text.trimmingCharacters(in: .whitespacesAndNewlines)
        levels = Array(repeating: 0, count: levels.count)
        text = ""

        guard spoken.count > 1 else { return }
        save(spoken)
    }

    private func save(_ spoken: String) {
        let stamp = DateFormatter()
        stamp.dateFormat = "yyyy-MM-dd HHmm"
        let heading = DateFormatter()
        heading.dateFormat = "EEEE d MMMM, HH:mm"

        let folder = NotesStore.shared.directory
        let name = "\(stamp.string(from: Date())) Dictated.md"
        let url = folder.appendingPathComponent(name)
        let body = "# Dictated note\n\n\(heading.string(from: Date()))\n\n\(spoken)\n"

        try? FileManager.default.createDirectory(at: folder,
                                                 withIntermediateDirectories: true)
        try? body.write(to: url, atomically: true, encoding: .utf8)
        NotesStore.shared.reload()

        var p = NotchPayload()
        p.source = NotchSource.system.rawValue
        p.kind = "success"
        p.key = "dictation"
        p.title = "Note saved"
        p.body = String(spoken.prefix(90))
        p.timeout = 8
        p.sound = false
        SoundKit.play(cue: .dictation)
        NotchState.shared.handle(p)
    }
}
