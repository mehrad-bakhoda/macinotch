import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

actor Summarizer {
    static let shared = Summarizer()

    private var cache: [String: String] = [:]

    static var onDeviceAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            if case .available = SystemLanguageModel.default.availability { return true }
        }
        #endif
        return false
    }

    func summarise(subject: String, body: String) async -> String {
        let key = subject + "\u{1F}" + String(body.prefix(200))
        if let cached = cache[key] { return cached }

        var result = await onDevice(subject: subject, body: body)
        if result.isEmpty { result = Self.extractive(body) }

        cache[key] = result
        if cache.count > 300 { cache.removeAll() }
        return result
    }

    private func onDevice(subject: String, body: String) async -> String {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            guard case .available = SystemLanguageModel.default.availability else {
                return ""
            }
            let session = LanguageModelSession(instructions: """
            You summarise an email in one short sentence, at most twenty words. \
            State what it asks for or tells the reader. No greeting, no sign off, \
            no preamble, and never invent detail that is not present.
            """)
            let prompt = "Subject: \(subject)\n\n\(body.prefix(1200))"
            guard let response = try? await session.respond(to: prompt) else { return "" }
            return response.content.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        #endif
        return ""
    }

    nonisolated static func extractive(_ body: String) -> String {
        let sentences = body
            .replacingOccurrences(of: "\n", with: " ")
            .components(separatedBy: CharacterSet(charactersIn: ".!?"))
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.count > 18 }

        let head = sentences.prefix(2).joined(separator: ". ")
        guard !head.isEmpty else { return String(body.prefix(140)) }
        return head.count > 180 ? String(head.prefix(180)) + "..." : head + "."
    }
}
