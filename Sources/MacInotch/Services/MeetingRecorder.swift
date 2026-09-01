import AVFoundation
import Foundation
import ScreenCaptureKit
import Speech

@MainActor
final class MeetingRecorder: NSObject, ObservableObject {
    static let shared = MeetingRecorder()

    @Published private(set) var recording = false
    @Published private(set) var startedAt: Date?
    @Published private(set) var transcript = ""
    @Published private(set) var status = ""
    @Published private(set) var working = false
    @Published var lastError = ""
    @Published private(set) var lastNote: String?

    private var engine: AVAudioEngine?
    private var stream: SCStream?
    private var analyzer: Any?
    private var transcriber: Any?
    private var continuation: AsyncStream<AVAudioPCMBuffer>.Continuation?
    private var converter: AVAudioConverter?
    private var target: AVAudioFormat?
    private var collector: Task<Void, Never>?
    private var title = "Meeting"

    private override init() { super.init() }

    var elapsed: String {
        guard let startedAt else { return "0:00" }
        let s = Int(Date().timeIntervalSince(startedAt))
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    static var available: Bool {
        if #available(macOS 26.0, *) { return true }
        return false
    }

    func toggle(title name: String) {
        recording ? Task { await stop() } : Task { await start(title: name) }
    }

    func start(title name: String) async {
        guard !recording, Self.available else { return }
        title = name.isEmpty ? "Meeting" : name
        transcript = ""
        lastError = ""
        lastNote = nil
        status = "Listening"

        guard #available(macOS 26.0, *) else { return }

        let speech = SpeechTranscriber(locale: Locale(identifier:
                                            Prefs.shared.d.meetingLocale),
                                       transcriptionOptions: [],
                                       reportingOptions: [.volatileResults],
                                       attributeOptions: [])
        let engineAnalyzer = SpeechAnalyzer(modules: [speech])
        transcriber = speech
        analyzer = engineAnalyzer

        do {
            if let request = try await AssetInventory
                .assetInstallationRequest(supporting: [speech]) {
                status = "Preparing the language model"
                try await request.downloadAndInstall()
            }
            target = await SpeechAnalyzer.bestAvailableAudioFormat(
                compatibleWith: [speech])
        } catch {
            lastError = "Speech model unavailable: \(error.localizedDescription)"
            status = ""
            return
        }

        let (stream, continuation) = AsyncStream<AVAudioPCMBuffer>.makeStream()
        self.continuation = continuation

        do {
            try await engineAnalyzer.start(inputSequence: stream.map {
                AnalyzerInput(buffer: $0)
            })
        } catch {
            lastError = "Could not start the transcriber."
            status = ""
            return
        }

        collector = Task { [weak self] in
            guard let self else { return }
            do {
                for try await result in speech.results where result.isFinal {
                    let piece = String(result.text.characters)
                    await MainActor.run {
                        self.transcript += piece
                    }
                }
            } catch {}
        }

        startMicrophone()
        if Prefs.shared.d.meetingCapturesSystemAudio { await startSystemAudio() }

        recording = true
        startedAt = Date()
        status = "Recording"
    }

    private func startMicrophone() {
        let audio = AVAudioEngine()
        let input = audio.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0 else { return }

        input.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buf, _ in
            Task { @MainActor in self?.submit(buf) }
        }
        do {
            try audio.start()
            engine = audio
        } catch {
            lastError = "Microphone unavailable: \(error.localizedDescription)"
        }
    }

    private func startSystemAudio() async {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(
                false, onScreenWindowsOnly: true)
            guard let display = content.displays.first else { return }

            let filter = SCContentFilter(display: display, excludingWindows: [])
            let config = SCStreamConfiguration()
            config.capturesAudio = true
            config.excludesCurrentProcessAudio = true
            config.width = 2
            config.height = 2
            config.minimumFrameInterval = CMTime(value: 1, timescale: 1)

            let capture = SCStream(filter: filter, configuration: config, delegate: nil)
            try capture.addStreamOutput(self, type: .audio,
                                        sampleHandlerQueue: DispatchQueue(
                                            label: "io.macinotch.sysaudio"))
            try await capture.startCapture()
            stream = capture
        } catch {
            status = "Recording, microphone only"
        }
    }

    fileprivate func submit(_ buffer: AVAudioPCMBuffer) {
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

    func stop() async {
        guard recording else { return }
        recording = false
        status = "Writing it up"
        working = true
        defer { working = false }

        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil

        if let stream { try? await stream.stopCapture() }
        stream = nil

        continuation?.finish()
        continuation = nil

        if #available(macOS 26.0, *), let analyzer = analyzer as? SpeechAnalyzer {
            try? await analyzer.finalizeAndFinishThroughEndOfInput()
        }
        collector?.cancel()
        collector = nil

        let text = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        let minutes = Int((Date().timeIntervalSince(startedAt ?? Date())) / 60)
        startedAt = nil

        guard text.count > 40 else {
            status = ""
            lastError = "Too little was said to write anything up."
            return
        }

        let notes = await Summarizer.shared.meetingNotes(title: title, transcript: text)
        let path = writeNote(title: title, minutes: minutes,
                             notes: notes, transcript: text)
        lastNote = path
        status = ""

        var p = NotchPayload()
        p.source = NotchSource.system.rawValue
        p.kind = "success"
        p.key = "meeting-note"
        p.title = "\(title) written up"
        p.body = "\(minutes) minutes, saved to your notes"
        p.timeout = 12
        p.sound = true
        NotchState.shared.handle(p)
    }

    private func writeNote(title: String, minutes: Int,
                           notes: String, transcript: String) -> String {
        let stamp = DateFormatter()
        stamp.dateFormat = "yyyy-MM-dd HHmm"
        let when = DateFormatter()
        when.dateFormat = "EEEE d MMMM, HH:mm"

        var body = "# \(title)\n\n"
        body += "\(when.string(from: Date())) · \(minutes) minutes\n\n"
        body += notes.isEmpty ? "" : notes + "\n\n"
        body += "---\n\n## Transcript\n\n" + transcript + "\n"

        let folder = NotesStore.shared.directory.path
        let name = "\(stamp.string(from: Date())) \(title).md"
            .replacingOccurrences(of: "/", with: "-")
        let url = URL(fileURLWithPath: folder).appendingPathComponent(name)
        try? FileManager.default.createDirectory(atPath: folder,
                                                 withIntermediateDirectories: true)
        try? body.write(to: url, atomically: true, encoding: .utf8)
        NotesStore.shared.reload()
        return url.path
    }
}

extension MeetingRecorder: SCStreamOutput {
    nonisolated func stream(_ stream: SCStream, didOutputSampleBuffer sample: CMSampleBuffer,
                            of type: SCStreamOutputType) {
        guard type == .audio,
              let buffer = sample.asPCMBuffer else { return }
        Task { @MainActor in MeetingRecorder.shared.submit(buffer) }
    }
}

extension CMSampleBuffer {
    var asPCMBuffer: AVAudioPCMBuffer? {
        try? withAudioBufferList { list, _ -> AVAudioPCMBuffer? in
            guard let description = formatDescription?.audioStreamBasicDescription
            else { return nil }
            var layout = AudioChannelLayout()
            layout.mChannelLayoutTag = description.mChannelsPerFrame == 2
                ? kAudioChannelLayoutTag_Stereo : kAudioChannelLayoutTag_Mono
            var asbd = description
            guard let format = AVAudioFormat(streamDescription: &asbd,
                                             channelLayout: AVAudioChannelLayout(
                                                layoutTag: layout.mChannelLayoutTag))
            else { return nil }
            return AVAudioPCMBuffer(pcmFormat: format, bufferListNoCopy: list.unsafePointer)
        }
    }
}
